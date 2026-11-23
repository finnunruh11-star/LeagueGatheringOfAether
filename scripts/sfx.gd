class_name Sfx
extends RefCounted
## Tiny synthesized retro sound effects (no audio files needed).

const RATE := 22050

static var _cache := {}
static var _last_played := {}


static func stream(sound: String) -> AudioStreamWAV:
	if not _cache.has(sound):
		_cache[sound] = _make(sound)
	return _cache[sound]


## Returns false if the same sound played very recently (avoids noise walls).
static func allow(sound: String, gap_ms := 60) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sound, -100000)) < gap_ms:
		return false
	_last_played[sound] = now
	return true


static func _make(sound: String) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	match sound:
		"boom":
			s = _noise(0.35, 6.0, 0.25)
			_mix(s, _sweep(110.0, 40.0, 0.35, 8.0, false), 0.8)
		"hit":
			s = _noise(0.07, 30.0, 0.5)
		"zap":
			s = _sweep(1400.0, 250.0, 0.16, 10.0, true)
		"pop":
			s = _sweep(500.0, 900.0, 0.08, 20.0, false)
		"cast":
			s = _sweep(300.0, 1000.0, 0.13, 12.0, true)
		"death":
			s = _sweep(420.0, 70.0, 0.55, 4.0, true)
		"level":
			s = _sweep(523.0, 523.0, 0.1, 6.0, true)
			s.append_array(_sweep(659.0, 659.0, 0.1, 6.0, true))
			s.append_array(_sweep(784.0, 784.0, 0.22, 6.0, true))
		"coin":
			s = _sweep(1568.0, 1568.0, 0.05, 25.0, false)
			s.append_array(_sweep(2093.0, 2093.0, 0.12, 14.0, false))
		"buy":
			s = _sweep(880.0, 880.0, 0.06, 12.0, true)
			s.append_array(_sweep(1320.0, 1320.0, 0.14, 10.0, true))
		"error":
			s = _sweep(220.0, 180.0, 0.16, 6.0, true)
		_:
			s = _sweep(440.0, 440.0, 0.1, 10.0, false)
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


static func _sweep(f0: float, f1: float, dur: float, decay: float, square: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var v := sin(phase * TAU)
		if square:
			v = signf(v) * 0.6
		out[i] = v * exp(-decay * t * dur * 4.0) * minf(1.0, i / 80.0)
	return out


static func _noise(dur: float, decay: float, lowpass: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		prev = lerpf(prev, randf_range(-1.0, 1.0), lowpass)
		out[i] = prev * exp(-decay * float(i) / RATE * 4.0) * 1.4
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain: float) -> void:
	for i in mini(a.size(), b.size()):
		a[i] += b[i] * gain
