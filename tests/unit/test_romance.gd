## Romance and approval scenes (S37, D-092): the four romanceable
## companions each reach a spark, a commitment and a night on the Quarters
## by approval and building level, and each can be refused at no cost;
## commitment is exclusive without jealousy; a partner's death in Mortal
## mode ends the romance with a scene and Story-Protected mode never gets
## there; the romance rides saves and reads in an ending.
extends TestCase

const LEDGER := "user://test_ledger_romance.json"
const SAVES := "user://test_saves_romance"
const ACCOUNT := "user://test_account_romance.json"
const ROMANCEABLE: Array[String] = ["sera", "kaj7", "whisper", "yev"]

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


func _offered() -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in world.quarters_scenes():
		out.append(String(s["scene"]))
	return out


func _choose_text(fragment: String) -> bool:
	var options := world.dialogue.available_choices()
	for i: int in options.size():
		if String(options[i]["text"]).contains(fragment):
			return world.choose(i)
	fail("no choice containing '%s' in %s" % [fragment, world.dialogue.node_id])
	return false


## Opens a Quarters scene from its menu item, picks the choice containing
## `fragment`, then walks to the end.
func _play(scene_id: String, fragment: String) -> void:
	assert_true(world.activate_system_item("scene_%s" % scene_id), "scene %s opens" % scene_id)
	assert_true(world.in_dialogue(), "%s is a dialogue" % scene_id)
	assert_true(world.choose(0) if fragment.is_empty() else _choose_text(fragment))
	while world.in_dialogue():
		world.choose(0)


func _commit_to(id: String) -> void:
	world.narrative.recruit(id)
	world.narrative.set_flag("scene_%s_quarters_seen" % id, true)
	world.narrative.add_approval(id, 7)
	world.narrative.set_flag("romance_%s_interested" % id, true) # the spark was played
	world.apply_effects({"romance": {"commit": id}})
	assert_eq(world.narrative.romance, id)


func test_every_romance_reaches_its_scene_and_its_refusal() -> void:
	_raise("quarters", 1)
	for id: String in ROMANCEABLE:
		world.narrative = NarrativeState.new()
		world.narrative.recruit(id)
		world.narrative.add_approval(id, 5)
		var friendship := "%s_quarters" % id
		assert_eq(_offered(), [friendship], "%s: the trust scene first, the spark waits on it" % id)
		_play(friendship, "")
		world.narrative.approval[id] = 5 # the trust scene paid approval; hold the bar where the test needs it
		assert_eq(_offered(), ["%s_spark" % id], "%s: the spark at approval 5" % id)
		# "Not now" leaves the spark on the list.
		var before := world.narrative.approval_of(id)
		_play("%s_spark" % id, ["Ask me again", "quieter night", "Say it again", "Not tonight"][ROMANCEABLE.find(id)])
		assert_eq(_offered(), ["%s_spark" % id], "%s: not now is not never" % id)
		# Refusal closes it without a cost.
		_play("%s_spark" % id, ["Not like that", "friend kind", "That is all it is", "The stream is enough"][ROMANCEABLE.find(id)])
		assert_true(world.narrative.flag("romance_%s_closed" % id))
		assert_eq(world.narrative.approval_of(id), before, "%s: refusal costs nothing" % id)
		assert_eq(_offered(), [], "%s: a closed romance stays closed" % id)
		# Reopen (another playthrough) and lean in.
		world.narrative.set_flag("romance_%s_closed" % id, false)
		_play("%s_spark" % id, ["I watch you too", "what it looks like", "it is yours", "Reach, then"][ROMANCEABLE.find(id)])
		assert_true(world.narrative.flag("romance_%s_interested" % id))
		assert_eq(world.narrative.approval_of(id), before + 1)
		assert_eq(_offered(), [], "%s: the commitment needs the Quarters at 2 and approval 7" % id)
		_raise("quarters", 2)
		assert_eq(_offered(), [], "%s: approval 6 is not enough" % id)
		world.narrative.add_approval(id, 1)
		assert_eq(_offered(), ["%s_commit" % id])
		_play("%s_commit" % id, ["Not tonight", "Let me think", "Ask me after", "a moon more"][ROMANCEABLE.find(id)])
		assert_eq(_offered(), ["%s_commit" % id], "%s: still on the table" % id)
		_play("%s_commit" % id, ["I cannot give you", "Not as a partner", "cannot be something", "cannot be one root"][ROMANCEABLE.find(id)])
		assert_eq(world.narrative.romance, "", "%s: refused at the door" % id)
		assert_true(world.narrative.flag("romance_%s_closed" % id))
		assert_eq(_offered(), [])
		world.narrative.set_flag("romance_%s_closed" % id, false)
		var approval_before := world.narrative.approval_of(id)
		_play("%s_commit" % id, ["Stay", "Permanently. Yes", "find out together", "I will"][ROMANCEABLE.find(id)])
		assert_eq(world.narrative.romance, id, "%s: committed" % id)
		assert_true(world.narrative.flag("romance_%s" % id))
		assert_eq(world.narrative.approval_of(id), approval_before + 2)
		assert_eq(_offered(), ["%s_night" % id], "%s: the night after; the commitment is gone" % id)
		_play("%s_night" % id, ["Wherever", "I have the watch", "You are allowed", "If we make it so"][ROMANCEABLE.find(id)])
		assert_eq(world.narrative.romance, id)
		assert_eq(_offered(), [], "%s: the night is once" % id)
		_raise("quarters", 1)
	# Dax has no romance, and no romance scene can be forged onto him.
	var dax: Dictionary = world.registry.get_entry("companions", "dax")
	assert_false(bool(dax.get("romanceable", false)))
	var original := dax.duplicate(true)
	var forged := dax.duplicate(true)
	forged["scenes"] = [{"id": "dax_forged", "label": "?", "dialogue": "sera_spark", "romance": true, "quarters": 1}]
	world.registry.put("companions", "dax", forged)
	world.narrative = NarrativeState.new()
	world.narrative.recruit("dax")
	assert_eq(_offered(), [], "a romance scene on a companion who is not romanceable is never offered")
	world.registry.put("companions", "dax", original) # the registry is shared across tests


