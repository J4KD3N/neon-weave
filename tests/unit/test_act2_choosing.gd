## Act 2, The Choosing, part 1 (S40, D-095): each faction path runs from the
## oath to a located Key with the casting rule holding on its choice; every
## companion's loyalty quest opens from talk at approval 4 in Act 2 and
## resolves loyal or broken at a Shard site; the Choir courts in borrowed
## voices, three times, in whichever voice is walking.
extends TestCase

const LEDGER := "user://test_ledger_act2.json"
const SAVES := "user://test_saves_act2"
const ENVOYS: Dictionary = {"lattice": "lattice_envoy", "rootched": "rootched_envoy", "ashfound": "ashfound_envoy"}
const OPENERS: Dictionary = {"lattice": ["Say your piece", "Get to the offer"], "rootched": ["Go on", "Get to the offer"], "ashfound": ["Make it", "Get to the offer"]}
const JOINS: Dictionary = {"lattice": "Join the Lattice", "rootched": "Join the Rootched", "ashfound": "Join the Ashfound"}
const PATHS: Dictionary = {
	"lattice": {"quest": "lattice_path", "first": "leak", "site": "lattice_leak", "way": "Seal it. Order first", "npc": "lattice_archivist", "area": "lattice_enclave", "report": "Then that is where we go", "leaner": "kaj7", "wounded": "sera"},
	"rootched": {"quest": "rootched_path", "first": "graft", "site": "rootched_graft", "way": "Set the seed", "npc": "rootched_speaker", "area": "rootched_grove", "report": "Then the Datacore", "leaner": "yev", "wounded": "dax"},
	"ashfound": {"quest": "ashfound_path", "first": "pyre", "site": "ashfound_pyre", "way": "Burn it", "npc": "ashfound_marshal", "area": "ashfound_forge", "report": "Cold. Understood", "leaner": "sera", "wounded": "kaj7"},
}
const LOYAL_CHOICE: Dictionary = {"sera": "Read them", "kaj7": "You decide, Kaj", "dax": "Open it", "whisper": "Your line, your call", "cinder": "What do you want", "yev": "Back in the grove"}

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


func _choice_texts() -> String:
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	return "\n".join(texts)


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry.get("pickups", []):
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


## Walks to a site in the current Shard and opens it; another site underfoot
## opens first sometimes and is played through (one site per check, S38).
func _open_site(entry: Dictionary, pickup: String, dialogue_name: String) -> void:
	var site := _site_cell(entry, pickup)
	assert_true(site.x >= 0, "%s placed" % pickup)
	world.teleport_party(site)
	for _try: int in 6:
		if not world.in_dialogue():
			world.check_pickups()
		if not world.in_dialogue():
			world.teleport_party(site)
			world.check_pickups()
		assert_true(world.in_dialogue(), "a site opened for %s" % pickup)
		if String(world.dialogue.dialogue.get("name", "")) == dialogue_name:
			return
		while world.in_dialogue():
			world.choose(0)
	fail("%s never opened" % dialogue_name)


func _act2_world(companions: Array) -> void:
	world.narrative = NarrativeState.new()
	for f: String in ["gate_lever_pulled", "gate_open", "road_end", "choir_contact", "act1_complete", "act2"]:
		world.narrative.set_flag(f, true)
	world.narrative.set_stage("main_waking", "choir")
	for id: String in companions:
		world.narrative.recruit(id)
	world.respawn_party()
	assert_true(world.enter_map("bastion"))


func _join(id: String) -> void:
	assert_true(world.talk_to(String(ENVOYS[id])), "talk to the %s envoy" % id)
	for text: String in OPENERS[id]:
		assert_true(_choose_text(text), "%s: %s" % [id, text])
	assert_true(_choose_text(String(JOINS[id])), "the join choice for %s" % id)
	while world.in_dialogue(): # the oath lands on the member greeting; leave without taking the first task yet
		if not world.leave_dialogue():
			world.choose(0)
	assert_eq(world.narrative.faction, id)


