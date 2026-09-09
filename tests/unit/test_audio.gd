## The audio pipeline: synthesised streams, the event map, sounds on every
## ability and walkable tile, music picking and crossfades on state
## changes, and the sound log through a real fight and a walk.
extends TestCase

const LEDGER := "user://test_ledger_audio.json"
const SAVES := "user://test_saves_audio"

var world: ExploreWorld


func before_each() -> void:
	_cleanup()
	var packed: PackedScene = load("res://scenes/main.tscn")
	world = packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.map_id = "proto_yard"
	world.home_map = "proto_yard"
	world.party_id = "prototype"
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
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


func test_synth_builds_sfx_and_loops() -> void:
	var beep := SynthWave.build({"wave": "sine", "freq": 440.0, "duration": 0.25})
	assert_eq(beep.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(beep.mix_rate, SynthWave.MIX_RATE)
	assert_true(absf(SynthWave.seconds(beep) - 0.25) < 0.001, "a quarter second (%.4f)" % SynthWave.seconds(beep))
	assert_eq(beep.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var peak := 0
	for i: int in beep.data.size() / 2:
		peak = maxi(peak, absi(beep.data.decode_s16(i * 2)))
	assert_true(peak > 8000, "the wave has amplitude (%d)" % peak)
	var tail := absi(beep.data.decode_s16(beep.data.size() - 2))
	assert_true(tail < 400, "decay ends near silence (%d)" % tail)
	var loop := SynthWave.build({"wave": "square", "bpm": 120, "step": 0.5, "notes": [60, 0, 67, 64], "bars": 2})
	assert_eq(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_true(absf(SynthWave.seconds(loop) - 0.25 * 4 * 2) < 0.002, "four half-beat notes at 120 bpm, twice (%.4f)" % SynthWave.seconds(loop))
	assert_eq(loop.loop_end, loop.data.size() / 2)
	for wave: String in ["sine", "square", "saw", "noise"]:
		assert_true(SynthWave.build({"wave": wave, "duration": 0.05}).data.size() > 0, wave)


func test_every_ability_and_walkable_tile_has_a_resolving_sound() -> void:
	var registry := world.registry
	for a: Dictionary in registry.get_all("abilities"):
		var s := String(a.get("sound", ""))
		assert_false(s.is_empty(), "ability %s has a sound" % a["id"])
		assert_true(registry.has_entry("audio", s), "ability %s sound %s exists" % [a["id"], s])
	for t: Dictionary in registry.get_all("tiles"):
		if not bool(t.get("walkable", false)):
			continue
		var s := String(t.get("sound", ""))
		assert_false(s.is_empty(), "tile %s has a footstep" % t["id"])
		assert_true(registry.has_entry("audio", s), "tile %s sound %s exists" % [t["id"], s])
	var rules := registry.get_entry("rules", "audio")
	for group: String in ["ui", "combat", "explore"]:
		for key: String in rules[group]:
			assert_true(registry.has_entry("audio", String(rules[group][key])), "rules/audio %s.%s" % [group, key])
	var music: Dictionary = rules["music"]
	for state: String in ["title", "bastion", "combat"]:
		assert_true(registry.has_entry("audio", String(music[state])), "music %s" % state)
	for biome: Dictionary in registry.get_all("biomes"):
		assert_true(Dictionary(music["explore"]).has(String(biome["id"])), "biome %s has explore music" % biome["id"])
	for e: Dictionary in registry.get_all("audio"):
		assert_true(["sfx", "music"].has(String(e.get("kind", ""))), "audio %s kind" % e["id"])
		assert_true(e.has("synth") or e.has("file"), "audio %s plays something" % e["id"])
		var stream := world.audio.stream_for(String(e["id"]))
		assert_true(stream != null, "audio %s builds" % e["id"])
		if String(e["kind"]) == "music":
			assert_eq((stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "music %s loops" % e["id"])


func test_music_picks_by_state_and_crossfades_on_change() -> void:
	var rules := world.registry.get_entry("rules", "audio")
	assert_eq(AudioDirector.pick_music(rules, "title"), "music_title")
	assert_eq(AudioDirector.pick_music(rules, "explore", "verdant_datacore"), "music_datacore")
	assert_eq(AudioDirector.pick_music(rules, "explore", "unknown_biome"), "music_undercity", "the default")
	assert_eq(AudioDirector.pick_music(rules, "nowhere"), "")
	var audio := world.audio
	assert_eq(audio.current_track, "music_bastion", "this test makes the yard home, so it plays the Bastion track")
	var before := audio.log.size()
	world.teleport_party(Vector2i(13, 4))
	world.start_combat(true)
	assert_eq(audio.current_track, "music_combat")
	assert_true(audio.is_crossfading(), "a tween is running the crossfade")
	assert_true(audio.log.slice(before).has("music:music_combat"))
	world.mode = "combat"
	world.combat._finish()
	world.mode = "explore"
	world.refresh_music()
	assert_eq(audio.current_track, "music_bastion")
	var same := audio.log.size()
	world.refresh_music()
	assert_eq(audio.log.size(), same, "no change, no crossfade")
	world.show_title()
	assert_eq(audio.current_track, "music_title")
	world.title_menu.close()
	world.enter_map("bastion")
	assert_eq(audio.current_track, "music_undercity", "a map that is not home plays its biome")
	world.home_map = "bastion"
	world.refresh_music()
	assert_eq(audio.current_track, "music_bastion")
	world.home_map = "proto_yard"
	world.ledger.bank({"salvage": 15, "aether": 2})
	world.upgrade_building("beacon")
	world.launch_shard("verdant_datacore")
	assert_eq(audio.current_track, "music_datacore")


func test_a_fight_and_a_walk_log_their_sounds() -> void:
	var audio := world.audio
	world.teleport_party(Vector2i(13, 4))
	world.rules.initiative_die = 1
	world.start_combat(true)
	var s := world.combat.state
	var actor := s.current()
	var foe := EnemyBrain.nearest_hostile(s, actor)
	var id := EnemyBrain.usable_ability(s, actor, foe)
	if id.is_empty():
		var reach: Array = s.reachable_cells(actor).keys()
		reach.sort()
		world.combat.player_click(reach[0])
		foe = EnemyBrain.nearest_hostile(s, actor)
		id = EnemyBrain.usable_ability(s, actor, foe)
	var before := audio.log.size()
	if not id.is_empty():
		world.combat.player_click(foe.cell)
		var played := audio.log.slice(before)
		var ability: Dictionary = world.registry.get_entry("abilities", id)
		assert_true(played.has(String(ability["sound"])), "the ability's own sound: %s" % [played])
		assert_true(played.has("sfx_hit") or played.has("sfx_miss"), "hit or miss: %s" % [played])
	assert_true(audio.plays_of("sfx_turn") >= 1, "turn starts tick")
	world.mode = "combat"
	world.combat._finish()
	world.mode = "explore"
	world.party.active = true
	# A walk: moving the leader across cells plays the footstep of the new cell.
	world._last_step_cell = world.leader_cell()
	var steps_before := audio.plays_of("sfx_step_concrete") + audio.plays_of("sfx_step_grate")
	world.teleport_party(Vector2i(6, 12))
	world._process(0.016)
	assert_true(audio.plays_of("sfx_step_concrete") + audio.plays_of("sfx_step_grate") > steps_before, "a footstep on arrival")
	assert_eq(world.footstep_sound(Vector2i(14, 2)), "sfx_step_grate", "grating sounds like grating")
	assert_eq(world.footstep_sound(Vector2i(9, 6)), "sfx_step_pool", "a mana pool sounds like a pool")
	assert_true(audio.event("ui.confirm"))
	assert_false(audio.event("ui.nothing"))
	assert_false(audio.play("no_such_sound"))
	assert_true(audio.log.has("?no_such_sound"), "unknown ids are logged, not fatal")
