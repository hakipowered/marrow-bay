#!/usr/bin/env python3
"""Game content packs for the in-game updater (see tools/content/README.md).

  packs.py build-info [--out boot/build_info.json]
      Write the base id and app version into the thin base before exporting it.
  packs.py split <full.pck> <out_dir> --version 0.12 [--like live|none|<dir>]
      Split one full content export into packs + manifest.json. Every file
      stays in the pack it was in on the server (--like live, the default) or
      in another build (<dir>), so players only download packs whose files
      changed; new files go into new packs. --like none packs from scratch.
  packs.py upload <out_dir> [--new-base] [--kv-limit BYTES]
      Put new packs and the manifest on the download server, then delete
      packs the new manifest doesn't use. Refuses when the server's storage
      would go over --kv-limit (default 1 GB, the free KV plan; 0 = no check).
      Signs with UPLOAD_TOKEN if set, otherwise with the content upload key
      ($CONTENT_UPLOAD_KEY, default
      /mnt/project-files/.signing/content_upload_ed25519.pem).
  packs.py live
      Print the manifest the server offers now.
  packs.py serve <out_dir> [--port 8790]
      Serve <out_dir> on /packs/ like the download server does (for tests).

Run from the project root.
"""
import argparse, base64, collections, hashlib, http.server, json, os, re, struct, subprocess, sys, time
import urllib.error, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONTENT_KEY = os.environ.get("CONTENT_UPLOAD_KEY", "/mnt/project-files/.signing/content_upload_ed25519.pem")
SERVER = os.environ.get("RAGOON_DOWNLOAD_URL", "https://ragoon-city-download.hakipowered.workers.dev").rstrip("/")
MANIFEST_FORMAT = 1
KV_CHUNK = 20 * 1024 * 1024  # the worker stores packs as 20 MiB KV values

# A pack holds a folder while the folder's exported data is at most MAX_PACK;
# bigger folders split into their subfolders. Subfolders under MIN_PACK ride
# along with their parent's loose files.
MAX_PACK = 24 * 1024 * 1024
MIN_PACK = 5 * 1024 * 1024
# Code, scenes and index files: small and change every build, so one pack.
CORE_PREFIXES = ("scripts/", "shaders/", "scenes/")
CORE_FILES = (".godot/global_script_class_cache.cfg", ".godot/uid_cache.bin", ".godot/extension_list.cfg")
# Packs only needed once the story starts (the browser can fetch them while
# the player is on the menu). Everything else is "boot".
LATER_PREFIXES = ("assets/story/video/",)
# What decides whether content fits an app: settings and resources Godot
# reads at startup from the base, plus the engine. Change one of these and
# players need a new APK.
BASE_FILES = ("project.godot", "default_bus_layout.tres")

PACK_MAGIC = 0x43504447
PACK_FORMAT_VERSION = 2
PACK_REL_FILEBASE = 1 << 1
PCK_PADDING = 16


# --- PCK files ----------------------------------------------------------------

Entry = collections.namedtuple("Entry", "path offset size md5 flags")


def read_pck(path):
    with open(path, "rb") as f:
        return _parse_pck(f, path)


def _parse_pck(f, path):
    """The version and file list of a pack; `f` only needs read(n)."""
    magic, fmt, major, minor, patch, flags = struct.unpack("<6I", f.read(24))
    if magic != PACK_MAGIC:
        sys.exit(f"{path}: not a Godot pack")
    if fmt != PACK_FORMAT_VERSION:
        sys.exit(f"{path}: pack format {fmt}, this tool knows {PACK_FORMAT_VERSION}")
    if flags & 1:
        sys.exit(f"{path}: encrypted packs aren't supported")
    (file_base,) = struct.unpack("<Q", f.read(8))
    f.read(16 * 4)
    (count,) = struct.unpack("<I", f.read(4))
    entries = []
    for _ in range(count):
        (sl,) = struct.unpack("<I", f.read(4))
        p = f.read(sl).rstrip(b"\0").decode("utf-8")
        ofs, size = struct.unpack("<QQ", f.read(16))
        md5 = f.read(16)
        (fl,) = struct.unpack("<I", f.read(4))
        entries.append(Entry(p, file_base + ofs, size, md5, fl))
    return (major, minor, patch), entries


