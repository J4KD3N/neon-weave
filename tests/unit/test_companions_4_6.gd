## Companions 4–6 (S38, D-093): Whisper in the relay rafters once the hive
## is cleared, Cinder at the source once the Warlord is beaten, Yev on the
## plaza after first contact; each recruits under the casting rule and can
## be refused and re-asked; six companions and a party of four means a
## bench and the Roster at home; three quest sites with every path (with
## them, alone, posthumous); three-way banter across all six.
extends TestCase

const LEDGER := "user://test_ledger_companions46.json"
const SAVES := "user://test_saves_companions46"

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
	fail("no choice containing '%s' in %s" % [fragment, world.dialogue.node_id])
	return false


func _choice_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	return texts


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry["pickups"]:
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


func _member_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for m: PartyMember in world.party.members:
		ids.append(m.member_id)
	return ids


func _banter_texts(trigger: String) -> String:
	var texts: PackedStringArray = []
	for l: Dictionary in world.banter(trigger):
		texts.append(String(l["text"]))
	return "\n".join(texts)


func test_whisper_waits_in_the_rafters_until_the_hive_is_cleared() -> void:
	assert_true(world.enter_map("relay_station"))
	assert_true(world.npc_at(Vector2i(24, 6)) == null, "not before the hive")
	world.narrative.set_flag("hive_cleared", true)
	assert_true(world.enter_map("relay_station"))
	assert_true(world.npc_at(Vector2i(24, 6)) != null, "she comes down once the hive is dead")
	# Refusal, and the way back.
	assert_true(world.talk_to("whisper"))
	assert_eq(world.dialogue.node_id, "greet")
	assert_false("\n".join(_choice_texts()).contains("[Splicekin]"), "no Splicekin leader, no shared line")
	assert_true(_choose_text("Why were you"))
	assert_true(_choose_text("corporate property"))
	assert_false(world.narrative.is_recruited("whisper"))
	assert_eq(world.narrative.approval_of("whisper"), -2)
	assert_true(world.talk_to("whisper"))
	assert_eq(world.dialogue.node_id, "refused")
	assert_true(_choose_text("Same answer"))
	# With Sera and Dax along, Dax reads her and the casting rule holds.
	world.narrative.recruit("sera")
	world.narrative.recruit("dax")
	world.respawn_party()
	world.narrative.set_flag("whisper_refused", false)
	world.narrative.approval["whisper"] = 0
	assert_true(world.talk_to("whisper"))
	assert_eq(world.dialogue.node_id, "greet")
	assert_true(_choose_text("Why were you"))
	assert_true(_choose_text("Dax, you have hired"))
	assert_eq(world.dialogue.speaker(), "dax")
	assert_true(_choose_text("Then she is hired"))
	assert_false(world.in_dialogue())
	assert_true(world.narrative.is_recruited("whisper"))
	assert_eq(world.narrative.approval_of("whisper"), 1)
	assert_eq(world.narrative.approval_of("dax"), 1)
	assert_eq(world.narrative.approval_of("sera"), -1, "the casting rule: one approves, one is wounded")
	assert_eq(world.narrative.stage_of("whisper_recall"), "start")
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "dax", "whisper"]))
	assert_eq(world.party.members[3].class_id, "wireghost")
	assert_true(world.npc_at(Vector2i(24, 6)) == null, "the stand-in is gone")
	assert_true(world.talk_to("whisper"))
	assert_eq(world.dialogue.node_id, "recruited")
	assert_eq(world.dialogue.available_choices().size(), 1, "opening up needs approval 2")
	world.leave_dialogue()


