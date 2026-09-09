## The Lattice in Act 1: reputation in the narrative state and saves, the
## envoy appearing once the road is open, hearing her out and answering
## either way, joining hidden until Act 2, companion reactions per the
## casting rule, the Kaj-7 tension hook, and faction content integrity.
extends TestCase

const LEDGER := "user://test_ledger_factions.json"
const SAVES := "user://test_saves_factions"

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


func _open_the_road() -> void:
	world.narrative.set_flag("gate_lever_pulled", true)
	world.narrative.set_flag("gate_open", true)
	world.narrative.set_flag("road_end", true)
	world.narrative.set_stage("main_waking", "done")


func _with_party() -> void:
	world.narrative.recruit("sera")
	world.narrative.recruit("kaj7")
	world.respawn_party()


func test_reputation_lives_in_the_narrative_state_and_conditions() -> void:
	var n := NarrativeState.new()
	assert_eq(n.reputation_of("lattice"), 0)
	n.add_reputation("lattice", 2)
	n.add_reputation("lattice", -1)
	assert_eq(n.reputation_of("lattice"), 1)
	var back := NarrativeState.from_dict(n.to_dict())
	assert_eq(back.reputation_of("lattice"), 1)
	assert_eq(NarrativeState.from_dict({"reputation": {"ashfound": 3.0}}).reputation_of("ashfound"), 3, "JSON floats become ints")
	var ctx := {"narrative": n}
	assert_true(Conditions.passes({"reputation": {"lattice": {"min": 1}}}, ctx))
	assert_false(Conditions.passes({"reputation": {"lattice": {"min": 2}}}, ctx))
	assert_true(Conditions.passes({"reputation": {"lattice": {"max": 1}}}, ctx))
	assert_false(Conditions.passes({"reputation": {"ashfound": {"min": 1}}}, ctx))
	Conditions.apply({"reputation": {"ashfound": -2}}, n)
	assert_eq(n.reputation_of("ashfound"), -2)


func test_envoy_appears_only_once_the_road_is_open() -> void:
	assert_true(world.npc_at(Vector2i(12, 13)) == null, "no envoy before the road")
	_open_the_road()
	world.enter_map("bastion")
	var envoy := world.npc_at(Vector2i(12, 13))
	assert_true(envoy != null, "the envoy arrives with the road")
	assert_true(envoy.is_story_npc())
	assert_eq(envoy.npc_id, "lattice_envoy")
	assert_eq(envoy.display_name, "Calder")
	assert_false(envoy.is_merchant())


func test_hearing_the_lattice_out_and_keeping_the_door_open() -> void:
	_open_the_road()
	_with_party()
	world.enter_map("bastion")
	var free := world.map_data.nearest_free_cells(Vector2i(12, 13), 1, [Vector2i(12, 13)])
	world.teleport_party(free[0])
	world.party.leader().position = world.map_view.cell_to_world(free[0])
	assert_true(world.interact(), "Enter / A talks to the envoy")
	assert_eq(world.dialogue.speaker(), "lattice_envoy")
	assert_contains(world.dialogue_menu.label.text, "Calder:")
	assert_true(_choose_text("Say your piece"))
	assert_eq(world.narrative.stage_of("lattice_offer"), "offer")
	assert_true(world.narrative.flag("lattice_heard"))
	assert_eq(world.dialogue.node_id, "piece")
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	assert_true(texts[0].begins_with("Kaj-7 hears what it hears"), "Kaj-7 is in the party, so the envoy talks about it")
	assert_true(_choose_text("Kaj-7 hears what it hears"))
	assert_eq(world.narrative.reputation_of("lattice"), -1)
	assert_eq(world.narrative.approval_of("kaj7"), 2, "explicit approval from the block")
	assert_true(world.narrative.flag("lattice_wants_kaj7"))
	assert_eq(world.dialogue.node_id, "answer")
	var answers: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		answers.append(String(c["text"]))
	assert_eq(answers.size(), 2, "joining is hidden until Act 2")
	assert_false("\n".join(answers).contains("Join the Lattice"))
	var sera_before := world.narrative.approval_of("sera")
	var kaj_before := world.narrative.approval_of("kaj7")
	assert_true(_choose_text("Keep talking to us"))
	assert_eq(world.narrative.reputation_of("lattice"), 1, "-1 + 2")
	assert_eq(world.narrative.approval_of("kaj7"), kaj_before + 1, "Kaj-7 leans Lattice: approves")
	assert_eq(world.narrative.approval_of("sera"), sera_before - 1, "Sera leans Ashfound, a rival: wounded")
	assert_eq(world.narrative.stage_of("lattice_offer"), "warm")
	assert_true(_choose_text("Warmly"))
	assert_false(world.in_dialogue())
	assert_contains(world.journal_text(), "✓ A Clean Offer")
	assert_contains(world.journal_text(), "Standing: The Lattice +1")
	assert_eq(world.save_slot(1), OK)
	var again := _fresh()
	assert_eq(again.load_slot(1), [])
	assert_eq(again.narrative.reputation_of("lattice"), 1, "reputation rides in the save")
	assert_eq(again.narrative.stage_of("lattice_offer"), "warm")
	_drop(again)