func test_each_faction_path_runs_from_the_oath_to_a_located_key() -> void:
	var seed_value := 30
	for id: String in PATHS:
		var p: Dictionary = PATHS[id]
		_act2_world(["sera", "kaj7", "dax"])
		if id == "rootched":
			world.narrative.recruit("yev")
			world.narrative.bench("dax")
			world.respawn_party()
		_join(id)
		# The envoy has a first task for a member.
		assert_true(world.talk_to(String(ENVOYS[id])))
		assert_true(_choose_text("want first"), "%s: the path starts at the envoy" % id)
		while world.in_dialogue():
			world.choose(0)
		assert_eq(world.narrative.stage_of(String(p["quest"])), String(p["first"]), "%s: the path's first stage" % id)
		assert_contains(world.journal_text(), world.registry.get_entry("quests", String(p["quest"]))["name"])
		# The Shard site, chosen the faction's way: the casting rule holds on the path.
		var before_leaner := world.narrative.approval_of(String(p["leaner"]))
		var before_wounded := world.narrative.approval_of(String(p["wounded"]))
		seed_value += 1
		var entry := world.enter_shard("rusted_undercity", seed_value)
		_open_site(entry, String(p["site"]), _dialogue_name(String(p["site"])))
		assert_true(_choose_text(String(p["way"])), "%s: the faction's way" % id)
		while world.in_dialogue():
			world.choose(0)
		assert_eq(world.narrative.stage_of(String(p["quest"])), "report", "%s: report next" % id)
		assert_true(world.narrative.approval_of(String(p["leaner"])) > before_leaner, "%s: %s approves" % [id, p["leaner"]])
		assert_true(world.narrative.approval_of(String(p["wounded"])) < before_wounded, "%s: %s is wounded" % [id, p["wounded"]])
		# Report in the faction's area: the Key is located.
		assert_true(world.enter_map(String(p["area"])), "%s: the area opens to a member" % id)
		assert_true(world.talk_to(String(p["npc"])), "%s: the report npc stands in the area" % id)
		assert_eq(world.dialogue.node_id, "report")
		assert_true(_choose_text(String(p["report"])))
		while world.in_dialogue():
			world.choose(0)
		assert_eq(world.narrative.stage_of(String(p["quest"])), "done")
		assert_true(world.narrative.flag("key_%s_located" % id), "%s: a Key located for S41" % id)
		assert_true(world.talk_to(String(p["npc"])))
		assert_eq(world.dialogue.node_id, "done")
		world.leave_dialogue()
		assert_contains(world.journal_text(), "✓ %s" % world.registry.get_entry("quests", String(p["quest"]))["name"])
		# The other two paths never start on this world.
		for other: String in PATHS:
			if other != id:
				assert_eq(world.narrative.stage_of(String(PATHS[other]["quest"])), "", "%s: %s's path is closed" % [id, other])


func _dialogue_name(pickup: String) -> String:
	var d := String(world.registry.get_entry("pickups", pickup).get("dialogue", ""))
	return String(world.registry.get_entry("dialogue", d).get("name", ""))


func test_the_report_npcs_take_a_companions_word() -> void:
	# Whisper meets her maker in the enclave; Yev asks the Speaker; Sera asks Hesk.
	var cases: Array = [
		["lattice", ["whisper", "kaj7", "dax"], ["Whisper wants a word", "You heard her"], "whisper", "whisper_recall_stopped"],
		["rootched", ["yev", "kaj7", "dax"], ["Yev has a question", "Answer her, Speaker", "There is a difference"], "yev", "yev_grove_answered"],
		["ashfound", ["sera", "kaj7", "dax"], ["Sera. The Ninth Stair", "Answer her", "Would you"], "sera", "sera_stair_named"],
	]
	for c: Array in cases:
		var id := String(c[0])
		var p: Dictionary = PATHS[id]
		_act2_world(c[1])
		_join(id)
		world.narrative.set_stage(String(p["quest"]), "report")
		var before := world.narrative.approval_of(String(c[3]))
		assert_true(world.enter_map(String(p["area"])))
		assert_true(world.talk_to(String(p["npc"])))
		for step: String in c[2]:
			assert_true(_choose_text(step), "%s: %s" % [id, step])
		while world.in_dialogue():
			world.choose(0)
		assert_true(world.narrative.flag(String(c[4])), "%s: %s" % [id, c[4]])
		assert_true(world.narrative.approval_of(String(c[3])) > before, "%s: %s heard" % [id, c[3]])
		assert_true(world.narrative.flag("key_%s_located" % id))


