## Sera in the real scene: recruitment, persistence, her quest site in
## Shards on every death-stakes path, Mortal-mode deaths, banter.
extends TestCase

const LEDGER := "user://test_ledger_sera.json"
const SAVES := "user://test_saves_sera"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	world = _fresh_scene()


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


func _fresh_scene() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.map_id = "proto_yard"
	w.home_map = "proto_yard"
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(scene: ExploreWorld) -> void:
	_root().remove_child(scene)
	scene.free()


func _recruit_sera() -> void:
	assert_true(world.talk_to("sera"))
	assert_true(world.choose(0)) # short a shield -> why
	assert_true(world.choose(0)) # come with us -> recruit, end


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry["pickups"]:
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


func test_sera_waits_in_the_yard_and_can_be_recruited() -> void:
	assert_eq(world.party.members.size(), 3)
	var npc := world.npc_at(Vector2i(5, 3))
	assert_true(npc != null, "Sera stands in the yard")
	assert_eq(npc.companion_id, "sera")
	assert_true(npc.uses_sheet(), "trueborn sheet")
	assert_true(world.talk_to("sera"))
	assert_true(world.in_dialogue())
	assert_eq(world.dialogue.speaker(), "sera")
	assert_contains(world.dialogue_menu.label.text, "Sera: You")
	assert_eq(world.dialogue.available_choices().size(), 2, "origin-gated lines hidden for a leader without an origin")
	assert_true(world.choose(0))
	assert_eq(world.dialogue.node_id, "why")
	assert_true(world.choose(0))
	assert_false(world.in_dialogue())
	assert_true(world.narrative.is_recruited("sera"))
	assert_eq(world.narrative.approval_of("sera"), 1)
	assert_eq(world.narrative.stage_of("sera_purge_village"), "start")
	assert_eq(world.party.members.size(), 4)
	var sera := world.party.members[3]
	assert_eq(sera.member_id, "sera")
	assert_eq(sera.display_name, "Sera")
	assert_eq(sera.class_id, "scrap_knight")
	assert_true(sera.uses_sheet())
	assert_true(world.map_data.is_walkable(world.member_cell(sera)))
	assert_true(world.npc_at(Vector2i(5, 3)) == null, "the NPC stand-in is gone")
	assert_contains(world.status_line(), "Sera ♥+1")
	assert_true(world.talk_to("sera"))
	assert_eq(world.dialogue.node_id, "recruited")
	assert_true(world.leave_dialogue())
	assert_false(world.in_dialogue())
	assert_true(FileAccess.file_exists(world.save_path("autosave")), "dialogue end autosaves")


func test_origin_gates_a_recruit_line() -> void:
	var vex := {"name": "Vex", "race_id": "chromed", "origin_id": "vault_child", "class_id": "circuit_witch", "attributes": {"body": 1, "arcane": 3, "tech": 2}}
	assert_eq(world.set_protagonist(vex), [])
	assert_true(world.talk_to("sera"))
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	assert_eq(texts.size(), 3)
	assert_true(String(texts[1]).begins_with("[Vault]"))
	world.leave_dialogue()


func test_recruit_persists_through_save_and_load() -> void:
	_recruit_sera()
	assert_eq(world.save_slot(1), OK)
	var again := _fresh_scene()
	assert_eq(again.party.members.size(), 3)
	assert_true(again.npc_at(Vector2i(5, 3)) != null)
	assert_eq(again.load_slot(1), [])
	assert_eq(again.party.members.size(), 4)
	assert_eq(again.party.members[3].member_id, "sera")
	assert_true(again.npc_at(Vector2i(5, 3)) == null)
	assert_true(again.narrative.is_recruited("sera"))
	assert_eq(again.narrative.stage_of("sera_purge_village"), "start")
	_drop(again)


