## Audio integration (S57, D-112): the music table picks by act, boss and
## biome; a recorded file beside its sidecar replaces the synth without a
## code change (imported or read from disk, looping when it is music); the
## validator refuses a file that is not there; the status tool says what
## plays for every entry and where it is fired, and the doc names them all.
extends TestCase

const LEDGER := "user://test_ledger_audio57.json"
const SAVES := "user://test_saves_audio57"
const WAV := "user://test_audio57_clip.wav"

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
	for f: String in [LEDGER, WAV]:
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
	w.settings_path = "user://test_settings_audio57.json"
	w.input_path = "user://test_input_audio57.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func _put_audio(id: String, entry: Dictionary) -> void:
	world.registry.put("audio", id, entry)
	world.registry._entries["audio"][id]["_path"] = "user://%s.json" % id # beside the test's files


func _drop_audio(id: String) -> void:
	world.registry._entries["audio"].erase(id)
	world.registry._fingerprint_cache = ""
	world.audio.streams.erase(id)
	world.audio.sources.erase(id)


func test_the_music_table_picks_by_act_boss_and_biome() -> void:
	var rules: Dictionary = world.registry.get_entry("rules", "audio")
	assert_eq(AudioDirector.pick_music(rules, "title"), "music_title", "a plain string still maps")
	assert_eq(AudioDirector.pick_music(rules, "bastion"), "music_bastion")
	assert_eq(AudioDirector.pick_music(rules, "bastion", "", 2), "music_bastion", "act 2 has no variant: the default")
	assert_eq(AudioDirector.pick_music(rules, "bastion", "", 3), "music_bastion_dusk", "act 3 has")
	assert_eq(AudioDirector.pick_music(rules, "combat"), "music_combat")
	assert_eq(AudioDirector.pick_music(rules, "combat", "", 1, "boss"), "music_combat_boss")
	assert_eq(AudioDirector.pick_music(rules, "explore", "loom_approach"), "music_loom")
	assert_eq(AudioDirector.pick_music(rules, "explore", "nowhere", 3, "boss"), "music_undercity", "a variant a table lacks falls through to the default")
	assert_eq(AudioDirector.pick_music({"music": {"x": 3}}, "x"), "", "not a track")
	# The world passes the act and the boss.
	assert_true(world.new_game(false))
	assert_eq(world.audio.current_track, "music_bastion")
	world.narrative.set_flag("catastrophe_seen", true)
	world.refresh_music()
	assert_eq(world.audio.current_track, "music_bastion_dusk", "the Bastion after the catastrophe")
	world.narrative.set_flag("catastrophe_seen", false)
	seed(20260922)
	assert_false(world.enter_shard("rusted_undercity", 7, 1).is_empty())
	assert_eq(world.audio.current_track, "music_undercity")
	var cell := world.map_data.nearest_free_cells(world.leader_cell(), 1, [world.leader_cell()])[0]
	var boss := world.spawn_summoned("undercity_warlord", cell, Combatant.TEAM_ENEMY)
	assert_true(boss != null, "a warlord stands next to the party")
	assert_eq(String(boss.tier), "boss")
	assert_true(world.boss_engaged())
	world.start_combat(true)
	assert_eq(world.mode, "combat")
	assert_eq(world.audio.current_track, "music_combat_boss", "a boss changes the fight's music")
	world.combat._finish()
	world.mode = "explore"
	world.clear_summons()
	world.refresh_music()
	assert_eq(world.audio.current_track, "music_undercity")


