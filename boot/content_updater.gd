class_name ContentUpdater
extends Node
## Keeps the downloaded game content up to date.
##
## check() fetches the manifest from the download server and works out which
## packs are missing on this phone. download() fetches only those, checks
## each one's SHA-256 and keeps it under user://content/packs/<file>. install()
## records the new set in user://content/installed.json and deletes packs the
## new set no longer uses. Restart the game afterwards (PackMount.restart())
## so every script loads from the new packs.
##
## Packs are content-addressed (name-<sha12>.pck), so a pack that didn't
## change between builds is never downloaded again. Manifest format and
## server routes: tools/content/README.md. The browser build uses this too.
##
## Like pack_mount.gd, this file lives in the base and must not preload
## anything from the packs.

signal progress(done_bytes: int, total_bytes: int, pack_name: String)

enum State {
	UP_TO_DATE,     ## the installed set is the newest and it is mounted
	UPDATE,         ## packs to download (or just a new set to record)
	NEEDS_APP,      ## the newest content needs a newer app (APK)
	SERVER_BEHIND,  ## this app is newer than the content on the server
	OFFLINE,        ## couldn't reach the server
	BAD_MANIFEST,   ## the server answered with something unreadable
}

const DEFAULT_URL := "https://ragoon-city-download.hakipowered.workers.dev/packs/"
const DOWNLOAD_PAGE := "https://ragoon-city-download.hakipowered.workers.dev/"
const MANIFEST_FORMAT := 1
## Web HTTPRequest reads one chunk per frame, so chunks must be big.
const CHUNK_SIZE := 1 << 23
const STALL_SECONDS := 30.0
const TRIES := 4
const SPACE_MARGIN := 64 << 20

var base_url := DEFAULT_URL
## The manifest the server offers (after check()).
var remote: Dictionary = {}
## Manifest entries of the packs that still have to download.
var plan: Array = []
var plan_bytes := 0
var state := State.OFFLINE
## Human-readable reason for the last failure.
var error := ""

var _http: HTTPRequest
var _cancelled := false


func _init() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		base_url = str(cfg.get_value("content", "url", DEFAULT_URL))
	if OS.get_environment("RAGOON_CONTENT_URL") != "":
		base_url = OS.get_environment("RAGOON_CONTENT_URL")
	if not base_url.ends_with("/"):
		base_url += "/"


## Asks the server for the newest content and works out what's missing.
func check(timeout := 8.0) -> State:
	remote = {}
	plan = []
	plan_bytes = 0
	error = ""
	var res := await _fetch_text(base_url + "manifest.json?t=%d" % int(Time.get_unix_time_from_system()), timeout)
	if res.code != 200:
		error = res.error if res.error != "" else "server answered %d" % res.code
		state = State.OFFLINE
		return state
	var m: Variant = JSON.parse_string(res.body)
	if not (m is Dictionary) or int(m.get("format", 0)) != MANIFEST_FORMAT or not (m.get("packs") is Array):
		error = "unreadable manifest"
		state = State.BAD_MANIFEST
		return state
	remote = m
	if str(m.get("base", "")) != PackMount.base_id:
		var need_code := int((m.get("app", {}) as Dictionary).get("code", 0))
		state = State.NEEDS_APP if need_code > PackMount.app_code else State.SERVER_BEHIND
		return state
	var deep := PackMount.mount_error.begins_with("corrupt")
	for p in m.packs:
		if not await _have(p, deep):
			plan.append(p)
			plan_bytes += int(p.get("size", 0))
	var same_set := _files(m) == _files(PackMount.installed) and str(m.get("build")) == PackMount.build_id
	state = State.UP_TO_DATE if plan.is_empty() and same_set and PackMount.mounted else State.UPDATE
	return state


## Downloads the planned packs of the given stages ("boot" is everything the
## game needs to start; "later" can come while the player is on the menu).
## Returns false on failure (see `error`).
func download(stages: Array = ["boot", "later"]) -> bool:
	_cancelled = false
	DirAccess.make_dir_recursive_absolute(PackMount.PACKS_DIR)
	_remove_parts()
	var todo := plan.filter(func(p): return stages.has(str(p.get("stage", "boot"))))
	var total := 0
	for p in todo:
		total += int(p.size)
	var dir := DirAccess.open(PackMount.CONTENT_DIR)
	var free := dir.get_space_left() if dir else 0
	if free > 0 and free < total + SPACE_MARGIN:
		error = "Not enough free space on the phone: the update needs %s and %s is free." % [mb(total + SPACE_MARGIN), mb(free)]
		return false
	var done := 0
	for p in todo:
		var ok := false
		for attempt in TRIES:
			if _cancelled:
				error = "cancelled"
				return false
			ok = await _fetch_pack(p, done, total)
			if ok or _cancelled or attempt == TRIES - 1:
				break
			await get_tree().create_timer(2.0 * (attempt + 1)).timeout
		if not ok:
			return false
		done += int(p.size)
		plan.erase(p)
		plan_bytes -= int(p.size)
	progress.emit(total, total, "")
	return true


