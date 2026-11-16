class_name NetSmooth
extends RefCounted
## Plays back the motion of something the other phone moves: the partner on
## both phones, and on the joiner's phone every infected, the Warden and the
## Tallyman (the host runs them).
##
## The other phone sends where each one is 20 to 30 times a second, through
## the relay over a WebSocket. Those don't arrive evenly: Wi-Fi holds a few
## back and lets them through together, and one lost packet stalls the whole
## TCP link for a fifth of a second or more. Putting each position on screen
## the moment it landed (what the game did up to 0.15) made everything the
## other phone moves stutter and jump, and on the joiner's phone that is
## every infected in the level, while the host sees its own smooth.
##
## So each snapshot carries the sender's clock (net_stamp), and the receiving
## phone plays them back a short delay behind, sliding between the two either
## side of "now minus the delay". The delay is shared per sender (Link) and
## follows how late that phone's snapshots run: about one send interval plus
## the usual lateness, longer while the link is rough, shorter again when it
## settles. When the link stalls for longer than that, motion carries on along
## its last heading for a moment, then waits, and eases back onto the real path
## when the snapshots catch up.
##
## Use: the sender's synchronizer replicates net_stamp, net_pos and net_yaw
## (getters that read the live values); the receiver's setters store them and
## its synchronizer's `synchronized` signal calls push(). Each physics frame
## the receiver calls step() and puts the body where it says.

## How much history to keep (ms of the sender's clock).
const KEEP_MS := 1000.0
## How far past the newest snapshot motion carries on when they stop coming.
const EXTRAPOLATE_MS := 160.0
## A jump longer than this between two snapshots is a teleport (a respawn,
## a cutscene's mark, a Continue): shown at once, not slid across.
const SNAP_DIST := 4.0
## How long a correction takes to ease out (s), after motion that carried on
## past the newest snapshot turns out to have been a little off.
const EASE_S := 0.12

## The link to one sender. Every snapshot from one phone travels the same
## way, so the clock gap and lateness are learned from all of them together.
class Link:
	## Our clock minus theirs, for the quickest snapshot lately (ms). Each
	## snapshot's lateness is how much slower than that it came.
	var offset := INF
	## Recent lateness, one per send tick of the sender, and how long each
	## of those snapshots had to be waited for at most: its lateness plus
	## the time since the one before it (playback needs the next snapshot
	## in hand before it gets there).
	var _late := PackedFloat32Array()
	var _late_i := 0
	var _last_stamp := -1
	var _need := PackedFloat32Array()
	var _need_i := 0
	var _need_stamp := -1
	## How far behind the sender's clock playback runs (ms), and where it is
	## heading.
	var delay := 120.0
	var target := 120.0
	## Longest send interval of anything this sender moves (ms).
	var interval := 33.0
	var _stepped_frame := -1
	var _stepped_ms := 0.0
	## For the readout: snapshots lately, ones that came too late to show,
	## and the longest silence from this phone in the last few seconds.
	var seen := 0
	var too_late := 0
	var _last_recv := 0.0
	var gap_ms := 0.0
	var _gap_until := 0.0

	func _init() -> void:
		_late.resize(128)   # about three seconds of snapshots
		_late.fill(0.0)
		_need.resize(64)
		_need.fill(interval)

	## `gap`: ms on the sender's clock since that node's previous snapshot
	## (0 for its first); below 0 when this node's playback doesn't matter
	## for the delay (out of sight, standing still).
	func observe(stamp: int, now: float, gap: float) -> void:
		var d := now - float(stamp)
		if offset == INF or d < offset:
			offset = d
		if stamp != _last_stamp:
			# The first snapshot of a send tick (the rest of that tick's
			# nodes came in the same packet).
			_last_stamp = stamp
			seen += 1
			_late[_late_i] = d - offset
			_late_i = (_late_i + 1) % _late.size()
			if _last_recv > 0.0:
				var quiet := now - _last_recv
				if quiet > gap_ms or now > _gap_until:
					gap_ms = quiet
					_gap_until = now + 6000.0
			_last_recv = now
		if gap < 0.0:
			return
		# How long this tick had to be waited for: per tick, the node that
		# needed it least (one sent often, close by) speaks for it.
		var need := d - offset + (gap if gap > 0.0 else interval)
		if stamp == _need_stamp:
			var last := (_need_i - 1 + _need.size()) % _need.size()
			if need >= _need[last]:
				return
			_need[last] = need
		else:
			_need_stamp = stamp
			_need[_need_i] = need
			_need_i = (_need_i + 1) % _need.size()
		var sorted := _need.duplicate()
		sorted.sort()
		# Cover nine snapshots in ten arriving in time. The tenth, the odd
		# stall of a fifth of a second and a hitch on the sender's phone are
		# what carrying on past the newest one is for: waiting long enough
		# to cover every stall would show everything that far behind all
		# the time.
		var p90: float = sorted[int(sorted.size() * 0.9)]
		target = clampf(p90 + 10.0, interval + 10.0, 400.0)

	## The longest this phone went quiet in the last few seconds (ms).
	func recent_gap_ms() -> float:
		return gap_ms if Time.get_ticks_usec() / 1000.0 < _gap_until else 0.0

	## Lateness at a percentile (0..1) over the last few seconds (ms).
	func late_at(f: float) -> float:
		var sorted := _late.duplicate()
		sorted.sort()
		return sorted[clampi(int(sorted.size() * f), 0, sorted.size() - 1)]


	## Once a frame: the delay drifts toward its target slowly enough that
	## playback only ever runs a little slower or faster, never backwards.
	## The clock gap relaxes upward too, so one lucky quick snapshot doesn't
	## pin it for good (and the two phones' clocks drift a little).
	func step(now: float) -> void:
		var f := Engine.get_physics_frames()
		if f == _stepped_frame:
			return
		var dt := clampf((now - _stepped_ms) / 1000.0, 0.0, 0.1) if _stepped_frame >= 0 else 0.0
		_stepped_frame = f
		_stepped_ms = now
		if offset != INF:
			offset += 3.0 * dt
		var rate := 80.0 if target > delay else 25.0   # ms per second
		delay = move_toward(delay, target, rate * dt)

	## Where on the sender's clock playback is now.
	func play_time(now: float) -> float:
		return now - offset - delay

