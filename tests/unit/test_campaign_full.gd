## The whole campaign, scripted (S46, D-101): Act 1 from the plaza to the
## source, saved; then for each of the three faction paths and the unsworn,
## Act 2 (the oath, the faction's first task, a loyalty, the Choir's three
## voices, three Key delves, the catastrophe) and Act 3 (the Approach, the
## door, the Loom, the confrontation) to an ending, in Story-Protected and
## in Mortal mode, where a companion dies on the way and the story carries
## on without him. Fights fall by fiat: the harness measures them; this
## test proves the campaign is wired end to end. Runs in its own CI job.
extends TestCase

const LEDGER := "user://test_ledger_full.json"
const SAVES := "user://test_saves_full"
const KEYS: Dictionary = {"lattice": "ghost_markets", "rootched": "verdant_datacore", "ashfound": "null_cathedral"}
const ENVOYS: Dictionary = {"lattice": "lattice_envoy", "rootched": "rootched_envoy", "ashfound": "ashfound_envoy"}
const OPENERS: Dictionary = {"lattice": ["Say your piece", "Get to the offer"], "rootched": ["Go on", "Get to the offer"], "ashfound": ["Make it", "Get to the offer"]}
const JOINS: Dictionary = {"lattice": "Join the Lattice", "rootched": "Join the Rootched", "ashfound": "Join the Ashfound"}
const PATHS: Dictionary = {
	"lattice": {"quest": "lattice_path", "site": "lattice_leak", "way": "Seal it. Order first", "npc": "lattice_archivist", "area": "lattice_enclave", "report": "Then that is where we go"},
	"rootched": {"quest": "rootched_path", "site": "rootched_graft", "way": "Set the seed", "npc": "rootched_speaker", "area": "rootched_grove", "report": "Then the Datacore"},
	"ashfound": {"quest": "ashfound_path", "site": "ashfound_pyre", "way": "Burn it", "npc": "ashfound_marshal", "area": "ashfound_forge", "report": "Cold. Understood"},
}
const SET_CHOICE: Dictionary = {"lattice": "Order.", "rootched": "Completion.", "ashfound": "Ash.", "": "Leave it weaving"}
const ENDING: Dictionary = {"lattice": "ORDER", "rootched": "THE BLOOM", "ashfound": "THE FIRE", "": "THE DRIFT"}
const BUDGET_SECONDS := 1200.0

var world: ExploreWorld
var seed_value := 500


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


func _stand_on(cell: Vector2i) -> void:
	world.teleport_party(cell)
	world.party.leader().position = world.map_view.cell_to_world(cell)


func _step_on(cell: Vector2i) -> void:
	_stand_on(cell)
	world.check_triggers()
	if world.mode == "explore" and not world.in_dialogue() and world.check_transitions():
		world.check_triggers()


func _choose(fragment: String) -> void:
	var options := world.dialogue.available_choices()
	for i: int in options.size():
		if String(options[i]["text"]).contains(fragment):
			assert_true(world.choose(i), "choose %s" % fragment)
			return
	fail("no choice containing %s in %s" % [fragment, world.dialogue.node_id if world.dialogue != null else "no dialogue"])


func _choice_texts() -> String:
	var texts: PackedStringArray = []
	for c: Dictionary in world.dialogue.available_choices():
		texts.append(String(c["text"]))
	return "\n".join(texts)


## Every fight falls by fiat: the harness measures the fights.
func _win() -> void:
	assert_eq(world.mode, "combat", "a fight to win")
	var s := world.combat.state
	if s != null and not s.finished:
		for c: Combatant in s.combatants:
			if c.team == Combatant.TEAM_ENEMY:
				c.hp = 0
		s._check_outcome()
	if world.mode == "combat":
		world._on_combat_ended("victory")
	assert_eq(world.mode, "explore", "the fight is won")
	for m: PartyMember in world.party.members:
		m.downed = false
		m.hp = m.max_hp


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry.get("pickups", []):
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


## Opens a site in the current Shard, playing through any other site that
## opens first (a full party covers several cells; one site per check).
func _open_site(entry: Dictionary, pickup: String, dialogue_name: String) -> void:
	var site := _site_cell(entry, pickup)
	assert_true(site.x >= 0, "%s placed" % pickup)
	world.teleport_party(site)
	for _try: int in 8:
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