func test_commitment_is_exclusive_and_jealousy_free() -> void:
	_raise("quarters", 2)
	for id: String in ["sera", "kaj7"]:
		world.narrative.recruit(id)
		world.narrative.add_approval(id, 7)
		world.narrative.set_flag("scene_%s_quarters_seen" % id, true)
	assert_eq(_offered(), ["kaj7_spark", "sera_spark"], "both sparks while nobody is chosen")
	_play("kaj7_spark", "what it looks like")
	_play("sera_spark", "I watch you too")
	assert_eq(_offered(), ["kaj7_commit", "sera_commit"], "interest is not exclusive")
	var kaj_before := world.narrative.approval_of("kaj7")
	_play("sera_commit", "Stay")
	assert_eq(world.narrative.romance, "sera")
	assert_eq(_offered(), ["sera_night"], "Kaj-7's romance scenes step aside; nothing else of his changes")
	assert_eq(world.narrative.approval_of("kaj7"), kaj_before, "no jealousy")
	assert_false(world.narrative.flag("romance_kaj7_closed"), "and nothing closed")
	world.apply_effects({"romance": {"commit": "kaj7"}})
	assert_eq(world.narrative.romance, "sera", "a second commitment is refused while the first stands")
	# Kaj-7's friendship scene, were one still open, would be offered: only `romance` scenes step aside.
	var kaj_original: Dictionary = world.registry.get_entry("companions", "kaj7").duplicate(true)
	var c: Dictionary = world.registry.get_entry("companions", "kaj7").duplicate(true)
	var extra: Array = c["scenes"]
	extra.append({"id": "kaj7_extra", "label": "Extra", "dialogue": "kaj7_quarters", "quarters": 1})
	c["scenes"] = extra
	world.registry.put("companions", "kaj7", c)
	assert_true(_offered().has("kaj7_extra"))
	world.registry.put("companions", "kaj7", kaj_original)
	# Ending it by choice reopens the others.
	_play("sera_night", "This has to end")
	assert_eq(world.narrative.romance, "")
	assert_true(world.narrative.flag("romance_sera_ended"))
	assert_false(world.narrative.flag("romance_sera"))
	assert_true(_offered().has("kaj7_commit"), "Kaj-7's commitment is back")
	assert_true(_offered().has("sera_commit"), "and Sera's can be asked again")
	_play("kaj7_commit", "Permanently. Yes")
	assert_eq(world.narrative.romance, "kaj7")
	assert_true(Conditions.passes({"romance": "kaj7"}, world.dialogue_ctx()))
	assert_false(Conditions.passes({"romance": ""}, world.dialogue_ctx()))
	assert_true(Conditions.passes({"romance_open": "kaj7"}, world.dialogue_ctx()))
	assert_false(Conditions.passes({"romance_open": "sera"}, world.dialogue_ctx()))
	assert_true(Conditions.passes({"not_romance": "sera"}, world.dialogue_ctx()))
	assert_false(Conditions.passes({"not_romance": "kaj7"}, world.dialogue_ctx()))
	assert_true(Conditions.passes({"romance_open": "sera"}, {"narrative": NarrativeState.new()}), "nobody chosen: open to anyone")