func test_refusing_the_lattice_pleases_sera() -> void:
	_open_the_road()
	_with_party()
	world.enter_map("bastion")
	assert_true(world.talk_to("lattice_envoy"))
	assert_true(_choose_text("Say your piece"))
	assert_true(_choose_text("Get to the offer"))
	var sera_before := world.narrative.approval_of("sera")
	var kaj_before := world.narrative.approval_of("kaj7")
	assert_true(_choose_text("Take your clean coat"))
	assert_eq(world.narrative.reputation_of("lattice"), -2)
	assert_eq(world.narrative.approval_of("sera"), sera_before + 1, "a rival slighted: Sera approves")
	assert_eq(world.narrative.approval_of("kaj7"), kaj_before - 1, "Kaj-7 is wounded")
	assert_eq(world.narrative.stage_of("lattice_offer"), "cold")
	assert_true(_choose_text("Go."))
	assert_true(world.talk_to("lattice_envoy"))
	assert_eq(world.dialogue.node_id, "answered", "the envoy remembers")
	assert_true(_choose_text("How does the Lattice feel"))
	assert_eq(world.dialogue.available_choices().size(), 1, "the follow-up needs standing 2")
	world.leave_dialogue()
	assert_contains(world.journal_text(), "Standing: The Lattice -2")


func test_act2_flag_reveals_the_join_choice() -> void:
	_open_the_road()
	world.narrative.set_flag("act2", true)
	world.enter_map("bastion")
	assert_true(world.talk_to("lattice_envoy"))
	assert_true(_choose_text("Say your piece"))
	assert_true(_choose_text("Get to the offer"))
	var answers: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		answers.append(String(c["text"]))
	assert_eq(answers.size(), 3)
	assert_eq(answers[0], "Join the Lattice.")
	world.leave_dialogue()


func test_kaj7_reacts_to_the_lattice_wanting_it() -> void:
	_open_the_road()
	_with_party()
	world.narrative.set_stage("kaj7_maker_signal", "start")
	world.enter_map("bastion")
	assert_true(world.talk_to("lattice_envoy"))
	assert_true(_choose_text("Say your piece"))
	assert_true(_choose_text("Restored how"))
	assert_eq(world.narrative.approval_of("kaj7"), -2)
	assert_true(_choose_text("Keep talking"))
	assert_true(_choose_text("Warmly"))
	assert_true(world.talk_to("kaj7"))
	assert_eq(world.dialogue.node_id, "lattice_word", "Kaj-7 heard the word restored")
	assert_true(_choose_text("Nobody restores you"))
	assert_true(world.narrative.flag("kaj7_lattice_talked"))
	assert_true(world.talk_to("kaj7"))
	assert_eq(world.dialogue.node_id, "recruited", "said once")
	world.leave_dialogue()


