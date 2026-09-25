## A writing pass through the data the game already has (S74, D-130): the
## companions speak on arriving at the Loom, the relay and the struck
## plaza; Pell has a second beat after first contact; the Loom's hall reads
## differently under each banner and leaves a tenth fragment.
extends TestCase

const LEDGER := "user://test_ledger_writing.json"
const SAVES := "user://test_saves_writing"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	world.settings_path = "user://test_settings_writing.json"
	world.input_path = "user://test_input_writing.json"
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


func test_companions_speak_on_arriving_and_only_once() -> void:
	assert_true(ContentValidator.BANTER_TRIGGERS.has("arrive"))
	for id: String in ["sera", "dax", "kaj7", "cinder", "whisper", "yev"]:
		var banter: Dictionary = world.registry.get_entry("dialogue", "%s_banter" % id)
		var arrives := 0
		for line: Dictionary in banter["lines"]:
			if String(line["trigger"]) == "arrive":
				arrives += 1
				assert_true(Dictionary(line.get("requires", {})).has("map"), "%s: an arrival line names its map" % id)
		assert_eq(arrives, 3, "%s: the Loom, the relay, the plaza" % id)
	world.narrative.recruit("sera") # the scene's party is full; banter reads the roster, not the line-up
	world.narrative.recruit("kaj7")
	assert_true(world.enter_map("relay_station"))
	assert_true(world.narrative.flag("sera_banter_relay"), "Sera spoke at the relay")
	assert_true(world.narrative.flag("kaj7_banter_relay"), "and Kaj-7")
	assert_false(world.narrative.flag("sera_banter_loom"))
	assert_eq(world.banter("arrive").size(), 0, "said once")
	assert_true(world.enter_map("the_loom"))
	assert_true(world.narrative.flag("sera_banter_loom") and world.narrative.flag("kaj7_banter_loom"))
	assert_true(world.enter_map("bastion"))
	assert_false(world.narrative.flag("sera_banter_plaza"), "the plaza line waits for the catastrophe")
	world.narrative.set_flag("catastrophe_seen", true)
	assert_true(world.enter_map("proto_yard"))
	assert_true(world.enter_map("bastion"))
	assert_true(world.narrative.flag("sera_banter_plaza"))
	var ctx := world.dialogue_ctx()
	assert_eq(String(ctx["map"]), "bastion")
	assert_true(Conditions.passes({"map": "bastion"}, ctx))
	assert_false(Conditions.passes({"map": "the_loom"}, ctx))


func test_pell_has_a_second_beat_and_the_hall_reads_by_banner() -> void:
	world.narrative.set_flag("pell_talked", true)
	world.narrative.set_flag("choir_contact", true)
	assert_true(world.enter_map("relay_station"))
	var salvage := world.ledger.total("salvage")
	assert_true(world.talk_to("pell"))
	assert_eq(world.dialogue.node_id, "light", "after first contact Pell has something to say first")
	world.choose(0)
	assert_true(world.narrative.flag("pell_light"))
	assert_eq(world.ledger.total("salvage"), salvage + 5, "the roof cache")
	assert_true(world.talk_to("pell"))
	assert_true(world.dialogue.node_id != "light", "once")
	world.leave_dialogue()
	# The hall.
	var lore_before := world.narrative.lore.size()
	assert_true(world.enter_map("the_loom"))
	world.teleport_party(Vector2i(6, 3))
	assert_true(world.check_triggers() >= 1, "unsworn: the hall speaks")
	assert_true(world.narrative.flag(ExploreWorld.trigger_flag("the_loom", "hall_unsworn")))
	assert_false(world.narrative.flag(ExploreWorld.trigger_flag("the_loom", "hall_lattice")))
	assert_true(world.narrative.lore.has("loom_ledger"), "the tenth fragment")
	assert_eq(world.narrative.lore.size(), lore_before + 1)
	assert_eq(int(world.registry.get_entry("lore", "loom_ledger")["order"]), 10)
	world.teleport_party(Vector2i(6, 3))
	assert_eq(world.check_triggers(), 0, "once")
	world.narrative.faction = "lattice"
	assert_true(world.enter_map("bastion"))
	assert_true(world.enter_map("the_loom"))
	world.teleport_party(Vector2i(6, 9))
	assert_true(world.check_triggers() >= 1)
	assert_true(world.narrative.flag(ExploreWorld.trigger_flag("the_loom", "hall_lattice")), "sworn: the Lattice reads its own marks")
	assert_eq(world.narrative.lore.size(), lore_before + 1, "the fragment is found once")
	assert_eq(ContentValidator.validate(world.registry, ["runtime"]).size(), 0)
