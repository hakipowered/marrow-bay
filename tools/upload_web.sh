#!/bin/bash
# Upload build/web/ (from tools/build_web.sh) to the download worker, which
# serves it at https://ragoon-city-download.hakipowered.workers.dev/play/
#   tools/upload_web.sh <version>      e.g. tools/upload_web.sh 0.11
# Uploads are signed with the content key (tools/web/upload_auth.py, private
# half in /mnt/project-files/.signing/content_upload_ed25519.pem); it can only
# write web:/pack: keys, never the APK. Text and wasm/pck files are stored gzipped, everything in
# 20 MiB chunks (KV caps values at 25 MiB) under web:<build>/<file>:<i>. The
# web:manifest switch comes last, so players never load a half-uploaded build;
# then every older build except the previous one is deleted.
set -e
cd "$(dirname "$0")/.."
VERSION="${1:?version, e.g. 0.11}"
AUTH=tools/web/upload_auth.py
python3 $AUTH --public > /dev/null || { echo "no content upload key (see $AUTH)"; exit 1; }
URL="${RAGOON_DOWNLOAD_URL:-https://ragoon-city-download.hakipowered.workers.dev}"
DIR=build/web
[ -f "$DIR/index.html" ] || { echo "no $DIR/index.html; run tools/build_web.sh"; exit 1; }
BUILD="$VERSION-$(git rev-parse --short=7 HEAD)-$(date -u +%m%d%H%M)"
OLD=$(curl -sSI "$URL/play/index.html" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-ragoon-build"{print $2}')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

put() {  # put <key> <file>
	local r try
	for try in 1 2 3 4 5; do
		r=$(curl -sS -X PUT $(python3 $AUTH PUT "$1" $(stat -c %s "$2")) --data-binary @"$2" "$URL/upload/$1" || true)
		[ "${r#ok}" != "$r" ] && return 0
		sleep $((try * 2))
	done
	echo "upload of $1 failed: $r"; exit 1
}

echo "uploading build $BUILD (live now: ${OLD:-none})"
MANIFEST="$TMP/manifest.json"
echo "{\"build\": \"$BUILD\", \"version\": \"$VERSION\", \"files\": {" > "$MANIFEST"
first=1
for f in "$DIR"/*; do
	name=$(basename "$f")
	size=$(stat -c %s "$f"); sha=$(sha256sum "$f" | cut -d' ' -f1)
	src="$f"; gz=false
	case "$name" in
		*.html|*.js|*.wasm|*.pck|*.json|*.webmanifest)
			gzip -9 -n -c "$f" > "$TMP/$name.gz"
			# Keep gzip only when it actually saves something.
			if [ $(stat -c %s "$TMP/$name.gz") -lt $((size * 95 / 100)) ]; then src="$TMP/$name.gz"; gz=true; fi ;;
	esac
	stored=$(stat -c %s "$src")
	rm -f "$TMP"/part_*
	split -b 20971520 -d -a 3 "$src" "$TMP/part_"
	i=0
	for part in "$TMP"/part_*; do put "web:$BUILD/$name:$i" "$part"; i=$((i + 1)); done
	[ $first = 1 ] || echo "," >> "$MANIFEST"; first=0
	printf '"%s": {"size": %s, "stored": %s, "chunks": %s, "sha256": "%s", "gzip": %s}' "$name" "$size" "$stored" "$i" "$sha" "$gz" >> "$MANIFEST"
	echo "  $name  $((size / 1024)) KB -> $((stored / 1024)) KB in $i chunk(s)"
done
echo "}}" >> "$MANIFEST"
python3 -m json.tool "$MANIFEST" > /dev/null
put web:manifest "$MANIFEST"

# KV takes up to a minute to show the new manifest everywhere; check until
# every file comes back byte-identical.
for try in $(seq 1 20); do
	ok=1
	for f in "$DIR"/*; do
		name=$(basename "$f")
		got=$(curl -sS --compressed "$URL/play/$name" | sha256sum | cut -d' ' -f1)
		[ "$got" = "$(sha256sum "$f" | cut -d' ' -f1)" ] || { ok=0; break; }
	done
	[ $ok = 1 ] && break
	sleep 6
done
[ $ok = 1 ] || { echo "the worker isn't serving build $BUILD yet ($name differs)"; exit 1; }
echo "browser version live: $URL/play/  (build $BUILD)"

# Delete builds older than the previous one.
keys=$(curl -sS $(python3 $AUTH GET web: 0) "$URL/upload-list?prefix=web:" | python3 -c "import json,sys; print('\n'.join(json.load(sys.stdin)['keys']))")
for k in $keys; do
	b=${k#web:}; b=${b%%/*}
	[ "$k" = "web:manifest" ] || [ "$b" = "$BUILD" ] || [ "$b" = "$OLD" ] && continue
	curl -sS -X DELETE $(python3 $AUTH DELETE "$k" 0) "$URL/upload/$k" > /dev/null
done
