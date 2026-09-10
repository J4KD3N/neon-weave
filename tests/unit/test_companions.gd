## Kaj-7 and Dax in the real scene with the demo party (protagonist alone):
## recruitment gates, the casting rule on choices, three companions filling
## the party, three-way banter, quest sites for both, both death-stakes
## paths, and a reload with the full party.
extends TestCase

const LEDGER := "user://test_ledger_companions.json"
const SAVES := "user://test_saves_companions"

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
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _choose_text(fragment: String) -> bool:
	var options := world.dialogue.available_choices()
	for i: int in options.size():
		if String(options[i]["text"]).contains(fragment):
			return world.choose(i)
	fail("no choice containing %s in %s" % [fragment, world.dialogue.node_id])
	return false


func _recruit_sera() -> void:
	world.enter_map("proto_yard")
	assert_true(world.talk_to("sera"))
	assert_true(_choose_text("short a shield"))
	assert_true(_choose_text("Come with us"))
	assert_true(world.narrative.is_recruited("sera"))


func _finish_the_road() -> void:
	world.narrative.set_flag("gate_lever_pulled", true)
	world.narrative.set_flag("gate_open", true)
	world.narrative.set_flag("road_end", true)
	world.narrative.set_stage("main_waking", "done")


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry["pickups"]:
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


func test_demo_party_is_the_protagonist_alone() -> void:
	assert_eq(world.party_id, "demo")
	assert_eq(world.party.members.size(), 1)
	assert_eq(world.party.leader().member_id, "weaver")
	assert_true(world.open_creator())
	assert_true(world.creator_state.races.has("vaultkin"), "Vaultkin is playable since S30")
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	r.put("races", "shade", {"name": "Shade", "overlay": {"kind": "none"}, "playable": false})
	var st := CreatorState.new()
	st.setup(r, world.rules)
	assert_false(st.races.has("shade"), "companion-only races stay off the creator")
	r.free()
	assert_true(world.creator_state.races.size() >= 5, "the five playable races (plus any mod races)")
	world.close_creator()
	assert_true(world.registry.has_entry("races", "vaultkin"))


func test_dax_recruits_in_the_yard_and_the_choice_wounds_sera() -> void:
	_recruit_sera()
	assert_eq(world.narrative.approval_of("sera"), 1)
	var dax := world.npc_at(Vector2i(17, 10))
	assert_true(dax != null and dax.companion_id == "dax")
	assert_true(world.talk_to("dax"))
	assert_eq(world.dialogue.speaker(), "dax")
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	assert_false(texts[1].begins_with("[Vault]"), "no origin, no vault line")
	assert_true(_choose_text("What's the catch"))
	assert_eq(world.dialogue.node_id, "catch")
	var texts2: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts2.append(String(c["text"]))
	assert_true(texts2.size() == 3 and texts2[1].begins_with("Sera, you're Ashfound"), "Sera weighs in only when recruited")
	assert_true(_choose_text("Deal. We'll find your seal."))
	assert_false(world.in_dialogue())
	assert_true(world.narrative.is_recruited("dax"))
	assert_eq(world.narrative.approval_of("dax"), 1)
	assert_eq(world.narrative.approval_of("sera"), 0, "the casting rule: one approves, one is wounded")
	assert_eq(world.narrative.stage_of("dax_failing_seal"), "start")
	assert_eq(world.party.members.size(), 3)
	assert_eq(world.party.members[2].member_id, "dax")
	assert_eq(world.party.members[2].race_id, "vaultkin")
	assert_eq(world.party.members[2].class_id, "null_blade")
	assert_true(world.npc_at(Vector2i(17, 10)) == null)


func test_vault_origin_opens_dax_up() -> void:
	var vex := {"name": "Vex", "race_id": "chromed", "origin_id": "vault_child", "class_id": "circuit_witch", "attributes": {"body": 1, "arcane": 3, "tech": 2}}
	assert_eq(world.set_protagonist(vex), [])
	world.enter_map("proto_yard")
	assert_true(world.talk_to("dax"))
	assert_true(_choose_text("[Vault]"))
	assert_eq(world.narrative.approval_of("dax"), 2)
	assert_true(world.narrative.flag("dax_shared_vault"))
	world.leave_dialogue()


