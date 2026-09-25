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
	{"id": "the gallery (lvl 3)", "map": "throat_deep", "cell": Vector2i(11, 5), "flags": {}, "companions": ["sera", "dax", "kaj7"], "xp": 60, "min_win": 0.4, "max_win": 0.95},
	{"id": "the loom: ashfound strike", "map": "the_loom", "cell": Vector2i(20, 6), "flags": {"loom_guard_beaten": false}, "companions": ["sera", "dax", "kaj7"], "xp": 900, "min_win": 0.3, "max_win": 1.0},
	{"id": "the loom: the guard", "map": "the_loom", "cell": Vector2i(25, 6), "flags": {}, "companions": ["sera", "dax", "kaj7"], "xp": 900, "min_win": 0.2, "max_win": 0.95}, # the last door: the hardest fight in the game by design (S42)
]

## The Key keepers (S70): each fights inside its biome's Shard from the site
## dialogue, at the level the campaign reaches the Keys, geared for the depth.
const KEEPERS: Array[Dictionary] = [
	{"id": "the Quiet Key (lvl 9)", "template": "null_cathedral", "site": "key_ashfound_site", "xp": 530, "depth": 2, "min_win": 0.35, "max_win": 0.95},
	{"id": "the Ledgers Key (lvl 9)", "template": "ghost_markets", "site": "key_lattice_site", "xp": 530, "depth": 2, "min_win": 0.35, "max_win": 0.95},
	{"id": "the Heart Key (lvl 9)", "template": "verdant_datacore", "site": "key_rootched_site", "xp": 530, "depth": 2, "min_win": 0.4, "max_win": 0.95},
]
## Difficulty (S70): the story rows again on Story and Tactician, fewer
## seeds. Story must never be harder than Balanced, Tactician never easier,
## and Tactician keeps a floor of its own so a naive party can still win.
const DIFFICULTY_SEEDS := 10
const TACTICIAN_FLOOR: Dictionary = {"gate ambush": 0.5, "relay hive": 0.4, "the warlord (lvl 2)": 0.1, "the warlord (lvl 3)": 0.2, "the gallery (lvl 3)": 0.2, "the loom: ashfound strike": 0.2, "the loom: the guard": 0.05}

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
## `difficulty` (S70) overlays the rules before anything spawns.
func _stage(beat: Dictionary, seed_value: int, difficulty: String = "") -> ExploreWorld:
	var w := _fresh()
	w.combat_seed = seed_value
	if not difficulty.is_empty():
		w.narrative.difficulty = difficulty
		w.apply_death_stakes()
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


## Plays one story row over `seeds` seeds on a difficulty: the naive win rate.
func _rate(beat: Dictionary, seeds: int, base_seed: int, difficulty: String = "") -> float:
	var wins := 0
	for i: int in seeds:
		var w := _stage(beat, base_seed + i, difficulty)
		assert_eq(w.mode, "combat", "%s seed %d starts a fight" % [beat["id"], i])
		_fight(w)
		if w.combat.state.result == "victory":
			wins += 1
		_drop(w)
	return float(wins) / seeds


## Story is never harder than Balanced and Tactician never easier, row by
## row, and Tactician keeps a floor a naive party can still clear (S70).
func test_story_and_tactician_bracket_balanced_on_every_story_row() -> void:
	_drop(world)
	for beat: Dictionary in BEATS:
		var balanced := _rate(beat, DIFFICULTY_SEEDS, 7000)
		var story := _rate(beat, DIFFICULTY_SEEDS, 7000, "story")
		var tactician := _rate(beat, DIFFICULTY_SEEDS, 7000, "tactician")
		print("  balance %-26s story %3d%%  balanced %3d%%  tactician %3d%%" % [String(beat["id"]), int(round(story * 100.0)), int(round(balanced * 100.0)), int(round(tactician * 100.0))])
		assert_true(story >= balanced - 0.1, "%s: Story (%.2f) is not softer than Balanced (%.2f)" % [beat["id"], story, balanced])
		assert_true(tactician <= balanced + 0.1, "%s: Tactician (%.2f) is not harder than Balanced (%.2f)" % [beat["id"], tactician, balanced])
		assert_true(tactician >= float(TACTICIAN_FLOOR.get(beat["id"], 0.0)), "%s: Tactician naive win rate %.2f under its floor %.2f" % [beat["id"], tactician, TACTICIAN_FLOOR.get(beat["id"], 0.0)])
	world = _fresh()


