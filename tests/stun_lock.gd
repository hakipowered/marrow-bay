extends SceneTree
## Two infected and a grappler on her, her back to a wall. In 0.13 Bulmaim
## was stun locked there twice: the grappler's squeezes each landed as a
## fresh blow, the button out of its grab was hidden, and the others hit
## her while she was held. Checks that:
##  1. Two shamblers either side of her, she stands still: flinches at least
##     1 s apart, blows at least 1.25 s apart, their swings never start
##     together (how long her feet were stopped is noted).
##  2. Right after a blow she can still roll out between them, untouched.
##  3. The grappler's grab: "Struggle free!" shows at once, nobody else lands
##     a blow while she's held, the squeeze only stings, mashing INTERACT gets
##     her out, and she isn't grabbed again straight away.
##  4. Held and not struggling, the grab ends on its own.
## Every gap is read from the moment the game stamped it (the blow's
## struck_ms, the flinch's and the swing's own times, the grab's pin_free_ms),
## never from when this script got round to noticing: on a loaded machine a
## late frame made two blows 1.3 s apart look 1.23 s. Each is measured on the
## clock its rule uses: the blow, flinch, swing and re-grab gaps on the
## game's wall clock, the grab's length in game time, and the prompt in
## physics ticks. The stages' own timers run on game time too, so a slow
## machine gets the same number of physics ticks for each stage.
## Prints STUN LOCK OK, or STUN LOCK FAIL with the reasons.
const STRUGGLE := "Struggle free!"
var frames := 0
var stage := 0
var t := 0.0
var p: Node = null
var lvl: Node = null
var fails := []
var notes := []
var start := Vector3.ZERO
var fwd := Vector3.ZERO
var side := Vector3.ZERO
var zs := []
var _wall: StaticBody3D = null
var last_hp := 0.0
var hits := []        # ms of each blow
var flinches := []    # ms of each fresh flinch
var swings := []      # ms of each swing start
var _last_swing := -1
var _last_flinch := 0
var stun_frames := 0
var all_frames := 0
var prompts := []     # [physics tick, text]
var pin_ms := -1      # wall clock, noticed the physics tick after the grab
var pin_tick := -1    # the physics tick the grab happened in
var free_ms := -1     # the game's own stamp (pin_free_ms)
var free_tick := -1
var _pt := 0.0        # game time not yet handed to _process
var held_t := 0.0     # game time held (the grab's own clock)
var regrab_ms := -1
var _was_pinned := false
var _cleared_checked := false
var taps := 0
var held_drops := []
var roll_hp := 0.0
var _freed_noted := false

## The grab, watched every physics tick (the game's own step).
## (This runs before the game's own nodes in each tick, so what they did in
## the last tick shows here.)
func _physics_process(delta: float) -> bool:
	_pt += delta
	if p == null or not is_instance_valid(p) or not stage in [5, 7]:
		return false
	var now := Time.get_ticks_msec()
	var tick := Engine.get_physics_frames()
	if p.pinned and not _was_pinned:
		if pin_ms < 0:
			pin_ms = now
			pin_tick = tick - 1
			held_t = 0.0
		elif free_ms >= 0 and regrab_ms < 0:
			regrab_ms = now
	elif _was_pinned and not p.pinned and free_ms < 0:
		free_ms = int(p.get_meta("pin_free_ms", now))
		free_tick = tick
	if p.pinned and free_ms < 0:
		held_t += delta
	_was_pinned = p.pinned
	return false

