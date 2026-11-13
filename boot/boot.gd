extends Control
## The app's first screen. It asks the download server for new game content,
## downloads only the packs that changed (with a progress bar), then restarts
## into the game. When everything is current it goes straight to the title
## screen, and with no connection it plays what's installed.
##
## This scene is part of the thin base, so it must not touch anything from the
## content packs: no game autoloads (GameState, Music...), no preloads from
## assets/, scenes/ or scripts/.

const MENU := "res://scenes/main_menu.tscn"
const FONT := preload("res://boot/Oswald.ttf")
const BG := preload("res://boot/boot_bg.jpg")
const UpdaterScript := preload("res://boot/content_updater.gd")
const RED := Color(0.78, 0.09, 0.06)
const TEXT := Color(0.92, 0.88, 0.8)
const DIM := Color(0.66, 0.6, 0.56)
## Updates bigger than this ask first when there's a version to play meanwhile.
const ASK_ABOVE := 150 << 20

var _updater: ContentUpdater
var _bg: TextureRect
var _title: Label
var _status: Label
var _detail: Label
var _bar: Bar
var _buttons: HBoxContainer
var _corner: Label
var _t := 0.0
var _flicker := 0.0
var _next_flicker := 2.5
var _samples: Array = []
var _leaving := false
var _first_install := false
## tests/updater_e2e.sh sets RAGOON_BOOT_SMOKE: log each step and quit a few
## seconds after the title screen is up.
var _smoke := OS.get_environment("RAGOON_BOOT_SMOKE") != ""


func _ready() -> void:
	if not PackMount.is_thin:
		# Full build or the project folder: the game is already here.
		_go_menu.call_deferred()
		return
	_build_ui()
	_updater = UpdaterScript.new()
	add_child(_updater)
	_updater.progress.connect(_on_progress)
	_first_install = not PackMount.mounted and PackMount.read_json(PackMount.INSTALLED).is_empty()
	_check()


func _check() -> void:
	_clear_buttons()
	_show("Checking for updates", "", -1.0)
	var state := await _updater.check()
	var ver := str(_updater.remote.get("version", "?"))
	_log("state %s, %d packs (%s) to download, mounted %s %s, error '%s'" % [ContentUpdater.State.keys()[state],
		_updater.plan.size(), ContentUpdater.mb(_updater.plan_bytes), PackMount.mounted, PackMount.build_id, _updater.error])
	match state:
		ContentUpdater.State.UP_TO_DATE:
			_go_menu()
		ContentUpdater.State.UPDATE:
			_offer(ver)
		ContentUpdater.State.NEEDS_APP:
			_show("Update %s needs the new app" % ver,
				"Download it from the RaGoon City page and install it over this one. Your saves stay.", 0.0)
			if OS.has_feature("web"):
				_button("Reload", PackMount.restart)
			else:
				_button("Get the new app", func(): OS.shell_open(ContentUpdater.DOWNLOAD_PAGE))
			_play_or_retry()
		ContentUpdater.State.SERVER_BEHIND:
			_show("The update server is still being updated", "Try again in a few minutes.", 0.0)
			_button("Try again", _check)
			_play_button()
		_:
			if PackMount.mounted:
				_go_menu()  # offline: play what's installed
				return
			_show("Can't reach the update server",
				"Connect to the internet to download RaGoon City (%s)." % _updater.error, 0.0)
			_button("Try again", _check)


func _offer(ver: String) -> void:
	var size := _updater.plan_bytes
	if size == 0:
		_install()
		return
	if PackMount.mounted and size > ASK_ABOVE:
		_show("Update %s is ready" % ver, "%s to download. Wi-Fi recommended." % ContentUpdater.mb(size), 0.0)
		_button("Download now", _download)
		_play_button()
		return
	_download()


