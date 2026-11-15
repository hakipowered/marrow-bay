extends Node
## Browser quality profile (the web version on a phone's Chrome / Samsung
## Internet). The browser draws with Godot's Compatibility (WebGL 2) renderer,
## which costs far more per pixel and per light than the app's Mobile
## renderer, and it rendered every frame at the screen's full resolution
## (about 4 million pixels on a Fold) with the desktop shadow settings. On a
## phone that was a few frames a second: the survivor could barely move.
##
## What changes on the web, and only there (the app keeps its own settings):
## - Shadows use the settings the app already uses on phones: 2048 px atlases
##   and hard-edged filtering (the desktop default was 4096 px, soft).
## - The 3D picture renders at a lower resolution and is scaled up to the
##   screen; menus, the HUD and text stay sharp at full resolution. The scale
##   adapts to the phone: it drops when frames run slow and climbs back when
##   there's headroom, so a fast phone keeps a sharper picture.
## - The moon's shadow is drawn in two distance bands instead of four (it is
##   redrawn every frame, once per band).
## - A shadow budget: only the few lamps and windows that matter most where
##   the camera is keep their shadows (the light itself always stays on); the
##   others fade their shadow out. Each shadowed light makes the browser draw
##   everything it touches once more (an omni light six times over for its
##   shadow), so the Great Hall's row of moonlit windows drew the hall nine
##   times over. "Matter most" is how much of the light would leak, without
##   its shadow, through a wall or past a shelf onto what you see (measured
##   with a few dozen physics rays, see _pick_begin), so a light that lost
##   its shadow is one whose leak you'd hardly see. How many adapts like the
##   scale: SHADOW_START to begin with, up to
##   SHADOW_BUDGET on a phone with frames to spare, down to none on a slow
##   one. The survivors' own torches and the moon always keep theirs.
## - The level's static pieces are batched (scripts/world/static_batch.gd).
##
## Level scripts don't need to know about any of this: LevelBase calls
## apply_level() once the level is built, and lights added later (fires, the
## elevator car, story lights) join the budget as they enter the tree.
## docs/web_performance.md has the numbers; tests/perf_probe.gd measures it.

## How many lamp / window shadows are drawn at once at most (plus the
## torches and the moon), and how many to start with: a phone with frames to
## spare climbs to SHADOW_BUDGET, a slow one goes down to none.
const SHADOW_BUDGET := 4
const SHADOW_START := 2
## A light only takes a budget place from one that's this much less
## important (no flicking between two lights that matter about as much).
const SHADOW_HYSTERESIS := 0.85
## Seconds for a shadow to fade in or out.
const SHADOW_FADE := 0.4

## Render scale bounds and the start, as a share of the screen's pixels on
## each axis. START is picked from the screen size (see _start_scale).
const MIN_SCALE := 0.5
const MAX_SCALE := 1.0
## Aim for about this many 3D pixels to start with (a 1280 x 1066 picture).
const START_PIXELS := 1280.0 * 1066.0
## Frame time targets (ms) for adapting: above SLOW_MS something steps down,
## under FAST_MS (sustained) it steps back up.
const SLOW_MS := 1000.0 / 28.0
const FAST_MS := 1000.0 / 50.0
const STEP_DOWN := 0.08
const STEP_UP := 0.04

static var forced := false
## Lamp / window shadows drawn right now (tests/perf_probe.gd sets it).
static var shadow_budget := SHADOW_START
## Whether the render scale and shadow budget follow the frame rate (tests
## that measure a fixed setting turn it off).
static var adaptive := true
static var _global_done := false

## True in the browser build (or when a test forces the profile on).
static func active() -> bool:
	return forced or OS.has_feature("web")

## Once per run, before the first level: shadow atlases and filtering as on
## the phone app, and the starting 3D render scale.
static func apply_global(tree: SceneTree) -> void:
	if not active() or _global_done:
		return
	_global_done = true
	var vp := tree.root
	vp.positional_shadow_atlas_size = 2048
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _start_scale(vp)

