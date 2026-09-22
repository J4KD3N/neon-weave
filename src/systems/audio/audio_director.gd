## Plays sound events and music from the `audio` content kind and the
## `rules/audio` event map. Sounds come from a file when the entry has one,
## else from SynthWave. Music crossfades between two players; the state
## (title, bastion, explore per biome, combat) picks the track. Every play
## is logged so tests can assert on it without ears.
class_name AudioDirector
extends Node

const POOL_SIZE := 8
## Sub-buses of Master (S54): the settings screen turns each down on its own.
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var registry: ContentRegistry
var rules: Dictionary = {}
var streams: Dictionary = {} # audio id -> AudioStream
var sources: Dictionary = {} # audio id -> "file" or "synth" (S57): what actually plays
var log: Array[String] = [] # sound ids played, in order (music as "music:<id>")
var current_track: String = ""
var crossfade_seconds: float = 1.5
var _pool: Array[AudioStreamPlayer] = []
var _next_player := 0
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_front: AudioStreamPlayer
var _tween: Tween


func setup(p_registry: ContentRegistry) -> void:
	registry = p_registry
	rules = registry.get_entry("rules", "audio")
	crossfade_seconds = float(rules.get("crossfade_seconds", 1.5))
	ensure_buses()
	for _i: int in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m: AudioStreamPlayer in [_music_a, _music_b]:
		m.bus = BUS_MUSIC
		m.volume_db = -80.0
		add_child(m)
	_music_front = _music_a


## Creates the Music and SFX buses under Master when the project has none.
static func ensure_buses() -> void:
	for name: String in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")


## The stream for an audio entry, built on first use and cached.
func stream_for(id: String) -> AudioStream:
	if streams.has(id):
		return streams[id]
	var entry: Dictionary = registry.get_entry("audio", id)
	if entry.is_empty():
		return null
	var stream: AudioStream = null
	var file := String(entry.get("file", ""))
	if not file.is_empty():
		stream = load_file(String(entry.get("_path", "")).get_base_dir().path_join(file), bool(entry.get("loop", String(entry.get("kind", "")) == "music")))
	sources[id] = "file" if stream != null else "synth"
	if stream == null:
		stream = SynthWave.build(entry.get("synth", {}))
	streams[id] = stream
	return stream


## A recorded file beside its sidecar (S57): an imported resource when the
## project imported it, else read straight from disk by extension (.wav,
## .ogg, .mp3), which is how a mod's files arrive. Music loops. Null when
## the file is missing or unreadable.
static func load_file(path: String, loop: bool) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		match path.get_extension().to_lower():
			"wav":
				stream = AudioStreamWAV.load_from_file(path)
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(path)
			"mp3":
				stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		return null
	if loop:
		if stream is AudioStreamWAV:
			(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
	return stream


## True while an entry still plays the synthesised placeholder.
func is_placeholder(id: String) -> bool:
	stream_for(id)
	return String(sources.get(id, "synth")) == "synth"


## Plays a one-shot sound by audio id. Unknown ids are ignored (logged as "?id").
func play(id: String) -> bool:
	if id.is_empty():
		return false
	var stream := stream_for(id)
	if stream == null:
		log.append("?" + id)
		return false
	var entry: Dictionary = registry.get_entry("audio", id)
	var p := _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	p.stream = stream
	p.volume_db = float(entry.get("volume_db", 0.0))
	p.play()
	log.append(id)
	return true


## Plays an event from rules/audio: "ui.confirm", "combat.hit", "explore.pickup".
func event(path: String) -> bool:
	var parts := path.split(".")
	if parts.size() != 2:
		return false
	var group: Dictionary = rules.get(parts[0], {})
	return play(String(group.get(parts[1], "")))


## The music track for a state ("title", "bastion", "combat", or "explore"
## with a biome), from rules/audio.music. A state maps to a track id or to
## a table: the first of `variant` (a fight with a boss: "boss"), "act<n>",
## the biome, then "default" that names a track wins (S57). Pure; "" when
## none is mapped.
static func pick_music(p_rules: Dictionary, state: String, biome: String = "", act: int = 1, variant: String = "") -> String:
	var music: Dictionary = p_rules.get("music", {})
	var v: Variant = music.get(state, "")
	if v is String:
		return String(v)
	if not v is Dictionary:
		return ""
	var table: Dictionary = v
	for key: String in [variant, "act%d" % act, biome, "default"]:
		if not key.is_empty() and table.has(key) and table[key] is String and not String(table[key]).is_empty():
			return String(table[key])
	return ""


## Switches music to the track for a state, crossfading when it changes.
func set_state(state: String, biome: String = "", act: int = 1, variant: String = "") -> String:
	var track := pick_music(rules, state, biome, act, variant)
	if track == current_track:
		return track
	current_track = track
	log.append("music:" + track)
	var stream := stream_for(track) if not track.is_empty() else null
	var back := _music_b if _music_front == _music_a else _music_a
	var front := _music_front
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if stream != null:
		back.stream = stream
		back.volume_db = -80.0
		back.play()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(front, "volume_db", -80.0, crossfade_seconds)
	if stream != null:
		var target_db := float(registry.get_entry("audio", track).get("volume_db", -8.0))
		_tween.tween_property(back, "volume_db", target_db, crossfade_seconds)
	_tween.chain().tween_callback(func() -> void: front.stop())
	_music_front = back
	return track


func is_crossfading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func plays_of(id: String) -> int:
	return log.count(id)