func test_every_companion_has_a_loyalty_quest_that_opens_at_approval_4_in_act_2() -> void:
	var seed_value := 40
	for batch: Array in [["sera", "kaj7", "dax"], ["whisper", "cinder", "yev"]]:
		_act2_world(batch)
		for id: String in batch:
			world.narrative.approval[id] = 3
			assert_true(world.talk_to(id))
			assert_ne(world.dialogue.node_id, "loyalty", "%s: approval 3 is not enough" % id)
			world.leave_dialogue()
			world.narrative.approval[id] = 4
			assert_true(world.talk_to(id))
			assert_eq(world.dialogue.node_id, "loyalty", "%s asks at approval 4" % id)
			assert_true(_choose_text("Not yet"))
			assert_true(world.talk_to(id))
			assert_eq(world.dialogue.node_id, "loyalty", "%s asks again" % id)
			assert_true(_choose_text("Yes"))
			assert_eq(world.narrative.stage_of("%s_loyalty" % id), "start")
			assert_true(world.talk_to(id))
			assert_ne(world.dialogue.node_id, "loyalty", "%s: offered once" % id)
			world.leave_dialogue()
		var sites := world.quest_sites()
		for id: String in batch:
			assert_true(sites.has("%s_loyalty_site" % id))
		seed_value += 1
		var entry := world.enter_shard("rusted_undercity", seed_value)
		for id: String in batch:
			var before := world.narrative.approval_of(id)
			_open_site(entry, "%s_loyalty_site" % id, _dialogue_name("%s_loyalty_site" % id))
			assert_eq(world.dialogue.node_id, "with_%s" % id)
			assert_true(_choose_text(String(LOYAL_CHOICE[id])), "%s: the loyal choice" % id)
			while world.in_dialogue():
				world.choose(0)
			assert_true(world.narrative.flag("%s_loyal" % id), "%s is loyal" % id)
			assert_eq(world.narrative.stage_of("%s_loyalty" % id), "loyal", "%s: the branch to loyal" % id)
			assert_true(world.narrative.approval_of(id) > before)
			assert_contains(world.journal_text(), "✓ %s" % world.registry.get_entry("quests", "%s_loyalty" % id)["name"])
	# A broken one: Dax's vault sold.
	_act2_world(["dax"])
	world.narrative.set_stage("dax_loyalty", "start")
	var e := world.enter_shard("rusted_undercity", 50)
	_open_site(e, "dax_loyalty_site", _dialogue_name("dax_loyalty_site"))
	assert_true(_choose_text("Sell the vault"))
	assert_eq(world.narrative.stage_of("dax_loyalty"), "broken")
	assert_false(world.narrative.flag("dax_loyal"))
	assert_eq(world.narrative.approval_of("dax"), -4)
	assert_eq(world.narrative.reputation_of("ashfound"), 2)
	# Alone and posthumous paths exist for every site.
	world.narrative = NarrativeState.new()
	for id: String in ["sera", "kaj7", "dax", "whisper", "cinder", "yev"]:
		world.narrative.set_stage("%s_loyalty" % id, "start")
	world.respawn_party()
	var alone := world.enter_shard("rusted_undercity", 51)
	for id: String in ["sera", "kaj7", "dax", "whisper", "cinder", "yev"]:
		_open_site(alone, "%s_loyalty_site" % id, _dialogue_name("%s_loyalty_site" % id))
		assert_eq(world.dialogue.node_id, "alone", id)
		world.choose(0)
	world.narrative = NarrativeState.new()
	for id: String in ["sera", "kaj7", "dax", "whisper", "cinder", "yev"]:
		world.narrative.set_stage("%s_loyalty" % id, "start")
		world.narrative.set_flag("%s_dead" % id, true)
	var after := world.enter_shard("rusted_undercity", 52)
	for id: String in ["sera", "kaj7", "dax", "whisper", "cinder", "yev"]:
		_open_site(after, "%s_loyalty_site" % id, _dialogue_name("%s_loyalty_site" % id))
		assert_eq(world.dialogue.node_id, "dead", id)
		world.choose(0)
		assert_true(world.narrative.flag("%s_loyal" % id), "%s: loyal in memory" % id)


