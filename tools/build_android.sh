#!/bin/bash
# Build the signed, installable app (APK) for Android phones (arm64).
#   tools/build_android.sh [key.pem]
# The APK is the thin base: engine, project settings and the boot/updater
# screen in boot/. The game itself ships as content packs
# (tools/build_content.sh) that the app downloads and keeps up to date, so a
# new APK is only needed when the base changes (project.godot, the bus
# layout, boot/ or the Godot version). See tools/content/README.md.
# Needs Godot 4.4.1 at ~/tools/godot with the Android export templates in
# ~/.local/share/godot/export_templates/4.4.1.stable/. No Android SDK is needed:
# Godot exports unsigned against a stub SDK folder, then tools/sign_apk.py
# adds the v2 signature. Keep using the same key so new builds install over
# the old one.
set -e
cd "$(dirname "$0")/.."
KEY="${1:-/mnt/project-files/.signing/ragoon_debug_key.pem}"
GODOT="${GODOT:-$HOME/tools/godot}"
tools/android_sdk_stub.sh
# Stamp the base id and app version into the APK (boot/build_info.json).
python3 tools/content/packs.py build-info
mkdir -p build
rm -f build/RaGoonCity-unsigned.apk build/RaGoonCity.apk
"$GODOT" --headless --path . --export-release "Android" build/RaGoonCity-unsigned.apk
python3 tools/sign_apk.py build/RaGoonCity-unsigned.apk build/RaGoonCity.apk "$KEY"
rm -f build/RaGoonCity-unsigned.apk
ls -la build/RaGoonCity.apk
