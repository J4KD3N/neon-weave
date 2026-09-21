## Endings (S43, D-098): every ending is reachable from a story state and
## reads the Loom choice; the Mend only on all its conditions; the epilogue
## lists every companion's fate, with taken, loyal, romanced and lost lines
## where the ending writes them and a ladder to the plain line where it
## does not; modifiers say what the Keys, the voice and the catastrophe
## changed; the credits roll; each ending is an achievement.
extends TestCase

const ALL: Array[String] = ["sera", "kaj7", "dax", "whisper", "cinder", "yev"]

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


func _state(faction: String, loom: String, keys_whole: bool = true, spared: bool = true) -> NarrativeState:
	var n := NarrativeState.new()
	if not faction.is_empty():
		n.join_faction(faction)
	for k: String in ["lattice", "rootched", "ashfound"]:
		n.set_flag("key_%s" % k, keys_whole)
		n.set_flag("key_%s_broken" % k, not keys_whole)
	n.set_flag("choir_spared", spared)
	n.set_flag("choir_ended", not spared)
	if not loom.is_empty():
		n.set_flag(loom, true)
	for id: String in ALL:
		n.recruit(id)
		n.approval[id] = 6
	return n


func _resolve(n: NarrativeState) -> String:
	return String(Endings.resolve(registry, {"narrative": n}).get("id", ""))


func test_every_ending_is_reachable_and_reads_the_loom_choice() -> void:
	assert_eq(registry.count("endings"), 5)
	assert_eq(_resolve(_state("lattice", "loom_set_order")), "lattice_order")
	assert_eq(_resolve(_state("rootched", "loom_set_fusion")), "rootched_bloom")
	assert_eq(_resolve(_state("ashfound", "loom_set_ash")), "ashfound_fire")
	assert_eq(_resolve(_state("lattice", "loom_mended")), "weavers_mend")
	assert_eq(_resolve(_state("", "loom_drift")), "drift")
	# The oath alone is not the ending: a sworn player who walks away drifts.
	assert_eq(_resolve(_state("lattice", "loom_drift")), "drift", "sworn to the Lattice, hand off the Loom")
	assert_eq(_resolve(_state("ashfound", "")), "drift", "no setting at all")
	# The unsworn can still earn the Mend.
	assert_eq(_resolve(_state("", "loom_mended")), "weavers_mend")


func test_the_mend_only_on_its_conditions() -> void:
	var n := _state("rootched", "loom_mended")
	assert_eq(_resolve(n), "weavers_mend")
	n.set_flag("key_ashfound", false)
	n.set_flag("key_ashfound_broken", true)
	assert_eq(_resolve(n), "drift", "a broken Key: no Mend, and the Rootched setting was not chosen either")
	n = _state("rootched", "loom_mended", true, false)
	assert_eq(_resolve(n), "drift", "the voice ended: no Mend")
	n = _state("rootched", "loom_mended")
	n.approval["dax"] = 4
	assert_eq(_resolve(n), "drift", "one companion under the loyalty bar")
	n.dismiss("dax")
	assert_eq(_resolve(n), "weavers_mend", "a companion who is not with you is not counted")
	n = _state("rootched", "loom_set_fusion")
	assert_eq(_resolve(n), "rootched_bloom", "all the Mend's conditions but the choice itself")