class _RemoteHead:
    """The start of a pack on the server, fetched with Range requests as
    read() needs it: enough to read a pack's file list without the data."""

    def __init__(self, url):
        self.url, self.buf, self.pos = url, b"", 0

    def read(self, n):
        end = self.pos + n
        while len(self.buf) < end:
            want = max(end, 2 * len(self.buf), 1 << 16)
            code, body, _ = _request("GET", self.url, headers={"Range": f"bytes={len(self.buf)}-{want - 1}"})
            if code not in (200, 206) or not body:
                sys.exit(f"reading {self.url}: {code}")
            self.buf = (self.buf + body) if code == 206 else body
            if code == 200:
                break
        out = self.buf[self.pos:end]
        self.pos = end
        return out


def write_pck(out_path, version, src_path, entries):
    """Write `entries` (read from src_path) as a new pack. Same input, same bytes."""
    entries = sorted(entries, key=lambda e: e.path)
    head = bytearray()
    head += struct.pack("<6I", PACK_MAGIC, PACK_FORMAT_VERSION, *version, PACK_REL_FILEBASE)
    base_pos = len(head)
    head += struct.pack("<Q", 0)
    head += b"\0" * 64
    head += struct.pack("<I", len(entries))
    ofs_pos = []
    for e in entries:
        p = e.path.encode("utf-8")
        pad = (4 - len(p) % 4) % 4
        head += struct.pack("<I", len(p) + pad) + p + b"\0" * pad
        ofs_pos.append(len(head))
        head += struct.pack("<QQ", 0, e.size) + e.md5 + struct.pack("<I", 0)
    file_base = len(head) + (PCK_PADDING - len(head) % PCK_PADDING) % PCK_PADDING
    struct.pack_into("<Q", head, base_pos, file_base)
    ofs = 0
    for e, pos in zip(entries, ofs_pos):
        struct.pack_into("<Q", head, pos, ofs)
        ofs += e.size + (PCK_PADDING - e.size % PCK_PADDING) % PCK_PADDING
    head += b"\0" * (file_base - len(head))
    h = hashlib.sha256()
    with open(src_path, "rb") as src, open(out_path + ".tmp", "wb") as out:
        out.write(head)
        h.update(head)
        for e in entries:
            src.seek(e.offset)
            left = e.size
            while left:
                buf = src.read(min(left, 1 << 22))
                out.write(buf)
                h.update(buf)
                left -= len(buf)
            pad = b"\0" * ((PCK_PADDING - e.size % PCK_PADDING) % PCK_PADDING)
            out.write(pad)
            h.update(pad)
    os.replace(out_path + ".tmp", out_path)
    return h.hexdigest(), os.path.getsize(out_path)


# --- Base id and version ------------------------------------------------------

def godot_version():
    godot = os.environ.get("GODOT", os.path.expanduser("~/tools/godot"))
    v = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip()
    parts = v.split(".")
    return ".".join(parts[:4]) if len(parts) >= 4 else v  # 4.4.1.stable


def base_id():
    h = hashlib.sha256(godot_version().encode())
    for name in BASE_FILES:
        with open(os.path.join(ROOT, name), "rb") as f:
            h.update(b"\0" + name.encode() + b"\0" + f.read())
    return h.hexdigest()[:12]


def app_version():
    """version/name and version/code of the Android (thin base) preset."""
    text = open(os.path.join(ROOT, "export_presets.cfg")).read()
    opts = text.split("[preset.0.options]", 1)[1].split("[preset.", 1)[0]
    name = re.search(r'^version/name="([^"]*)"', opts, re.M).group(1)
    code = int(re.search(r"^version/code=(\d+)", opts, re.M).group(1))
    return name, code


