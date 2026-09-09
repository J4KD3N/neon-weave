## Demo-slice balance harness (S27). Plays every fight of the demo and the
## two Shard depths across many combat seeds with the same naive policy the
## Act 1 test uses (attack the nearest thing, else walk at it), then holds
## each to a win-rate band. The policy is a floor: a player who uses cover,
## abilities and focus fire does better, so a band here says "winnable when
## played badly" (low edge) and "not a walkover" (high edge). Numbers in
## content/rules, classes and enemies are tuned against this table; the
## table prints on every run so a change shows its effect.
extends TestCase

const LEDGER := "user://test_ledger_balance.json"
const SAVES := "user://test_saves_balance"
const SEEDS := 20
const MAX_STEPS := 600

## The demo path: who is in the party and how much XP is banked at each beat.
## Gate: the yard pair, level 1. Hive: Kaj-7 joined, two scavs' XP. Warlord:
## after the hive and one depth-2 extraction, level 3.
const BEATS: Array[Dictionary] = [
	{"id": "gate ambush", "map": "gate_road", "cell": Vector2i(12, 4), "flags": {"gate_open": true}, "companions": ["sera", "dax"], "xp": 0, "min_win": 0.85, "max_win": 1.0},
	{"id": "relay hive", "map": "relay_station", "cell": Vector2i(12, 5), "flags": {}, "companions": ["sera", "dax", "kaj7"], "xp": 15, "min_win": 0.7, "max_win": 1.0},
	{"id": "the warlord (lvl 2)", "map": "undercity_throat", "cell": Vector2i(14, 4), "flags": {}, "companions": ["sera", "dax", "kaj7"], "xp": 39, "min_win": 0.3, "max_win": 0.9},
	{"id": "the warlord (lvl 3)", "map": "undercity_throat", "cell": Vector2i(14, 4), "flags": {}, "companions": ["sera", "dax", "kaj7"], "xp": 60, "min_win": 0.5, "max_win": 0.95},
]

var world: ExploreWorld
var rows: PackedStringArray = []


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _heal_up(w: ExploreWorld) -> void:
	for m: PartyMember in w.party.members:
		m.downed = false
		m.hp = m.max_hp


## The Act 1 policy: nearest hostile, hit it if anything reaches, else close.
static func _fight(w: ExploreWorld) -> void:
	var s := w.combat.state
	var steps := 0
	while not s.finished and steps < MAX_STEPS:
		steps += 1
		if not w.combat.current_is_player():
			w.combat.end_player_turn()
			continue
		var actor := s.current()
		var target := EnemyBrain.nearest_hostile(s, actor)
		if target == null:
			w.combat.end_player_turn()
			continue
		if not EnemyBrain.usable_ability(s, actor, target).is_empty():
			var ap_before := actor.ap
			w.combat.player_click(target.cell)
			if actor.ap == ap_before:
				w.combat.end_player_turn()
		elif actor.move_left > 0:
			var field := s.distance_field(target.cell)
			var best := actor.cell
			var best_d := int(field.get(actor.cell, 9999))
			var cells: Array = s.reachable_cells(actor).keys()
			cells.sort()
			for cell: Vector2i in cells:
				if int(field.get(cell, 9999)) < best_d:
					best = cell
					best_d = int(field.get(cell, 9999))
			if best == actor.cell:
				w.combat.end_player_turn()
			else:
				w.combat.player_click(best)
		else:
			w.combat.end_player_turn()


## Party HP left as a fraction of the total, downed members counting as 0.
static func _hp_fraction(w: ExploreWorld) -> float:
	var hp := 0
	var max_hp := 0
	for m: PartyMember in w.party.members:
		hp += maxi(m.hp, 0) if not m.downed else 0
		max_hp += m.max_hp
	return float(hp) / float(maxi(max_hp, 1))


## Stages one beat on a fresh world: party, level, flags, then the trigger.
func _stage(beat: Dictionary, seed_value: int) -> ExploreWorld:
	var w := _fresh()
	w.combat_seed = seed_value
	for id: String in beat["companions"]:
		assert_true(w.add_companion(id), "recruit %s" % id)
	w.ledger.xp = int(beat["xp"])
	w.refresh_progression()
	_heal_up(w)
	for flag: String in beat["flags"]:
		w.narrative.set_flag(flag, bool(beat["flags"][flag]))
	assert_true(w.enter_map(String(beat["map"])), "enter %s" % beat["map"])
	w.teleport_party(beat["cell"])
	w.check_triggers()
	return w


func _report(id: String, wins: int, n: int, rounds: float, hp_left: float, downed: float, extra: String = "") -> void:
	var line := "%-22s win %3d%%  rounds %4.1f  hp left %3d%%  downed %.1f%s" % [id, int(round(100.0 * wins / n)), rounds, int(round(100.0 * hp_left)), downed, extra]
	rows.append(line)
	print("  balance ", line)