func test_the_epilogue_lists_every_companions_fate_in_every_ending() -> void:
	for e: Dictionary in registry.get_all("endings"):
		var n := _state("lattice", "loom_set_order")
		var fates := Endings.fates(registry, e, n)
		assert_eq(fates.size(), 6, "%s: six alive" % e["id"])
		# One dead, one taken, one loyal, one a partner (and lost), the rest alive.
		n.set_flag("dax_dead", true)
		n.dismiss("dax")
		n.set_flag("whisper_taken", true)
		n.dismiss("whisper")
		n.set_flag("kaj7_loyal", true)
		n.commit_romance("sera")
		fates = Endings.fates(registry, e, n)
		assert_eq(fates.size(), 6, "%s: six fates whatever became of them: %s" % [e["id"], fates])
		var lines: Dictionary = e["epilogue"]
		assert_eq(Endings.fate_key("dax", lines["dax"], n), "dead")
		assert_eq(Endings.fate_key("whisper", lines["whisper"], n), "taken", "%s writes the taken" % e["id"])
		assert_eq(Endings.fate_key("kaj7", lines["kaj7"], n), "loyal", "%s writes the loyal" % e["id"])
		assert_eq(Endings.fate_key("sera", lines["sera"], n), "romanced" if e["id"] == "weavers_mend" else "alive", "%s: a partner reads romanced only where written" % e["id"])
		assert_eq(Endings.fate_key("cinder", lines["cinder"], n), "alive")
		n.set_flag("sera_dead", true)
		n.lose_romance("sera")
		n.dismiss("sera")
		assert_eq(Endings.fate_key("sera", lines["sera"], n), "lost" if e["id"] == "weavers_mend" else "dead", "%s: a lost partner" % e["id"])
	# The ladder falls back when an ending writes fewer keys.
	var sparse := {"alive": "a", "dead": "d", "absent": ""}
	var n2 := NarrativeState.new()
	n2.recruit("sera")
	n2.set_flag("sera_loyal", true)
	n2.commit_romance("sera")
	assert_eq(Endings.fate_key("sera", sparse, n2), "alive")
	n2.set_flag("sera_taken", true)
	n2.dismiss("sera")
	assert_eq(Endings.fate_key("sera", sparse, n2), "absent", "taken with no line: absent, and the line is skipped")
	assert_eq(Endings.fates(registry, {"epilogue": {"sera": sparse}}, n2), [])


func test_modifiers_say_what_the_keys_the_voice_and_the_catastrophe_changed() -> void:
	var n := _state("lattice", "loom_set_order", true, false)
	n.set_flag("key_rootched", false)
	n.set_flag("key_rootched_broken", true)
	n.set_flag("bastion_struck", true)
	var order := registry.get_entry("endings", "lattice_order")
	var mods := Endings.modifiers(order, {"narrative": n})
	assert_eq(mods.size(), 3, "a broken Key, the ended voice, the struck plaza: %s" % [mods])
	assert_any_contains(mods, "The Key of the Heart went in cracked")
	assert_any_contains(mods, "You ended the voice")
	assert_any_contains(mods, "The plaza was struck")
	var text := EndingMenu.render(order, Endings.fates(registry, order, n), {"level": 11, "runs": 9, "wipes": 1, "kills": 80, "standing": "Sworn to The Lattice"}, mods, ["Engine: Godot 4.7.", "Thank you for reaching the Loom."])
	assert_contains(text, "ORDER")
	assert_contains(text, "The plaza was struck")
	assert_contains(text, "Afterwards:")
	assert_contains(text, "NEON WEAVE")
	assert_contains(text, "Thank you for reaching the Loom.")
	assert_true(text.find("The Key of the Heart") < text.find("Afterwards:"), "modifiers come before the fates")
	assert_true(text.find("Afterwards:") < text.find("NEON WEAVE"), "credits come last")
	# The drift knows who you were sworn to.
	var drift := registry.get_entry("endings", "drift")
	assert_any_contains(Endings.modifiers(drift, {"narrative": _state("ashfound", "loom_drift")}), "You were sworn to the Ashfound")
	assert_eq(Endings.modifiers(drift, {"narrative": _state("", "loom_drift")}).filter(func(m: String) -> bool: return m.begins_with("You were sworn")), [])
	assert_true(registry.get_entry("rules", "credits").get("lines", []).size() >= 5)


func test_each_ending_is_an_achievement() -> void:
	var entries: Array[Dictionary] = registry.get_all("achievements")
	var n := NarrativeState.new()
	var b := NullPlatformBackend.new()
	for id: String in ["lattice_order", "rootched_bloom", "ashfound_fire", "weavers_mend", "drift"]:
		assert_true(registry.has_entry("achievements", "ending_%s" % id), "achievement for %s" % id)
		n.set_flag("ending_%s" % id, true)
		assert_true(PlatformService.due_achievements(entries, {"narrative": n}, b).has("ending_%s" % id), "%s due" % id)
		b.unlock_achievement("ending_%s" % id)