# --- Splitting ----------------------------------------------------------------

def _norm(p):
    return p[len("res://"):] if p.startswith("res://") else p


def _is_base_only(src):
    return "/" not in src or src.startswith("boot/")


def _remap_targets(text):
    return [_norm(m.group(1)) for m in re.finditer(r'^path[\w.]*="([^"]+)"', text, re.M)]


def assign_sources(entries, read):
    """Map every file in the export to the source path it belongs to.

    Returns (core, by_source, dropped): `core` is the index files (.import,
    .remap, caches) that always go in the core pack, `by_source` maps a
    source path to its data files.
    """
    owner = {}
    core, dropped = [], []
    for e in entries:
        p = _norm(e.path)
        if p.endswith(".import") or p.endswith(".remap"):
            src = p.rsplit(".", 1)[0]
            for t in _remap_targets(read(e).decode("utf-8", "replace")):
                owner[t] = src
    by_source = collections.defaultdict(list)
    for e in entries:
        p = _norm(e.path)
        if p == "project.binary":
            dropped.append(e)
        elif p in CORE_FILES:
            core.append(e)
        elif p.endswith(".import") or p.endswith(".remap"):
            (dropped if _is_base_only(p.rsplit(".", 1)[0]) else core).append(e)
        elif p.startswith(".godot/"):
            src = owner.get(p, "_orphans/" + p)
            (dropped if _is_base_only(src) else by_source[src]).append(e)
        elif _is_base_only(p):
            dropped.append(e)
        else:
            by_source[p].append(e)
    return core, by_source, dropped


def group_sources(by_source, like=None):
    """Deterministically group sources into packs: {pack name: [sources]}.

    `like` is the layout players already have ({pack name: set of paths}, see
    reference_layout). A source whose files were in one of those packs stays
    in it, so a pack only changes when its own files do; sources that are new
    are grouped into new packs of their own. Without `like`, everything is
    grouped from scratch.
    """
    size = {s: sum(e.size for e in es) for s, es in by_source.items()}
    packs = {"core": [s for s in by_source if s.startswith(CORE_PREFIXES)]}
    rest = [s for s in by_source if not s.startswith(CORE_PREFIXES)]
    if like:
        where = {path: name for name, paths in like.items() if name != "core" for path in paths}
        new = []
        for s in sorted(rest):
            names = sorted({where[_norm(e.path)] for e in by_source[s] if _norm(e.path) in where})
            if names:
                packs.setdefault(names[0], []).append(s)
            else:
                new.append(s)
        rest = new

    def name_of(prefix):
        n = prefix.strip("/")
        n = n[len("assets/"):] if n.startswith("assets/") else n
        return re.sub(r"[^a-z0-9_]+", "-", n.lower()).strip("-") or "misc"

    def cut_after(s):
        # Where a run of loose files may end, decided by the file's own name,
        # so adding or removing one file moves at most the packs next to it.
        return int(hashlib.sha1(s.encode()).hexdigest()[:8], 16) % 4 == 0

    def chunk(prefix, sources):
        # Loose files of a folder: fill packs in path order; big files alone.
        # Each pack is named after its first file, not numbered, so a pack
        # added in front doesn't rename the ones after it.
        out, cur, cur_size = [], [], 0
        for s in sorted(sources):
            if size[s] > MAX_PACK // 2:
                out.append([s])
                continue
            if cur and cur_size + size[s] > MAX_PACK:
                out.append(cur)
                cur, cur_size = [], 0
            cur.append(s)
            cur_size += size[s]
            if cur_size >= MAX_PACK // 2 and cut_after(s):
                out.append(cur)
                cur, cur_size = [], 0
        if cur:
            out.append(cur)
        if len(out) == 1:
            return [(name_of(prefix), out[0])]
        first = lambda g: os.path.splitext(g[0][len(prefix):].split("/", 1)[0])[0]
        return [(name_of(prefix + first(g)), g) for g in out]

    def split(prefix, sources):
        total = sum(size[s] for s in sources)
        if total <= MAX_PACK:
            return [(name_of(prefix), sources)]
        children, loose = collections.defaultdict(list), []
        for s in sources:
            rest = s[len(prefix):]
            (children[rest.split("/", 1)[0]] if "/" in rest else loose).append(s)
        result = []
        for child in sorted(children):
            group = children[child]
            if sum(size[s] for s in group) < MIN_PACK:
                loose += group
            else:
                result += split(prefix + child + "/", group)
        if loose:
            result += chunk(prefix, loose)
        return result

    if rest:
        # New files: start from the folder they all share, so their pack is
        # named after where they are.
        common = os.path.commonpath(rest) if len(rest) > 1 else os.path.dirname(rest[0])
        common = "" if not common or common in rest else common + "/"
        for name, group in split(common, rest):
            base, n = name, 1
            while name in packs:
                n += 1
                name = f"{base}-{n}"
            packs[name] = group
    return {name: group for name, group in packs.items() if group or name == "core"}