func _name_of(pickup: String) -> String:
	var d := String(world.registry.get_entry("pickups", pickup).get("dialogue", ""))
	return String(world.registry.get_entry("dialogue", d).get("name", ""))


func _launch(template: String = "", depth: int = 0) -> Dictionary:
	seed_value += 1
	var t := template if not template.is_empty() else "rusted_undercity"
	var entry := world.enter_shard(t, seed_value, depth if depth > 0 else world.bastion.depth())
	assert_false(entry.is_empty(), "entered %s" % t)
	return entry


func _extract() -> void:
	_stand_on(world.extraction_cell())
	assert_true(world.can_extract(), "on the pad")
	assert_true(world.interact(), "E on the pad")
	assert_true(world.at_home(), "home")
	for m: PartyMember in world.party.members:
		m.downed = false
		m.hp = m.max_hp


# --- Act 1 ---------------------------------------------------------------

## The plaza to the source, through the same calls the keys use; ends on the
## plaza with Act 2 open, Whisper and Cinder on the bench.
func _play_act1(mortal: bool) -> void:
	world.narrative.set_flag("mortal_mode", mortal)
	world.apply_death_stakes()
	assert_eq(world.is_mortal_mode(), mortal)
	_step_on(Vector2i(22, 7))
	assert_eq(world.map_id, "proto_yard")
	_stand_on(Vector2i(5, 4))
	assert_true(world.interact(), "talk to Sera")
	_choose("short a shield")
	_choose("Come with us")
	_stand_on(Vector2i(16, 10))
	assert_true(world.interact(), "talk to Dax")
	_choose("What's the catch")
	_choose("Sera, you're Ashfound")
	_choose("Good enough")
	_step_on(Vector2i(18, 14))
	_step_on(Vector2i(7, 1))
	_stand_on(Vector2i(8, 4))
	assert_true(world.interact(), "the gate opens")
	_step_on(Vector2i(12, 4))
	_win()
	_step_on(Vector2i(21, 4))
	_stand_on(Vector2i(19, 4))
	assert_true(world.interact(), "talk to Kaj-7")
	_choose("What's calling you")
	_choose("Walk with us")
	assert_eq(world.party.members.size(), 4)
	_step_on(Vector2i(22, 4))
	assert_eq(world.map_id, "relay_station")
	_stand_on(Vector2i(4, 5))
	assert_true(world.interact(), "talk to Pell")
	_choose("Where is the rest")
	_choose("We'll get the log")
	_step_on(Vector2i(12, 5))
	_win()
	_stand_on(Vector2i(23, 8))
	world.check_pickups()
	_choose("Take the log")
	_stand_on(Vector2i(24, 5))
	assert_true(world.interact(), "talk to Whisper")
	_choose("Why were you")
	_choose("Come with us")
	assert_true(world.narrative.is_benched("whisper"), "Whisper waits at the Bastion")
	_stand_on(Vector2i(4, 5))
	assert_true(world.interact(), "Pell again")
	_choose("Give me the positions")
	_choose("We'll be back")
	_step_on(Vector2i(1, 1))
	_step_on(Vector2i(1, 1))
	_step_on(Vector2i(1, 7))
	assert_eq(world.map_id, "bastion")
	world.ledger.bank({"salvage": 40, "aether": 6})
	assert_true(world.upgrade_building("beacon"), "the Beacon to depth 2")
	_launch()
	_extract()
	assert_eq(world.narrative.stage_of("main_waking"), "expeditions")
	var entry := _launch()
	_open_site(entry, "crew_ostrand_marker", "Crew Ostrand — the marker")
	_choose("Take the marker")
	_extract()
	entry = _launch()
	_open_site(entry, "crew_vane_nest", "Crew Vane — the nest")
	_choose("Kaj-7, can you quiet")
	_choose("Quiet it")
	_extract()
	entry = _launch()
	_open_site(entry, "crew_marrow_cistern", "Crew Marrow — the cistern")
	_choose("Pull them out")
	_extract()
	assert_eq(world.narrative.stage_of("main_waking"), "throat", "three crews: the throat opens")
	_step_on(Vector2i(22, 7))
	_step_on(Vector2i(10, 14))
	assert_eq(world.map_id, "undercity_throat")
	_stand_on(Vector2i(10, 4))
	assert_true(world.interact(), "the throat door")
	_step_on(Vector2i(14, 4))
	_win()
	assert_true(world.narrative.flag("warlord_beaten"), "warlord_beaten")
	_stand_on(Vector2i(22, 7))
	assert_true(world.interact(), "talk to Cinder")
	_choose("What is a tether")
	_choose("Walk with us, priest")
	assert_true(world.narrative.is_benched("cinder"), "Cinder waits at the Bastion")
	_step_on(Vector2i(26, 8))
	assert_eq(world.map_id, "throat_deep")
	_step_on(Vector2i(11, 5))
	_win()
	_step_on(Vector2i(26, 10))
	assert_eq(world.map_id, "throat_source")
	_step_on(Vector2i(10, 4))
	assert_true(world.in_dialogue(), "the Choir speaks")
	_choose("Who drowned you")
	_choose("Chosen how")
	_choose("Then the Sundering was a choice")
	assert_true(world.narrative.flag("act2"), "Act 2 opens")
	_step_on(Vector2i(1, 1))
	_step_on(Vector2i(1, 1))
	_step_on(Vector2i(1, 1))
	_step_on(Vector2i(1, 7))
	assert_eq(world.map_id, "bastion")
	world.advance_quests()
	assert_eq(world.narrative.stage_of("choir_courting"), "voice_1", "the courting starts itself")


