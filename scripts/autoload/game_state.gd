extends Node
## Shared run state: who plays whom, customization, and the shared checkpoint.

signal shared_checkpoint_changed(checkpoint_id: String)

enum Mode { SOLO, COOP }
const CHARACTERS := ["zegan", "obcera"]

var mode: Mode = Mode.SOLO
## peer_id -> character id ("zegan" / "obcera")
var character_by_peer: Dictionary = {}
## peer_id -> customization Dictionary (see default_customization)
var customization_by_peer: Dictionary = {}
## Last checkpoint that every player in the session was standing at together.
var shared_checkpoint: String = "start"
const FIRST_LEVEL := "res://scenes/levels/archive_hub.tscn"
var level_path: String = FIRST_LEVEL
## Persistent world flags (opened doors, picked items, solved puzzles).
var world_flags: Dictionary = {}
## peer_id -> inventory snapshot, filled from the players on save.
var inventories: Dictionary = {}
## Time spent in the levels this run (the title and menus don't count).
var play_time_sec: float = 0.0
## Which playthrough this is: every save of one run carries the same id, so a
## co-op copy of the host's save never lands over a different run on the
## partner's phone (SaveSystem.mirror_target). New on each new game.
var run_id: String = ""
## This phone's own look per character (outfit + body sliders), kept between
## sessions in LOOKS_PATH. The character select edits these; co-op sends
## them to the host, and saves carry the look each survivor had.
var looks: Dictionary = {}
const LOOKS_PATH := "user://looks.json"

## How hard the run is: picked when a new game starts, sent to the partner
## with the rest of the run, and kept in its saves (old saves are Normal).
## Normal is the game as balanced (tools/balance_report.py).
var difficulty := "normal"
const DIFFICULTIES := ["easy", "normal", "hard"]
## enemy_damage: what a blow takes off a survivor. enemy_health: the infected
## (head and body shots scale alike). boss_health: bosses, times COOP_BOSS
## with two guns on them. ammo: rounds in each box found. drops: the chance an
## infected or a crate leaves something. revive: seconds a downed survivor
## lasts. aim_assist: how far hip fire bends toward a target. pressure: how
## many infected come (see pressure()).
const DIFFICULTY := {
	"easy": {"name": "Easy", "blurb": "For the story. Infected hit softer and go down sooner, every box holds more ammo, and hip fire finds its target. In co-op, more time to reach a downed partner.",
		"enemy_damage": 0.6, "enemy_health": 0.8, "boss_health": 0.75, "ammo": 1.5, "drops": 1.4, "revive": 45.0, "aim_assist": 1.7, "pressure": 0},
	"normal": {"name": "Normal", "blurb": "The way RaGoon City is meant to be played. Every shot counts, but there's enough to get through if you're careful.",
		"enemy_damage": 1.0, "enemy_health": 1.0, "boss_health": 1.0, "ammo": 1.0, "drops": 1.0, "revive": 30.0, "aim_assist": 1.0, "pressure": 1},
	"hard": {"name": "Hard", "blurb": "More infected, and they hit much harder and take more to put down. Less ammo in every box and fewer drops. In co-op, only 20 seconds to reach a downed partner.",
		"enemy_damage": 1.5, "enemy_health": 1.2, "boss_health": 1.25, "ammo": 0.7, "drops": 0.6, "revive": 20.0, "aim_assist": 1.0, "pressure": 2},
}
## Boss health with two survivors shooting at it.
const COOP_BOSS := 1.6
## In co-op each survivor gets their own roll at what an infected or a crate
## leaves (see LevelBase.drop_loot), each at this much of the solo chance.
const COOP_DROPS := 0.6
## How many infected come for each "pressure" (difficulty, plus one in
## co-op): groups that come in (scares, the generator's waves) grow by this,
## and the hand-placed extras in extra_infected.gd join at their tier.
const PRESSURE_COUNT := [1.0, 1.0, 1.35, 1.7]

func _ready() -> void:
	if FileAccess.file_exists(LOOKS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LOOKS_PATH))
		if d is Dictionary:
			looks = d

## The current difficulty's value for `key` (see DIFFICULTY).
func tuning(key: String) -> float:
	return float(DIFFICULTY.get(difficulty, DIFFICULTY["normal"]).get(key, 1.0))

func difficulty_name(d := "") -> String:
	return str(DIFFICULTY.get(d if d != "" else difficulty, DIFFICULTY["normal"])["name"])

func set_difficulty(d: String) -> void:
	difficulty = d if DIFFICULTY.has(d) else "normal"