def reference_layout(like):
    """The packs players already have, as {name: set of paths in it}, with the
    manifest they came from. `like` is "live" (the download server), "none",
    or a build folder (with manifest.json and packs/)."""
    if like == "none":
        return None, None
    if like == "live":
        manifest = live_manifest()
        if not manifest:
            print("no content on the server yet: packing from scratch")
            return None, None
        open_pack = lambda p: _RemoteHead(f"{SERVER}/packs/{p['file']}")
    else:
        manifest = json.load(open(os.path.join(like, "manifest.json")))
        open_pack = lambda p: open(os.path.join(like, "packs", p["file"]), "rb")
    layout = {}
    for p in manifest["packs"]:
        f = open_pack(p)
        _, entries = _parse_pck(f, p["file"])
        if hasattr(f, "close"):
            f.close()
        layout[p["name"]] = {_norm(e.path) for e in entries}
    return layout, manifest


def _preset_salt():
    """The engine and the content export settings: change either and every
    pack's inputs change."""
    text, out = open("export_presets.cfg").read().splitlines(), []
    sections = {}
    current = None
    for line in text:
        if line.startswith("[preset."):
            current = line.strip("[]").split(".")[1]
        if current is not None and not line.startswith("version/"):
            sections.setdefault(current, []).append(line)
    for lines in sections.values():
        if 'name="Android Content"' in lines:
            out = lines
    return godot_version() + "\n" + "\n".join(out)


def _fingerprint(src):
    """What a source's exported files are made from: the file, its import
    settings (without the uid, which differs between machines for files
    that aren't in git), and for a glTF the buffers and images it points to."""
    h = hashlib.sha256(src.encode() + b"\0")
    def add(path):
        try:
            with open(path, "rb") as f:
                h.update(hashlib.sha256(f.read()).digest())
        except OSError:
            h.update(b"-")
    add(src)
    try:
        imp = open(src + ".import", encoding="utf-8").read()
        h.update("\n".join(l for l in imp.splitlines() if not l.startswith("uid=")).encode())
    except OSError:
        pass
    if src.endswith(".gltf"):
        try:
            g = json.load(open(src, encoding="utf-8"))
            for item in g.get("buffers", []) + g.get("images", []):
                uri = item.get("uri", "")
                if uri and not uri.startswith("data:"):
                    add(os.path.join(os.path.dirname(src), urllib.parse.unquote(uri)))
        except (OSError, ValueError):
            pass
    return h.hexdigest()


def _fetch_pack(like, p, dest):
    """Copy pack `p` of the reference build to `dest`, checking its sha256."""
    h = hashlib.sha256()
    if like == "live":
        src = urllib.request.urlopen(urllib.request.Request(
            f"{SERVER}/packs/{p['file']}", headers={"User-Agent": "ragoon-city-build/1.0"}), timeout=600)
    else:
        src = open(os.path.join(like, "packs", p["file"]), "rb")
    with src, open(dest + ".tmp", "wb") as out:
        while True:
            buf = src.read(1 << 22)
            if not buf:
                break
            h.update(buf)
            out.write(buf)
    if h.hexdigest() != p["sha256"]:
        os.remove(dest + ".tmp")
        sys.exit(f"{p['file']} from {like} doesn't match its sha256")
    os.replace(dest + ".tmp", dest)