func test_faction_content_is_consistent() -> void:
	var registry := world.registry
	var factions := registry.get_all("factions")
	assert_eq(factions.size(), 3)
	var ids: Array[String] = []
	for f: Dictionary in factions:
		ids.append(String(f["id"]))
	for f: Dictionary in factions:
		assert_true(Color.html_is_valid(String(f.get("color", ""))), "faction %s colour" % f["id"])
		assert_eq(int(f.get("joinable_act", 0)), 2, "joining is Act 2")
		for r: String in f.get("rivals", []):
			assert_true(ids.has(r) and r != String(f["id"]), "faction %s rival %s" % [f["id"], r])
	for c: Dictionary in registry.get_all("companions"):
		assert_true(ids.has(String(c.get("faction", ""))), "companion %s leans toward a real faction" % c["id"])
	for n: Dictionary in registry.get_all("npcs"):
		assert_true(registry.has_entry("dialogue", String(n.get("dialogue", ""))), "npc %s dialogue" % n["id"])
		assert_true(ids.has(String(n.get("faction", ""))), "npc %s faction" % n["id"])
	var quest := registry.get_entry("quests", "lattice_offer")
	assert_eq(quest["faction"], "lattice")
	assert_true(bool(quest["main"]))
	assert_false(bool(quest.get("auto_start", false)), "the envoy starts it")



# --- S32: joining, exclusivity, vendors, areas (D-087) ---------------------------

const ENVOYS: Dictionary = {"lattice": "lattice_envoy", "rootched": "rootched_envoy", "ashfound": "ashfound_envoy"}
const OPENERS: Dictionary = {"lattice": ["Say your piece", "Get to the offer"], "rootched": ["Go on", "Get to the offer"], "ashfound": ["Make it", "Get to the offer"]}
const JOINS: Dictionary = {"lattice": "Join the Lattice", "rootched": "Join the Rootched", "ashfound": "Join the Ashfound"}
const DOORS: Dictionary = {"lattice": Vector2i(2, 1), "rootched": Vector2i(11, 1), "ashfound": Vector2i(21, 1)}


func _npc(id: String) -> NpcActor:
	for n: NpcActor in world.npcs:
		if n.npc_id == id:
			return n
	return null


func _full_party() -> void:
	world.narrative.recruit("sera")
	world.narrative.recruit("kaj7")
	world.narrative.recruit("dax")
	world.respawn_party()


func _join(id: String) -> void:
	assert_true(world.talk_to(String(ENVOYS[id])), "talk to the %s envoy" % id)
	for text: String in OPENERS[id]:
		assert_true(_choose_text(text), "%s: %s" % [id, text])
	assert_true(_choose_text(String(JOINS[id])), "the join choice for %s" % id)
	while world.in_dialogue():
		world.choose(0)


func test_all_three_envoys_wait_on_the_plaza_once_the_road_is_open() -> void:
	world.enter_map("bastion")
	for id: String in ENVOYS:
		assert_true(_npc(String(ENVOYS[id])) == null, "%s not before the road" % id)
	_open_the_road()
	world.enter_map("bastion")
	for id: String in ENVOYS:
		assert_true(_npc(String(ENVOYS[id])) != null, "%s waits" % id)


func test_joining_is_gated_on_act2_and_then_exclusive() -> void:
	_open_the_road()
	world.enter_map("bastion")
	assert_eq(world.join_faction("lattice"), "not before act2")
	assert_eq(world.join_faction("nope"), "no such faction")
	assert_true(world.talk_to("rootched_envoy"))
	assert_true(_choose_text("Go on"))
	assert_true(_choose_text("Get to the offer"))
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	assert_false(texts.has("Join the Rootched."), "no join before Act 2: %s" % [texts])
	world.leave_dialogue()
	world.narrative.set_flag("act2", true)
	assert_eq(world.join_faction("rootched"), "")
	assert_eq(world.narrative.faction, "rootched")
	assert_true(world.narrative.flag("joined_rootched") and world.narrative.flag("faction_locked"))
	assert_eq(world.join_faction("lattice"), "already sworn to The Rootched")
	# The other envoys have one line left for you.
	assert_true(world.talk_to("lattice_envoy"))
	assert_eq(world.dialogue.node_id, "locked")
	world.leave_dialogue()
	assert_true(world.talk_to("ashfound_envoy"))
	assert_eq(world.dialogue.node_id, "locked")
	world.leave_dialogue()
	assert_true(world.talk_to("rootched_envoy"))
	assert_eq(world.dialogue.node_id, "joined", "your own speaker greets a member")
	world.leave_dialogue()
	assert_contains(world.standing_text(), "Sworn to The Rootched")