func test_a_partner_dying_in_mortal_mode_ends_the_romance_with_a_scene() -> void:
	_raise("quarters", 1)
	world.narrative.recruit("kaj7")
	world.narrative.add_approval("kaj7", 5)
	world.narrative.set_flag("scene_kaj7_quarters_seen", true)
	_commit_to("sera")
	world.respawn_party()
	assert_eq(world.party.members.size(), 3)
	world.rules.story_protected = false
	var sera := world.member_by_id("sera")
	sera.hp = 0
	sera.dead = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_true(world.narrative.flag("sera_dead"))
	assert_false(world.narrative.is_recruited("sera"))
	assert_eq(world.narrative.romance, "", "the romance ended with her")
	assert_true(world.narrative.flag("romance_sera_lost"))
	assert_true(world.narrative.flag("romance_sera"), "what was, stays")
	assert_eq(_offered(), ["kaj7_spark", "sera_lost"], "the empty bunk, and Kaj-7's spark is open again")
	assert_true(world.open_quarters())
	assert_contains(world.system_menu.label.text, "The empty bunk")
	_play("sera_lost", "Take the shield")
	assert_true(world.narrative.flag("sera_mourned") and world.narrative.flag("sera_shield_kept"))
	assert_eq(_offered(), ["kaj7_spark"], "once")
	assert_eq(world.save_slot(1), OK)
	assert_eq(world.load_slot(1), [])
	assert_true(world.narrative.flag("romance_sera_lost") and world.narrative.flag("sera_mourned"))
	assert_eq(world.narrative.romance, "")
	# The ending knows.
	var mend := world.registry.get_entry("endings", "weavers_mend")
	var fates := Endings.fates(world.registry, mend, world.narrative)
	assert_any_contains(fates, "Sera: Sera would have hated the singing. You keep the gate on the hill alone")


func test_story_protected_mode_keeps_a_downed_partner() -> void:
	_raise("quarters", 2)
	_commit_to("kaj7")
	world.respawn_party()
	assert_true(world.rules.story_protected)
	var kaj := world.member_by_id("kaj7")
	kaj.hp = 0
	kaj.downed = true
	world.mode = "combat"
	world._on_combat_ended("victory")
	assert_true(world.narrative.is_recruited("kaj7"))
	assert_eq(kaj.hp, 1)
	assert_eq(world.narrative.romance, "kaj7", "downed is not dead")
	assert_false(world.narrative.flag("romance_kaj7_lost"))
	assert_eq(_offered(), ["kaj7_night"], "the story keeps its people")


func test_romance_rides_saves_and_reads_in_an_ending() -> void:
	_commit_to("whisper")
	assert_eq(world.save_slot(2), OK)
	world.narrative = NarrativeState.new()
	assert_eq(world.load_slot(2), [])
	assert_eq(world.narrative.romance, "whisper")
	assert_true(world.narrative.is_recruited("whisper"))
	var old := NarrativeState.from_dict({"flags": {"x": true}})
	assert_eq(old.romance, "", "a save from before S37 loads with nobody chosen")
	var mend := world.registry.get_entry("endings", "weavers_mend")
	var fates := Endings.fates(world.registry, mend, world.narrative)
	assert_any_contains(fates, "Whisper: Whisper's line is never recalled. Nobody hears about the two of you.")
	world.narrative.end_romance()
	fates = Endings.fates(world.registry, mend, world.narrative)
	assert_any_contains(fates, "Whisper: Whisper's line is never recalled. She finds her maker anyway")
	assert_false(world.narrative.end_romance(), "nothing to end")
	assert_false(world.narrative.lose_romance("whisper"), "nothing to lose")


func test_whisper_and_yev_stand_in_the_party_ahead_of_their_stories() -> void:
	world.narrative.recruit("whisper")
	world.narrative.recruit("yev")
	world.respawn_party()
	assert_eq(world.party.members.size(), 3)
	assert_eq(world.member_by_id("whisper").class_id, "wireghost")
	assert_eq(world.member_by_id("yev").class_id, "circuit_witch")
	assert_true(world.talk_to("whisper"), "the placeholder recruit line opens")
	world.leave_dialogue()
	assert_eq(world.banter("enter_shard").size(), 2, "both have a first-Shard line")
	assert_eq(world.registry.count("companions"), 5)
