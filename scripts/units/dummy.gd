class_name Dummy
extends Unit
## Immortal training dummy. Enemy to everyone; shows recent damage per second.

var home := Vector2.ZERO
var since_hit := 99.0
var hits: Array = []
var dps := 0.0
var total_taken := 0.0


func setup(d: Dictionary) -> void:
	kind = "dummy"
	team = 2
	display_name = "Training Dummy"
	base_stats.max_hp = float(d.get("hp", 4000.0))
	base_stats.hp_regen = 0.0
	base_stats.armor = float(d.get("armor", 0.0))
	base_stats.magic_resist = float(d.get("mr", 0.0))
	base_stats.move_speed = 220.0
	base_stats.attack_damage = 0.0
	base_radius = 26.0
	color = Color(0.78, 0.62, 0.42)
	global_position = d.pos
	home = d.pos


func _think(delta: float) -> void:
	since_hit += delta
	if since_hit > 4.0 and hp < stats.max_hp:
		hp = stats.max_hp
	move_goal = home if since_hit > 1.5 and global_position.distance_to(home) > 12.0 else null
	while not hits.is_empty() and hits[0].x < world.time - 5.0:
		hits.pop_front()
	var total := 0.0
	for h in hits:
		total += h.y
	dps = total / clampf(world.time - (hits[0].x if not hits.is_empty() else world.time), 1.0, 5.0)


func on_damaged(amount: float, _src) -> void:
	since_hit = 0.0
	total_taken += amount
	hits.append(Vector2(world.time, amount))


func die(_killer = null) -> void:
	hp = stats.max_hp
	world.fx("text", {"pos": global_position + Vector2(0, -70), "text": "Reset!", "color": Color(1, 1, 0.5), "size": 20})


func net_state() -> PackedFloat32Array:
	var s := super.net_state()
	s.append(dps)
	return s


func apply_net_state(s: PackedFloat32Array) -> void:
	super.apply_net_state(s)
	dps = s[NET_BASE]


func _draw_body() -> void:
	var c := color.lerp(Color.WHITE, 0.6) if flash > 0.0 else color
	draw_rect(Rect2(-5, -radius * 0.2, 10, radius * 1.4), Color(0.45, 0.32, 0.2))
	draw_circle(Vector2(0, -radius * 0.3), radius, c)
	draw_circle(Vector2(0, -radius * 0.3), radius * 0.65, Color(0.9, 0.25, 0.2))
	draw_circle(Vector2(0, -radius * 0.3), radius * 0.35, Color(0.95, 0.95, 0.9))
	draw_circle(Vector2(0, -radius * 0.3), radius * 0.12, Color(0.9, 0.25, 0.2))


func bar_width() -> float:
	return 70.0


func _draw_overlay(n: Node2D) -> void:
	super._draw_overlay(n)
	var top := bar_top()
	n.draw_string_outline(ThemeDB.fallback_font, Vector2(-60, top - 6), "DPS %d" % int(dps), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, 3, Color(0, 0, 0, 0.8))
	n.draw_string(ThemeDB.fallback_font, Vector2(-60, top - 6), "DPS %d" % int(dps), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 0.9, 0.6))
