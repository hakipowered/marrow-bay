#!/bin/bash
# Build a signed, installable APK for Android phones (arm64).
#   tools/build_android.sh [key.pem]
# Needs Godot 4.4.1 at ~/tools/godot with the Android export templates in
# ~/.local/share/godot/export_templates/4.4.1.stable/. No Android SDK is needed:
# Godot exports unsigned (it only checks that an SDK folder exists, so a stub
# one is made), then tools/sign_apk.py adds the v2 signature.
# Keep using the same key so new builds install over the old one.
set -e
cd "$(dirname "$0")/.."
KEY="${1:-/mnt/project-files/.signing/ragoon_debug_key.pem}"
SDK="$HOME/android-sdk"
mkdir -p "$SDK/platform-tools" "$SDK/build-tools/34.0.0"
[ -x "$SDK/platform-tools/adb" ] || { printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"; chmod +x "$SDK/platform-tools/adb"; }
[ -x "$SDK/build-tools/34.0.0/apksigner" ] || { printf '#!/bin/sh\nexit 1\n' > "$SDK/build-tools/34.0.0/apksigner"; chmod +x "$SDK/build-tools/34.0.0/apksigner"; }
ES="$HOME/.config/godot/editor_settings-4.4.tres"
if [ -f "$ES" ] && ! grep -q "android_sdk_path = \"$SDK\"" "$ES"; then
	sed -i '/export\/android\/android_sdk_path/d' "$ES"
	sed -i "/^\[resource\]/a export/android/android_sdk_path = \"$SDK\"" "$ES"
fi
mkdir -p build
rm -f build/RaGoonCity-unsigned.apk build/RaGoonCity.apk
~/tools/godot --headless --path . --export-release "Android" build/RaGoonCity-unsigned.apk
python3 tools/sign_apk.py build/RaGoonCity-unsigned.apk build/RaGoonCity.apk "$KEY"
rm -f build/RaGoonCity-unsigned.apk
ls -la build/RaGoonCity.apk