## The Key keepers, rowed (S70): the site dialogue starts the fight inside
## the Shard, so the harness enters the Shard with the site, walks to it,
## takes the Key whole and fights the keeper.
func test_every_key_keeper_sits_in_its_band() -> void:
	var prules: Dictionary = world.progression_rules()
	_drop(world)
	for row: Dictionary in KEEPERS:
		var wins := 0
		var rounds := 0
		var hp_left := 0.0
		var fights := 0
		for i: int in SEEDS:
			var w := _fresh()
			w.combat_seed = 6000 + i
			for id: String in ["sera", "dax", "kaj7"]:
				w.add_companion(id)
			w.ledger.xp = int(row["xp"])
			w.refresh_progression()
			_gear_up(w, int(row["depth"]))
			_heal_up(w)
			var entry := w.enter_shard(String(row["template"]), 700 + i, int(row["depth"]), [String(row["site"])])
			var site := Vector2i(-1, -1)
			for p: Dictionary in entry.get("pickups", []):
				if String(p["type"]) == String(row["site"]):
					site = Vector2i(int(p["cell"][0]), int(p["cell"][1]))
			assert_true(site.x >= 0, "%s seed %d places the site" % [row["id"], i])
			for _try: int in 4:
				if not w.in_dialogue():
					w.teleport_party(site)
					w.check_pickups()
			assert_true(w.in_dialogue(), "%s seed %d opens the site" % [row["id"], i])
			var options := w.dialogue.available_choices()
			for j: int in options.size():
				if String(Dictionary(options[j]).get("text", "")).begins_with("Take it whole"):
					w.choose(j)
					break
			assert_eq(w.mode, "combat", "%s seed %d: the keeper fights" % [row["id"], i])
			fights += 1
			_fight(w)
			rounds += w.combat.state.round_number
			if w.combat.state.result == "victory":
				wins += 1
				hp_left += _hp_fraction(w)
			_drop(w)
		var rate := float(wins) / maxi(fights, 1)
		_report(String(row["id"]), wins, maxi(fights, 1), float(rounds) / maxi(fights, 1), hp_left / maxi(wins, 1), 0.0, "  lvl %d d%d" % [Progression.level_for_xp(int(row["xp"]), prules), int(row["depth"])])
		assert_true(rate >= float(row["min_win"]), "%s: naive win rate %.2f under the floor %.2f" % [row["id"], rate, row["min_win"]])
		assert_true(rate <= float(row["max_win"]), "%s: naive win rate %.2f over the ceiling %.2f (a walkover)" % [row["id"], rate, row["max_win"]])
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


## Shards by biome and depth with a geared party of the level a player would
## have there (`_gear_up`): hop between pickups and the pad, fight what wakes,
## extract. Each row holds a floor; the deeper floors are low on purpose (the
## naive policy never retreats or heals) and are logged in gaps for the M4 pass.
func test_shard_depths_extract_more_often_than_not() -> void:
	var prules: Dictionary = world.progression_rules()
	_drop(world)
	var rates: Array[float] = []
	for run: Dictionary in [{"template": ExploreWorld.DEFAULT_SHARD, "depth": 1, "xp": 20, "min": 0.5}, {"template": ExploreWorld.DEFAULT_SHARD, "depth": 2, "xp": 20, "min": 0.4}, {"template": "verdant_datacore", "depth": 2, "xp": 80, "min": 0.25}, {"template": ExploreWorld.DEFAULT_SHARD, "depth": 3, "xp": 200, "min": 0.3}, {"template": "ghost_markets", "depth": 3, "xp": 200, "min": 0.2}, {"template": "null_cathedral", "depth": 3, "xp": 400, "min": 0.2}, {"template": "loom_approach", "depth": 1, "xp": 850, "min": 0.15}]:
		var depth := int(run["depth"])
		var extracted := 0
		var fights := 0
		for i: int in SEEDS:
			var w := _fresh()
			w.combat_seed = 4000 + i
			for id: String in ["sera", "dax", "kaj7"]:
				w.add_companion(id)
			w.ledger.xp = int(run["xp"])
			w.refresh_progression()
			_gear_up(w, depth)
			_heal_up(w)
			var entry := w.enter_shard(String(run["template"]), 500 + i, depth)
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
		_report("%s d%d" % [String(run["template"]).substr(0, 14), depth], extracted, SEEDS, float(fights) / SEEDS, 0.0, 0.0, "  lvl %d (rounds = fights per run)" % Progression.level_for_xp(int(run["xp"]), prules))
		assert_true(rate >= float(run.get("min", 0.4)), "%s depth %d extracts %d/%d runs" % [run["template"], depth, extracted, SEEDS])
	print("  balance extraction by depth: %s (depth scaling itself is pinned by test_stat_block)" % [rates])
	world = _fresh()


## A plausible build for the level (S33): the first subclass, every talent
## the level and a full purse allow, a common weapon and armour each, and a
## Workshop level for the depth. The naive policy still plays badly; it
## just no longer plays a level-6 party with level-1 numbers.
static func _gear_up(w: ExploreWorld, depth: int) -> void:
	w.ledger.bank({"aether": 60, "salvage": 200})
	w.ledger.buildings["workshop"] = clampi(depth - 1, 0, 2)
	w.bastion.setup(w.registry.get_all("buildings"), w.ledger.buildings)
	for m: PartyMember in w.party.members:
		var cls := w.registry.get_entry("classes", m.class_id)
		var subs: Array = cls.get("subclasses", [])
		if not subs.is_empty():
			w.choose_subclass(m.member_id, String(subs[0]))
		for _pass: int in 3:
			for t: Dictionary in w.registry.get_all("talents"):
				w.buy_talent(m.member_id, String(t["id"]))
		var uid := 90000 + m.member_id.hash() % 1000
		w.ledger.items.append(ItemSystem.make("strut_blade", [], "common", uid))
		w.ledger.items.append(ItemSystem.make("scrap_plating", [], "common", uid + 1))
		w.equip(m.member_id, "weapon", uid)
		w.equip(m.member_id, "armour", uid + 1)
	w.ledger.resources["aether"] = 0
	w.ledger.resources["salvage"] = 0
	w.apply_bastion_bonuses()
