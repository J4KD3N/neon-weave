## The engineering gaps the v1.0.0 analysis found (D-116): a crash report
## from the marker and the engine log; caps on mod media before it is
## decoded, in the validator and the loaders; tests that set no path never
## touch the player's files; the engine version agreeing everywhere; and
## the screenshot check that fails a blank, flat or missing frame.
extends TestCase

const CRASH_DIR := "user://test_crash116"
const MEDIA_DIR := "user://test_media116"


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()
	CrashReport.last_report = ""


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d: String in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _cleanup() -> void:
	for d: String in [CRASH_DIR, MEDIA_DIR, "user://test_saves_default"]:
		_remove_tree(d)
	for f: String in ["user://test_account_default.json", "user://test_ledger_default.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


static func _write_bytes(path: String, size: int, head: PackedByteArray = PackedByteArray()) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(head)
	var chunk := PackedByteArray()
	chunk.resize(65536)
	var left := size - head.size()
	while left > 0:
		f.store_buffer(chunk if left >= chunk.size() else chunk.slice(0, left))
		left -= chunk.size()
	f.close()


func test_a_run_that_did_not_end_leaves_a_crash_report_with_the_log_tail() -> void:
	var marker := CRASH_DIR.path_join("marker.json")
	var logs := CRASH_DIR.path_join("logs")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(logs))
	var log := FileAccess.open(logs.path_join("godot.log"), FileAccess.WRITE)
	for i: int in 300:
		log.store_line("line %d" % i)
	log.store_line("SCRIPT ERROR: the thing that broke")
	log.close()
	assert_false(CrashReport.begin(marker, logs), "a first run has nothing before it")
	assert_eq(CrashReport.last_report, "")
	assert_true(FileAccess.file_exists(marker), "the marker says a run began")
	# No end(): the next begin() sees a run that died.
	assert_true(CrashReport.begin(marker, logs), "the last run did not end")
	var report := CrashReport.last_report
	assert_true(report.begins_with(CRASH_DIR.path_join("crash_")), "the report sits beside the marker: %s" % report)
	assert_true(FileAccess.file_exists(report))
	var text := FileAccess.get_file_as_string(report)
	assert_contains(text, "did not end cleanly")
	assert_contains(text, "SCRIPT ERROR: the thing that broke", "the log's tail")
	assert_contains(text, "line 299")
	assert_false(text.contains("line 50\n"), "only the last 200 lines")
	assert_contains(text, "Send this file with your playtest log")
	# A clean end, then a start: nothing to report.
	CrashReport.end(marker)
	assert_false(CrashReport.begin(marker, logs), "ended cleanly")
	assert_eq(CrashReport.last_report, "")
	CrashReport.end(marker)
	assert_eq(CrashReport.latest_log("user://nope"), "")
	assert_eq(CrashReport.write_report({"started": "t"}, "user://nope", CRASH_DIR).is_empty(), false, "a report without a log still says so")
	assert_contains(FileAccess.get_file_as_string(CrashReport.write_report({"started": "t"}, "user://nope", CRASH_DIR)), "no engine log found")
	assert_true(bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false)), "the engine writes its log to disk")
	assert_eq(String(ProjectSettings.get_setting("debug/file_logging/log_path", "")), "user://logs/godot.log")


func test_media_past_the_caps_is_refused_before_it_is_decoded() -> void:
	var big_png := MEDIA_DIR.path_join("big.png")
	_write_bytes(big_png, MediaLimits.MAX_IMAGE_BYTES + 1, MediaLimits.png_signature())
	var fake_png := MEDIA_DIR.path_join("fake.png")
	_write_bytes(fake_png, 64)
	var big_wav := MEDIA_DIR.path_join("big.wav")
	_write_bytes(big_wav, MediaLimits.MAX_AUDIO_BYTES + 1)
	assert_eq(MediaLimits.check_image("user://nope.png"), "missing")
	assert_eq(MediaLimits.check_image("res://content/sprites/trueborn.json"), "not a .png")
	assert_contains(MediaLimits.check_image(big_png), "too large")
	assert_contains(MediaLimits.check_image(fake_png), "bad signature")
	assert_eq(MediaLimits.check_image("res://content/sprites/trueborn.png"), "", "the real sheet passes")
	var wide := Image.create_empty(MediaLimits.MAX_IMAGE_SIDE + 1, 8, false, Image.FORMAT_RGBA8)
	assert_contains(MediaLimits.check_image_size(wide), "too big")
	assert_eq(MediaLimits.check_image_size(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)), "")
	assert_eq(MediaLimits.check_audio("user://nope.wav"), "missing")
	assert_contains(MediaLimits.check_audio(big_wav), "too large")
	assert_eq(MediaLimits.check_audio(fake_png), "not .wav, .ogg or .mp3")
	# The loaders refuse the same things.
	var sheet := SpriteSheet.load_entry({"id": "zz_big", "image": "big.png", "frame": [48, 64], "directions": ["s"], "animations": {}, "_path": MEDIA_DIR.path_join("zz_big.json")})
	assert_false(sheet.is_valid())
	assert_any_contains(sheet.errors, "too large")
	assert_true(AudioDirector.load_file(big_wav, false) == null, "a file past the cap does not load")
	# The validator says so per entry.
	var r := ContentRegistry.new()
	r.load_from(ContentRegistry.BASE_ROOT, [])
	r.put("sprites", "zz_big", {"image": "big.png", "frame": [48, 64]})
	r._entries["sprites"]["zz_big"]["_path"] = MEDIA_DIR.path_join("zz_big.json")
	r.put("audio", "zz_loud", {"name": "Loud", "kind": "sfx", "file": "big.wav"})
	r._entries["audio"]["zz_loud"]["_path"] = MEDIA_DIR.path_join("zz_loud.json")
	var problems := ContentValidator.validate(r, ["runtime"])
	assert_any_contains(problems, "sprites/zz_big (runtime): image 'big.png' too large")
	assert_any_contains(problems, "audio/zz_loud (runtime): file 'big.wav' too large")
	r.free()


