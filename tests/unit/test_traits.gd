## Race hooks as generic traits (S30, D-085): every one is a rule any
## entry can carry, exercised here on fixture combatants and on the world:
## resist (and weakness), regen on a surface, detecting hidden enemies,
## per-ability damage, arcane heal immunity, bonus abilities, salvage
## bonus, mending after a fight, talent cost, race tags in conditions.
## Plus: all ten races exist, are playable, and stamp an overlay.
extends TestCase

const LEDGER := "user://test_ledger_traits.json"
const SAVES := "user://test_saves_traits"
const TILES: Dictionary = {
	"floor": {"id": "floor", "walkable": true},
	"acid": {"id": "acid", "walkable": true, "surface": "corrosive"},
}
const ABILITIES: Dictionary = {
	"strike": {"id": "strike", "name": "Strike", "ap": 2, "range": 1, "damage": [4, 4], "accuracy": 100, "damage_type": "physical"},
	"bolt": {"id": "bolt", "name": "Bolt", "ap": 2, "range": 4, "damage": [4, 4], "accuracy": 100, "damage_type": "arcane"},
	"zap": {"id": "zap", "name": "Zap", "ap": 2, "range": 4, "damage": [4, 4], "accuracy": 100, "damage_type": "tech"},
	"hide": {"id": "hide", "name": "Hide", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "stealth", "duration": 3},
	"mend": {"id": "mend", "name": "Mend", "ap": 1, "range": 0, "damage": [0, 0], "accuracy": 100, "targets": "self", "effect": "vent", "heal": 3, "damage_type": "arcane"},
}

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.combat.animate = false


func after_each() -> void:
	(Engine.get_main_loop() as SceneTree).root.remove_child(world)
	world.free()
	_cleanup()


static func _cleanup() -> void:
	if FileAccess.file_exists(LEDGER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEDGER))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


static func _map(rows: Array) -> MapData:
	return MapData.parse({"id": "t", "legend": {".": "floor", "a": "acid", "P": "floor"}, "rows": rows}, TILES)


static func _c(id: String, team: String, cell: Vector2i, abilities: Array[String], traits: Dictionary = {}) -> Combatant:
	var c := Combatant.make(id, id, team, cell, {"hp": 10, "move": 4, "evasion": 0, "initiative": 0}, abilities, 4)
	c.traits = traits
	return c


func _state(rows: Array, combatants: Array[Combatant], first: String) -> CombatState:
	var s := CombatState.new()
	var rules := CombatRules.new()
	rules.initiative_die = 1
	rules.story_protected = false
	rules.max_hit_chance = 100 # the fixtures roll at 100%: no misses to explain
	s.setup(_map(rows), rules, ABILITIES, combatants, 1)
	s.start(first)
	return s


func test_all_ten_races_are_playable_content_with_overlays() -> void:
	var r := world.registry
	var ids: Array[String] = []
	for race: Dictionary in r.get_all("races"):
		ids.append(String(race["id"]))
		assert_true(bool(race.get("playable", true)), "%s is playable" % race["id"])
		if String(race.get("_source", "")) != "base":
			continue # a mod race (the example mod) is not held to the base bar
		var kind := String(Dictionary(race.get("overlay", {})).get("kind", ""))
		assert_true(PlaceholderActorArt.OVERLAY_KINDS.has(kind), "%s overlay kind %s is drawable" % [race["id"], kind])
		for key: String in race.get("traits", {}):
			assert_true(["resist", "regen_on_surface", "detect_hidden", "salvage_bonus", "mend_after_combat", "bonus_abilities", "ability_damage_bonus", "heal_immune_types", "talent_cost_mod", "tags"].has(key), "%s trait %s is in the vocabulary" % [race["id"], key])
	for want: String in ["trueborn", "chromed", "aetherborn", "synth", "rootkin", "hollow", "splicekin", "vaultkin", "skyborn", "swarmborn"]:
		assert_true(ids.has(want), "race %s" % want)
	assert_true(ids.size() >= 10)
	var st := CreatorState.new()
	st.setup(r, world.rules)
	assert_true(st.races.size() >= 10, "all ten in the creator (plus any mod race)")
	# Every overlay kind stamps something on the shared rig and keeps its silhouette.
	for kind: String in PlaceholderActorArt.OVERLAY_KINDS:
		if kind == "none":
			continue
		var plain := PlaceholderActorArt.body_image(Color.RED, "capsule", {"kind": "none"})
		var stamped := PlaceholderActorArt.body_image(Color.RED, "capsule", {"kind": kind, "color": "#00ff00"})
		var changed := 0
		for y: int in plain.get_height():
			for x: int in plain.get_width():
				assert_eq(plain.get_pixel(x, y).a == 0.0, stamped.get_pixel(x, y).a == 0.0, "%s keeps the silhouette at %d,%d" % [kind, x, y])
				if plain.get_pixel(x, y) != stamped.get_pixel(x, y):
					changed += 1
		assert_true(changed > 0, "%s stamps pixels" % kind)