func test_cinder_stands_at_the_source_after_the_warlord() -> void:
	assert_true(world.enter_map("undercity_throat"))
	assert_true(world.npc_at(Vector2i(23, 7)) == null, "not while the Warlord holds the throat")
	world.narrative.set_flag("warlord_beaten", true)
	world.narrative.recruit("sera")
	world.narrative.recruit("dax")
	world.respawn_party()
	assert_true(world.enter_map("undercity_throat"))
	assert_true(world.npc_at(Vector2i(23, 7)) != null)
	assert_true(world.talk_to("cinder"))
	assert_eq(world.dialogue.node_id, "greet")
	assert_false("\n".join(_choice_texts()).contains("[Hollow]"), "a Trueborn leader has no Hollow line")
	assert_true(_choose_text("You are dead"))
	assert_eq(world.narrative.approval_of("cinder"), -1)
	assert_true(_choose_text("Sera, you have buried"))
	assert_eq(world.dialogue.speaker(), "sera")
	assert_true(_choose_text("Then walk with us"))
	assert_true(world.narrative.is_recruited("cinder"))
	assert_eq(world.narrative.approval_of("cinder"), 0)
	assert_eq(world.narrative.approval_of("sera"), 1)
	assert_eq(world.narrative.approval_of("dax"), -1, "Dax is allergic to walking corpses")
	assert_eq(world.narrative.stage_of("cinder_tether"), "start")
	assert_eq(world.member_by_id("cinder").race_id, "hollow")
	assert_eq(world.member_by_id("cinder").class_id, "aetherbinder")
	assert_true(world.npc_at(Vector2i(23, 7)) == null)
	# A Hollow leader shares the pull.
	var again := _fresh()
	var ash := {"name": "Ash", "race_id": "hollow", "origin_id": "vault_child", "class_id": "aetherbinder", "attributes": {"body": 1, "arcane": 3, "tech": 2}}
	assert_eq(again.set_protagonist(ash), [])
	again.narrative.set_flag("warlord_beaten", true)
	assert_true(again.enter_map("undercity_throat"))
	assert_true(again.talk_to("cinder"))
	var texts: PackedStringArray = []
	for c: Dictionary in again.dialogue.available_choices():
		texts.append(String(c["text"]))
	assert_true("\n".join(texts).contains("[Hollow]"))
	for i: int in texts.size():
		if texts[i].begins_with("[Hollow]"):
			again.choose(i)
	assert_true(again.narrative.flag("cinder_shared_hollow"))
	assert_eq(again.narrative.approval_of("cinder"), 1)
	_drop(again)


func test_yev_comes_to_the_plaza_after_first_contact() -> void:
	assert_eq(world.map_id, "bastion")
	assert_true(world.npc_at(Vector2i(5, 13)) == null, "not before the Choir")
	world.narrative.set_flag("choir_contact", true)
	world.narrative.recruit("kaj7")
	world.respawn_party()
	assert_true(world.enter_map("bastion"))
	assert_true(world.npc_at(Vector2i(5, 13)) != null)
	assert_true(world.talk_to("yev"))
	assert_eq(world.dialogue.node_id, "greet")
	assert_true(_choose_text("What are they cutting"))
	assert_true(_choose_text("Kaj, she sees"))
	assert_eq(world.dialogue.speaker(), "kaj7")
	assert_true(_choose_text("Then walk with us"))
	assert_true(world.narrative.is_recruited("yev"))
	assert_eq(world.narrative.approval_of("yev"), 1)
	assert_eq(world.narrative.approval_of("kaj7"), 1)
	assert_eq(world.narrative.approval_of("dax"), -1, "wounded in absentia; he will hear")
	assert_eq(world.narrative.stage_of("yev_grove"), "start")
	assert_eq(world.member_by_id("yev").class_id, "circuit_witch")
	assert_true(world.talk_to("yev"))
	assert_eq(world.dialogue.node_id, "recruited")
	world.narrative.add_approval("yev", 1)
	assert_true(_choose_text("Do they like"))
	assert_true(_choose_text("Slowly is fine"))
	assert_true(world.narrative.flag("yev_opened_up"))
	# Refusing her costs the Rootched a point.
	world.narrative = NarrativeState.new()
	world.narrative.set_flag("choir_contact", true)
	world.respawn_party()
	assert_true(world.enter_map("bastion"))
	assert_true(world.talk_to("yev"))
	assert_true(_choose_text("What are they cutting"))
	assert_true(_choose_text("We do not take Rootched"))
	assert_true(world.narrative.flag("yev_refused"))
	assert_eq(world.narrative.reputation_of("rootched"), -1)
	assert_true(world.talk_to("yev"))
	assert_eq(world.dialogue.node_id, "refused")
	world.leave_dialogue()


