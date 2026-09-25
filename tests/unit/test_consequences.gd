## Consequences past the door (S72, D-128): a companion who resisted the
## catastrophe has a line in every ending, a companion waiting at the
## Bastion has one too, `walking` and `benched` are conditions authors can
## write, and each faction's people and area have something to say after
## the Keys and after the catastrophe.
extends TestCase

const LEDGER := "user://test_ledger_cons.json"
const SAVES := "user://test_saves_cons"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	world.settings_path = "user://test_settings_cons.json"
	world.input_path = "user://test_input_cons.json"
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


func test_resisted_and_benched_are_fates_every_ending_writes() -> void:
	var r := world.registry
	for e: Dictionary in r.get_all("endings"):
		var epilogue: Dictionary = e["epilogue"]
		for id: String in ["sera", "kaj7", "whisper", "yev"]:
			assert_false(String(Dictionary(epilogue[id]).get("resisted", "")).is_empty(), "%s: %s resisted" % [e["id"], id])
		for id: String in ["sera", "kaj7", "dax", "cinder", "whisper", "yev"]:
			assert_false(String(Dictionary(epilogue[id]).get("benched", "")).is_empty(), "%s: %s benched" % [e["id"], id])
	var n := NarrativeState.new()
	n.recruit("sera")
	n.recruit("kaj7")
	n.recruit("dax")
	var lines: Dictionary = Dictionary(r.get_entry("endings", "weavers_mend")["epilogue"])
	assert_eq(Endings.fate_key("sera", lines["sera"], n), "alive")
	n.set_flag("sera_resisted", true)
	n.romance = "sera"
	n.set_flag("sera_loyal", true)
	assert_eq(Endings.fate_key("sera", lines["sera"], n), "resisted", "standing against the Choir outranks the romance")
	n.bench("dax")
	assert_eq(Endings.fate_key("dax", lines["dax"], n), "benched", "waiting at the Bastion outranks alive")
	n.set_flag("dax_loyal", true)
	assert_eq(Endings.fate_key("dax", lines["dax"], n), "loyal", "but not loyalty")
	n.unbench("dax")
	n.set_flag("dax_dead", true)
	assert_eq(Endings.fate_key("dax", lines["dax"], n), "dead")
	var sparse := {"alive": "a", "benched": ""}
	n.bench("kaj7")
	assert_eq(Endings.fate_key("kaj7", sparse, n), "alive", "an empty benched line falls through")
	var fates := Endings.fates(r, r.get_entry("endings", "drift"), n)
	var joined := "\n".join(fates)
	assert_contains(joined, "Sera: Sera broke a conduit")
	assert_contains(joined, "Kaj-7: Kaj-7 waited at the Bastion")


func test_walking_and_benched_are_conditions() -> void:
	var n := NarrativeState.new()
	n.recruit("sera")
	var ctx := {"narrative": n, "origin_tag": "", "race": "trueborn", "class": "scrap_knight"}
	assert_true(Conditions.passes({"walking": "sera"}, ctx))
	assert_false(Conditions.passes({"benched": "sera"}, ctx))
	n.bench("sera")
	assert_false(Conditions.passes({"walking": "sera"}, ctx))
	assert_true(Conditions.passes({"benched": "sera"}, ctx))
	assert_false(Conditions.passes({"recruited": "sera"}, ctx), "recruited means walking, as it did")
	assert_false(Conditions.passes({"benched": "dax"}, ctx), "never recruited: not benched either")
	assert_true(ContentValidator.REQUIRES_KEYS.has("walking") and ContentValidator.REQUIRES_KEYS.has("benched"))
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	r.put("dialogue", "zz_bench", {"name": "Bench", "act": 2, "start": [{"node": "a"}], "nodes": {"a": {"speaker": "narrator", "text": "x", "choices": [{"text": "y", "requires": {"benched": "nobody"}, "end": true}, {"text": "z", "end": true}]}}})
	assert_any_contains(ContentValidator.validate(r, ["runtime"]), "nobody")
	r.free()


func test_each_faction_has_words_and_a_changed_room_after_the_keys_and_the_catastrophe() -> void:
	for f: String in ["lattice", "rootched", "ashfound"]:
		var report: Dictionary = world.registry.get_entry("dialogue", "%s_path_report" % f)
		assert_true(Dictionary(report["nodes"]).has("keys") and Dictionary(report["nodes"]).has("loom"), "%s report has its late nodes" % f)
		var intro: Dictionary = world.registry.get_entry("dialogue", "%s_intro" % f)
		assert_true(Dictionary(intro["nodes"]).has("late"), "%s envoy has a late node" % f)
		var area: String = {"lattice": "lattice_enclave", "rootched": "rootched_grove", "ashfound": "ashfound_forge"}[f]
		var m: Dictionary = world.registry.get_entry("maps", area)
		var ids: Array[String] = []
		for t: Dictionary in m.get("triggers", []):
			ids.append(String(t["id"]))
		assert_true(ids.has("after_keys") and ids.has("after_catastrophe"), "%s: %s" % [area, ids])
	assert_eq(ContentValidator.validate(world.registry, ["runtime"]).size(), 0)
	# Played: the Lattice, after its Key, then after the catastrophe.
	world.narrative.set_flag("road_end", true)
	world.narrative.set_flag("act2_open", true)
	assert_true(world.enter_map("bastion"))
	world.narrative.faction = "lattice"
	world.narrative.set_flag("key_lattice_resolved", true)
	assert_true(world.enter_map("lattice_enclave"))
	assert_eq(world.check_triggers(), 1, "the first frame on the spawn cells") # the frame loop fires triggers
	assert_true(world.narrative.flag(ExploreWorld.trigger_flag("lattice_enclave", "after_keys")), "the enclave changed on arrival")
	assert_false(world.narrative.flag(ExploreWorld.trigger_flag("lattice_enclave", "after_catastrophe")))
	assert_true(world.talk_to("lattice_archivist"))
	assert_eq(world.dialogue.node_id, "keys", "the archivist speaks to the Key")
	world.choose(0)
	assert_true(world.narrative.flag("lattice_keys_reported"))
	world.narrative.set_flag("catastrophe_seen", true)
	assert_true(world.enter_map("bastion"))
	assert_true(world.enter_map("lattice_enclave"))
	assert_eq(world.check_triggers(), 1)
	assert_true(world.narrative.flag(ExploreWorld.trigger_flag("lattice_enclave", "after_catastrophe")))
	assert_true(world.talk_to("lattice_archivist"))
	assert_eq(world.dialogue.node_id, "loom", "and to the plaza")
	world.choose(0)
	assert_true(world.narrative.flag("lattice_loom_blessed"))
	assert_true(world.enter_map("bastion"))
	assert_true(world.talk_to("lattice_envoy"))
	assert_eq(world.dialogue.node_id, "late", "the envoy too")
	world.leave_dialogue()
