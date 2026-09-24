## Player settings: fullscreen, master, music and sound volume, pad glyph
## style, pad rumble, text size (S53) and the colour-blind palette (S54).
## Persist as
## `user://settings.json`; `apply()` pushes them to the display and audio
## servers (guarded so headless runs stay quiet).
class_name Settings
extends RefCounted

const PATH := "user://settings.json"
const VOLUME_MIN_DB := -30.0
const VOLUME_STEP_DB := 3.0
const GLYPH_STYLES: Array[String] = ["auto", "xbox", "playstation"]
const AUTOSAVES_MAX := 5

var fullscreen: bool = false
var volume_db: float = 0.0
var glyphs: String = "auto"
var rumble: bool = true
var text_scale: float = 1.0
var music_db: float = 0.0
var sfx_db: float = 0.0
var palette: String = "normal"
var locale: String = Loc.DEFAULT
var lighting: bool = true
var screen_fx: String = "glow"
var gore: String = "full"
## How many older autosaves stay beside the newest (S68): 1 to AUTOSAVES_MAX.
var autosaves_kept: int = 3
var load_error: String = ""


func to_dict() -> Dictionary:
	return {"version": 1, "fullscreen": fullscreen, "volume_db": volume_db, "glyphs": glyphs, "rumble": rumble, "text_scale": text_scale, "music_db": music_db, "sfx_db": sfx_db, "palette": palette, "locale": locale, "lighting": lighting, "screen_fx": screen_fx, "gore": gore, "autosaves_kept": autosaves_kept}


static func from_dict(d: Dictionary) -> Settings:
	var s := Settings.new()
	s.fullscreen = bool(d.get("fullscreen", false))
	s.volume_db = clampf(float(d.get("volume_db", 0.0)), VOLUME_MIN_DB, 0.0)
	var g := String(d.get("glyphs", "auto"))
	s.glyphs = g if GLYPH_STYLES.has(g) else "auto"
	s.rumble = bool(d.get("rumble", true))
	s.text_scale = nearest_scale(float(d.get("text_scale", 1.0)))
	s.music_db = clampf(float(d.get("music_db", 0.0)), VOLUME_MIN_DB, 0.0)
	s.sfx_db = clampf(float(d.get("sfx_db", 0.0)), VOLUME_MIN_DB, 0.0)
	var p := String(d.get("palette", "normal"))
	s.palette = p if ColorFilter.MODES.has(p) else "normal"
	s.locale = String(d.get("locale", Loc.DEFAULT))
	s.lighting = bool(d.get("lighting", true))
	var fx := String(d.get("screen_fx", "glow"))
	s.screen_fx = fx if ScreenFx.MODES.has(fx) else "glow"
	var g2 := String(d.get("gore", "full"))
	s.gore = g2 if DecalLayer.MODES.has(g2) else "full"
	s.autosaves_kept = clampi(int(d.get("autosaves_kept", 3)), 1, AUTOSAVES_MAX)
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
		for pair: Array in [[AudioDirector.BUS_MUSIC, music_db], [AudioDirector.BUS_SFX, sfx_db]]:
			var i := AudioServer.get_bus_index(String(pair[0]))
			if i >= 0:
				AudioServer.set_bus_volume_db(i, float(pair[1]))
	Glyphs.style = glyphs
	Rumble.enabled = rumble
	UiScale.text_scale = text_scale
	locale = Loc.set_locale(locale)
	LightingRig.enabled = lighting
	DecalLayer.level = gore


func volume_percent() -> int:
	return percent_of(volume_db)


static func percent_of(db: float) -> int:
	return int(round((db - VOLUME_MIN_DB) / (0.0 - VOLUME_MIN_DB) * 100.0))


func step_volume(direction: int) -> void:
	volume_db = stepped(volume_db, direction)


static func stepped(db: float, direction: int) -> float:
	return clampf(db + VOLUME_STEP_DB * float(direction), VOLUME_MIN_DB, 0.0)


func step_music(direction: int) -> void:
	music_db = stepped(music_db, direction)


func step_sfx(direction: int) -> void:
	sfx_db = stepped(sfx_db, direction)


func cycle_palette(direction: int) -> void:
	palette = ColorFilter.cycle(palette, direction)


func cycle_screen_fx(direction: int) -> void:
	screen_fx = ScreenFx.cycle(screen_fx, direction)


func cycle_gore(direction: int) -> void:
	gore = DecalLayer.cycle(gore, direction)


func cycle_autosaves(direction: int) -> void:
	autosaves_kept = clampi(autosaves_kept + direction, 1, AUTOSAVES_MAX)


func cycle_locale(direction: int) -> void:
	var ids := Loc.available()
	if ids.is_empty():
		return
	var i := ids.find(locale)
	locale = ids[posmod(i + direction, ids.size())]


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
