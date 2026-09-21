## Act 2 part 2 (S41, D-096): the third borrowed voice names all three Keys
## on every faction path; each Key is a delve bound to its biome with a
## keeper to kill or a Key to break; three Keys start the Loom quest; the
## catastrophe on the plaza reads prior choices (the invitation, the
## partner, loyalty) and resolves differently for each, and ends with the
## Loom located.
extends TestCase

const LEDGER := "user://test_ledger_act2k.json"
const SAVES := "user://test_saves_act2k"
const KEYS: Dictionary = {"lattice": "ghost_markets", "rootched": "verdant_datacore", "ashfound": "null_cathedral"}

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


func _site_cell(entry: Dictionary, pickup: String) -> Vector2i:
	for p: Dictionary in entry.get("pickups", []):
		if String(p["type"]) == pickup:
			var raw: Array = p["cell"]
			return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i(-1, -1)


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


func _fight(fiat_only: bool = false) -> void:
	var s := world.combat.state
	var steps := 0
	while not fiat_only and not s.finished and steps < 250:
		steps += 1
		if not world.combat.current_is_player():
			world.combat.end_player_turn()
			continue
		var actor := s.current()
		var target := EnemyBrain.nearest_hostile(s, actor)
		if target == null:
			world.combat.end_player_turn()
			continue
		if not EnemyBrain.usable_ability(s, actor, target).is_empty():
			world.combat.player_click(target.cell)
		elif actor.move_left > 0:
			var field := s.distance_field(target.cell)
			var best := actor.cell
			var best_d := int(field.get(actor.cell, 9999))
			var cells: Array = s.reachable_cells(actor).keys()
			cells.sort()
			for cell: Vector2i in cells:
				if int(field.get(cell, 9999)) < best_d:
					best = cell
					best_d = int(field.get(cell, 9999))
			if best == actor.cell:
				world.combat.end_player_turn()
			else:
				world.combat.player_click(best)
		else:
			world.combat.end_player_turn()
	if not s.finished: # the naive fighter stalls on summoners; the wiring is what this test proves, so the keeper falls by fiat
		for c: Combatant in s.combatants:
			if c.team == Combatant.TEAM_ENEMY:
				c.hp = 0
		s._check_outcome()
		if world.mode == "combat": # the controller drains its events on its own calls; hand the result to the world as the wipe tests do
			world._on_combat_ended("victory")
	assert_true(s.finished, "fight resolved (or ended by fiat) in %d steps" % steps)


func _heal_up() -> void:
	for m: PartyMember in world.party.members:
		m.downed = false
		m.hp = m.max_hp


func _act2_world(companions: Array, faction: String = "") -> void:
	world.narrative = NarrativeState.new()
	for f: String in ["gate_lever_pulled", "gate_open", "road_end", "choir_contact", "act1_complete", "act2"]:
		world.narrative.set_flag(f, true)
	world.narrative.set_stage("main_waking", "choir")
	if not faction.is_empty():
		world.narrative.join_faction(faction)
	for id: String in companions:
		world.narrative.recruit(id)
	world.ledger.xp = 900 # a party that has done Act 2's delving (level 9 or so)
	world.refresh_progression()
	world.respawn_party()
	assert_true(world.enter_map("bastion"), "world.enter_map('bastion')")


func _name_of(pickup: String) -> String:
	var d := String(world.registry.get_entry("pickups", pickup).get("dialogue", ""))
	return String(world.registry.get_entry("dialogue", d).get("name", ""))