def cmd_split(args):
    version, entries = read_pck(args.pck)
    with open(args.pck, "rb") as f:
        def read(e):
            f.seek(e.offset)
            return f.read(e.size)
        core, by_source, dropped = assign_sources(entries, read)
    like, like_manifest = reference_layout(args.like)
    groups = group_sources(by_source, like)
    os.makedirs(args.out, exist_ok=True)
    packs_dir = os.path.join(args.out, "packs")
    os.makedirs(packs_dir, exist_ok=True)
    manifest_packs = []
    order = ["core"] + sorted(n for n in groups if n != "core")
    written = set()
    salt = _preset_salt()
    before = {p["name"]: p for p in like_manifest["packs"]} if like_manifest else {}
    kept = []
    for name in order:
        files = list(core) if name == "core" else []
        for s in groups[name]:
            files += by_source[s]
        if not files:
            continue
        inputs = None
        if name != "core":
            h = hashlib.sha256(salt.encode())
            for s in sorted(groups[name]):
                h.update(f"{s}\0{_fingerprint(s)}\n".encode())
            inputs = h.hexdigest()
        tmp = os.path.join(packs_dir, name + ".pck")
        sha, size = write_pck(tmp, version, args.pck, files)
        file = f"{name}-{sha[:12]}.pck"
        old = before.get(name)
        if old and old["sha256"] != sha and inputs and old.get("inputs") == inputs:
            # Made from exactly the same files as the pack players have; only
            # the import wasn't byte-identical (Godot's mesh import differs
            # from machine to machine). Keep theirs.
            os.remove(tmp)
            file, sha, size = old["file"], old["sha256"], old["size"]
            if not os.path.exists(os.path.join(packs_dir, file)):
                _fetch_pack(args.like, old, os.path.join(packs_dir, file))
            kept.append(name)
        else:
            os.replace(tmp, os.path.join(packs_dir, file))
        written.add(file)
        later = groups[name] and all(s.startswith(LATER_PREFIXES) for s in groups[name])
        entry = {"name": name, "file": file, "sha256": sha, "size": size,
                 "stage": "later" if later else "boot", "files": len(files)}
        if inputs:
            entry["inputs"] = inputs
        manifest_packs.append(entry)
    for old in os.listdir(packs_dir):
        if old not in written:
            os.remove(os.path.join(packs_dir, old))
    app_name, app_code = app_version()
    content = hashlib.sha256("".join(p["sha256"] for p in manifest_packs).encode()).hexdigest()
    manifest = {
        "format": MANIFEST_FORMAT,
        "version": args.version,
        "build": f"{args.version}-{content[:8]}",
        "engine": godot_version(),
        "base": base_id(),
        "app": {"version": app_name, "code": app_code},
        "created": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "packs": manifest_packs,
    }
    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(p["size"] for p in manifest_packs)
    for p in manifest_packs:
        print(f"{p['size'] / 1048576:8.1f} MB  {p['stage']:5}  {p['file']}")
    print(f"{total / 1048576:8.1f} MB in {len(manifest_packs)} packs, build {manifest['build']}, base {manifest['base']}"
          f" ({len(dropped)} base-only files left out)")
    if kept:
        print(f"kept {len(kept)} packs players have whose files didn't change (this machine's import differs): {', '.join(kept)}")
    if like_manifest:
        had = {p["file"] for p in like_manifest["packs"]}
        old_names = {p["name"] for p in like_manifest["packs"]}
        fresh = [p for p in manifest_packs if p["file"] not in had]
        print(f"players on {like_manifest['build']} download {sum(p['size'] for p in fresh) / 1048576:.1f} MB:"
              f" {sum(p['name'] in old_names for p in fresh)} changed packs, {sum(p['name'] not in old_names for p in fresh)} new")
        for p in fresh:
            print(f"  {'changed' if p['name'] in old_names else 'new':7}  {p['size'] / 1048576:6.1f} MB  {p['name']}")