func test_a_world_under_test_never_touches_the_players_files() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(w)
	assert_eq(w.account_path, "user://test_account_default.json", "the default account path is redirected under tests")
	assert_eq(w.ledger_path, "user://test_ledger_default.json")
	assert_eq(w.saves_dir, "user://test_saves_default")
	assert_eq(w.ledger.path, w.ledger_path, "the ledger was reloaded from the test path")
	root.remove_child(w)
	w.free()
	assert_false(FileAccess.file_exists("user://test_crash116/marker.json"), "no crash marker is written under tests")


func test_the_engine_version_agrees_everywhere() -> void:
	var feature := String(PackedStringArray(ProjectSettings.get_setting("application/config/features", PackedStringArray()))[0])
	var running := "%d.%d" % [int(Engine.get_version_info()["major"]), int(Engine.get_version_info()["minor"])]
	assert_eq(feature, running, "project.godot's feature tag is the engine running the tests")
	var re := RegEx.new()
	re.compile("GODOT_VERSION:\\s*([0-9.]+)-stable")
	for path: String in ["res://.github/workflows/ci.yml", "res://.github/workflows/release.yml"]:
		var m := re.search(FileAccess.get_file_as_string(path))
		assert_true(m != null, "%s pins GODOT_VERSION" % path)
		assert_true(m.get_string(1).begins_with(feature + "."), "%s pins %s, the project says %s" % [path, m.get_string(1), feature])
	var release := FileAccess.get_file_as_string("res://.github/workflows/release.yml")
	assert_contains(release, "editor_settings-%s.tres" % feature, "the notarize step writes the editor settings for the same engine")
	var preset := AppleCheck.macos_preset()
	assert_eq(String(preset["application/version"]), String(ProjectSettings.get_setting("application/config/version", "")), "the preset's version is the project's")


func test_the_screenshot_check_fails_blank_flat_small_and_missing_frames() -> void:
	assert_eq(CheckShots.check("user://nope.png"), "missing")
	var small := Image.create_empty(640, 360, false, Image.FORMAT_RGBA8)
	assert_contains(CheckShots.judge(small), "too small")
	var clear := Color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.05, 0.04, 0.07)))
	var blank := Image.create_empty(1280, 720, false, Image.FORMAT_RGBA8)
	blank.fill(clear)
	assert_contains(CheckShots.judge(blank), "blank")
	var flat := Image.create_empty(1280, 720, false, Image.FORMAT_RGBA8)
	flat.fill(clear)
	flat.fill_rect(Rect2i(0, 0, 640, 720), Color.WHITE)
	assert_contains(CheckShots.judge(flat), "flat")
	var rich := Image.create_empty(1280, 720, false, Image.FORMAT_RGBA8)
	rich.fill(clear)
	for i: int in 200:
		rich.fill_rect(Rect2i(i * 6, 100, 6, 200), Color(float(i) / 200.0, 0.5, 1.0 - float(i) / 200.0))
	assert_eq(CheckShots.judge(rich), "", "a frame with things on it passes")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEDIA_DIR))
	assert_eq(rich.save_png(MEDIA_DIR.path_join("rich.png")), OK)
	assert_eq(CheckShots.check(MEDIA_DIR.path_join("rich.png")), "")
	assert_true(CheckShots.DEFAULT_EXPECTED.has("screenshot-title.png"))