func _process(_d: float) -> bool:
	frames += 1
	# The stages' timers run on game time (the physics ticks since the last
	# frame), not the frame's wall-clock delta.
	var d := _pt
	_pt = 0.0
	var cs = root.get_node_or_null("Cutscenes")
	if stage > 0 and stage < 30 and cs and cs.active:
		if frames % 10 == 0:
			cs._on_skip_pressed()
		return false
	var now := Time.get_ticks_msec()
	match stage:
		0:
			if frames > 2:
				root.get_node("Net").start_solo("obcera")
				change_scene_to_file(root.get_node("GameState").level_path)
				stage = 1
				frames = 0
		1:
			if frames > 40:
				p = get_first_node_in_group("players")
				lvl = get_first_node_in_group("level")
				p.interact_prompt.connect(func(s): prompts.append([Engine.get_physics_frames(), s]))
				start = p.global_position
				fwd = -p.body.global_transform.basis.z
				fwd.y = 0.0
				fwd = fwd.normalized()
				side = fwd.cross(Vector3.UP).normalized()
				_setup(["shambler", "shambler"])
				stage = 2
		# --- 1. two either side of her ---------------------------------
		2:
			t += d
			p.move_input = Vector2.ZERO
			_watch(now)
			if t > 9.0:
				var fg := _gaps(flinches)
				var hg := _gaps(hits)
				var sg := _gaps(swings)
				var free := 1.0 - float(stun_frames) / float(maxi(all_frames, 1))
				notes.append("two on her: %d blows, gaps %s; flinch gaps %s; swing starts gaps %s; feet free %d%% of the time" % [hits.size(), str(hg), str(fg), str(sg), int(free * 100.0)])
				if hits.size() < 3:
					fails.append("they hardly hit her (%d blows: test setup?)" % hits.size())
				for g in fg:
					if g < 0.98:
						fails.append("flinches chained %.2f s apart" % g)
				for g in hg:
					if g < 1.25:
						fails.append("blows %.2f s apart" % g)
				for g in sg:
					if g < 0.6:
						fails.append("two swings started %.2f s apart" % g)
				stage = 3
				t = 0.0
		# --- 2. roll out right after a blow ----------------------------
		3:
			t += d
			var before := hits.size()
			_watch(now)
			if hits.size() > before or t > 6.0:
				var stunned: bool = p._hit_stun > 0.0
				var local: Vector3 = Basis(Vector3.UP, p.yaw).inverse() * fwd
				p.move_input = Vector2(local.x, local.z).normalized()
				p.roll()
				roll_hp = p.hp
				notes.append("roll right after a blow (still flinching %s): started %s" % [str(stunned), str(p.rolling)])
				if not p.rolling:
					fails.append("couldn't roll out right after a blow")
					stage = 4
				else:
					stage = 31
				t = 0.0
		31:
			t += d
			if not p.rolling or t > 2.0:
				p.move_input = Vector2.ZERO
				var away: float = (p.global_position - start).length()
				notes.append("rolled %.1f m clear, hp %d -> %d" % [away, roll_hp, p.hp])
				if away < 2.3:
					fails.append("roll out only got %.1f m clear" % away)
				if p.hp < roll_hp - 0.01:
					fails.append("hit mid-roll")
				stage = 4
		# --- 3. the grappler, the other two beside it ------------------
		4:
			_setup(["grappler", "shambler", "shambler"])
			stage = 5
			t = 0.0
		5:
			t += d
			p.move_input = Vector2.ZERO
			_watch(now)
			if pin_ms >= 0 and p.pinned and free_ms < 0:
				if p.hp < last_hp - 0.01:
					held_drops.append(snappedf(last_hp - p.hp, 0.1))
					last_hp = p.hp
				# Mash after a beat, as a player would once she sees the prompt.
				if now - pin_ms > 900 and frames % 6 == 0 and taps < 12:
					taps += 1
					p.interact()
			if free_ms >= 0 and not _freed_noted:
				_freed_noted = true
				var shown := -1
				for pr in prompts:
					if pr[1] == STRUGGLE and pr[0] >= pin_tick:
						shown = pr[0] - pin_tick
						break
				notes.append("grabbed: prompt %d ticks later, freed after %d taps in %.1f s, hurt while held %s" % [shown, taps, held_t, str(held_drops)])
				# (the same tick, or the next if she moved before the grappler)
				if shown < 0 or shown > 2:
					fails.append("no \"%s\" when grabbed" % STRUGGLE)
				if taps > 8:
					fails.append("%d taps to break the grab" % taps)
				for dd in held_drops:
					if dd > 8.6:
						fails.append("took a %.1f blow while held" % dd)
			if free_ms >= 0:
				if regrab_ms >= 0 and regrab_ms - free_ms < 4000:
					fails.append("grabbed again %.1f s after breaking free" % ((regrab_ms - free_ms) / 1000.0))
					stage = 6
				elif Engine.get_physics_frames() - free_tick >= 30 and not _cleared_checked:
					_cleared_checked = true
					if prompts.size() > 0 and prompts[prompts.size() - 1][1] == STRUGGLE:
						fails.append("\"%s\" still showing after she got free" % STRUGGLE)
				if now - free_ms >= 4000 and stage == 5:
					stage = 6
			if t > 12.0 and stage == 5:
				fails.append("the grappler never grabbed her" if pin_ms < 0 else "she never got free by struggling")
				stage = 6
		# --- 4. held and not struggling --------------------------------
		6:
			_setup(["grappler"])
			pin_ms = -1
			pin_tick = -1
			free_ms = -1
			free_tick = -1
			regrab_ms = -1
			held_t = 0.0
			_was_pinned = p.pinned
			held_drops = []
			stage = 7
			t = 0.0
		7:
			t += d
			p.move_input = Vector2.ZERO
			if pin_ms >= 0 and p.pinned and free_ms < 0 and p.hp < last_hp - 0.01:
				held_drops.append(snappedf(last_hp - p.hp, 0.1))
				last_hp = p.hp
			if free_ms >= 0:
				notes.append("held without struggling: let go after %.2f s of game time, squeezes %s" % [held_t, str(held_drops)])
				if held_t > 3.6:
					fails.append("the grab lasted %.2f s" % held_t)
				stage = 30
			elif pin_ms >= 0 and held_t > 8.0:
				fails.append("held for 8 s and never let go")
				stage = 30
			elif t > 10.0 and pin_ms < 0:
				fails.append("the lone grappler never grabbed her")
				stage = 30
		30:
			for n in notes:
				print("  ", n)
			if fails.is_empty():
				print("STUN LOCK OK")
			else:
				print("STUN LOCK FAIL: ", fails)
			quit(0 if fails.is_empty() else 1)
	return false