def cmd_build_info(args):
    name, code = app_version()
    info = {"base": base_id(), "app_version": name, "app_code": code, "engine": godot_version()}
    if args.version:
        info["version"] = args.version
        info["build"] = args.version + "-full"
    with open(os.path.join(ROOT, args.out), "w") as f:
        json.dump(info, f, indent=1)
    print(json.dumps(info))


# --- Server -------------------------------------------------------------------

def _request(method, url, data=None, headers=None):
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    req.add_header("User-Agent", "ragoon-city-build/1.0")
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return r.status, r.read(), r.headers
        except urllib.error.HTTPError as e:
            if e.code < 500:
                return e.code, e.read(), e.headers
            err = e
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            err = e
        time.sleep(2 * (attempt + 1))
    raise SystemExit(f"{method} {url} failed: {err}")


def live_manifest():
    code, body, _ = _request("GET", SERVER + "/packs/manifest.json")
    return json.loads(body) if code == 200 else None


def cmd_live(args):
    m = live_manifest()
    print(json.dumps(m, indent=1) if m else "no content on the server yet")


def _auth(method, key, length=0):
    """Upload headers: the worker's UPLOAD_TOKEN, or an Ed25519 signature of
    "METHOD\nkey\nts\nlength" (accepted for pack and web keys only)."""
    if os.environ.get("UPLOAD_TOKEN"):
        return {"x-upload-token": os.environ["UPLOAD_TOKEN"]}
    from cryptography.hazmat.primitives import serialization
    if not os.path.exists(CONTENT_KEY):
        sys.exit(f"set UPLOAD_TOKEN, or put the content upload key at {CONTENT_KEY}")
    priv = serialization.load_pem_private_key(open(CONTENT_KEY, "rb").read(), None)
    ts = str(int(time.time()))
    sig = priv.sign(f"{method}\n{key}\n{ts}\n{int(length)}".encode())
    return {"x-upload-ts": ts, "x-upload-sig": base64.b64encode(sig).decode()}


def _list_keys(prefix):
    keys, cursor = [], None
    while True:
        q = f"{SERVER}/upload-list?prefix={prefix}" + (f"&cursor={urllib.parse.quote(cursor)}" if cursor else "")
        code, body, _ = _request("GET", q, headers=_auth("GET", prefix))
        if code != 200:
            return None
        page = json.loads(body)
        keys += page["keys"]
        cursor = page.get("cursor")
        if not cursor:
            return keys


# KV can serve a value that was just written stale or incomplete for a while,
# so a read-back that doesn't match is tried again after these waits (seconds).
CHECK_WAITS = (0, 15, 45, 90)


def _send_pack(p, out):
    file = p["file"]
    chunks = 0
    with open(os.path.join(out, "packs", file), "rb") as f:
        while True:
            buf = f.read(KV_CHUNK)
            if not buf and chunks:
                break
            key = f"pack:{file}:{chunks}"
            code, body, _ = _request("PUT", f"{SERVER}/upload/{key}", buf, _auth("PUT", key, len(buf)))
            if code != 200:
                sys.exit(f"upload {file} chunk {chunks}: {code} {body[:200]!r}")
            chunks += 1
            if len(buf) < KV_CHUNK:
                break
    meta = json.dumps({"size": p["size"], "chunks": chunks, "chunk": KV_CHUNK, "sha256": p["sha256"]}).encode()
    code, body, _ = _request("PUT", f"{SERVER}/upload/packmeta:{file}", meta,
                             dict(_auth("PUT", "packmeta:" + file, len(meta)), **{"content-type": "application/json"}))
    if code != 200:
        sys.exit(f"upload meta {file}: {code} {body[:200]!r}")