func _download() -> void:
	var ver := str(_updater.remote.get("version", "?"))
	_clear_buttons()
	_samples.clear()
	_show("Downloading RaGoon City" if _first_install else "Downloading update %s" % ver, "", 0.0)
	if PackMount.mounted:
		var play_old := func() -> void:
			_updater.cancel()
			_go_menu()
		_button("Play %s instead" % PackMount.version_name, play_old, true, false)
	DisplayServer.screen_set_keep_on(true)
	var ok := await _updater.download()
	DisplayServer.screen_set_keep_on(false)
	if _leaving:
		return
	_log("download %s %s" % ["ok" if ok else "failed:", _updater.error])
	if not ok:
		_clear_buttons()
		_show("Download stopped", _updater.error.substr(0, 1).to_upper() + _updater.error.substr(1) + ".", _bar.value)
		_button("Try again", _check)
		_play_button()
		return
	_install()


func _install() -> void:
	_clear_buttons()
	if not _updater.install():
		_show("Couldn't install the update", _updater.error, 1.0)
		_button("Try again", _check)
		return
	_show("RaGoon City is ready" if _first_install else "Update installed", "Starting the game", 1.0)
	_log("installed %s, restarting" % _updater.remote.get("build", "?"))
	await get_tree().create_timer(0.8).timeout
	PackMount.restart()


func _on_progress(done: int, total: int, _pack: String) -> void:
	if total <= 0:
		return
	_bar.value = clampf(float(done) / total, 0.0, 1.0)
	var now := Time.get_ticks_msec()
	_samples.append([now, done])
	while _samples.size() > 2 and now - int(_samples[0][0]) > 4000:
		_samples.pop_front()
	var line := "%s of %s" % [ContentUpdater.mb(done), ContentUpdater.mb(total)]
	var span := now - int(_samples[0][0])
	if span > 800:
		var rate := (done - int(_samples[0][1])) * 1000.0 / span
		line += "  ·  %.1f MB/s" % (rate / 1048576.0)
	if _first_install:
		line += "  ·  Wi-Fi recommended"
	_detail.text = line


func _go_menu() -> void:
	if _leaving:
		return
	_leaving = true
	_log("to the title screen with build %s" % PackMount.build_id)
	var tree := get_tree()
	tree.change_scene_to_file(MENU)
	if _smoke:
		tree.create_timer(5.0).timeout.connect(func():
			print("boot: title screen is %s" % tree.current_scene.scene_file_path)
			if OS.get_environment("RAGOON_BOOT_SMOKE") != "level":
				tree.quit()
				return
			# Also start the first level from the packs and let it run.
			tree.change_scene_to_file(tree.root.get_node("GameState").level_path)
			tree.create_timer(12.0).timeout.connect(func():
				print("boot: level is %s" % tree.current_scene.scene_file_path)
				tree.quit()))


func _log(text: String) -> void:
	if _smoke:
		print("boot: ", text)


func _play_or_retry() -> void:
	if PackMount.mounted:
		_play_button()
	else:
		_button("Try again", _check, true)


func _play_button() -> void:
	if PackMount.mounted:
		_button("Play %s" % PackMount.version_name, _go_menu, true)


# --- Look -------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var black := ColorRect.new()
	black.color = Color(0.02, 0.015, 0.015)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	# Key art of the city, dimmed, drifting slowly closer.
	_bg = TextureRect.new()
	_bg.texture = BG
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.modulate = Color(0.42, 0.4, 0.4)
	add_child(_bg)
	# Darken the bottom so the progress text reads over the art.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.92))
	grad.add_point(0.45, Color(0, 0, 0, 0.15))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 8
	gt.height = 256
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	_title = _label("RAGOON CITY", 150, RED)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_title.add_theme_constant_override("shadow_offset_x", 0)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	_title.add_theme_constant_override("shadow_outline_size", 18)
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.2
	_title.anchor_bottom = 0.2
	_title.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_title)
	var tag := _label("THE CITY HAS GONE SILENT", 34, DIM)
	tag.anchor_left = 0.0
	tag.anchor_right = 1.0
	tag.anchor_top = 0.2
	tag.anchor_bottom = 0.2
	tag.offset_top = 110
	tag.offset_bottom = 160
	add_child(tag)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	box.anchor_left = 0.12
	box.anchor_right = 0.88
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -470
	box.offset_bottom = -110
	add_child(box)
	_status = _label("", 46, TEXT)
	box.add_child(_status)
	_bar = Bar.new()
	_bar.custom_minimum_size = Vector2(0, 16)
	box.add_child(_bar)
	_detail = _label("", 30, DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	box.add_child(spacer)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 28)
	box.add_child(_buttons)

	_corner = _label(_version_text(), 24, Color(0.5, 0.46, 0.44))
	_corner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_corner.offset_left = -900
	_corner.offset_top = -64
	_corner.offset_right = -36
	_corner.offset_bottom = -24
	add_child(_corner)