func test_the_third_voice_names_all_three_keys_on_every_path() -> void:
	var seed_value := 70
	for faction: String in ["", "lattice", "rootched", "ashfound"]:
		_act2_world(["sera"], faction)
		world.narrative.set_stage("choir_courting", "voice_3")
		seed_value += 1
		var entry := world.enter_shard("rusted_undercity", seed_value)
		_open_site(entry, "choir_voice_3", "Stolen voices — the third")
		assert_true(_choose_text("Keep talking" if faction == "lattice" else "That is not"), "_choose_text('Keep talking' if faction == 'lattice' else 'That is not')")
		for f: String in KEYS:
			assert_true(world.narrative.flag("key_%s_located" % f), "%s path: the %s Key is named" % [faction, f])
		assert_true(world.narrative.flag("null_cathedral_found"), "and the Cathedral is found for the Quiet Key")
		assert_eq(world.narrative.flag("choir_invited"), faction == "lattice", "%s: listening to the third voice is the invitation" % faction)
		assert_eq(world.narrative.stage_of("choir_courting"), "courted")
		for f: String in KEYS:
			assert_eq(world.narrative.stage_of("delve_%s" % f), "delve", "%s: the %s delve started itself" % [faction, f])
		assert_eq(world.narrative.stage_of("the_loom"), "", "no Loom until the Keys are resolved")
	# Sites are bound to their biome.
	var all := world.quest_sites()
	for f: String in KEYS:
		assert_true(all.has("key_%s_site" % f), "all.has('key_%s_site' % f)")
	assert_false(world.quest_sites("rusted_undercity").has("key_lattice_site"), "no Key in the Undercity")
	assert_eq(world.quest_sites("ghost_markets").filter(func(p: String) -> bool: return p.begins_with("key_")), ["key_lattice_site"])
	assert_eq(world.quest_sites("verdant_datacore").filter(func(p: String) -> bool: return p.begins_with("key_")), ["key_rootched_site"])
	assert_eq(world.quest_sites("null_cathedral").filter(func(p: String) -> bool: return p.begins_with("key_")), ["key_ashfound_site"])


func test_each_key_is_a_delve_with_a_keeper_and_three_keys_wake_the_loom() -> void:
	_act2_world(["sera", "kaj7", "cinder"], "lattice")
	for f: String in KEYS:
		world.narrative.set_flag("key_%s_located" % f, true)
	world.advance_quests()
	var seed_value := 80
	for f: String in KEYS:
		seed_value += 1
		var entry := world.enter_shard(String(KEYS[f]), seed_value, 2) # depth 2: the biome without its pad boss in the far room
		assert_true(_site_cell(entry, "key_%s_site" % f).x >= 0, "%s: the Key lies in its biome" % f)
		_open_site(entry, "key_%s_site" % f, _name_of("key_%s_site" % f))
		if f == "ashfound":
			assert_true(_choose_text("Cinder. This is the one"), "Cinder knows the Quiet Key")
			assert_eq(world.dialogue.speaker(), "cinder")
		assert_true(_choose_text("Take it whole"), "_choose_text('Take it whole')")
		assert_eq(world.mode, "combat", "%s: the keeper wakes" % f)
		assert_true(world.living_enemies().size() >= 3, "world.living_enemies().size() >= 3")
		assert_false(world.narrative.flag("key_%s" % f), "%s: no Key until the keeper falls" % f)
		_fight(f == "ashfound") # the Cathedral wipes naive play (the harness says so); the Quiet Key's keeper falls by fiat, its wiring is the same
		assert_eq(world.mode, "explore", "%s: the keeper falls" % f)
		assert_true(world.narrative.flag("key_%s" % f) and world.narrative.flag("key_%s_resolved" % f), "%s: a victory sets both flags" % f)
		assert_eq(world.narrative.stage_of("delve_%s" % f), "taken")
		_heal_up()
		world.return_home()
	assert_true(world.narrative.flag("cinder_called_the_key"), "world.narrative.flag('cinder_called_the_key')")
	assert_eq(world.narrative.stage_of("the_loom"), "catastrophe", "three Keys: the Loom quest starts itself")
	assert_contains(world.journal_text(), "Return to the Bastion")
	# A broken Key resolves the delve too, without a fight, and forecloses the Mend.
	_act2_world(["sera"], "ashfound")
	world.narrative.set_flag("key_rootched_located", true)
	world.advance_quests()
	var e := world.enter_shard("verdant_datacore", 90, 2)
	_open_site(e, "key_rootched_site", _name_of("key_rootched_site"))
	assert_true(_choose_text("Break it"), "_choose_text('Break it')")
	assert_eq(world.mode, "explore")
	assert_true(world.narrative.flag("key_rootched_broken") and world.narrative.flag("key_rootched_resolved"), "world.narrative.flag('key_rootched_broken') and world.narrative.flag('key_rootched_resolved')")
	assert_false(world.narrative.flag("key_rootched"))
	assert_eq(world.narrative.stage_of("delve_rootched"), "broken")
	assert_eq(world.narrative.reputation_of("ashfound"), 1)


