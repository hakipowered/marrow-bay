#!/bin/bash
# Upload build/RaGoonCity.apk to the download page (download/worker.js), which
# serves it at https://ragoon-city-download.hakipowered.workers.dev/
# The APK is the thin base: only upload it when the base changed (see
# tools/content/README.md); game updates go up as content packs.
#   UPLOAD_TOKEN=... tools/upload_build.sh <version>
# The token is the worker's UPLOAD_TOKEN secret (set it again by redeploying
# the worker with a new secret_text binding if it's lost). KV values are capped
# at 25 MiB, so the APK goes up in 20 MiB chunks plus a manifest.
set -e
cd "$(dirname "$0")/.."
: "${UPLOAD_TOKEN:?set UPLOAD_TOKEN}"
VERSION="${1:?version, e.g. 0.2}"
URL=${RAGOON_DOWNLOAD_URL:-https://ragoon-city-download.hakipowered.workers.dev}
APK=build/RaGoonCity.apk
TMP=$(mktemp -d)
split -b 20971520 -d -a 3 "$APK" "$TMP/part_"
i=0
for f in "$TMP"/part_*; do
	for try in 1 2 3 4; do
		r=$(curl -sS -X PUT -H "x-upload-token: $UPLOAD_TOKEN" --data-binary @"$f" "$URL/upload/apk:$i" || true)
		[ "${r#ok}" != "$r" ] && break
		[ $try = 4 ] && { echo "chunk $i failed: $r"; exit 1; }
		sleep $((try * 2))
	done
	i=$((i + 1))
done
SIZE=$(stat -c %s "$APK"); SHA=$(sha256sum "$APK" | cut -d' ' -f1)
curl -sS -X PUT -H "x-upload-token: $UPLOAD_TOKEN" -H "content-type: application/json" \
	--data "{\"chunks\": $i, \"size\": $SIZE, \"sha256\": \"$SHA\", \"version\": \"$VERSION\"}" "$URL/upload/apk:manifest"
echo
rm -rf "$TMP"
# Check the link serves exactly this file.
GOT=$(curl -sS "$URL/RaGoonCity.apk" | sha256sum | cut -d' ' -f1)
[ "$GOT" = "$SHA" ] && echo "download link OK ($i chunks, $SIZE bytes)" || { echo "checksum mismatch"; exit 1; }
# Delete chunks left over from a bigger APK (the full 0.10 APK had 29; the
# thin one has 2), so they don't use up the KV storage.
KEYS=$(curl -sS -H "x-upload-token: $UPLOAD_TOKEN" "$URL/upload-list?prefix=apk:" || true)
echo "$KEYS" | python3 -c "
import json, sys
try:
    keys = json.load(sys.stdin)['keys']
except Exception:
    sys.exit()
for k in keys:
    n = k.split(':', 1)[1]
    if n.isdigit() and int(n) >= $i:
        print(k)" | while read -r k; do
	curl -sS -X DELETE -H "x-upload-token: $UPLOAD_TOKEN" "$URL/upload/$k" > /dev/null && echo "removed old $k"
done