## 0 Easy solo, 1 Easy co-op and Normal solo (the game as balanced), 2 Normal
## co-op and Hard solo, 3 Hard co-op. Two survivors each find their own
## supplies, so co-op brings more infected.
func pressure() -> int:
	if test_pressure >= 0:
		return test_pressure
	return int(tuning("pressure")) + (1 if mode == Mode.COOP else 0)

## Tests only: plays a solo run at this pressure (-1: off), so the level
## probe and the scares can be checked with every extra infected in place.
var test_pressure := -1

## A group of n infected at this pressure (never fewer than n).
func group_size(n: int) -> int:
	return maxi(n, roundi(n * PRESSURE_COUNT[clampi(pressure(), 0, PRESSURE_COUNT.size() - 1)]))

## A spawn list grown to group_size, the newcomers taken from its lighter
## infected (shamblers, runners, crawlers) in turn, never more bosses or brutes.
func grown_mix(mix: Array) -> Array:
	var out := mix.duplicate()
	var light := mix.filter(func(v): return v in ["shambler", "runner", "crawler"])
	if light.is_empty():
		light = ["shambler"]
	var k := 0
	while out.size() < group_size(mix.size()):
		out.append(light[k % light.size()])
		k += 1
	return out

## The chance an infected or crate leaves something for one survivor, times
## its drop table's own.
func drop_chance() -> float:
	return tuning("drops") * (COOP_DROPS if mode == Mode.COOP else 1.0)

func boss_health() -> float:
	return tuning("boss_health") * (COOP_BOSS if mode == Mode.COOP else 1.0)

## Rounds in an ammo box at this difficulty (at least one).
func ammo_amount(n: int) -> int:
	return maxi(1, roundi(n * tuning("ammo")))

## Supplies (ammo, herbs, guns) are each survivor's own: one taking a box
## leaves the partner's there for them. Keys and files are found once, for
## both. Whether `character` (default: this phone's) has taken item `pid`.
func item_taken(pid: String, character := "") -> bool:
	if has_flag("taken:" + pid):
		return true
	return has_flag("taken:%s:%s" % [pid, character if character != "" else local_character()])

func _process(delta: float) -> void:
	if get_tree().get_first_node_in_group("level") != null:
		play_time_sec += delta

## Its own random source: a draw from the global one would shift every
## random thing after it (the playtest route bot depends on that order).
func new_run_id() -> String:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return "%d-%06d" % [int(Time.get_unix_time_from_system()), r.randi() % 1000000]

## The saved look for a character, filled out with defaults.
func look(character: String) -> Dictionary:
	var c := default_customization(character)
	var saved: Variant = looks.get(character, {})
	if saved is Dictionary:
		for k in saved:
			if c.has(k):
				c[k] = saved[k]
	c["outfit"] = Outfits.resolve(character, c.get("outfit", Outfits.DEFAULT))
	return c

func set_look(character: String, c: Dictionary) -> void:
	looks[character] = c.duplicate()
	var f := FileAccess.open(LOOKS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(looks, "\t"))

static func default_customization(character: String) -> Dictionary:
	return {
		"outfit": "default",
		# Body-shape sliders, 0..1, 0.5 = base model.
		"height": 0.5, "shoulders": 0.5, "chest": 0.5,
		"waist": 0.5, "hips": 0.5, "legs": 0.5, "muscle": 0.5,
		"hair": "default", "hair_color": Color(0.1, 0.07, 0.05).to_html(),
	}

func local_character() -> String:
	return character_by_peer.get(multiplayer.get_unique_id(), "zegan")

func partner_character(of_character: String) -> String:
	return "obcera" if of_character == "zegan" else "zegan"

func set_flag(key: String, value: Variant = true) -> void:
	world_flags[key] = value

## A flag every phone keeps (the host's saves hold what both survivors did).
func share_flag(key: String, value: Variant = true) -> void:
	set_flag(key, value)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_rpc_flag.rpc(key, value)

@rpc("any_peer", "reliable")
func _rpc_flag(key: String, value: Variant) -> void:
	world_flags[key] = value

func has_flag(key: String) -> bool:
	return world_flags.get(key, false) != false

func set_shared_checkpoint(id: String) -> void:
	if shared_checkpoint == id:
		return
	shared_checkpoint = id
	shared_checkpoint_changed.emit(id)

func reset_run() -> void:
	# A new game starts at the beginning, even after reaching a later chapter.
	level_path = FIRST_LEVEL
	shared_checkpoint = "start"
	world_flags.clear()
	inventories.clear()
	play_time_sec = 0.0
	run_id = new_run_id()
	difficulty = "normal"
	SaveSystem.checkpoint_snapshot = {}
	SaveSystem.autosave_on_arrival = false
