extends Node
## Mounts the downloaded game content before anything else loads.
##
## The phone app is a thin base: the engine, project settings and this boot
## folder. The game itself (scripts, scenes, models, sounds, films) comes as
## content packs that the boot screen downloads into user://content/packs/
## (see content_updater.gd and tools/content/README.md).
##
## This autoload must stay FIRST in project.godot. Godot loads and constructs
## autoloads one by one, so mounting the packs in _init() means every later
## autoload (GameState, Net, Music...) already loads from the packs.
##
## Run from the project folder (editor, tests) or from a full build, the game
## is already in res:// and nothing is mounted.
##
## Keep this file free of preload() and class_name references to anything in
## the packs: it is compiled before they are mounted.

const CONTENT_DIR := "user://content"
const PACKS_DIR := "user://content/packs"
const INSTALLED := "user://content/installed.json"
const BUILD_INFO := "res://boot/build_info.json"
## A file every content set has. If the base can see it, the base is a full build.
const PROBE := "res://scenes/main_menu.tscn"

## True when the running app has no game content of its own (the thin base).
var is_thin := false
## The app's base id (hash of project.godot, bus layout and engine version).
## Content only mounts when its "base" matches. "dev" when run from source.
var base_id := "dev"
var app_version := "dev"
var app_code := 0
## Manifest of the content set mounted at startup ({} when none).
var installed: Dictionary = {}
## What co-op compares: both phones must run the same content build.
var build_id := "dev"
var version_name := "dev"
## True when the content packs were mounted at startup.
var mounted := false
## Why installed content was not mounted ("" when it was, or none was there).
var mount_error := ""

var _mounted_files := {}


func _init() -> void:
	var info := read_json(BUILD_INFO)
	base_id = str(info.get("base", "dev"))
	app_version = str(info.get("app_version", "dev"))
	app_code = int(info.get("app_code", 0))
	is_thin = not ResourceLoader.exists(PROBE)
	if not is_thin:
		# Full build or project folder: the content is built in.
		build_id = str(info.get("build", "dev"))
		version_name = str(info.get("version", app_version))
		return
	_mount_installed()


func _mount_installed() -> void:
	var m := read_json(INSTALLED)
	if m.is_empty():
		return
	if str(m.get("base", "")) != base_id:
		# Made for another version of the app (the player installed a new
		# APK). The boot screen fetches a matching set; unchanged packs on
		# disk are reused, so only the difference downloads.
		mount_error = "base"
		return
	var packs: Array = []
	# Check everything first: a mounted pack can't be taken back out. Packs
	# marked "later" (films) may still be on their way in the browser build;
	# they're mounted when they arrive.
	for p in m.get("packs", []):
		var path := PACKS_DIR.path_join(str(p.get("file", "")))
		if file_size(path) == int(p.get("size", -1)):
			packs.append(p)
		elif str(p.get("stage", "boot")) != "later":
			mount_error = "missing " + str(p.get("file", ""))
			return
	for p in packs:
		if not mount(str(p.file)):
			mount_error = "corrupt " + str(p.file)
			return
	installed = m
	mounted = true
	build_id = str(m.get("build", "unknown"))
	version_name = str(m.get("version", "?"))


## Mounts one downloaded pack (by file name) over res://. Also used for packs
## that download after startup, like the films in the browser version.
func mount(file: String) -> bool:
	if _mounted_files.has(file):
		return true
	var ok := ProjectSettings.load_resource_pack(PACKS_DIR.path_join(file), true)
	if ok:
		_mounted_files[file] = true
	return ok


func is_pack_mounted(file: String) -> bool:
	return _mounted_files.has(file)


## Starts the game again so every script and autoload loads from the newly
## installed packs.
func restart() -> void:
	if OS.get_environment("RAGOON_BOOT_SMOKE") != "":
		print("boot: restart")  # tests/updater_e2e.sh starts it again
		get_tree().quit()
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
		return
	var args := PackedStringArray() if OS.has_feature("android") else OS.get_cmdline_args()
	var pid := OS.create_instance(args)
	if OS.has_feature("android") and pid >= 0:
		# Android relaunches the activity and ends this process for us.
		return
	get_tree().quit()


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return -1 if f == null else int(f.get_length())
