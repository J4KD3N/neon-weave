## The races' mechanics (S67, D-123): a Synth repairs with parts and the
## Garden cannot touch it, a Skyborn reads the ruin (secret doors from
## farther, fragments where they lie), the Swarmborn disguise is a roll per
## talk, and every origin does something mechanical.
extends TestCase

const LEDGER := "user://test_ledger_races.json"
const SAVES := "user://test_saves_races"

const SECRET_MAP: Dictionary = {
	"id": "zz_secret", "name": "Secret yard", "biome": "rusted_undercity", "spawn_marker": "P",
	"legend": {".": "floor_concrete", "#": "wall_rust", "P": "floor_concrete", "?": "secret_door"},
	"rows": [
		"############",
		"#PPPP.....?#",
		"############",
	],
	"enemies": [],
}

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	world.settings_path = "user://test_settings_races.json"
	world.input_path = "user://test_input_races.json"
	_root().add_child(world)
	world.combat.animate = false


func after_each() -> void:
	_root().remove_child(world)
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


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _lead(race: String, origin: String = "corp_asset", arcane: int = 2) -> PartyMember:
	world.protagonist = {"name": "Lead", "race_id": race, "origin_id": origin, "class_id": "scrap_knight", "attributes": {"body": 4 - arcane + 2 - 2, "arcane": arcane, "tech": 2}}
	world.protagonist["attributes"]["body"] = 6 - arcane - 2
	world.respawn_party()
	return world.party.members[0]


func test_a_synth_repairs_with_parts_and_the_garden_cannot_touch_it() -> void:
	var unit := _lead("synth")
	assert_eq(unit.race_id, "synth")
	assert_eq(int(Dictionary(unit.traits["repair_with_parts"])["salvage"]), 3)
	assert_eq(world.repair_member("protagonist"), "nothing to mend", "at full health")
	unit.hp = 1
	assert_eq(world.repair_member("protagonist"), "needs 3 salvage", "no parts")
	world.ledger.bank({"salvage": 10})
	var rows: Array[Dictionary] = world.system_items()
	var found := false
	for row: Dictionary in rows:
		if String(row["id"]) == "repair_protagonist":
			found = true
			assert_true(bool(row["enabled"]))
			assert_contains(String(row["label"]), "Repair Lead with parts (3 salvage): +30% HP")
	assert_true(found, "the pause menu offers the repair")
	assert_eq(world.repair_member("protagonist"), "")
	assert_eq(unit.hp, 1 + int(ceil(unit.max_hp * 0.3)), "three parts, a third of the plates")
	assert_eq(world.ledger.total("salvage"), 7)
	assert_eq(world.repair_member("weaver") if world.member_by_id("weaver") != null else "nothing to repair with parts", "nothing to repair with parts", "flesh does not take rivets")
	world.mode = "combat"
	assert_eq(world.repair_member("protagonist"), "not in a fight")
	world.mode = "explore"
	unit.hp = 1
	assert_true(world.activate_system_item("repair_protagonist"), "through the menu")
	assert_eq(world.ledger.total("salvage"), 4)
	# The Garden is arcane: it closes what it can, and a Synth is not that.
	world.ledger.bank({"salvage": 40, "aether": 10})
	assert_true(world.upgrade_building("garden"))
	unit.hp = 1
	var other := world.party.members[1]
	other.hp = 1
	assert_true(world.tend_garden())
	assert_eq(unit.hp, 1, "nothing arcane healing can find")
	assert_true(other.hp > 1, "the others heal")
	# The med-bay is tech: it does.
	world.heal_party(0.25)
	assert_true(unit.hp > 1)
	# A downed Synth comes back with parts.
	unit.downed = true
	unit.hp = 0
	assert_eq(world.repair_member("protagonist"), "")
	assert_false(unit.downed)
	assert_true(unit.hp > 0)