func test_resist_shrugs_off_a_fraction_and_weakness_adds() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["bolt", "zap"])
	var stone := _c("s", "enemy", Vector2i(2, 0), ["strike"], {"resist": {"arcane": 0.5}})
	var glass := _c("g", "enemy", Vector2i(0, 2), ["strike"], {"resist": {"tech": -0.25}})
	var s := _state(["....", "....", "...."], [p, stone, glass], "party")
	var hit := s.use_ability(p, "bolt", stone.cell)
	assert_eq(stone.hp, 8, "4 arcane, half shrugged: %s" % [hit])
	assert_eq(int(hit.get("resisted", 0)), 2)
	var zap := s.use_ability(p, "zap", glass.cell)
	assert_eq(glass.hp, 5, "4 tech and a quarter more on a weakness: %s" % [zap])
	assert_eq(int(zap.get("resisted", 0)), -1)
	assert_eq(Combatant.new().resist("arcane"), 0.0, "no traits, no resist")


func test_surfaces_burn_the_unprotected_feed_rootkin_and_spare_the_immune() -> void:
	var soft := _c("soft", "party", Vector2i(0, 0), ["strike"])
	var root := _c("root", "party", Vector2i(1, 0), ["strike"], {"resist": {"corrosive": 1.0}, "regen_on_surface": {"corrosive": 2}})
	var vault := _c("vault", "party", Vector2i(2, 0), ["strike"], {"resist": {"corrosive": 0.5}})
	var e := _c("e", "enemy", Vector2i(3, 2), ["strike"])
	root.hp = 5 # before the state: the party group begins every turn at once
	var s := _state(["aaa.", "....", "...."], [soft, root, vault, e], "party")
	# The party's grouped turns begin as each is entered: end turns to walk the order.
	var seen: Dictionary = {}
	for _i: int in 4:
		var actor := s.current()
		seen[actor.id] = actor.hp
		s.end_turn()
	assert_eq(int(seen["soft"]), 8, "2 corrosive damage on the biogrowth")
	assert_eq(int(seen["root"]), 7, "the Rootkin healed 2 instead")
	assert_eq(int(seen["vault"]), 9, "half shrugged")
	assert_any_contains(s.history, "mends 2 in the corrosive")


func test_detect_hidden_reveals_a_stalker_in_range() -> void:
	var p := _c("p", "party", Vector2i(0, 0), ["strike"], {"detect_hidden": 2})
	var blind := _c("b", "party", Vector2i(0, 2), ["strike"])
	var lurker := _c("l", "enemy", Vector2i(2, 0), ["strike", "hide"])
	var s := _state(["....", "....", "...."], [lurker, p, blind], "enemy")
	assert_eq(s.current(), lurker)
	s.use_ability(lurker, "hide", lurker.cell)
	assert_true(lurker.hidden)
	s.end_turn()
	if s.current() != p:
		s.switch_to("p") # turns begin lazily on the switch
	assert_false(lurker.hidden, "the detector took its turn within two cells: revealed")
	assert_any_contains(s.history, "senses l hiding")
	assert_true(EnemyBrain.nearest_hostile(s, blind) == lurker, "and everyone can target it now")