# --- Act 2 and Act 3 -------------------------------------------------------

func _join(id: String) -> void:
	assert_true(world.talk_to(String(ENVOYS[id])), "talk to the %s envoy" % id)
	for text: String in OPENERS[id]:
		_choose(text)
	_choose(String(JOINS[id]))
	while world.in_dialogue():
		if not world.leave_dialogue():
			world.choose(0)
	assert_eq(world.narrative.faction, id)


func _play_act2(faction: String, mortal: bool) -> void:
	assert_eq(world.map_id, "bastion")
	# The Choir's three voices first, before other sites share the Shards with them; the third is answered on the Lattice path, which names every Key either way.
	for n: int in [1, 2, 3]:
		var voice := _launch()
		_open_site(voice, "choir_voice_%d" % n, "Stolen voices — the %s" % ["first", "second", "third"][n - 1])
		_choose("Keep talking" if (n == 3 and faction == "lattice") else "That is not")
		_extract()
	assert_eq(world.narrative.stage_of("choir_courting"), "courted")
	if not faction.is_empty():
		var p: Dictionary = PATHS[faction]
		_join(faction)
		assert_true(world.talk_to(String(ENVOYS[faction])), "the envoy's first task")
		_choose("want first")
		while world.in_dialogue():
			world.choose(0)
		var entry := _launch()
		_open_site(entry, String(p["site"]), _name_of(String(p["site"])))
		_choose(String(p["way"]))
		while world.in_dialogue():
			world.choose(0)
		_extract()
		assert_true(world.enter_map(String(p["area"])), "%s: the area" % faction)
		assert_true(world.talk_to(String(p["npc"])), "%s: the report" % faction)
		_choose(String(p["report"]))
		while world.in_dialogue():
			world.choose(0)
		assert_true(world.narrative.flag("key_%s_located" % faction), "%s: its Key located" % faction)
		assert_true(world.enter_map("bastion"))
	# A loyalty: Sera's roll of names (approval is banked slowly by Act 1; set for the walk).
	world.narrative.approval["sera"] = 4
	assert_true(world.talk_to("sera"))
	assert_eq(world.dialogue.node_id, "loyalty", "Sera asks at approval 4 in Act 2")
	_choose("Yes")
	var loyal := _launch()
	_open_site(loyal, "sera_loyalty_site", "Sera — the roll of names")
	_choose("Read them")
	while world.in_dialogue():
		world.choose(0)
	_extract()
	assert_true(world.narrative.flag("sera_loyal"), "Sera is loyal")
	# Mortal mode: Dax dies on a run, and the story carries on without him.
	if mortal:
		_launch()
		world.teleport_party(world.leader_cell())
		var dax := world.member_by_id("dax")
		assert_true(dax != null, "Dax walks")
		dax.hp = 0
		dax.dead = true
		world.mode = "combat"
		world._on_combat_ended("victory")
		assert_true(world.narrative.flag("dax_dead"), "Dax is dead")
		assert_false(world.narrative.is_recruited("dax"))
		_extract()
		assert_true(world.enter_map("bastion"))
		assert_true(world.take_companion("cinder"), "Cinder takes his place from the Roster")
	for f: String in KEYS:
		assert_eq(world.narrative.stage_of("delve_%s" % f), "delve", "%s: every Key delve is open" % f)
	# Three delves, one per biome; the Rootched one is broken on the Ashfound path.
	for f: String in KEYS:
		var entry := _launch(String(KEYS[f]), 2)
		_open_site(entry, "key_%s_site" % f, _name_of("key_%s_site" % f))
		if faction == "ashfound" and f == "rootched":
			_choose("Break it")
		else:
			_choose("Take it whole")
			_win()
		while world.in_dialogue():
			world.choose(0)
		assert_true(world.narrative.flag("key_%s_resolved" % f), "%s resolved" % f)
		_extract()
	assert_eq(world.narrative.stage_of("the_loom"), "catastrophe", "three Keys: the Loom wakes")
	# The catastrophe on the plaza.
	assert_true(world.enter_map("bastion"))
	_stand_on(Vector2i(10, 5))
	assert_true(world.check_triggers() >= 1, "the catastrophe fires")
	world.advance_quests()
	assert_true(world.narrative.flag("loom_located"), "the Loom is located")
	assert_eq(world.narrative.stage_of("the_loom"), "located")
	if faction == "lattice":
		assert_true(world.narrative.flag("kaj7_taken"), "invited, nobody chosen, Kaj-7 not loyal: the Choir takes Kaj-7")
	else:
		assert_true(world.narrative.flag("bastion_struck"), "refused: the plaza is struck")


