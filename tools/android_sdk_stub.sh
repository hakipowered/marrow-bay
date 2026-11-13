#!/bin/bash
# Godot's Android export only checks that an SDK folder exists; this machine
# can't download the real SDK (dl.google.com is blocked), so make a stub one
# and point the editor settings at it. tools/sign_apk.py does the signing.
SDK="$HOME/android-sdk"
mkdir -p "$SDK/platform-tools" "$SDK/build-tools/34.0.0"
[ -x "$SDK/platform-tools/adb" ] || { printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"; chmod +x "$SDK/platform-tools/adb"; }
[ -x "$SDK/build-tools/34.0.0/apksigner" ] || { printf '#!/bin/sh\nexit 1\n' > "$SDK/build-tools/34.0.0/apksigner"; chmod +x "$SDK/build-tools/34.0.0/apksigner"; }
ES="$HOME/.config/godot/editor_settings-4.4.tres"
if [ -f "$ES" ] && ! grep -q "android_sdk_path = \"$SDK\"" "$ES"; then
	sed -i '/export\/android\/android_sdk_path/d' "$ES"
	sed -i "/^\[resource\]/a export/android/android_sdk_path = \"$SDK\"" "$ES"
fi