func test_each_path_opens_its_area_and_vendor_and_moves_the_party() -> void:
	for id: String in ENVOYS:
		var w := _fresh()
		w.narrative.set_flag("gate_lever_pulled", true)
		w.narrative.set_flag("gate_open", true)
		w.narrative.set_flag("road_end", true)
		w.narrative.set_flag("act2", true)
		w.narrative.recruit("sera")
		w.narrative.recruit("kaj7")
		w.narrative.recruit("dax")
		w.respawn_party()
		w.enter_map("bastion")
		var faction := w.registry.get_entry("factions", id)
		# Every door is shut until you are sworn to its faction.
		for other: String in DOORS:
			w.teleport_party(DOORS[other])
			assert_false(w.check_transitions(), "%s door shut for the unsworn" % other)
		var before: Dictionary = {}
		for c: String in ["sera", "kaj7", "dax"]:
			before[c] = w.narrative.approval_of(c)
		world = w
		_join(id)
		world = null
		assert_eq(w.narrative.faction, id)
		assert_eq(w.narrative.stage_of("%s_offer" % id), "joined")
		# The casting rule: leaners approve, rivals are wounded, by the join_reputation deltas.
		var approved := 0
		var wounded := 0
		for c: String in ["sera", "kaj7", "dax"]:
			var lean := String(w.registry.get_entry("companions", c).get("faction", ""))
			var delta := w.narrative.approval_of(c) - int(before[c])
			if lean == id:
				assert_true(delta > 0, "%s leans %s and approves (%+d)" % [c, id, delta])
				approved += 1
			elif Array(faction["rivals"]).has(lean):
				assert_true(delta < 0, "%s leans a rival and is wounded (%+d)" % [c, delta])
				wounded += 1
		assert_true(wounded >= 1, "%s: someone is wounded" % id)
		if id != "rootched":
			assert_true(approved >= 1, "%s: someone approves" % id)
		assert_eq(w.narrative.reputation_of(id), 3, "join_reputation applied")
		# The door opens and the vendor trades.
		w.teleport_party(DOORS[id])
		assert_true(w.check_transitions(), "%s door opens for a member" % id)
		assert_eq(w.map_id, String(faction["area"]))
		var vendor: NpcActor = null
		for n: NpcActor in w.npcs:
			if n.is_merchant():
				vendor = n
		assert_true(vendor != null and vendor.merchant_id == String(faction["vendor"]), "the vendor stands in the area")
		w.ledger.bank({"salvage": 60})
		assert_true(w.open_merchant(vendor))
		var first := String(Dictionary(w.merchant_menu.rows[0])["id"])
		assert_eq(w.buy(first), "")
		w.close_merchant()
		# Other doors stay shut, and a save remembers the oath.
		w.enter_map("bastion")
		for other: String in DOORS:
			if other == id:
				continue
			w.teleport_party(DOORS[other])
			assert_false(w.check_transitions(), "%s door stays shut to a %s member" % [other, id])
		assert_eq(w.save_slot(1), OK)
		var again := _fresh()
		assert_eq(again.load_slot(1), [])
		assert_eq(again.narrative.faction, id, "the oath survives a save")
		_drop(again)
		_drop(w)
	world = _fresh()


func test_faction_v2_content_resolves() -> void:
	var r := world.registry
	for f: Dictionary in r.get_all("factions"):
		assert_true(r.has_entry("npcs", String(f.get("envoy", ""))), "%s envoy" % f["id"])
		assert_true(r.has_entry("merchants", String(f.get("vendor", ""))), "%s vendor" % f["id"])
		assert_true(r.has_entry("maps", String(f.get("area", ""))), "%s area" % f["id"])
		assert_true(r.has_entry("quests", "%s_offer" % f["id"]), "%s offer quest" % f["id"])
		var deltas: Dictionary = f.get("join_reputation", {})
		assert_true(int(deltas.get(String(f["id"]), 0)) > 0, "%s join warms itself" % f["id"])
		for rival: String in f.get("rivals", []):
			assert_true(int(deltas.get(rival, 0)) < 0, "%s join cools %s" % [f["id"], rival])
		var area := r.get_entry("maps", String(f["area"]))
		var back := false
		for t: Dictionary in area.get("transitions", []):
			if String(t.get("to", "")) == "bastion":
				back = true
		assert_true(back, "%s area leads back to the plaza" % f["id"])