func test_a_skyborn_reads_the_ruin() -> void:
	assert_true(world._enter(SECRET_MAP.duplicate(true)))
	var door := Vector2i(10, 1)
	assert_eq(world.map_data.door_kind(door), "secret")
	world.teleport_party(Vector2i(7, 1)) # a corridor: the followers settle at (8,1) and (6,1), the nearest two cells from the seam
	assert_eq(world.check_secrets(), 0, "no Skyborn: a secret door opens beside you only")
	assert_eq(world.map_data.door_kind(door), "secret")
	var sky := _lead("skyborn")
	assert_eq(int(sky.traits["secret_sight"]), 2)
	assert_true(world._enter(SECRET_MAP.duplicate(true)))
	world.teleport_party(Vector2i(7, 1))
	assert_true(world.check_secrets() >= 1, "a Skyborn reads the seam from two cells")
	assert_eq(world.map_data.door_kind(door), "", "open")
	assert_eq(world.party_trait_max("secret_sight"), 2.0)
	# A fragment read where it lies.
	var logged := world.narrative.log.size()
	var id := world.find_lore()
	assert_false(id.is_empty())
	assert_eq(world.narrative.log.size(), logged + 1, "the reading is in the history")
	var entry: Dictionary = world.narrative.log[world.narrative.log.size() - 1]
	assert_eq(String(entry["who"]), "Lead")
	assert_contains(String(entry["text"]), "reads the fragment:")
	assert_contains(String(entry["text"]), String(world.registry.get_entry("lore", id)["text"]).left(20))
	# Without a reader the fragment waits for the Archive.
	_lead("trueborn")
	logged = world.narrative.log.size()
	world.find_lore()
	assert_eq(world.narrative.log.size(), logged, "nobody read it")
	# The Beacon Keeper knows the way down too, one cell of it.
	world.account.unlock("origin:beacon_keeper")
	var keeper := _lead("trueborn", "beacon_keeper")
	assert_eq(int(keeper.traits["secret_sight"]), 1)


func test_the_swarmborn_disguise_is_a_roll_per_talk() -> void:
	var attr: Dictionary = world.registry.get_entry("rules", "attributes")
	assert_eq(ExploreWorld.disguise_chance(attr, 1), 0.0, "under the minimum: no face at all")
	assert_eq(ExploreWorld.disguise_chance(attr, 2), 0.5)
	assert_true(is_equal_approx(ExploreWorld.disguise_chance(attr, 4), 0.9))
	assert_eq(ExploreWorld.disguise_chance({"disguise_arcane_min": 2, "disguise_base_chance": 0.9, "disguise_per_arcane": 0.5}, 3), 1.0, "never past one")
	_lead("swarmborn", "corp_asset", 2)
	assert_true(bool(world.dialogue_ctx()["disguised"]), "out of a talk the old rule stands: arcane clears the bar")
	var held := 0
	var slipped := 0
	for seed_value: int in range(1, 41):
		world.detect_rng.seed = seed_value
		assert_true(world.talk_to("sera"), "the yard talk opens")
		if world.disguise_holds:
			held += 1
			assert_true(bool(world.dialogue_ctx()["disguised"]), "the roll is what the talk reads")
		else:
			slipped += 1
			assert_false(bool(world.dialogue_ctx()["disguised"]))
		world.leave_dialogue()
	assert_true(held >= 10 and slipped >= 10, "half and half over forty talks: %d held, %d slipped" % [held, slipped])
	_lead("swarmborn", "corp_asset", 1)
	world.detect_rng.seed = 5
	assert_true(world.talk_to("sera"))
	assert_false(world.disguise_holds, "arcane 1: no face")
	assert_false(bool(world.dialogue_ctx()["disguised"]))
	world.leave_dialogue()
	_lead("trueborn")
	world.detect_rng.seed = 5
	assert_true(world.talk_to("sera"))
	assert_false(world.disguise_holds, "no colony to reshape")
	world.leave_dialogue()


func test_every_origin_does_something_mechanical() -> void:
	var r := world.registry
	for o: Dictionary in r.get_all("origins"):
		assert_false(Dictionary(o.get("traits", {})).is_empty(), "%s has a trait" % o["id"])
	var touched := _lead("trueborn", "choir_touched")
	assert_eq(int(touched.traits["detect_hidden"]), 2, "the Choir-touched hear the hidden")
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_eq(int(world.combat.state.by_id("p:protagonist").traits.get("detect_hidden", 0)), 2, "and the fight knows")
	world.combat.state._finish("victory")
	world._on_combat_ended("victory")
	var corp := _lead("trueborn", "corp_asset")
	assert_eq(int(corp.traits["talent_cost_mod"]), -2, "corporate training on top of Trueborn thrift")
	var vault := _lead("trueborn", "vault_child")
	assert_true(is_equal_approx(float(vault.traits["mend_after_combat"]), 0.1), "vault medicine")
	var runner := _lead("trueborn", "scav_runner")
	assert_eq(int(runner.traits["stealth"]), 1)
	# The validator refuses a repair trait with no parts and a sight of nothing.
	r.put("races", "zz_tin", {"name": "Tin", "overlay": {"kind": "plating", "color": "#888888"}, "art": {"placeholder": "rig"}, "traits": {"repair_with_parts": {"salvage": 0, "heal": 2.0}, "secret_sight": 0}})
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "traits.repair_with_parts needs salvage of at least 1")
	assert_any_contains(problems, "traits.secret_sight must be at least 1")
	r._entries["races"].erase("zz_tin")
	r._fingerprint_cache = ""
