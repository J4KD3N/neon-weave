## Bastion v2 (S35, D-090): seven buildings on the plaza; lore fragments
## found in Shards ride the story and read in the Archive; the Garden adds
## healing on return and pays Aether at level 2; a Quarters scene fires from
## approval once the Quarters stand; an origin earned in one playthrough is
## on the creator of the next.
extends TestCase

const LEDGER := "user://test_ledger_bv2.json"
const SAVES := "user://test_saves_bv2"
const ACCOUNT := "user://test_account_bv2.json"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh()


func after_each() -> void:
	_drop(world)
	_cleanup()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cleanup() -> void:
	for f: String in [LEDGER, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.account_path = ACCOUNT
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _raise(id: String, to: int) -> void:
	world.ledger.buildings[id] = to
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)


func test_seven_buildings_stand_on_the_plaza_in_order() -> void:
	assert_eq(world.bastion.order, ["beacon", "medbay", "workshop", "arcanum", "archive", "garden", "quarters"])
	assert_eq(world.map_id, "bastion")
	var placed: Array[String] = []
	for b: BuildingActor in world.buildings:
		placed.append(b.building_id)
	for id: String in world.bastion.order:
		assert_true(placed.has(id), "%s stands on the plaza" % id)
		assert_eq(world.bastion.max_level(id), 2)
	for b: BuildingActor in world.buildings:
		assert_true(world.map_data.is_walkable(b.cell + Vector2i(0, 1)) or world.map_data.is_walkable(b.cell + Vector2i(1, 0)), "%s can be walked up to" % b.building_id)


func test_fragments_ride_the_story_and_read_in_the_archive() -> void:
	var r := world.registry
	assert_true(r.count("lore") >= 8)
	assert_contains(world.archive_text(), "0 of %d fragments" % r.count("lore"))
	assert_contains(world.archive_text(), "sealed")
	# A fragment pickup in a Shard.
	world.enter_shard("rusted_undercity", 7)
	var cell := world.leader_cell()
	var actor := PickupActor.new()
	actor.setup("lore_fragment", r.get_entry("pickups", "lore_fragment"), cell)
	actor.position = world.map_view.cell_to_world(cell)
	world.pickups_node.add_child(actor)
	world.pickups.append(actor)
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_eq(String(Dictionary(gained[0])["lore"]), "council_minute_one", "history order: the first gap fills first")
	assert_eq(world.narrative.lore, ["council_minute_one"])
	# A wipe keeps it: it is story, not haul.
	world._on_combat_ended("defeat")
	world.return_home()
	assert_eq(world.narrative.lore.size(), 1)
	assert_contains(world.archive_text(), "a gap in the record")
	assert_false(world.archive_text().contains("Item four"), "sealed: nothing reads yet")
	_raise("archive", 1)
	assert_true(world.open_archive())
	assert_true(world.archive_menu.visible)
	assert_contains(world.archive_text(), "1. Council minute, session 1140  (a council chamber)")
	assert_contains(world.archive_text(), "Item four")
	assert_contains(world.archive_text(), "2. — a gap in the record —")
	world.close_archive()
	# Level 2 pays insight per new fragment; the record completes in order.
	_raise("archive", 2)
	var aether := world.ledger.total("aether")
	assert_eq(world.find_lore(), "maintenance_log_weft")
	assert_eq(world.ledger.total("aether"), aether + 1)
	var found := 2
	while not world.find_lore().is_empty():
		found += 1
	assert_eq(found, r.count("lore"))
	assert_eq(world.find_lore(), "", "the record is complete")
	assert_contains(world.archive_text(), "%d of %d fragments" % [found, found])
	# Saved with the story.
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.narrative.lore.size(), found)
	_drop(again)
	# Fragments sit in every Shard pool.
	for t: Dictionary in r.get_all("shards"):
		var pool: Array = Dictionary(ShardGenerator.expand_remix(t, r).get("pickups", {})).get("pool", [])
		var has := false
		for p: Dictionary in pool:
			if String(p.get("type", "")) == "lore_fragment":
				has = true
		assert_true(has, "%s can hold a fragment" % t["id"])