func test_six_recruited_means_a_bench_and_the_roster_at_home() -> void:
	for id: String in ["sera", "kaj7", "dax"]:
		world.narrative.recruit(id)
	world.respawn_party()
	assert_eq(world.party.members.size(), 4)
	world.narrative.set_flag("hive_cleared", true)
	assert_true(world.enter_map("relay_station"))
	assert_true(world.talk_to("whisper"))
	assert_true(_choose_text("Why were you"))
	assert_true(_choose_text("Come with us"))
	assert_true(world.narrative.is_recruited("whisper"))
	assert_true(world.narrative.is_benched("whisper"), "a fourth companion waits at the Bastion")
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "kaj7", "dax"]))
	assert_true(world.npc_at(Vector2i(24, 6)) == null, "she left the rafters all the same")
	assert_eq(world.narrative.active_companions(), ["sera", "kaj7", "dax"])
	# The Roster is a home thing: never inside a Shard.
	world.enter_shard("rusted_undercity", 3)
	assert_false(world.open_roster())
	for item: Dictionary in world.system_items():
		if String(item["id"]) == "roster":
			assert_false(bool(item["enabled"]), "only at home")
	assert_false(world.bench_companion("sera"), "not in a Shard")
	assert_true(world.enter_map("bastion"))
	assert_true(world.open_roster())
	assert_contains(world.system_menu.label.text, "Whisper waits at the Bastion")
	assert_contains(world.system_menu.label.text, "Dax walks with you")
	assert_false(world.take_companion("whisper"), "the party is full")
	assert_true(world.activate_system_item("bench_dax"))
	assert_true(world.narrative.is_benched("dax"))
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "kaj7"]))
	assert_true(world.activate_system_item("take_whisper"))
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "kaj7", "whisper"]))
	assert_false(world.bench_companion("nobody"))
	assert_false(world.bench_companion("dax"), "already waiting")
	# Banter comes from the walkers only.
	var lines := _banter_texts("enter_shard")
	assert_false(lines.contains("Air's bad"), "Dax is at the Bastion")
	assert_contains(lines, "Cameras")
	# Saves keep the bench.
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	assert_true(world.narrative.is_benched("dax"))
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "kaj7", "whisper"]))
	# Mortal mode: a dead walker leaves the roster, and the dead do not stand in the rafters again.
	world.rules.story_protected = false
	var w := world.member_by_id("whisper")
	w.hp = 0
	w.dead = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_true(world.narrative.flag("whisper_dead"))
	assert_false(world.narrative.is_recruited("whisper"))
	assert_false(world.narrative.is_benched("whisper"))
	assert_true(world.enter_map("relay_station"))
	assert_true(world.npc_at(Vector2i(24, 6)) == null, "the dead do not come back as stand-ins")
	assert_true(world.enter_map("bastion"))
	assert_true(world.take_companion("dax"))
	assert_eq(_member_ids(), PackedStringArray(["weaver", "sera", "kaj7", "dax"]))