func _play_act3(faction: String) -> void:
	var entry := _launch("loom_approach", 1)
	_open_site(entry, "loom_door", "The Loom's door")
	_choose("Go through")
	world.check_triggers()
	assert_eq(world.map_id, "the_loom")
	for rival: String in ["lattice", "rootched", "ashfound"]:
		var column: int = {"lattice": 8, "rootched": 14, "ashfound": 20}[rival]
		_step_on(Vector2i(column, 6))
		if rival != faction:
			_win()
	_step_on(Vector2i(25, 6))
	_win()
	_step_on(Vector2i(28, 6))
	assert_true(world.in_dialogue(), "the heart speaks")
	_choose("You are a voice")
	_choose(String(SET_CHOICE[faction]))
	assert_true(world.ending_menu.visible, "%s: the ending" % faction)
	assert_contains(world.ending_menu.label.text, String(ENDING[faction]))
	assert_contains(world.ending_menu.label.text, "Afterwards:")
	assert_contains(world.ending_menu.label.text, "NEON WEAVE")


func test_three_acts_on_every_path_in_both_death_stakes_modes() -> void:
	var started := Time.get_ticks_msec()
	seed(20260921)
	for mortal: bool in [false, true]:
		_play_act1(mortal)
		assert_eq(world.save_slot(1), OK, "Act 1 saved")
		var act1_ms := Time.get_ticks_msec() - started
		print("  campaign: act 1 (%s) in %.0f s" % ["mortal" if mortal else "story-protected", act1_ms / 1000.0])
		for faction: String in ["lattice", "rootched", "ashfound", ""]:
			var run_started := Time.get_ticks_msec()
			assert_eq(world.load_slot(1), [], "%s: back to the end of Act 1" % faction)
			assert_eq(world.narrative.faction, "", "unsworn at the start of Act 2")
			assert_eq(world.is_mortal_mode(), mortal, "the mode rides with the save")
			_play_act2(faction, mortal)
			_play_act3(faction)
			var fates := world.ending_menu.label.text
			if mortal:
				assert_contains(fates, "Dax: ", "Dax has a fate in death")
				assert_true(fates.contains("Dax's family") or fates.contains("Dax's"), "a dead man's line")
			assert_contains(fates, "Sera: ")
			world.close_ending()
			print("  campaign: %s path (%s) to %s in %.0f s" % ["unsworn" if faction.is_empty() else faction, "mortal" if mortal else "story-protected", ENDING[faction], (Time.get_ticks_msec() - run_started) / 1000.0])
		_drop(world)
		_cleanup()
		world = _fresh()
	var total := (Time.get_ticks_msec() - started) / 1000.0
	print("  campaign: eight endings in %.0f s" % total)
	assert_true(total < BUDGET_SECONDS, "the campaign test runs under %.0f s (took %.0f s)" % [BUDGET_SECONDS, total])