def _read_back(p):
    """None when the server streams the pack back exactly, otherwise what was wrong."""
    h = hashlib.sha256()
    n = 0
    url = f"{SERVER}/packs/{p['file']}?check={time.time():.0f}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "ragoon-city-build/1.0"}),
                                    timeout=600) as r:
            while True:
                buf = r.read(1 << 20)
                if not buf:
                    break
                h.update(buf)
                n += len(buf)
    except Exception as e:  # HTTP errors, a stream cut short, timeouts
        return f"{type(e).__name__}: {e}"
    if n != p["size"]:
        return f"{n} bytes instead of {p['size']}"
    if h.hexdigest() != p["sha256"]:
        return "different bytes"
    return None


def _check_pack(p):
    why = None
    for wait in CHECK_WAITS:
        if wait:
            print(f"  wait  {p['file']}: {why}; checking again in {wait} s")
            time.sleep(wait)
        why = _read_back(p)
        if why is None:
            return None
    return why


def cmd_upload(args):
    manifest = json.load(open(os.path.join(args.out, "manifest.json")))
    live = live_manifest()
    if live and live.get("base") != manifest["base"] and not args.new_base:
        sys.exit(f"The live content is for app base {live.get('base')} and this is {manifest['base']}: "
                 "upload the new APK first (tools/upload_build.sh), then run this again with --new-base.")
    live_files = {q.get("file") for q in (live or {}).get("packs", [])}
    want = {p["file"] for p in manifest["packs"]}
    # Packs neither players nor this set use (left by a stopped run) go first.
    _delete_packs(lambda f: f not in live_files and f not in want, "left over")
    have, to_send = set(), []
    for p in manifest["packs"]:
        code, _, headers = _request("HEAD", f"{SERVER}/packs/{p['file']}")
        if code == 200 and headers.get("x-sha256") == p["sha256"]:
            have.add(p["file"])
        else:
            to_send.append(p)
    if args.kv_limit:
        _check_room(live, manifest, to_send, args.kv_limit)
    sent = 0
    sent_files = set()
    for p in manifest["packs"]:
        file = p["file"]
        if file in have:
            print(f"  have  {file}")
            continue
        _send_pack(p, args.out)
        sent += p["size"]
        sent_files.add(file)
        print(f"  sent  {file} ({p['size'] / 1048576:.1f} MB)")
    # Before switching players over, every pack they don't already get must
    # stream back byte for byte: the ones sent now, and any an earlier run sent
    # but stopped before checking (those count as "have" above).
    for p in manifest["packs"]:
        if p["file"] not in sent_files and p["file"] in live_files:
            continue
        why = _check_pack(p)
        if why:
            print(f"  again {p['file']}: {why}; uploading it again")
            _send_pack(p, args.out)
            sent += p["size"]
            why = _check_pack(p)
        if why:
            sys.exit(f"{p['file']} doesn't come back as uploaded ({why}); manifest NOT switched")
        print(f"  ok    {p['file']}")
    body = json.dumps(manifest).encode()
    code, body, _ = _request("PUT", f"{SERVER}/upload/packs:manifest", body,
                             dict(_auth("PUT", "packs:manifest", len(body)), **{"content-type": "application/json"}))
    if code != 200:
        sys.exit(f"upload manifest: {code} {body[:200]!r}")
    print(f"manifest switched to {manifest['build']} ({sent / 1048576:.1f} MB new)")
    # Delete packs nothing points at any more.
    _delete_packs(lambda f: f not in want, "old")


def _delete_packs(unused, what):
    files = collections.defaultdict(list)
    for prefix in ("pack:", "packmeta:"):
        keys = _list_keys(prefix)
        if keys is None:
            print(f"couldn't list {prefix} keys; not deleting {what} packs")
            return
        for key in keys:
            m = re.match(r"^(?:pack|packmeta):([^:]+)", key)
            if m and unused(m.group(1)):
                files[m.group(1)].append(key)
    for file in sorted(files):
        # packmeta last, so a half-deleted pack never looks complete
        for key in sorted(files[file], key=lambda k: k.startswith("packmeta:")):
            _request("DELETE", f"{SERVER}/upload/{key}", headers=_auth("DELETE", key))
    if files:
        print(f"removed {len(files)} {what} packs")