func test_every_story_fight_sits_in_its_band() -> void:
	var rules: Dictionary = world.progression_rules()
	_drop(world)
	for beat: Dictionary in BEATS:
		var wins := 0
		var rounds := 0
		var hp_left := 0.0
		var downed := 0
		for i: int in SEEDS:
			var w := _stage(beat, 1000 + i)
			assert_eq(w.mode, "combat", "%s seed %d starts a fight" % [beat["id"], i])
			_fight(w)
			assert_true(w.combat.state.finished, "%s seed %d resolves" % [beat["id"], i])
			rounds += w.combat.state.round_number
			if w.combat.state.result == "victory":
				wins += 1
				hp_left += _hp_fraction(w)
				for m: PartyMember in w.party.members:
					if m.hp <= 1:
						downed += 1
			_drop(w)
		var rate := float(wins) / SEEDS
		_report(String(beat["id"]), wins, SEEDS, float(rounds) / SEEDS, hp_left / maxi(wins, 1), float(downed) / maxi(wins, 1), "  lvl %d" % Progression.level_for_xp(int(beat["xp"]), rules))
		assert_true(rate >= float(beat["min_win"]), "%s: naive win rate %.2f under the floor %.2f" % [beat["id"], rate, beat["min_win"]])
		assert_true(rate <= float(beat["max_win"]), "%s: naive win rate %.2f over the ceiling %.2f (a walkover)" % [beat["id"], rate, beat["max_win"]])
	world = _fresh()


## The road as a player walks it: the ambush, then the hive with the same
## wounds (Kaj-7 joins fresh), no Med-bay in between. Must be survivable
## most of the time or the demo's second fight is a wall.
func test_the_road_chain_without_healing_is_survivable() -> void:
	_drop(world)
	var wins := 0
	var hp_after_gate := 0.0
	for i: int in SEEDS:
		var w := _stage(BEATS[0], 2000 + i)
		_fight(w)
		if w.combat.state.result != "victory":
			_drop(w)
			continue
		hp_after_gate += _hp_fraction(w)
		assert_true(w.add_companion("kaj7"), "line 176")
		w.refresh_progression()
		assert_true(w.enter_map("relay_station"), "line 178")
		w.combat_seed = 3000 + i
		w.teleport_party(Vector2i(12, 5))
		w.check_triggers()
		assert_eq(w.mode, "combat", "the hive wakes")
		_fight(w)
		if w.combat.state.result == "victory":
			wins += 1
		_drop(w)
	_report("road chain (no heal)", wins, SEEDS, 0.0, hp_after_gate / SEEDS, 0.0)
	assert_true(float(wins) / SEEDS >= 0.6, "the road chain wins %d/%d without healing" % [wins, SEEDS])
	world = _fresh()


## One Shard at each demo depth with the full party at level 2: hop between
## pickups and the pad, fight what wakes, extract. Depth 2 must be harder
## than depth 1 and both must be extractable more often than not.
func test_shard_depths_extract_more_often_than_not() -> void:
	_drop(world)
	var rates: Array[float] = []
	for depth: int in [1, 2]:
		var extracted := 0
		var fights := 0
		for i: int in SEEDS:
			var w := _fresh()
			w.combat_seed = 4000 + i
			for id: String in ["sera", "dax", "kaj7"]:
				w.add_companion(id)
			w.ledger.xp = 20
			w.refresh_progression()
			_heal_up(w)
			var entry := w.enter_shard(ExploreWorld.DEFAULT_SHARD, 500 + i, depth)
			assert_false(entry.is_empty(), "line 213")
			var hops := 0
			while w.mode != "defeated" and not w.at_home() and hops < 40:
				hops += 1
				if w.mode == "combat":
					fights += 1
					_fight(w)
					continue
				var reach := ShardValidator.reachable_from(w.map_data, w.leader_cell())
				var goal := w.extraction_cell()
				for p: PickupActor in w.remaining_pickups():
					if reach.has(p.cell):
						goal = p.cell
						break
				var taken: Array[Vector2i] = []
				var free := w.map_data.nearest_free_cells(goal, 1, taken)
				w.teleport_party(free[0] if goal != w.extraction_cell() and not free.is_empty() else goal)
				w.check_pickups()
				if w.mode == "explore" and w.check_encounters():
					continue
				if w.mode == "explore" and w.can_extract():
					w.extract()
			if w.at_home() and w.mode == "explore":
				extracted += 1
			_drop(w)
		var rate := float(extracted) / SEEDS
		rates.append(rate)
		_report("shard depth %d" % depth, extracted, SEEDS, float(fights) / SEEDS, 0.0, 0.0, "  (rounds = fights per run)")
		assert_true(rate >= 0.5, "depth %d extracts %d/%d runs" % [depth, extracted, SEEDS])
	print("  balance extraction by depth: %s (depth scaling itself is pinned by test_stat_block)" % [rates])
	world = _fresh()