func test_quest_site_appears_in_shards_and_resolves_with_sera() -> void:
	_recruit_sera()
	assert_eq(world.quest_sites(), ["sera_village_site"])
	var entry := world.enter_shard("rusted_undercity", 7)
	assert_true(world.narrative.flag("sera_banter_first_shard"), "banter fired on entering")
	assert_eq(ShardValidator.validate(entry, world.tiles_by_id()), [])
	var site := _site_cell(entry, "sera_village_site")
	assert_true(site.x >= 0, "the Ninth Stair is placed")
	assert_true(world.map_data.is_walkable(site))
	var gen: Dictionary = entry["generation"]
	assert_eq(gen["extra_pickups"], ["sera_village_site"])
	world.teleport_party(site)
	var gained := world.check_pickups()
	assert_eq(gained.size(), 1)
	assert_eq(gained[0]["dialogue"], "sera_village")
	assert_true(world.in_dialogue())
	assert_eq(world.dialogue.node_id, "with_sera")
	assert_eq(world.dialogue.available_choices().size(), 2, "the approval-gated line needs 2")
	assert_true(world.choose(0))
	assert_eq(world.dialogue.node_id, "seen_kind")
	assert_eq(world.narrative.stage_of("sera_purge_village"), "seen")
	assert_true(world.choose(0))
	assert_false(world.in_dialogue())
	assert_eq(world.narrative.stage_of("sera_purge_village"), "done")
	assert_eq(world.narrative.approval_of("sera"), 2)
	assert_eq(world.quest_sites(), [], "no site once the stage moved on")
	assert_true(world.run.is_empty(), "the site grants nothing")


func test_quest_site_alone_and_posthumous_paths() -> void:
	world.narrative.set_stage("sera_purge_village", "start")
	var entry := world.enter_shard("rusted_undercity", 7)
	world.teleport_party(_site_cell(entry, "sera_village_site"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "alone", "not recruited")
	assert_true(world.choose(0))
	assert_eq(world.narrative.stage_of("sera_purge_village"), "done_alone")
	world.enter_map("proto_yard")
	world.narrative.set_stage("sera_purge_village", "start")
	world.narrative.recruit("sera")
	world.narrative.dismiss("sera")
	world.narrative.set_flag("sera_dead", true)
	var again := world.enter_shard("rusted_undercity", 8)
	world.teleport_party(_site_cell(again, "sera_village_site"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "dead", "Mortal mode: her story continues without her")
	assert_true(world.choose(0))
	assert_eq(world.narrative.stage_of("sera_purge_village"), "done_posthumous")
	assert_true(world.narrative.flag("sera_names_recovered"))


func test_shard_save_keeps_the_quest_site_in_place() -> void:
	_recruit_sera()
	var entry := world.enter_shard("rusted_undercity", 7)
	var site := _site_cell(entry, "sera_village_site")
	assert_eq(world.save_slot(2), OK)
	world.narrative.set_stage("sera_purge_village", "done")
	var again := _fresh_scene()
	assert_eq(again.load_slot(2), [])
	assert_eq(_site_cell(again.map_entry, "sera_village_site"), site, "saved extras regenerate the same layout")
	assert_eq(again.map_entry["rows"], entry["rows"])
	_drop(again)


func test_mortal_mode_death_removes_companion_and_flags() -> void:
	_recruit_sera()
	world.rules.story_protected = false
	var sera := world.party.members[3]
	sera.dead = true
	sera.hp = 0
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_eq(world.mode, "explore")
	assert_eq(world.party.members.size(), 3)
	assert_false(world.narrative.is_recruited("sera"))
	assert_true(world.narrative.flag("sera_dead"))
	assert_true(world.npc_at(Vector2i(5, 3)) == null, "the dead do not come back to the yard")
	var leader := world.party.leader()
	leader.dead = true
	leader.hp = 0
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_eq(world.mode, "defeated", "a dead leader is a wipe")


func test_banter_lines_fire_once_and_by_condition() -> void:
	assert_eq(world.banter("victory"), [], "nobody recruited, nobody talks")
	_recruit_sera()
	var first := world.banter("victory")
	assert_eq(first.size(), 1)
	assert_eq(first[0]["text"], "Clean. Nobody carried.")
	assert_eq(world.banter("victory"), [], "once-line spent, praise needs approval 3")
	world.narrative.add_approval("sera", 5)
	assert_eq(world.banter("victory")[0]["once"], "sera_banter_praise")
	assert_eq(world.narrative.approval_of("sera"), 7, "praise line adds approval")
	assert_true(String(world.banter("extract")[0]["text"]).begins_with("Home."))