func test_quest_sites_for_the_three_with_them_alone_and_posthumous() -> void:
	for id: String in ["whisper", "cinder", "yev"]:
		world.narrative.recruit(id)
	world.narrative.set_stage("whisper_recall", "start")
	world.narrative.set_stage("cinder_tether", "start")
	world.narrative.set_stage("yev_grove", "start")
	world.respawn_party()
	var sites := world.quest_sites()
	assert_true(sites.has("whisper_recall_beacon") and sites.has("cinder_tether_knot") and sites.has("yev_cuttings_frame"))
	var entry := world.enter_shard("rusted_undercity", 9)
	assert_eq(ShardValidator.validate(entry, world.tiles_by_id()), [])
	var beacon := _site_cell(entry, "whisper_recall_beacon")
	var knot := _site_cell(entry, "cinder_tether_knot")
	var frame := _site_cell(entry, "yev_cuttings_frame")
	assert_true(beacon.x >= 0 and knot.x >= 0 and frame.x >= 0, "all three sites placed")
	# Sites land in the far room and a full party stands on several cells, so
	# the order they open in is the generator's; one opens per check (S38).
	var plan := {
		"with_whisper": ["whisper_recall_beacon", "Spoof it", "Your secret"],
		"with_cinder": ["cinder_tether_knot", "Follow it", "Fair"],
		"with_yev": ["yev_cuttings_frame", "Take a cutting", "Slowly is fine"],
	}
	var guard := 0
	while not plan.is_empty() and guard < 12:
		guard += 1
		if not world.in_dialogue():
			world.check_pickups()
		if not world.in_dialogue():
			var next: Array = plan[plan.keys()[0]]
			world.teleport_party(_site_cell(entry, String(next[0])))
			world.check_pickups()
		assert_true(world.in_dialogue(), "a site opened")
		var node := world.dialogue.node_id
		assert_true(plan.has(node), "site node %s" % node)
		var steps: Array = plan[node]
		assert_true(_choose_text(String(steps[1])))
		assert_true(_choose_text(String(steps[2])))
		assert_false(world.in_dialogue())
		plan.erase(node)
	assert_true(plan.is_empty(), "every site played: %s left" % [plan.keys()])
	assert_eq(world.narrative.stage_of("whisper_recall"), "silenced")
	assert_true(world.narrative.flag("whisper_recall_spoofed"))
	assert_eq(world.narrative.approval_of("whisper"), 2)
	assert_eq(world.narrative.reputation_of("lattice"), -1)
	assert_eq(world.narrative.stage_of("cinder_tether"), "traced")
	assert_true(world.narrative.flag("null_cathedral_found"), "Cinder's tether finds the Cathedral")
	assert_eq(world.narrative.approval_of("dax"), 1)
	assert_eq(world.narrative.stage_of("yev_grove"), "saved")
	assert_true(world.narrative.flag("yev_cutting_saved"))
	assert_eq(world.narrative.approval_of("kaj7"), 2, "the spoof and the cutting both please Kaj-7")
	var journal := world.journal_text()
	assert_contains(journal, "✓ Recall Notice")
	assert_contains(journal, "✓ The Tether")
	assert_contains(journal, "✓ The Weaponised Grove")
	# The other paths, each from a fresh story.
	var runs: Array = [
		["whisper", "whisper_recall", "whisper_recall_beacon", "Trace it", "traced", "whisper_maker_found"],
		["whisper", "whisper_recall", "whisper_recall_beacon", "Answer it", "traced", "whisper_answered_recall"],
		["cinder", "cinder_tether", "cinder_tether_knot", "Cut it", "cut", "cinder_tether_cut"],
		["yev", "yev_grove", "yev_cuttings_frame", "Burn the frame", "burned", "yev_frame_burned"],
		["yev", "yev_grove", "yev_cuttings_frame", "Leave it", "left", "yev_frame_left"],
	]
	var seed := 20
	for run: Array in runs:
		world.narrative = NarrativeState.new()
		world.narrative.recruit(String(run[0]))
		world.narrative.set_stage(String(run[1]), "start")
		seed += 1
		var e := world.enter_shard("rusted_undercity", seed)
		world.teleport_party(_site_cell(e, String(run[2])))
		world.check_pickups()
		assert_true(_choose_text(String(run[3])), "%s: %s" % [run[0], run[3]])
		assert_eq(world.narrative.stage_of(String(run[1])), String(run[4]), "%s: %s" % [run[0], run[3]])
		assert_true(world.narrative.flag(String(run[5])), "%s: %s" % [run[0], run[5]])
		world.choose(0)
	assert_eq(world.narrative.reputation_of("rootched"), 1, "leaving the frame warms the Rootched")
	# Alone.
	world.narrative = NarrativeState.new()
	for q: String in ["whisper_recall", "cinder_tether", "yev_grove"]:
		world.narrative.set_stage(q, "start")
	var alone := world.enter_shard("rusted_undercity", 10)
	for pair: Array in [["whisper_recall_beacon", "whisper_recall"], ["cinder_tether_knot", "cinder_tether"], ["yev_cuttings_frame", "yev_grove"]]:
		world.teleport_party(_site_cell(alone, String(pair[0])))
		world.check_pickups()
		assert_eq(world.dialogue.node_id, "alone", String(pair[0]))
		world.choose(0)
		assert_eq(world.narrative.stage_of(String(pair[1])), "done_alone")
	assert_true(world.narrative.flag("null_cathedral_found"), "the thread leads there without him too")
	# Posthumous.
	world.narrative = NarrativeState.new()
	for id: String in ["whisper", "cinder", "yev"]:
		world.narrative.set_flag("%s_dead" % id, true)
	for q: String in ["whisper_recall", "cinder_tether", "yev_grove"]:
		world.narrative.set_stage(q, "start")
	var after := world.enter_shard("rusted_undercity", 11)
	for pair: Array in [["whisper_recall_beacon", "whisper_recall"], ["cinder_tether_knot", "cinder_tether"], ["yev_cuttings_frame", "yev_grove"]]:
		world.teleport_party(_site_cell(after, String(pair[0])))
		world.check_pickups()
		assert_eq(world.dialogue.node_id, "dead", String(pair[0]))
		world.choose(0)
		assert_eq(world.narrative.stage_of(String(pair[1])), "done_posthumous")
	assert_true(world.narrative.flag("whisper_recall_spoofed") and world.narrative.flag("cinder_tether_cut") and world.narrative.flag("yev_cutting_saved"))


