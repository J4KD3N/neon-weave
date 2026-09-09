## Plays sound events and music from the `audio` content kind and the
## `rules/audio` event map. Sounds come from a file when the entry has one,
## else from SynthWave. Music crossfades between two players; the state
## (title, bastion, explore per biome, combat) picks the track. Every play
## is logged so tests can assert on it without ears.
class_name AudioDirector
extends Node

const POOL_SIZE := 8

var registry: ContentRegistry
var rules: Dictionary = {}
var streams: Dictionary = {} # audio id -> AudioStream
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
	for _i: int in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m: AudioStreamPlayer in [_music_a, _music_b]:
		m.bus = "Master"
		m.volume_db = -80.0
		add_child(m)
	_music_front = _music_a


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
		var path := String(entry["_path"]).get_base_dir().path_join(file)
		if ResourceLoader.exists(path):
			stream = load(path)
	if stream == null:
		stream = SynthWave.build(entry.get("synth", {}))
	streams[id] = stream
	return stream


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
## with a biome), from rules/audio.music. Pure; "" when none is mapped.
static func pick_music(p_rules: Dictionary, state: String, biome: String = "") -> String:
	var music: Dictionary = p_rules.get("music", {})
	if state == "explore":
		var per_biome: Dictionary = music.get("explore", {})
		return String(per_biome.get(biome, per_biome.get("default", "")))
	var v: Variant = music.get(state, "")
	return String(v) if v is String else ""


## Switches music to the track for a state, crossfading when it changes.
func set_state(state: String, biome: String = "") -> String:
	var track := pick_music(rules, state, biome)
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
