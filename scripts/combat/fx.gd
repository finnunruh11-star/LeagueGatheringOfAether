class_name Fx
extends Node2D
## One-shot visual effect (rings, blasts, telegraphs, floating text, lines).
## Drawn in world coordinates; frees itself when finished.

const DURATIONS := {"ring": 0.35, "blast": 0.35, "text": 1.0, "line": 0.3, "beam": 0.35, "click": 0.3}

var kind := ""
var d := {}
var t := 0.0
var dur := 0.4


func setup(k: String, data: Dictionary) -> void:
	kind = k
	d = data
	dur = float(d.get("dur", DURATIONS.get(k, 0.4)))
	if kind == "text":
		z_index = 10


func _process(delta: float) -> void:
	t += delta
	if t >= dur:
		queue_free()
		return
	queue_redraw()


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
			var c := Color(col, 0.45 * (1.0 - p))
			if angle < 359.0:
				var dir: Vector2 = d.get("dir", Vector2.RIGHT)
				var pts := PackedVector2Array([d.pos])
				var half := deg_to_rad(angle) * 0.5
				for i in 17:
					pts.append(d.pos + dir.rotated(-half + 2.0 * half * i / 16.0) * r)
				draw_colored_polygon(pts, c)
			else:
				draw_circle(d.pos, r, c)
				draw_arc(d.pos, r * (0.85 + 0.15 * p), 0, TAU, 64, Color(col, 1.0 - p), 3.0, true)
		"telegraph":
			var r: float = d.get("radius", 100.0)
			draw_circle(d.pos, r, Color(col, 0.1))
			draw_circle(d.pos, r * p, Color(col, 0.25))
			draw_arc(d.pos, r, 0, TAU, 64, Color(col, 0.85), 2.0, true)
		"text":
			var font := ThemeDB.fallback_font
			var size := int(d.get("size", 18))
			var pos: Vector2 = d.pos + Vector2(-100, -50.0 * p)
			var a := 1.0 - p * p
			draw_string_outline(font, pos, str(d.text), HORIZONTAL_ALIGNMENT_CENTER, 200, size, 4, Color(0, 0, 0, 0.8 * a))
			draw_string(font, pos, str(d.text), HORIZONTAL_ALIGNMENT_CENTER, 200, size, Color(col, a))
		"line":
			draw_line(d.from, d.to, Color(col, 1.0 - p), 4.0)
		"beam":
			var w: float = d.get("width", 60.0)
			draw_line(d.from, d.to, Color(col, 0.6 * (1.0 - p)), w * (1.0 - 0.5 * p))
			draw_line(d.from, d.to, Color(1, 1, 1, 0.8 * (1.0 - p)), w * 0.25)
		"beam_warn":
			var w: float = d.get("width", 60.0)
			draw_line(d.from, d.to, Color(col, 0.12), w)
			draw_line(d.from, d.from.lerp(d.to, p), Color(col, 0.3), w)
		"click":
			draw_arc(d.pos, 18.0 * (1.0 - p) + 4.0, 0, TAU, 20, Color(col, 1.0 - p), 3.0)
