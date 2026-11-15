extends SceneTree
## Checks how the browser profile adapts (scripts/world/web_quality.gd) on
## made-up phones: each one turns the render scale and the number of lamp
## shadows into a frame time, and the profile is judged every "1.5 s" on it.
##
##   godot --headless --path . --script tests/web_quality_adapt_test.gd
## Prints ADAPT lines and "ADAPT_OK" (exit 0) or "ADAPT_FAIL" (exit 1).
const WQ := preload("res://scripts/world/web_quality.gd")
var fails := 0

var _done := false

func _process(_d: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false

func _run() -> void:
	# A phone whose GPU is the limit: fewer pixels help, shadows help a bit.
	_case("gpu_bound", 0.59, 2, func(s, b): return 10.0 + 70.0 * s * s + 4.0 * b,
		func(s, b): return _ms(s, b, 10.0, 70.0, 4.0) < WQ.SLOW_MS)
	# A phone where draw calls are the limit: the scale doesn't matter, the
	# shadows do. The scale must come back after its useless step down.
	_case("draw_bound", 0.9, 2, func(s, b): return 20.0 + 9.0 * b,
		func(s, b): return s >= 0.9 - 0.001 and 20.0 + 9.0 * b < WQ.SLOW_MS)
	# A fast phone: everything climbs to full.
	_case("fast", 0.59, 2, func(s, b): return 9.0,
		func(s, b): return s >= WQ.MAX_SCALE - 0.001 and b == WQ.SHADOW_BUDGET)
	# The 4th shadow tips it over: settles at 3 instead of flicking.
	_case("tipping", 1.0, 3, func(s, b): return 12.0 if b < 4 else 40.0,
		func(s, b): return b == 3)
	# Too slow whatever happens (scripts, not drawing): nothing is given up
	# for nothing, and the tries get rarer.
	_case("hopeless", 0.59, 2, func(s, b): return 80.0,
		func(s, b): return b == 2 and absf(s - 0.59) < 0.001)
	print("ADAPT_OK" if fails == 0 else "ADAPT_FAIL %d" % fails)
	quit(0 if fails == 0 else 1)

func _ms(s: float, b: int, base: float, px: float, per: float) -> float:
	return base + px * s * s + per * b

func _case(name: String, scale: float, budget: int, frame_ms: Callable, ok: Callable) -> void:
	var n: Node = WQ.new()
	root.add_child(n)
	root.scaling_3d_scale = scale
	WQ.shadow_budget = budget
	var changes := 0
	var last := [scale, budget]
	var trail := PackedStringArray()
	# 300 checks = 7.5 minutes of play. Holds count down as if 1.5 s passed.
	for i in 300:
		for k in n._hold:
			n._hold[k] -= WQ.CHECK_S
		n._judge(frame_ms.call(root.scaling_3d_scale, WQ.shadow_budget))
		var now := [snappedf(root.scaling_3d_scale, 0.01), WQ.shadow_budget]
		if now != last:
			changes += 1
			if trail.size() < 24:
				trail.append("%s/%d" % [now[0], now[1]])
			last = now
	var s: float = root.scaling_3d_scale
	var b: int = WQ.shadow_budget
	var good: bool = ok.call(s, b)
	# Settled: no change at all in the last 60 checks.
	var settled := true
	var before := [snappedf(s, 0.01), b]
	for i in 60:
		for k in n._hold:
			n._hold[k] -= WQ.CHECK_S
		n._judge(frame_ms.call(root.scaling_3d_scale, WQ.shadow_budget))
		if [snappedf(root.scaling_3d_scale, 0.01), WQ.shadow_budget] != before:
			settled = false
	print("ADAPT %s: scale %.2f shadows %d after %d changes (%s) settled=%s %s" % [
		name, s, b, changes, " ".join(trail), settled, "ok" if good and settled else "FAIL"])
	if not (good and settled):
		fails += 1
	n.queue_free()
	root.remove_child(n)
