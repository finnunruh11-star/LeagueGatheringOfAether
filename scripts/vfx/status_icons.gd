class_name StatusIcons
extends RefCounted
## Tiny vector glyphs for status effects, drawn above health bars.


static func draw(n: CanvasItem, c: Vector2, kind: String) -> void:
	n.draw_circle(c, 7.5, Color(0.05, 0.05, 0.08, 0.85))
	match kind:
		"stun":
			var pts := PackedVector2Array()
			for i in 8:
				pts.append(c + Vector2.from_angle(i * TAU / 8.0 - PI / 2.0) * (6.0 if i % 2 == 0 else 2.4))
			n.draw_colored_polygon(pts, Color(1.0, 0.88, 0.25))
		"root":
			n.draw_arc(c, 4.5, 0, TAU, 12, Color(0.45, 0.85, 0.3), 2.0)
			n.draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color(0.45, 0.85, 0.3), 2.0)
		"silence":
			n.draw_arc(c, 4.5, 0, TAU, 12, Color(0.8, 0.55, 1.0), 2.0)
			n.draw_line(c + Vector2(-3.5, 3.5), c + Vector2(3.5, -3.5), Color(0.8, 0.55, 1.0), 2.0)
		"slow":
			n.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -3), c + Vector2(5, -3), c + Vector2(0, 5)]), Color(0.45, 0.72, 1.0))
		"dot":
			n.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(4, 1), c + Vector2(-4, 1)]), Color(1.0, 0.55, 0.15))
			n.draw_circle(c + Vector2(0, 2), 4.0, Color(1.0, 0.45, 0.12))
			n.draw_circle(c + Vector2(0, 2.5), 2.0, Color(1.0, 0.85, 0.3))
		"hot":
			n.draw_rect(Rect2(c + Vector2(-1.5, -5), Vector2(3, 10)), Color(0.45, 1.0, 0.45))
			n.draw_rect(Rect2(c + Vector2(-5, -1.5), Vector2(10, 3)), Color(0.45, 1.0, 0.45))
		"buff":
			n.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, 3), c + Vector2(5, 3), c + Vector2(0, -5)]), Color(0.75, 1.0, 0.35))
		"debuff":
			n.draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -3), c + Vector2(5, -3), c + Vector2(0, 5)]), Color(1.0, 0.35, 0.55))
		"invuln":
			n.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 0), c + Vector2(0, 6), c + Vector2(-5, 0)]), Color(1.0, 0.85, 0.25))
		"shield":
			n.draw_circle(c, 4.5, Color(0.75, 0.88, 1.0, 0.6))
			n.draw_arc(c, 4.5, 0, TAU, 12, Color(0.95, 0.97, 1.0), 1.5)