func test_the_choir_courts_in_whichever_voice_is_walking() -> void:
	_act2_world(["sera"])
	assert_eq(world.narrative.stage_of("choir_courting"), "", "not before a save or a beat advances quests")
	world.advance_quests()
	assert_eq(world.narrative.stage_of("choir_courting"), "voice_1", "start_when: Act 2 starts the courting")
	assert_contains(world.journal_text(), "Stolen Voices")
	var entry := world.enter_shard("rusted_undercity", 60)
	_open_site(entry, "choir_voice_1", "Stolen voices — the first")
	assert_eq(world.dialogue.node_id, "as_sera")
	assert_eq(world.dialogue.speaker(), "choir")
	assert_eq(world.dialogue.voice(), "sera")
	assert_contains(world.dialogue_menu.label.text, "The Choir, in Sera's voice:")
	assert_contains(world.dialogue_menu.label.text, "Shields up. Corridors first", "her own banter, stolen")
	var before := world.narrative.approval_of("sera")
	assert_true(_choose_text("That is not her"))
	assert_eq(world.narrative.approval_of("sera"), before + 1)
	assert_true(world.narrative.flag("choir_refused_1"))
	assert_eq(world.narrative.stage_of("choir_courting"), "voice_2")
	# Kaj-7 walks, Sera waits: the second voice is Kaj-7's.
	world.narrative.recruit("kaj7")
	world.narrative.bench("sera")
	world.respawn_party()
	var second := world.enter_shard("rusted_undercity", 61)
	_open_site(second, "choir_voice_2", "Stolen voices — the second")
	assert_eq(world.dialogue.node_id, "as_kaj7", "Sera is at the Bastion; her voice is not here to steal")
	assert_contains(world.dialogue_menu.label.text, "in Kaj-7's voice")
	assert_true(_choose_text("Keep talking"))
	assert_true(world.narrative.flag("choir_listened_2"))
	assert_eq(world.narrative.stage_of("choir_courting"), "voice_3")
	# Nobody walks: the Choir uses yours.
	world.narrative.bench("kaj7")
	world.respawn_party()
	assert_eq(world.party.members.size(), 1)
	var third := world.enter_shard("rusted_undercity", 62)
	_open_site(third, "choir_voice_3", "Stolen voices — the third")
	assert_eq(world.dialogue.node_id, "as_you")
	assert_contains(world.dialogue_menu.label.text, "in %s's voice" % world.party.leader().display_name)
	assert_true(_choose_text("That is not me"))
	assert_eq(world.narrative.stage_of("choir_courting"), "courted")
	assert_contains(world.journal_text(), "✓ Stolen Voices")
	assert_true(world.narrative.flag("choir_refused_1") and world.narrative.flag("choir_listened_2") and world.narrative.flag("choir_refused_3"), "the answers are flags for the catastrophe to read")
	# A save before Act 2 does not start it; loading one after does.
	world.narrative = NarrativeState.new()
	world.advance_quests()
	assert_eq(world.narrative.stage_of("choir_courting"), "")