func test_three_way_banter_across_all_six() -> void:
	for id: String in ["whisper", "cinder", "yev"]:
		world.narrative.recruit(id)
	world.respawn_party()
	assert_eq(world.party.members.size(), 4)
	var first := _banter_texts("enter_shard")
	assert_contains(first, "Cameras")
	assert_contains(first, "I can hear the floor")
	assert_contains(first, "The current runs strong")
	# Swap Yev for Sera: the old three talk about the new three, and back.
	world.narrative.recruit("sera")
	world.narrative.bench("yev")
	world.respawn_party()
	assert_eq(_member_ids(), PackedStringArray(["weaver", "whisper", "cinder", "sera"]))
	var second := _banter_texts("enter_shard") + "\n" + _banter_texts("enter_shard")
	assert_contains(second, "Rafters are not a formation", "Sera on Whisper")
	var wins := _banter_texts("victory") + "\n" + _banter_texts("victory")
	assert_contains(wins, "did not flinch", "Sera on Cinder")
	assert_contains(wins, "leave no witnesses", "Cinder on Whisper")
	assert_eq(world.narrative.approval_of("cinder"), 1, "Sera's line is praise")
	world.narrative.recruit("kaj7")
	world.narrative.bench("sera")
	world.respawn_party()
	var kaj := _banter_texts("enter_shard") + "\n" + _banter_texts("enter_shard") + "\n" + _banter_texts("victory") + "\n" + _banter_texts("extract")
	assert_contains(kaj, "scanned you five", "Kaj-7 on Whisper")
	assert_contains(kaj, "made twice", "Cinder and Kaj-7 on each other")
	assert_eq(world.registry.count("companions"), 6, "all six")
