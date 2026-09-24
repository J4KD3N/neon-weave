## Checks the screenshots CI renders (gap analysis 2026-09-24, D-116):
##
##   godot --headless --path . -s tools/check_shots.gd -- --dir=build [--expect=a.png,b.png]
##
## A frame that rendered badly is usually blank, uniform or tiny; a menu
## that broke is a frame with nothing on it. Every expected file must
## exist, be at least 1280×720, have at least 2% of its pixels off the
## clear colour, and at least 64 distinct colours. Exit 1 on the first
## file that fails, with why.
class_name CheckShots
extends SceneTree

const DEFAULT_EXPECTED: Array[String] = ["screenshot.png", "screenshot-title.png", "screenshot-combat.png", "screenshot-shard.png", "screenshot-datacore.png", "screenshot-markets.png", "screenshot-cathedral.png", "screenshot-loom.png", "screenshot-road.png", "screenshot-dialogue.png", "screenshot-creator.png", "screenshot-crt.png", "screenshot-flat.png", "screenshot-gallery.png"]
const MIN_WIDTH := 1280
const MIN_HEIGHT := 720
const MIN_INK := 0.02
const MIN_COLOURS := 64


func _init() -> void:
	var dir := "build"
	var expected: Array[String] = DEFAULT_EXPECTED.duplicate()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.get_slice("=", 1)
		elif arg.begins_with("--expect="):
			expected.assign(arg.get_slice("=", 1).split(","))
	var failed := 0
	for name: String in expected:
		var why := check(dir.path_join(name))
		print("shot %-28s %s" % [name, "ok" if why.is_empty() else "FAIL: " + why])
		if not why.is_empty():
			failed += 1
	print("shots: %d checked, %d failed" % [expected.size(), failed])
	quit(1 if failed > 0 else 0)


## "" when the frame looks rendered, else why not.
static func check(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return "unreadable"
	return judge(img)


static func judge(img: Image) -> String:
	if img.get_width() < MIN_WIDTH or img.get_height() < MIN_HEIGHT:
		return "too small: %dx%d" % [img.get_width(), img.get_height()]
	var clear := Color(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.05, 0.04, 0.07)))
	var ink := 0
	var colours: Dictionary = {}
	var step := 4 # every fourth pixel each way: 1/16 of the frame, plenty
	var samples := 0
	for y: int in range(0, img.get_height(), step):
		for x: int in range(0, img.get_width(), step):
			var p := img.get_pixel(x, y)
			samples += 1
			if absf(p.r - clear.r) > 0.02 or absf(p.g - clear.g) > 0.02 or absf(p.b - clear.b) > 0.02:
				ink += 1
			if colours.size() < MIN_COLOURS:
				colours[p.to_rgba32()] = true
	var fraction := float(ink) / float(maxi(samples, 1))
	if fraction < MIN_INK:
		return "blank: %.1f%% of pixels off the clear colour" % (fraction * 100.0)
	if colours.size() < MIN_COLOURS:
		return "flat: only %d distinct colours" % colours.size()
	return ""
