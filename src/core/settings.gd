## Player settings: fullscreen, master volume, pad glyph style, pad rumble
## and text size (S53). Persist as
## `user://settings.json`; `apply()` pushes them to the display and audio
## servers (guarded so headless runs stay quiet).
class_name Settings
extends RefCounted

const PATH := "user://settings.json"
const VOLUME_MIN_DB := -30.0
const VOLUME_STEP_DB := 3.0
const GLYPH_STYLES: Array[String] = ["auto", "xbox", "playstation"]

var fullscreen: bool = false
var volume_db: float = 0.0
var glyphs: String = "auto"
var rumble: bool = true
var text_scale: float = 1.0
var load_error: String = ""


func to_dict() -> Dictionary:
	return {"version": 1, "fullscreen": fullscreen, "volume_db": volume_db, "glyphs": glyphs, "rumble": rumble, "text_scale": text_scale}


static func from_dict(d: Dictionary) -> Settings:
	var s := Settings.new()
	s.fullscreen = bool(d.get("fullscreen", false))
	s.volume_db = clampf(float(d.get("volume_db", 0.0)), VOLUME_MIN_DB, 0.0)
	var g := String(d.get("glyphs", "auto"))
	s.glyphs = g if GLYPH_STYLES.has(g) else "auto"
	s.rumble = bool(d.get("rumble", true))
	s.text_scale = nearest_scale(float(d.get("text_scale", 1.0)))
	return s


static func load_or_default(path: String = PATH) -> Settings:
	if not FileAccess.file_exists(path):
		return deck_default()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var s := Settings.new()
		s.load_error = "cannot open %s" % path
		return s
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		var s := Settings.new()
		s.load_error = "settings JSON error"
		return s
	return from_dict(json.data)


func save(path: String = PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "  "))
	return OK


## Pushes the settings to the engine. Safe headless: window and audio
## calls are skipped when no display or audio device is up.
func apply() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if AudioServer.bus_count > 0:
		AudioServer.set_bus_volume_db(0, volume_db)
	Glyphs.style = glyphs
	Rumble.enabled = rumble
	UiScale.text_scale = text_scale


func volume_percent() -> int:
	return int(round((volume_db - VOLUME_MIN_DB) / (0.0 - VOLUME_MIN_DB) * 100.0))


func step_volume(direction: int) -> void:
	volume_db = clampf(volume_db + VOLUME_STEP_DB * float(direction), VOLUME_MIN_DB, 0.0)


func cycle_glyphs(direction: int) -> void:
	var i := GLYPH_STYLES.find(glyphs)
	glyphs = GLYPH_STYLES[posmod(i + direction, GLYPH_STYLES.size())]


## The Steam Deck's screen is 1280×800 and shows the 1920×1080 canvas at
## two thirds: a fresh install there starts with Deck text and fullscreen.
## `--deck` on the command line forces it; any saved settings win.
static func deck_default() -> Settings:
	var s := Settings.new()
	if looks_like_deck():
		s.text_scale = 1.5
		s.fullscreen = true
	return s


static func looks_like_deck() -> bool:
	if OS.get_cmdline_user_args().has("--deck"):
		return true
	if DisplayServer.get_name() == "headless":
		return false
	return OS.get_name() == "Linux" and DisplayServer.screen_get_size() == Vector2i(1280, 800)


static func nearest_scale(value: float) -> float:
	var best := 1.0
	for s: float in UiScale.SCALES:
		if absf(s - value) < absf(best - value):
			best = s
	return best


func cycle_text_scale(direction: int) -> void:
	var i := UiScale.SCALES.find(nearest_scale(text_scale))
	text_scale = UiScale.SCALES[posmod(i + direction, UiScale.SCALES.size())]


func text_scale_name() -> String:
	return UiScale.name_of(text_scale)