func test_the_garden_heals_on_return_and_pays_aether_at_level_two() -> void:
	assert_true(is_equal_approx(world.bastion.heal_fraction(), 0.25))
	_raise("garden", 1)
	assert_true(is_equal_approx(world.bastion.heal_fraction(), 0.4), "Med-bay 0.25 plus the bed 0.15")
	var m := world.party.members[0]
	m.hp = 1
	assert_true(world.tend_garden())
	assert_eq(m.hp, 1 + int(ceil(m.max_hp * 0.15)))
	_raise("garden", 0)
	m.hp = 1
	assert_false(world.tend_garden(), "one stubborn vine heals nobody")
	assert_eq(m.hp, 1)
	_raise("garden", 2)
	world.enter_shard("rusted_undercity", 8)
	var aether := world.ledger.total("aether")
	world.teleport_party(world.extraction_cell())
	assert_true(world.extract())
	assert_eq(world.ledger.total("aether"), aether + 1, "an Aether of sap per extraction")


func test_a_quarters_scene_fires_from_approval_once() -> void:
	world.narrative.recruit("sera")
	world.narrative.recruit("dax")
	world.respawn_party()
	assert_false(world.open_quarters(), "bunks in a container")
	_raise("quarters", 1)
	assert_eq(world.quarters_scenes().size(), 0, "nobody trusts you enough yet")
	world.narrative.add_approval("sera", 3)
	var scenes := world.quarters_scenes()
	assert_eq(scenes.size(), 1)
	assert_eq(String(Dictionary(scenes[0])["companion"]), "sera")
	assert_true(world.open_quarters())
	assert_true(world.system_menu.visible)
	assert_contains(world.system_menu.label.text, "Sera")
	assert_true(world.activate_system_item("scene_sera_quarters"))
	assert_true(world.in_dialogue())
	assert_eq(world.dialogue.node_id, "start")
	var before := world.narrative.approval_of("sera")
	assert_true(world.choose(1))
	while world.in_dialogue():
		world.choose(0)
	assert_eq(world.narrative.approval_of("sera"), before + 3)
	assert_true(world.narrative.flag("sera_quarters_together"))
	assert_eq(world.quarters_scenes().size(), 0, "once")
	assert_true(world.narrative.flag("scene_sera_quarters_seen"))
	world.narrative.add_approval("dax", 3)
	assert_eq(String(Dictionary(world.quarters_scenes()[0])["companion"]), "dax")


func test_an_origin_earned_once_is_on_the_creator_next_time() -> void:
	var r := world.registry
	var keeper := r.get_entry("origins", "beacon_keeper")
	assert_eq(String(keeper["unlock_flag"]), "choir_contact")
	assert_true(world.open_creator())
	assert_false(world.creator_state.origins.has("beacon_keeper"), "locked on a fresh account")
	world.close_creator()
	assert_eq(world.account.unlocked, [])
	world.narrative.set_flag("choir_contact", true)
	assert_eq(world.grant_account_unlocks(), ["origin:beacon_keeper"])
	assert_eq(world.grant_account_unlocks(), [], "once")
	assert_true(FileAccess.file_exists(ACCOUNT))
	# A second playthrough on the same account.
	var again := _fresh()
	assert_true(again.account.has("origin:beacon_keeper"))
	assert_true(again.open_creator())
	assert_true(again.creator_state.origins.has("beacon_keeper"), "the creator offers it")
	again.close_creator()
	again.protagonist = {"name": "Keeper", "race_id": "trueborn", "origin_id": "beacon_keeper", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}}
	assert_eq(again.set_protagonist(again.protagonist, false), [])
	assert_eq(again.party.leader().origin_id, "beacon_keeper")
	_drop(again)
	# Autosave grants without being asked.
	var w := _fresh()
	w.account.unlocked.clear()
	w.narrative.set_flag("choir_contact", true)
	w.autosave()
	assert_true(w.account.has("origin:beacon_keeper"))
	_drop(w)