func test_ability_damage_bonus_and_heal_immunity() -> void:
	var claw := _c("c", "party", Vector2i(0, 0), ["strike", "bolt"], {"ability_damage_bonus": {"strike": 1}})
	var e := _c("e", "enemy", Vector2i(1, 0), ["strike"])
	var s := _state(["....", "...."], [claw, e], "party")
	s.use_ability(claw, "strike", e.cell)
	assert_eq(e.hp, 5, "4 + 1 on strikes only")
	s.use_ability(claw, "bolt", e.cell)
	assert_eq(e.hp, 1, "no bonus on the bolt")
	var synth := _c("y", "party", Vector2i(0, 1), ["mend"], {"heal_immune_types": ["arcane"]})
	var soft := _c("s", "party", Vector2i(1, 1), ["mend"])
	var s2 := _state(["....", "...."], [synth, soft, _c("z", "enemy", Vector2i(3, 1), ["strike"])], "party")
	synth.hp = 5
	soft.hp = 5
	s2.switch_to("y")
	assert_eq(s2.use_ability(synth, "mend", synth.cell).get("type", ""), "vent")
	assert_eq(synth.hp, 5, "arcane mending does nothing for a Synth")
	s2.switch_to("s")
	assert_eq(s2.use_ability(soft, "mend", soft.cell).get("type", ""), "vent")
	assert_eq(soft.hp, 8)


func test_the_world_carries_traits_into_fights_banking_and_talents() -> void:
	var r := world.registry
	# Aetherborn: the innate spark rides along whatever the class.
	world.protagonist = {"name": "Lio", "race_id": "aetherborn", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	var lio := world.party.members[0]
	assert_eq(lio.race_id, "aetherborn")
	assert_true(lio.abilities.has("weft_spark"), "bonus ability from the race: %s" % [lio.abilities])
	assert_eq(float(Dictionary(lio.traits["resist"])["tech"]), -0.25)
	# Traits reach the combatant.
	world.enter_shard("rusted_undercity", 7)
	world.spawn_summoned("scav", world.leader_cell() + Vector2i(1, 0))
	world.start_combat(true)
	var c := world.combat.state.by_id("p:protagonist")
	assert_true(c != null and c.traits.has("resist"), "combatant traits")
	world.combat.state._finish("victory")
	world._on_combat_ended("victory")
	# Salvage bonus: a Vaultkin in the party lifts what is banked.
	world.protagonist = {"name": "Dun", "race_id": "vaultkin", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	assert_true(world.party.members[0].abilities.size() >= 1)
	assert_eq(world.party_trait_total("salvage_bonus"), 0.2)
	var before := world.ledger.total("salvage")
	world._bank({"salvage": 10, "aether": 0, "ciphers": 0, "xp": 0}, false)
	assert_eq(world.ledger.total("salvage"), before + 12, "20% more Salvage")
	# Mending after a fight: a Swarmborn closes wounds on victory.
	world.protagonist = {"name": "Many", "race_id": "swarmborn", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	var many := world.party.members[0]
	many.hp = 4
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_eq(many.hp, 4 + int(ceil(many.max_hp * 0.25)), "a quarter mended")
	# Talent cost: Trueborn pay one less Aether.
	world.protagonist = {"name": "Ada", "race_id": "trueborn", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	var talent_id := String(r.get_all("talents")[0]["id"])
	var list_cost := int(Dictionary(r.get_entry("talents", talent_id).get("cost", {})).get("aether", 0))
	assert_eq(Progression.talent_cost(r, talent_id, -1), maxi(list_cost - 1, 0))
	assert_eq(Progression.talent_cost(r, talent_id, -99), 0, "never below zero")
	# Race tags gate dialogue.
	world.protagonist = {"name": "Sky", "race_id": "skyborn", "origin_id": "corp_asset", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	world.respawn_party()
	var ctx := world.dialogue_ctx()
	assert_true(Array(ctx["race_tags"]).has("old_world"))
	assert_true(Conditions.passes({"race_tag": "old_world"}, ctx))
	assert_false(Conditions.passes({"race_tag": "hollow"}, ctx))


func test_traits_merge_across_sources() -> void:
	var m := PartyBuilder.merge_traits([{"resist": {"arcane": 0.25}, "tags": ["a"], "detect_hidden": 1}, {"resist": {"arcane": 0.25, "tech": 0.5}, "tags": ["a", "b"], "detect_hidden": 2, "bonus_abilities": ["x"]}])
	assert_eq(float(Dictionary(m["resist"])["arcane"]), 0.5, "numbers inside add")
	assert_eq(float(Dictionary(m["resist"])["tech"]), 0.5)
	assert_eq(m["tags"], ["a", "b"], "arrays union")
	assert_eq(float(m["detect_hidden"]), 3.0)
	assert_eq(m["bonus_abilities"], ["x"])
	assert_eq(PartyBuilder.merge_traits([null, {}]), {})