static func _start_scale(vp: Viewport) -> float:
	var size := Vector2(vp.get_visible_rect().size)
	if vp is Window:
		size = Vector2((vp as Window).size)
	var px := maxf(size.x * size.y, 1.0)
	return clampf(sqrt(START_PIXELS / px), MIN_SCALE, MAX_SCALE)

## A built level: tune its lights now and any added later, and start the
## adaptive render scale.
static func apply_level(level: Node, force := false) -> void:
	if force:
		forced = true
	if not active():
		return
	apply_global(level.get_tree())
	if level is Node3D and not level.has_node("StaticBatches"):
		preload("res://scripts/world/static_batch.gd").run(level)
	var n: Node = level.get_node_or_null("WebQuality")
	if n == null:
		n = load("res://scripts/world/web_quality.gd").new()
		n.name = "WebQuality"
		level.add_child(n)
	for l in level.find_children("*", "Light3D", true, false):
		n.track(l)

## Takes a light into the profile: the moon's shadow in two splits; other
## shadowed lights (not the survivors' torches) join the shadow budget.
func track(l) -> void:
	# Untyped: a deferred call can arrive after the light was freed (a muzzle
	# flash's light lives for a few frames).
	if not is_instance_valid(l) or not l is Light3D or not l.shadow_enabled or l.has_meta("web_shadow"):
		return
	l.set_meta("web_shadow", true)
	if l is DirectionalLight3D:
		# The moon: its shadow map is redrawn every frame, once per split.
		# Two splits instead of four halve that. (Its shadow stays: it is
		# what keeps moonlight out of the rooms.)
		var d := l as DirectionalLight3D
		if d.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			d.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		return
	if _on_player(l):
		return
	l.set_meta("web_shadow_opacity", l.shadow_opacity)
	_budget_lights.append(l)
	_budget_t = 0.0