def _check_room(live, manifest, to_send, limit):
    """Stop before the upload would fill the server's KV storage: what is
    there now (packs, the APK, the browser version) plus the new packs."""
    def size_of(path, headers=None):
        code, _, h = _request("HEAD", SERVER + path, headers=headers)
        return int(h.get("content-length") or 0) if code == 200 else 0
    stored = {}
    for key in _list_keys("packmeta:") or []:
        file = key[len("packmeta:"):]
        stored[file] = size_of(f"/packs/{file}")
    packs = sum(stored.values())
    apk = size_of("/RaGoonCity.apk")
    web = 0
    web_builds = collections.defaultdict(set)
    for key in _list_keys("web:") or []:
        m = re.match(r"^web:([^/]+)/([\w.-]+):\d+$", key)
        if m:
            web_builds[m.group(2)].add(m.group(1))
    for name, builds in web_builds.items():
        # what the current build's copy takes; older builds count the same
        web += size_of(f"/play/{name}", {"Accept-Encoding": "gzip"}) * len(builds)
    new = sum(p["size"] for p in to_send if p["file"] not in stored)
    total = packs + apk + web + new
    mb = lambda b: f"{b / 1e6:.0f} MB"
    line = f"packs {mb(packs)} + APK {mb(apk)} + browser version {mb(web)} + new packs {mb(new)} = {mb(total)}"
    if total > limit:
        sys.exit(f"Not enough room on the download server: {line}, over the {mb(limit)} limit.\n"
                 "Nothing was uploaded. Old packs are only deleted once the new set is live, so the"
                 " new set has to fit next to the live one.")
    print(f"room: {line} of {mb(limit)}")


class _PackHandler(http.server.SimpleHTTPRequestHandler):
    """Serves /packs/manifest.json and /packs/<file> like download/worker.js."""
    out_dir = "."

    def translate_path(self, path):
        path = path.split("?", 1)[0]
        if path == "/packs/manifest.json":
            return os.path.join(self.out_dir, "manifest.json")
        if path.startswith("/packs/") and "/" not in path[len("/packs/"):]:
            return os.path.join(self.out_dir, "packs", path[len("/packs/"):])
        return os.path.join(self.out_dir, "__missing__")

    def log_message(self, fmt, *a):
        sys.stderr.write("serve: " + fmt % a + "\n")


def cmd_serve(args):
    _PackHandler.out_dir = os.path.abspath(args.out)
    http.server.ThreadingHTTPServer(("127.0.0.1", args.port), _PackHandler).serve_forever()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build-info")
    b.add_argument("--out", default="boot/build_info.json")
    b.add_argument("--version", help="only for a full (not thin) build")
    s = sub.add_parser("split")
    s.add_argument("pck")
    s.add_argument("out")
    s.add_argument("--version", required=True)
    s.add_argument("--like", default=os.environ.get("RAGOON_CONTENT_LIKE", "live"),
                   help='keep files in the packs they had: "live" (default), "none", or a build folder')
    u = sub.add_parser("upload")
    u.add_argument("out")
    u.add_argument("--new-base", action="store_true", help="the APK for a new base is already up")
    u.add_argument("--kv-limit", type=float, default=1e9,
                   help="refuse when the server's storage would go over this many bytes (0 = no check)")
    sub.add_parser("live")
    v = sub.add_parser("serve")
    v.add_argument("out")
    v.add_argument("--port", type=int, default=8790)
    args = ap.parse_args()
    os.chdir(ROOT)
    {"build-info": cmd_build_info, "split": cmd_split, "upload": cmd_upload, "live": cmd_live,
     "serve": cmd_serve}[args.cmd](args)


if __name__ == "__main__":
    main()
