## Placeholder audio synthesised from a small spec, so every sound event
## has something to play before any recorded asset exists. Real assets
## replace an entry by adding `file` to its `audio` sidecar; the spec
## stays as the fallback.
##
## Spec (sfx): {"wave": sine|square|saw|noise, "freq": 440, "duration": 0.12,
##   "sweep": -0.6 (octaves over the sound), "decay": true, "volume": 0.5}
## Spec (music): {"wave", "bpm": 96, "notes": [midi or 0 for rest], "step": 0.5
##   (beats per note), "volume": 0.3, "bars": repeats} -> a looping stream.
class_name SynthWave
extends RefCounted

const MIX_RATE := 22050


static func build(spec: Dictionary) -> AudioStreamWAV:
	if spec.has("notes"):
		return build_loop(spec)
	return build_sfx(spec)


static func build_sfx(spec: Dictionary) -> AudioStreamWAV:
	var duration := clampf(float(spec.get("duration", 0.12)), 0.01, 4.0)
	var freq := float(spec.get("freq", 440.0))
	var sweep := float(spec.get("sweep", 0.0))
	var decay := bool(spec.get("decay", true))
	var volume := clampf(float(spec.get("volume", 0.5)), 0.0, 1.0)
	var wave := String(spec.get("wave", "square"))
	var frames := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	var noise_seed := 12345
	for i: int in frames:
		var t := float(i) / float(frames)
		var f := freq * pow(2.0, sweep * t)
		phase += f / float(MIX_RATE)
		var env := (1.0 - t) if decay else 1.0
		var v := _sample(wave, phase, noise_seed + i) * env * volume
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	return _stream(data, false)


static func build_loop(spec: Dictionary) -> AudioStreamWAV:
	var bpm := maxf(float(spec.get("bpm", 96.0)), 20.0)
	var step := maxf(float(spec.get("step", 0.5)), 0.0625)
	var notes: Array = spec.get("notes", [60])
	var bars := maxi(int(spec.get("bars", 1)), 1)
	var volume := clampf(float(spec.get("volume", 0.3)), 0.0, 1.0)
	var wave := String(spec.get("wave", "square"))
	var note_seconds := 60.0 / bpm * step
	var note_frames := maxi(int(note_seconds * MIX_RATE), 1)
	var total := note_frames * notes.size() * bars
	var data := PackedByteArray()
	data.resize(total * 2)
	var phase := 0.0
	var i := 0
	for _bar: int in bars:
		for note: Variant in notes:
			var midi := int(note)
			var f := 0.0 if midi <= 0 else 440.0 * pow(2.0, float(midi - 69) / 12.0)
			for k: int in note_frames:
				var t := float(k) / float(note_frames)
				var env := minf(1.0, t * 20.0) * (1.0 - t * 0.6)
				var v := 0.0
				if f > 0.0:
					phase += f / float(MIX_RATE)
					v = _sample(wave, phase, i) * env * volume
				data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
				i += 1
	return _stream(data, true)


static func _sample(wave: String, phase: float, seed_value: int) -> float:
	var p := fmod(phase, 1.0)
	match wave:
		"sine":
			return sin(p * TAU)
		"saw":
			return p * 2.0 - 1.0
		"noise":
			var h := (seed_value * 1103515245 + 12345) & 0x7fffffff
			return float(h % 2000) / 1000.0 - 1.0
	return 1.0 if p < 0.5 else -1.0


static func _stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size() / 2
	return s


static func seconds(stream: AudioStreamWAV) -> float:
	return float(stream.data.size() / 2) / float(MIX_RATE)