## Records `remote` as the installed set and deletes packs it doesn't use.
func install() -> bool:
	var tmp := PackMount.INSTALLED + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		error = "can't write " + tmp
		return false
	f.store_string(JSON.stringify(remote, "\t"))
	f.close()
	if DirAccess.rename_absolute(tmp, PackMount.INSTALLED) != OK:
		error = "can't write " + PackMount.INSTALLED
		return false
	var keep := _files(remote)
	var dir := DirAccess.open(PackMount.PACKS_DIR)
	if dir:
		for name in dir.get_files():
			if not keep.has(name):
				dir.remove(name)
	return true


func cancel() -> void:
	_cancelled = true
	if is_instance_valid(_http):
		_http.cancel_request()


## True when the pack is on disk. Files only get their final name after their
## hash checked out, so the size is enough unless `deep` (a pack failed to
## mount) asks for the hash again.
func _have(p: Dictionary, deep: bool) -> bool:
	var path := PackMount.PACKS_DIR.path_join(str(p.get("file", "")))
	if PackMount.file_size(path) != int(p.get("size", -1)):
		return false
	if deep and await _sha256(path) != str(p.get("sha256", "")):
		DirAccess.remove_absolute(path)
		return false
	return true


func _fetch_pack(p: Dictionary, done_before: int, total: int) -> bool:
	var file := str(p.file)
	var final_path := PackMount.PACKS_DIR.path_join(file)
	var part := final_path + ".part"
	_http = HTTPRequest.new()
	_http.use_threads = not OS.has_feature("web")
	_http.download_chunk_size = CHUNK_SIZE
	_http.accept_gzip = false
	_http.download_file = part
	add_child(_http)
	var outcome := {}
	_http.request_completed.connect(func(result, code, _h, _b): outcome["result"] = result; outcome["code"] = code)
	if _http.request(base_url + file.uri_encode()) != OK:
		_http.queue_free()
		error = "couldn't start the download"
		return false
	var last := -1
	var last_change := Time.get_ticks_msec()
	while outcome.is_empty():
		await get_tree().process_frame
		if _cancelled:
			_http.cancel_request()
			outcome["result"] = HTTPRequest.RESULT_REQUEST_FAILED
			outcome["code"] = 0
			break
		var got := _http.get_downloaded_bytes()
		progress.emit(done_before + got, total, str(p.get("name", file)))
		if got != last:
			last = got
			last_change = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_change > STALL_SECONDS * 1000.0:
			_http.cancel_request()
			outcome["result"] = HTTPRequest.RESULT_TIMEOUT
			outcome["code"] = 0
	_http.queue_free()
	if outcome.result != HTTPRequest.RESULT_SUCCESS or outcome.code != 200:
		DirAccess.remove_absolute(part)
		error = "the download stopped (%s)" % ("server answered %d" % outcome.code if outcome.code else _result_text(outcome.result))
		return false
	if PackMount.file_size(part) != int(p.size):
		DirAccess.remove_absolute(part)
		error = "a download came through incomplete"
		return false
	if await _sha256(part) != str(p.sha256):
		DirAccess.remove_absolute(part)
		error = "a download came through damaged"
		return false
	DirAccess.remove_absolute(final_path)
	if DirAccess.rename_absolute(part, final_path) != OK:
		error = "couldn't save " + file
		return false
	return true


func _sha256(path: String) -> String:
	if OS.has_feature("web"):
		return FileAccess.get_sha256(path)
	var t := Thread.new()
	t.start(func(): return FileAccess.get_sha256(path))
	while t.is_alive():
		await get_tree().process_frame
	return str(t.wait_to_finish())


func _fetch_text(url: String, timeout: float) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return {"code": 0, "body": "", "error": "couldn't start the request"}
	var r: Array = await http.request_completed
	http.queue_free()
	var err := "" if r[0] == HTTPRequest.RESULT_SUCCESS else _result_text(r[0])
	return {"code": int(r[1]), "body": (r[3] as PackedByteArray).get_string_from_utf8(), "error": err}


func _remove_parts() -> void:
	var dir := DirAccess.open(PackMount.PACKS_DIR)
	if dir:
		for name in dir.get_files():
			if name.ends_with(".part"):
				dir.remove(name)


static func _files(m: Dictionary) -> Dictionary:
	var out := {}
	for p in m.get("packs", []):
		out[str(p.get("file", ""))] = true
	return out


static func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "no connection"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "couldn't write to storage"
	return "network error %d" % result


static func mb(bytes: int) -> String:
	return "%.0f MB" % (bytes / 1048576.0) if bytes >= 100 << 20 else "%.1f MB" % (bytes / 1048576.0)