## Her back to a wall, one in front (the first type) and the rest either
## side of her, all coming for her.
func _setup(types: Array) -> void:
	for zz in get_nodes_in_group("zombies"):
		zz.queue_free()
	zs.clear()
	if _wall:
		_wall.queue_free()
	p.global_position = start
	p.velocity = Vector3.ZERO
	p.hp = 5000.0
	last_hp = p.hp
	hits.clear()
	flinches.clear()
	swings.clear()
	_last_swing = int(p.get_meta("swing_ms", -1))
	_last_flinch = p._last_flinch_ms
	stun_frames = 0
	all_frames = 0
	_wall = _make_wall(start - fwd * 0.75, fwd)
	var spots: Array = [side * 1.05, -side * 1.05] if types.size() == 2 else [fwd * 1.0, fwd * 0.6 + side * 0.95, fwd * 0.6 - side * 0.95]
	for i in types.size():
		var n := "StunZ%d_%d" % [stage, i]
		lvl.spawn_zombie_synced(n, start + spots[i], types[i])
		var z: Node = lvl.get_node(n)
		z.look_at(start, Vector3.UP)
		z.state = z.S.CHASE
		z.target = p
		zs.append(z)

func _watch(now: int) -> void:
	all_frames += 1
	if p._hit_stun > 0.0:
		stun_frames += 1
	if p.hp < last_hp - 0.01:
		if not p.pinned:
			# when the blow landed (the game's own stamp), not now
			hits.append(int(p.get_meta("struck_ms", now)))
		last_hp = p.hp
	if p._last_flinch_ms != _last_flinch:
		_last_flinch = p._last_flinch_ms
		flinches.append(_last_flinch)
	# A swing stamps her when it starts (Zombie._begin_attack).
	var sw := int(p.get_meta("swing_ms", -1))
	if sw != _last_swing:
		_last_swing = sw
		swings.append(sw)

func _gaps(ms: Array) -> Array:
	var out := []
	for i in range(1, ms.size()):
		out.append(snappedf((ms[i] - ms[i - 1]) / 1000.0, 0.01))
	return out

func _make_wall(at: Vector3, normal: Vector3) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = 1
	var c := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(6.0, 3.0, 0.3)
	c.shape = b
	w.add_child(c)
	lvl.add_child(w)
	w.global_position = at + Vector3.UP * 1.5
	w.look_at(w.global_position + normal, Vector3.UP)
	return w