static func _on_player(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.is_in_group("players"):
			return true
		p = p.get_parent()
	return false

# ---- adapting to the phone (the node LevelBase adds) ----
# Two knobs: the 3D render scale and how many lamps / windows keep their
# shadows. Every 1.5 s the average frame time is checked. Slow: one knob
# steps down (the picture's sharpness first while it's above SHARP_SCALE,
# then lamp shadows, then sharpness again), and if that step didn't make
# frames faster it was the wrong knob (the phone was busy elsewhere): it goes
# back and is left alone for a while. Fast for a few checks in a row: the
# last thing given up comes back. A knob that keeps making frames slow when
# raised waits longer each time before it's tried again, so the picture
# doesn't keep flicking between two settings.

## Above this scale, sharpness is given up before shadows; below it, shadows
## first.
const SHARP_SCALE := 0.75
const CHECK_S := 1.5
## A step down must make frames at least this much faster to stay.
const MUST_GAIN := 0.92

var _acc_ms := 0.0
var _frames := 0
var _fast_windows := 0
var _cooldown := 3.0   # let the level settle (shader compiles) before judging
## The last step down, still to be judged: {knob, from, ms}.
var _pending := {}
## The last step up, for 2 checks: {knob, from, left}.
var _raised := {}
## Seconds a knob is left alone after a step down that didn't help, and how
## long the next such hold will be (it doubles each time).
var _hold := {"scale": 0.0, "shadow": 0.0}
var _hold_next := {"scale": 20.0, "shadow": 20.0}
## Fast checks in a row needed before a knob steps back up (doubles each
## time raising it made frames slow).
var _raise_wait := {"scale": 3, "shadow": 3}
## Lights in the shadow budget, and the time to the next re-pick.
var _budget_lights: Array[Light3D] = []
var _budget_t := 0.0
## A pick in progress: the points in view, and the lights still to weigh
## (a few each frame, so a pick never makes one frame late).
var _pick_pts: Array = []
var _pick_queue: Array[Light3D] = []
var _pick_space: PhysicsDirectSpaceState3D

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(n: Node) -> void:
	if n is Light3D:
		# Some code turns the shadow on right after add_child, so look once
		# the frame's setup is done.
		track.call_deferred(n)

func _process(delta: float) -> void:
	var vp := get_viewport()
	if vp == null or get_tree().paused:
		return
	_budget_t -= delta
	if not _pick_queue.is_empty():
		_pick_step()
	elif _budget_t <= 0.0:
		_budget_t = 0.25
		_pick_begin(vp.get_camera_3d())
	_cooldown -= delta
	for k in _hold:
		_hold[k] -= delta
	# Long hitches (loading, a cutscene starting) say nothing about the
	# steady frame rate.
	if delta > 0.25 or not adaptive:
		return
	_acc_ms += delta * 1000.0
	_frames += 1
	if _acc_ms < CHECK_S * 1000.0:
		return
	var avg := _acc_ms / _frames
	_acc_ms = 0.0
	_frames = 0
	if _cooldown <= 0.0:
		_judge(avg)

func _judge(avg: float) -> void:
	if not _pending.is_empty():
		var p := _pending
		_pending = {}
		if avg > float(p["ms"]) * MUST_GAIN:
			# No better: this knob wasn't the problem.
			var k0: String = p["knob"]
			_set_knob(k0, p["from"])
			_hold[k0] = _hold_next[k0]
			_hold_next[k0] = minf(_hold_next[k0] * 2.0, 300.0)
			_cooldown = 1.0
			return
	if not _raised.is_empty():
		_raised["left"] -= 1
		if avg > SLOW_MS:
			# Raising it made frames slow again: back down, and wait longer
			# before the next try.
			var k: String = _raised["knob"]
			_set_knob(k, _raised["from"])
			_raise_wait[k] = mini(_raise_wait[k] * 2, 200)
			_raised = {}
			_fast_windows = 0
			_cooldown = 1.0
			return
		if _raised["left"] <= 0:
			_raised = {}
	if avg > SLOW_MS:
		_fast_windows = 0
		var k := _knob_to_lower()
		if k != "":
			var from = _get_knob(k)
			_pending = {"knob": k, "from": from, "ms": avg}
			_set_knob(k, _lower(k, from))
			_cooldown = 1.0
	elif avg < FAST_MS:
		_fast_windows += 1
		var k := _knob_to_raise()
		if k != "" and _fast_windows >= _raise_wait[k]:
			var from = _get_knob(k)
			_set_knob(k, _higher(k, from))
			_raised = {"knob": k, "from": from, "left": 2}
			_fast_windows = 0
			_cooldown = 1.0
	else:
		_fast_windows = 0

func _knob_to_lower() -> String:
	var s := get_viewport().scaling_3d_scale
	if s > SHARP_SCALE + 0.001 and _hold["scale"] <= 0.0:
		return "scale"
	if shadow_budget > 0 and _hold["shadow"] <= 0.0:
		return "shadow"
	if s > MIN_SCALE + 0.001 and _hold["scale"] <= 0.0:
		return "scale"
	return ""

## The reverse of _knob_to_lower: what was given up last comes back first.
func _knob_to_raise() -> String:
	var s := get_viewport().scaling_3d_scale
	if s < SHARP_SCALE - 0.001:
		return "scale"
	if shadow_budget < SHADOW_BUDGET:
		return "shadow"
	if s < MAX_SCALE - 0.001:
		return "scale"
	return ""

func _get_knob(k: String):
	return get_viewport().scaling_3d_scale if k == "scale" else shadow_budget

func _set_knob(k: String, v) -> void:
	if k == "scale":
		get_viewport().scaling_3d_scale = v
	else:
		shadow_budget = v
		_budget_t = 0.0

func _lower(k: String, v):
	if k == "scale":
		return maxf(MIN_SCALE, v - STEP_DOWN)
	return maxi(0, v - 1)

func _higher(k: String, v):
	if k == "scale":
		return minf(MAX_SCALE, v + STEP_UP)
	return mini(SHADOW_BUDGET, v + 1)

# ---- shadow budget ----

## Where a light's importance is measured: rays through a grid on the
## screen (what you see) and a ring around the camera, weighted less (what
## you'd see on turning round, so turning doesn't swap shadows at once), to
## the first wall, floor or shelf they hit.
const VIEW_GRID := Vector2i(6, 4)
const RING_RAYS := 8
const RING_WEIGHT := 0.35
const VIEW_DIST := 30.0
## Light that reaches a point in the open counts for this share of light
## that would reach it through something (a leak): a shadow only changes the
## picture where something stands between the light and what you see, and
## the open share stands for the small things the rays pass between.
const OPEN_WEIGHT := 0.15
## A survivor on screen counts as this many points in view (each of two).
const PLAYER_WEIGHT := 3.0
## Below this a light lights nothing you see: no shadow even with places free.
const MIN_IMPORTANCE := 0.0005
## The most microseconds one frame of the last pick took
## (tests/perf_probe.gd prints it).
static var last_pick_us := 0

## Lights weighed per frame while a pick is in progress.
const PICK_PER_FRAME := 4

## Gives the shadow_budget most important lights their shadows (fading in)
## and fades the others' out. A light's importance is how much of its light
## would land, without its shadow, on what you see from behind something (a
## wall, a shelf, a door): a lamp in the next room leaking through the wall,
## or the vault's own lamp shining through the shelves onto the boxes under
## them. That's measured with physics rays at a few dozen points in view
## (see _sample_points), so a lamp that would leak where you look wins over
## a nearer one whose light reaches nothing you see. A pick starts every
## 0.25 s and weighs PICK_PER_FRAME lights a frame.
func _pick_begin(cam: Camera3D) -> void:
	if cam == null or not cam.is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	_pick_space = cam.get_world_3d().direct_space_state
	_pick_pts = _sample_points(cam, _pick_space)
	for i in range(_budget_lights.size() - 1, -1, -1):
		if not is_instance_valid(_budget_lights[i]):
			_budget_lights.remove_at(i)
	_pick_queue = _budget_lights.duplicate()
	last_pick_us = Time.get_ticks_usec() - t0
	if _pick_queue.is_empty():
		return
	_pick_step()

func _pick_step() -> void:
	var t0 := Time.get_ticks_usec()
	for _n in PICK_PER_FRAME:
		if _pick_queue.is_empty():
			break
		var l: Light3D = _pick_queue.pop_back()
		if not is_instance_valid(l):
			continue
		var imp := 0.0
		if l.is_visible_in_tree() and l.light_energy > 0.0:
			imp = _leak(l, _pick_pts, _pick_space)
		# Smoothed over picks: a ray slipping past a table leg doesn't flick
		# a shadow.
		l.set_meta("web_shadow_imp", lerpf(float(l.get_meta("web_shadow_imp", imp)), imp, 0.5))
	last_pick_us = maxi(last_pick_us, Time.get_ticks_usec() - t0)
	if _pick_queue.is_empty():
		_pick_finish()

func _pick_finish() -> void:
	var scored: Array = []
	for l in _budget_lights:
		if not is_instance_valid(l):
			continue
		var imp: float = l.get_meta("web_shadow_imp", 0.0)
		if l.get_meta("web_shadow_on", false):
			imp /= SHADOW_HYSTERESIS
		scored.append([imp, l])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	for i in scored.size():
		var l: Light3D = scored[i][1]
		_set_shadow(l, i < shadow_budget and scored[i][0] > MIN_IMPORTANCE)

## Points the camera sees, as [position, normal, weight].
func _sample_points(cam: Camera3D, space: PhysicsDirectSpaceState3D) -> Array:
	var pts: Array = []
	var size := cam.get_viewport().get_visible_rect().size
	for y in VIEW_GRID.y:
		for x in VIEW_GRID.x:
			var px := Vector2((x + 0.5) / VIEW_GRID.x, (y + 0.5) / VIEW_GRID.y) * size
			_cast(space, cam.project_ray_origin(px), cam.project_ray_normal(px), 1.0, pts)
	var at := cam.global_position
	for i in RING_RAYS:
		var a := TAU * i / RING_RAYS
		_cast(space, at, Vector3(cos(a), -0.35, sin(a)).normalized(), RING_WEIGHT, pts)
	# The survivors themselves: a lamp's light on her hair while she stands
	# behind a pillar from it shows more than a patch of wall. No normal: a
	# light from any side lights some of her you can see.
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node3D and p.is_inside_tree():
			for h in [1.0, 1.55]:
				var pt: Vector3 = (p as Node3D).global_position + Vector3.UP * h
				if pt.distance_to(at) < VIEW_DIST and cam.is_position_in_frustum(pt):
					pts.append([pt, Vector3.ZERO, PLAYER_WEIGHT])
	return pts

func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, w: float, pts: Array) -> void:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * VIEW_DIST, 1))
	if not hit.is_empty():
		pts.append([hit.position + hit.normal * 0.05, hit.normal, w])