## Stages the plaza with three Keys resolved and the given prior choices,
## then walks onto the spawn cell where the catastrophe waits.
func _catastrophe(companions: Array, flags: Dictionary, romance: String) -> void:
	_act2_world(companions, "lattice")
	for f: String in KEYS:
		world.narrative.set_flag("key_%s" % f, true)
		world.narrative.set_flag("key_%s_resolved" % f, true)
	for k: String in flags:
		world.narrative.set_flag(k, bool(flags[k]))
	if not romance.is_empty():
		world.narrative.commit_romance(romance)
	world.advance_quests()
	assert_eq(world.narrative.stage_of("the_loom"), "catastrophe")
	if world.map_id != "bastion":
		assert_true(world.enter_map("bastion"), "home")
	world.teleport_party(Vector2i(10, 5))
	assert_eq(world.check_triggers(), 1, "the catastrophe fires once, at home")
	world.advance_quests()


func test_the_catastrophe_resolves_by_prior_choices() -> void:
	# 1. Invited, with a partner who is not yet loyal: the Choir takes her.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": true}, "sera")
	assert_true(world.narrative.flag("sera_taken"), "world.narrative.flag('sera_taken')")
	assert_false(world.narrative.is_recruited("sera"), "off the roster")
	assert_true(world.member_by_id("sera") == null, "and out of the party")
	assert_eq(world.party.members.size(), 3)
	assert_eq(world.narrative.romance, "sera", "the romance is not ended by choice; S43 reads the taken flag")
	assert_false(world.narrative.flag("kaj7_taken"), "one is enough")
	assert_true(world.narrative.flag("catastrophe_seen") and world.narrative.flag("loom_located"), "world.narrative.flag('catastrophe_seen') and world.narrative.flag('loom_located')")
	assert_eq(world.narrative.stage_of("the_loom"), "located")
	assert_eq(world.shard_locked_reason("loom_approach"), "", "Act 3's Shard is open")
	assert_true(world.map_data.is_walkable(Vector2i(11, 8)), "the plaza is whole")
	# 2. Invited, with a loyal partner: she resists, and stays.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": true, "sera_loyal": true}, "sera")
	assert_true(world.narrative.flag("sera_resisted"), "world.narrative.flag('sera_resisted')")
	assert_false(world.narrative.flag("sera_taken"))
	assert_true(world.narrative.is_recruited("sera") and world.member_by_id("sera") != null, "world.narrative.is_recruited('sera') and world.member_by_id('sera') != null")
	assert_eq(world.narrative.approval_of("sera"), 1)
	assert_true(world.narrative.flag("loom_located"), "world.narrative.flag('loom_located')")
	# 3. Refused the third voice: nobody to call, so the plaza is struck.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": false}, "sera")
	assert_true(world.narrative.flag("bastion_struck"), "world.narrative.flag('bastion_struck')")
	assert_false(world.narrative.flag("sera_taken") or world.narrative.flag("kaj7_taken"))
	assert_false(world.map_data.is_walkable(Vector2i(11, 8)), "the Garden path caved in")
	assert_eq(world.party.members.size(), 4)
	assert_true(world.narrative.flag("loom_located"), "world.narrative.flag('loom_located')")
	assert_true(world.enter_map("proto_yard") and world.enter_map("bastion"), "world.enter_map('proto_yard') and world.enter_map('bastion')")
	assert_false(world.map_data.is_walkable(Vector2i(11, 8)), "and stays caved in")
	# 4. Invited, nobody chosen: Kaj-7 answers its name.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": true}, "")
	assert_true(world.narrative.flag("kaj7_taken"), "world.narrative.flag('kaj7_taken')")
	assert_false(world.narrative.is_recruited("kaj7"))
	assert_eq(world.party.members.size(), 3)
	# 5. Invited, nobody chosen, Kaj-7 loyal and Cinder walking: Cinder says yes again.
	_catastrophe(["sera", "kaj7", "cinder"], {"choir_invited": true, "kaj7_loyal": true}, "")
	assert_false(world.narrative.flag("kaj7_taken"))
	assert_true(world.narrative.flag("cinder_taken"), "world.narrative.flag('cinder_taken')")
	# 6. Invited, everyone loyal: it called, and nobody went.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": true, "kaj7_loyal": true}, "")
	assert_true(world.narrative.flag("choir_called_nobody"), "world.narrative.flag('choir_called_nobody')")
	assert_eq(world.party.members.size(), 4)
	assert_true(world.narrative.flag("loom_located"), "world.narrative.flag('loom_located')")
	# The ending state machine sees a taken partner as absent, not dead.
	_catastrophe(["sera", "kaj7", "dax"], {"choir_invited": true}, "sera")
	var mend := world.registry.get_entry("endings", "weavers_mend")
	var fates := Endings.fates(world.registry, mend, world.narrative)
	for line: String in fates:
		assert_false(line.begins_with("Sera:"), "no line for the taken until S43 writes one")
