class_name Fx
extends Node2D
## One-shot procedural effect (rings, blasts, telegraphs, numbers, beams).
## Drawn in world coordinates; frees itself when finished.

const DURATIONS := {"ring": 0.35, "blast": 0.3, "text": 1.1, "num": 0.9, "line": 0.3, "beam": 0.4, "click": 0.3}
const ENEMY_WARN := Color(1.0, 0.22, 0.18)

var kind := ""
var d := {}
var t := 0.0
var dur := 0.4


func setup(k: String, data: Dictionary) -> void:
	kind = k
	d = data
	dur = float(d.get("dur", DURATIONS.get(k, 0.4)))
	if kind == "text" or kind == "num":
		z_index = 10


func _process(delta: float) -> void:
	t += delta
	if t >= dur:
		queue_free()
		return
	queue_redraw()


func _enemy_telegraph() -> bool:
	return d.has("team") and Game.world != null and int(d.team) != Game.world.local_team


func _draw() -> void:
	var p := t / dur
	var col: Color = d.get("color", Color.WHITE)
	match kind:
		"ring":
			var r: float = d.get("radius", 50.0)
			draw_arc(d.pos, r * (0.4 + 0.6 * p), 0, TAU, 48, Color(col, 1.0 - p), 4.0, true)
		"blast":
			var r: float = d.get("radius", 100.0)
			var angle: float = d.get("angle", 360.0)
			var fade := (1.0 - p) * (1.0 - p)
			if angle < 359.0:
				var dir: Vector2 = d.get("dir", Vector2.RIGHT)
				var pts := PackedVector2Array([d.pos])
				var half := deg_to_rad(angle) * 0.5
				for i in 17:
					pts.append(d.pos + dir.rotated(-half + 2.0 * half * i / 16.0) * r * (0.7 + 0.3 * p))
				draw_colored_polygon(pts, Color(col, 0.45 * fade))
				pts.append(d.pos)
				draw_polyline(pts, Color(col.lightened(0.4), fade), 3.0, true)
			else:
				draw_circle(d.pos, r, Color(col, 0.3 * fade))
				draw_arc(d.pos, r * (0.75 + 0.25 * p), 0, TAU, 64, Color(col.lightened(0.5), fade), 2.0 + 6.0 * (1.0 - p), true)
		"telegraph":
			var r: float = d.get("radius", 100.0)
			var c := ENEMY_WARN if _enemy_telegraph() else col
			var pulse := 0.5 + 0.5 * sin(t * 16.0)
			draw_circle(d.pos, r, Color(c, 0.08 + 0.06 * pulse))
			draw_circle(d.pos, r * p, Color(c, 0.22 + 0.1 * p))
			draw_arc(d.pos, r, 0, TAU, 72, Color(c, 0.65 + 0.35 * pulse), 3.0, true)
			for i in 8:
				var a := i * TAU / 8.0 + t * 1.5
				draw_line(d.pos + Vector2.from_angle(a) * r * 0.82, d.pos + Vector2.from_angle(a) * r * 0.96, Color(c, 0.8), 3.0)
		"text", "num":
			_draw_number(p, col)
		"line":
			draw_line(d.from, d.to, Color(col, col.a * (1.0 - p)), 4.0)
		"beam":
			var w: float = d.get("width", 60.0)
			var fade := 1.0 - p
			draw_line(d.from, d.to, Color(col, 0.25 * fade), w * 1.6 * (1.0 - 0.4 * p))
			draw_line(d.from, d.to, Color(col.lightened(0.2), 0.7 * fade), w * (1.0 - 0.5 * p))
			draw_line(d.from, d.to, Color(1, 1, 1, 0.9 * fade), maxf(w * 0.22 * (1.0 - p), 1.0))
			draw_circle(d.from, w * 0.6 * fade, Color(col.lightened(0.4), 0.6 * fade))
		"beam_warn":
			var w: float = d.get("width", 60.0)
			var c := ENEMY_WARN if _enemy_telegraph() else col
			var a: Vector2 = d.from
			var b: Vector2 = d.to
			var side := (b - a).normalized().orthogonal() * w * 0.5
			draw_line(a, b, Color(c, 0.1), w)
			draw_line(a, a.lerp(b, p), Color(c, 0.28), w)
			draw_line(a + side, b + side, Color(c, 0.8), 2.0)
			draw_line(a - side, b - side, Color(c, 0.8), 2.0)
		"click":
			draw_arc(d.pos, 18.0 * (1.0 - p) + 4.0, 0, TAU, 20, Color(col, 1.0 - p), 3.0)
			draw_arc(d.pos, 8.0 * (1.0 - p) + 2.0, 0, TAU, 12, Color(col, 0.6 * (1.0 - p)), 2.0)


## Damage numbers and floating text: pop in, rise, drift, fade.
func _draw_number(p: float, col: Color) -> void:
	var big := bool(d.get("big", kind == "text"))
	var size := int(d.get("size", 18))
	var peak := 1.55 if big else 1.25
	var s := 1.0
	if t < 0.07:
		s = lerpf(0.5, peak, t / 0.07)
	elif t < 0.2:
		s = lerpf(peak, 1.0, (t - 0.07) / 0.13)
	var rise := 46.0 * (1.0 - (1.0 - p) * (1.0 - p))
	var a := 1.0 if p < 0.65 else 1.0 - (p - 0.65) / 0.35
	var pos: Vector2 = Vector2(d.pos) + Vector2(float(d.get("drift", 0.0)) * p, -rise)
	draw_set_transform(pos, 0.0, Vector2(s, s))
	var font := ThemeDB.fallback_font
	var text := str(d.get("text", ""))
	draw_string_outline(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, 6, Color(0.05, 0.02, 0.05, 0.9 * a))
	draw_string(font, Vector2(-150, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 300, size, Color(col, a))
	draw_set_transform(Vector2.ZERO)