## How much of the light would reach the points from behind something with
## its shadow off (light reaching them in the open counts OPEN_WEIGHT).
## Falloff as the renderer has it: the range window, the decay, the angle to
## the surface and, for a spot, its cone.
func _leak(l: Light3D, pts: Array, space: PhysicsDirectSpaceState3D) -> float:
	var pos := l.global_position
	var reach := 1.0
	var decay := 1.0
	var cut := -2.0
	var aim := Vector3.ZERO
	if l is OmniLight3D:
		reach = (l as OmniLight3D).omni_range
		decay = (l as OmniLight3D).omni_attenuation
	elif l is SpotLight3D:
		var sl := l as SpotLight3D
		reach = sl.spot_range
		decay = sl.spot_attenuation
		cut = cos(deg_to_rad(sl.spot_angle))
		aim = -sl.global_transform.basis.z
	var strength := l.light_energy * l.light_color.get_luminance()
	var sum := 0.0
	for p in pts:
		var to: Vector3 = pos - p[0]
		var d := to.length()
		if d >= reach or d < 0.01:
			continue
		var ldir := to / d
		var n: Vector3 = p[1]
		var facing := n.dot(ldir) if n != Vector3.ZERO else 0.6
		if facing <= 0.0:
			continue
		var cone := 1.0
		if cut > -2.0:
			var c := aim.dot(-ldir)
			if c <= cut:
				continue
			cone = clampf((c - cut) / maxf(1.0 - cut, 0.001) * 4.0, 0.0, 1.0)
		var nd := d / reach
		nd *= nd
		nd *= nd
		var lit := strength * pow(1.0 - nd, 2.0) / pow(maxf(d, 1.0), decay) * facing * cone * float(p[2])
		if lit < 0.0005:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p[0], pos, 1))
		var blocked := not hit.is_empty() and (hit.position as Vector3).distance_to(pos) > 0.3
		sum += lit if blocked else lit * OPEN_WEIGHT
	return sum

func _set_shadow(l: Light3D, on: bool) -> void:
	if l.get_meta("web_shadow_on", true) == on and l.has_meta("web_shadow_on"):
		return
	l.set_meta("web_shadow_on", on)
	if l.has_meta("web_shadow_tween"):
		var old: Tween = l.get_meta("web_shadow_tween")
		if old and old.is_valid():
			old.kill()
	var t := l.create_tween()
	l.set_meta("web_shadow_tween", t)
	if on:
		if not l.shadow_enabled:
			l.shadow_opacity = 0.0
			l.shadow_enabled = true
		t.tween_property(l, "shadow_opacity", float(l.get_meta("web_shadow_opacity", 1.0)), SHADOW_FADE)
	else:
		t.tween_property(l, "shadow_opacity", 0.0, SHADOW_FADE)
		t.tween_callback(func():
			if not l.get_meta("web_shadow_on", false):
				l.shadow_enabled = false)