func test_kaj7_waits_for_the_road_then_fills_the_party() -> void:
	_recruit_sera()
	assert_true(world.enter_map("gate_road"))
	assert_true(world.npc_at(Vector2i(19, 5)) != null)
	assert_true(world.talk_to("kaj7"))
	assert_eq(world.dialogue.node_id, "not_yet", "the gate is still closed")
	world.choose(0)
	assert_false(world.narrative.is_recruited("kaj7"))
	_finish_the_road()
	assert_true(world.talk_to("kaj7"))
	assert_eq(world.dialogue.node_id, "greet")
	assert_true(_choose_text("What's calling you"))
	assert_true(_choose_text("Sera, you've fought machines"))
	assert_eq(world.dialogue.speaker(), "sera")
	assert_true(_choose_text("Then it's settled"))
	assert_true(world.narrative.is_recruited("kaj7"))
	assert_eq(world.narrative.approval_of("kaj7"), 1)
	assert_eq(world.narrative.approval_of("sera"), 2)
	assert_eq(world.party.members.size(), 3)
	world.enter_map("proto_yard")
	assert_true(world.talk_to("dax"))
	assert_true(_choose_text("What's the catch"))
	assert_true(_choose_text("Deal."))
	assert_eq(world.party.members.size(), 4, "protagonist plus three companions is the party")
	var ids: PackedStringArray = []
	for m: PartyMember in world.party.members:
		ids.append(m.member_id)
	assert_eq(ids, PackedStringArray(["weaver", "sera", "kaj7", "dax"]))
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.party.members.size(), 4)
	assert_eq(again.party.members[3].member_id, "dax")
	assert_eq(again.narrative.stage_of("kaj7_maker_signal"), "start")
	_drop(again)


func test_three_way_banter_fires_between_the_companions() -> void:
	_recruit_sera()
	_finish_the_road()
	world.narrative.recruit("kaj7")
	world.narrative.recruit("dax")
	world.respawn_party()
	assert_eq(world.party.members.size(), 4)
	var lines: Array[Dictionary] = world.banter("enter_shard")
	var texts: PackedStringArray = []
	for l: Dictionary in lines:
		texts.append(String(l["text"]))
	assert_true(texts.size() >= 3, "one line per companion")
	var joined := "\n".join(texts)
	assert_true(joined.contains("Shields up") or joined.contains("Watch the grates"))
	assert_contains(joined, "The signal is louder here")
	assert_contains(joined, "Air's bad down here")
	var second := world.banter("enter_shard")
	var joined2 := "\n".join(PackedStringArray(second.map(func(l: Dictionary) -> String: return String(l["text"]))))
	assert_contains(joined2, "Sera, you walk in front of the drones", "Kaj-7 notices Sera")
	assert_contains(joined2, "Purge detail. I read the marks", "Dax reads Sera")
	assert_eq(world.narrative.approval_of("sera"), 0, "Dax's line costs Sera a point (1 - 1)")
	var wins := world.banter("victory")
	wins.append_array(world.banter("victory"))
	var joined3 := "\n".join(PackedStringArray(wins.map(func(l: Dictionary) -> String: return String(l["text"]))))
	assert_contains(joined3, "The machine fights fine")
	assert_contains(joined3, "You fight like you are late")
	assert_eq(world.narrative.approval_of("kaj7"), 1, "Dax's grudging praise")