static var _links := {}

static func link(peer: int) -> Link:
	if not _links.has(peer):
		_links[peer] = Link.new()
	return _links[peer]

## Forget every link (a new session: the other phone's clock is new).
static func reset() -> void:
	_links.clear()

static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0

var _link: Link
var _t := PackedFloat64Array()
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _err := Vector3.ZERO
var _last_raw := Vector3.ZERO
var _last_play := -INF
## True when the newest snapshot was a teleport and nothing has been shown since.
var teleported := false

func _init(sender_peer: int, send_interval_s: float) -> void:
	_link = link(sender_peer)
	_link.interval = maxf(_link.interval, send_interval_s * 1000.0)

func has_data() -> bool:
	return not _t.is_empty()

## Forget the path so far (it was just put somewhere new on this phone too).
func clear() -> void:
	_t.clear()
	_pos.clear()
	_yaw.clear()
	_err = Vector3.ZERO
	_last_play = -INF

## Where the newest snapshot has it: closer to where it really is now than
## what step() shows, for game rules that reason about the other phone's
## survivor (the host's infected chase and swing at her there).
func newest_pos() -> Vector3:
	return _pos[_pos.size() - 1]

## A snapshot from the sender: where it was at its clock's `stamp` (ms).
## `matters`: whether the playback delay should be set to show this one
## smoothly (the infected near this phone's survivor do; one 60 m away or
## lying dead doesn't, and its sparse snapshots mustn't hold everything back).
func push(stamp: int, pos: Vector3, yaw: float, matters := true) -> void:
	var now := now_ms()
	var t := float(stamp)
	var n := _t.size()
	var gap := t - _t[n - 1] if n > 0 and t > _t[n - 1] else 0.0
	if n > 0 and pos.distance_squared_to(_pos[n - 1]) < 0.0001:
		matters = false   # standing still: nothing to smooth
	_link.observe(stamp, now, gap if matters else -1.0)
	if n > 0 and t <= _t[n - 1]:
		if t == _t[n - 1]:
			_pos[n - 1] = pos
			_yaw[n - 1] = yaw
		return   # older than what we have: Godot drops those, but be safe
	if n > 0 and pos.distance_to(_pos[n - 1]) > SNAP_DIST:
		_t.clear()
		_pos.clear()
		_yaw.clear()
		_err = Vector3.ZERO
		teleported = true
		n = 0
	var carrying_on := n > 0 and _last_play > _t[n - 1]
	_t.append(t)
	_pos.append(pos)
	_yaw.append(yaw)
	if t < _link.play_time(now):
		_link.too_late += 1
	if carrying_on:
		# Shown so far: a guess along the last heading. Ease from it onto
		# the real path rather than jump.
		var fresh := _sample(_last_play)[0] as Vector3
		_err += _last_raw - fresh
		_last_raw = fresh
		if _err.length() > 2.0:
			_err = Vector3.ZERO
	# Keep about a second.
	var cut := 0
	while cut < _t.size() - 2 and _t[cut + 1] < t - KEEP_MS:
		cut += 1
	if cut > 0:
		_t = _t.slice(cut)
		_pos = _pos.slice(cut)
		_yaw = _yaw.slice(cut)

## Where to show it this frame: [position, yaw].
func step(delta: float) -> Array:
	var now := now_ms()
	_link.step(now)
	var play := _link.play_time(now)
	if teleported:
		# Straight to where it went, whatever playback time says.
		play = maxf(play, _t[_t.size() - 1])
		teleported = false
	var s := _sample(play)
	_err *= exp(-delta / EASE_S)
	if _err.length() < 0.002:
		_err = Vector3.ZERO
	_last_raw = s[0]
	_last_play = play
	return [s[0] + _err, s[1]]

func _sample(play: float) -> Array:
	var n := _t.size()
	if play <= _t[0]:
		return [_pos[0], _yaw[0]]
	if play >= _t[n - 1]:
		var over := minf(play - _t[n - 1], EXTRAPOLATE_MS)
		if n < 2 or over <= 0.0:
			return [_pos[n - 1], _yaw[n - 1]]
		var span := _t[n - 1] - _t[n - 2]
		if span <= 0.0 or span > 250.0:
			return [_pos[n - 1], _yaw[n - 1]]
		var vel := (_pos[n - 1] - _pos[n - 2]) / span
		vel.y = minf(vel.y, 0.0)   # carry on walking or falling, never rising
		return [_pos[n - 1] + vel * over, _yaw[n - 1]]
	# Binary search for the pair either side.
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _t[mid] <= play:
			lo = mid
		else:
			hi = mid
	var k := (play - _t[lo]) / (_t[hi] - _t[lo])
	return [_pos[lo].lerp(_pos[hi], k), lerp_angle(_yaw[lo], _yaw[hi], k)]