func _version_text() -> String:
	var s := "App %s" % PackMount.app_version
	if PackMount.mounted:
		s += "  ·  Game %s" % PackMount.version_name
	return s


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
	return l


func _show(status: String, detail: String, fraction: float) -> void:
	_status.text = status
	_detail.text = detail
	_bar.value = fraction


## `waits`: the screen now waits for the player (smoke runs stop there).
func _button(text: String, action: Callable, quiet := false, waits := true) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 104)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.06, 0.9) if quiet else Color(0.42, 0.06, 0.04, 0.95)
	sb.border_color = Color(0.6, 0.15, 0.1) if quiet else Color(0.85, 0.22, 0.14)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	var down := sb.duplicate()
	down.bg_color = Color(0.55, 0.1, 0.07, 1.0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", down)
	b.pressed.connect(action)
	_buttons.add_child(b)
	if _smoke and waits:
		_log("waiting on: " + text)
		get_tree().create_timer(1.0).timeout.connect(get_tree().quit, CONNECT_ONE_SHOT)


func _clear_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()


func _process(delta: float) -> void:
	if _bg == null:
		return
	_t += delta
	# Slow push-in on the art, like a camera creeping closer.
	_bg.pivot_offset = _bg.size * 0.5
	_bg.scale = Vector2.ONE * (1.04 + 0.04 * sin(_t * 0.07))
	# The title flickers now and then like a failing neon sign.
	_next_flicker -= delta
	if _next_flicker <= 0.0:
		_flicker = randf_range(0.12, 0.3)
		_next_flicker = randf_range(2.0, 6.0)
	_flicker = maxf(0.0, _flicker - delta)
	var lit := 1.0 if _flicker <= 0.0 else (0.35 if fmod(_t * 23.0, 1.0) < 0.5 else 0.9)
	_title.modulate = Color(1, 1, 1, lit)
	if _corner:
		_corner.text = _version_text()


## Thin progress bar: a dim track, a red fill with a bright head. A value
## below zero shows a sweeping glint while the size isn't known yet.
class Bar extends Control:
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if value < 0.0:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := size.y * 0.5
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.08)
		track.set_corner_radius_all(int(rad))
		draw_style_box(track, r)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.78, 0.09, 0.06)
		fill.set_corner_radius_all(int(rad))
		fill.shadow_color = Color(0.9, 0.12, 0.06, 0.45)
		fill.shadow_size = 10
		if value < 0.0:
			var w := size.x * 0.22
			var x := fmod(_t * 0.5, 1.0) * (size.x + w) - w
			var x0 := maxf(0.0, x)
			var x1 := minf(size.x, x + w)
			if x1 - x0 > size.y:
				draw_style_box(fill, Rect2(Vector2(x0, 0), Vector2(x1 - x0, size.y)))
			return
		var fw := size.x * clampf(value, 0.0, 1.0)
		if fw >= size.y:
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(fw, size.y)))
			draw_circle(Vector2(fw - rad, rad), rad * 0.55, Color(1.0, 0.55, 0.4, 0.9))