func test_a_recorded_file_beside_the_sidecar_replaces_the_synth_and_loops_when_music() -> void:
	var clip := SynthWave.build_sfx({"wave": "sine", "freq": 440, "duration": 0.05, "volume": 0.3})
	assert_eq(clip.save_to_wav(WAV), OK)
	assert_true(AudioDirector.load_file("user://does_not_exist.wav", false) == null, "no file, nothing")
	var loaded := AudioDirector.load_file(WAV, false)
	assert_true(loaded is AudioStreamWAV, "read from disk by extension")
	assert_eq((loaded as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var looped := AudioDirector.load_file(WAV, true)
	assert_eq((looped as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "music loops")
	_put_audio("zz_clip", {"name": "Clip", "kind": "sfx", "file": "test_audio57_clip.wav", "volume_db": -3})
	_put_audio("zz_track", {"name": "Track", "kind": "music", "file": "test_audio57_clip.wav", "synth": {"wave": "sine", "bpm": 90, "step": 0.5, "notes": [60], "bars": 1}})
	_put_audio("zz_gone", {"name": "Gone", "kind": "sfx", "file": "nope.wav", "synth": {"wave": "noise", "freq": 200, "duration": 0.05}})
	assert_true(world.audio.stream_for("zz_clip") is AudioStreamWAV)
	assert_eq(String(world.audio.sources["zz_clip"]), "file")
	assert_false(world.audio.is_placeholder("zz_clip"))
	assert_eq((world.audio.stream_for("zz_track") as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "a music entry's file loops")
	assert_true(world.audio.stream_for("zz_gone") != null, "a missing file falls back to the synth")
	assert_eq(String(world.audio.sources["zz_gone"]), "synth")
	assert_true(world.audio.is_placeholder("zz_gone"))
	assert_true(world.audio.is_placeholder("sfx_hit"), "the base game's entries are placeholders today")
	assert_true(world.audio.play("zz_clip"))
	assert_eq(world.audio.log[world.audio.log.size() - 1], "zz_clip")
	# The validator refuses a file that is not there, or of a kind the loader cannot read.
	_put_audio("zz_odd", {"name": "Odd", "kind": "sfx", "file": "test_audio57_clip.wav"})
	world.registry._entries["audio"]["zz_odd"]["file"] = "clip.flac"
	var problems := ContentValidator.validate(world.registry, ["runtime"])
	assert_any_contains(problems, "audio/zz_gone (runtime): file 'nope.wav' is not beside the sidecar")
	assert_any_contains(problems, "audio/zz_odd (runtime): file 'clip.flac' is not beside the sidecar")
	world.registry._entries["audio"]["zz_odd"]["file"] = "test_audio57_clip.wav"
	world.registry._entries["audio"]["zz_odd"]["loop"] = "yes"
	problems = ContentValidator.validate(world.registry, ["runtime"])
	assert_any_contains(problems, "audio/zz_odd (runtime): loop must be true or false")
	for id: String in ["zz_clip", "zz_track", "zz_gone", "zz_odd"]:
		_drop_audio(id)


func test_the_status_tool_names_every_entry_and_where_it_is_fired() -> void:
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	var result := AudioStatus.report(r)
	assert_eq(result["problems"], PackedStringArray(), "nothing fired is missing, no file is missing")
	assert_eq(int(result["files"]), 0, "no recorded audio yet")
	assert_eq(int(result["placeholders"]), int(result["entries"]), "every entry is the synth")
	assert_eq(result["unused"], PackedStringArray(), "every entry is fired from somewhere: %s" % ", ".join(result["unused"]))
	var uses := AudioStatus.uses_of(r)
	assert_true(PackedStringArray(uses["sfx_hit"]).has("rules/audio combat.hit"))
	assert_true(PackedStringArray(uses["music_combat_boss"]).has("music combat.boss"))
	assert_true(PackedStringArray(uses["music_loom"]).has("music explore.loom_approach"))
	assert_true(PackedStringArray(uses["sfx_step_pool"]).has("tile mana_pool"))
	var any_ability := false
	for where: String in PackedStringArray(uses.get("sfx_zap", PackedStringArray())):
		if where.begins_with("ability "):
			any_ability = true
	assert_true(any_ability, "an ability fires zap")
	assert_eq(AudioStatus.source_of(r.get_entry("audio", "sfx_hit")), "synth placeholder")
	assert_eq(AudioStatus.source_of({"file": "x.wav", "_path": "user://nope/x.json"}), "file x.wav (missing: the synth plays)")
	var doc := FileAccess.get_file_as_string("res://docs/audio-status.md")
	assert_false(doc.is_empty(), "docs/audio-status.md exists")
	for a: Dictionary in r.get_all("audio"):
		assert_contains(doc, "(%s)" % a["id"], "the status doc names %s" % a["id"])
	assert_contains(doc, "synth placeholder")
	r.free()