func test_quest_sites_for_both_appear_and_resolve_with_them() -> void:
	_recruit_sera()
	_finish_the_road()
	world.narrative.recruit("kaj7")
	world.narrative.set_stage("kaj7_maker_signal", "start")
	world.narrative.recruit("dax")
	world.narrative.set_stage("dax_failing_seal", "start")
	world.respawn_party()
	var sites := world.quest_sites()
	assert_true(sites.has("kaj_signal_relay") and sites.has("dax_vault_seal") and sites.has("sera_village_site"))
	var entry := world.enter_shard("rusted_undercity", 9)
	assert_eq(ShardValidator.validate(entry, world.tiles_by_id()), [])
	var relay := _site_cell(entry, "kaj_signal_relay")
	var seal := _site_cell(entry, "dax_vault_seal")
	assert_true(relay.x >= 0 and seal.x >= 0, "both sites placed")
	# Sites cluster in the far room and a full party covers several cells, so
	# whichever site is underfoot opens first; one opens per check (S38).
	var village := _site_cell(entry, "sera_village_site")
	var plan := {"with_kaj7": relay, "with_dax": seal, "with_sera": village}
	var guard := 0
	while not plan.is_empty() and guard < 9:
		guard += 1
		if not world.in_dialogue():
			world.check_pickups()
		if not world.in_dialogue():
			world.teleport_party(plan[plan.keys()[0]])
			world.check_pickups()
		assert_true(world.in_dialogue(), "a site opened")
		var node := world.dialogue.node_id
		assert_true(plan.has(node), "site node %s" % node)
		if node == "with_kaj7":
			assert_true(_choose_text("You are home"))
			assert_eq(world.narrative.stage_of("kaj7_maker_signal"), "heard")
			assert_true(_choose_text("Deal"))
			assert_eq(world.narrative.stage_of("kaj7_maker_signal"), "done")
			assert_true(world.narrative.flag("choir_named_kaj7"))
		elif node == "with_dax":
			assert_eq(world.dialogue.available_choices().size(), 1, "the clean route needs approval 2")
			assert_true(_choose_text("Reset it"))
			assert_eq(world.narrative.stage_of("dax_failing_seal"), "sealed")
			assert_true(_choose_text("That's what you do"))
		else:
			assert_true(_choose_text("You didn't know"))
			while world.in_dialogue():
				world.choose(0)
		assert_false(world.in_dialogue())
		plan.erase(node)
	assert_true(plan.is_empty(), "every site played: %s left" % [plan.keys()])
	assert_eq(world.narrative.approval_of("dax"), 2)
	assert_eq(world.narrative.approval_of("kaj7"), 3, "the Weft choice pleases Kaj-7")
	var journal := world.journal_text()
	assert_contains(journal, "✓ The Maker-Signal")
	assert_contains(journal, "✓ The Failing Seal")


func test_alone_and_posthumous_paths_for_both() -> void:
	world.narrative.set_stage("kaj7_maker_signal", "start")
	world.narrative.set_stage("dax_failing_seal", "start")
	var entry := world.enter_shard("rusted_undercity", 9)
	world.teleport_party(_site_cell(entry, "kaj_signal_relay"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "alone")
	world.choose(0)
	assert_eq(world.narrative.stage_of("kaj7_maker_signal"), "done_alone")
	assert_true(world.narrative.flag("choir_confirmed"))
	world.teleport_party(_site_cell(entry, "dax_vault_seal"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "alone")
	world.choose(0)
	assert_eq(world.narrative.stage_of("dax_failing_seal"), "done_alone")
	world.enter_map("proto_yard")
	world.narrative.set_stage("kaj7_maker_signal", "start")
	world.narrative.set_stage("dax_failing_seal", "start")
	world.narrative.set_flag("kaj7_dead", true)
	world.narrative.set_flag("dax_dead", true)
	var again := world.enter_shard("rusted_undercity", 10)
	world.teleport_party(_site_cell(again, "kaj_signal_relay"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "dead")
	world.choose(0)
	assert_eq(world.narrative.stage_of("kaj7_maker_signal"), "done_posthumous")
	world.teleport_party(_site_cell(again, "dax_vault_seal"))
	world.check_pickups()
	assert_eq(world.dialogue.node_id, "dead")
	world.choose(0)
	assert_eq(world.narrative.stage_of("dax_failing_seal"), "done_posthumous")


func test_mortal_mode_death_flags_the_right_companion() -> void:
	_recruit_sera()
	_finish_the_road()
	world.narrative.recruit("dax")
	world.respawn_party()
	world.rules.story_protected = false
	var dax := world.member_by_id("dax")
	dax.hp = 0
	dax.dead = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_false(world.narrative.is_recruited("dax"))
	assert_true(world.narrative.flag("dax_dead"))
	assert_true(world.narrative.is_recruited("sera"), "Sera lives")
	assert_eq(world.party.members.size(), 2)
