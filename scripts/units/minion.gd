class_name Minion
extends Unit
## Lane minion: walks its lane and fights whatever enemy is closest.

const TYPES := {
	"melee": {"max_hp": 465.0, "attack_damage": 11.0, "attack_speed": 1.25, "attack_range": 110.0, "move_speed": 310.0,
		"armor": 0.0, "magic_resist": 0.0, "radius": 15.0, "xp": 62.0, "gold": 20.0, "ranged": false},
	"ranged": {"max_hp": 284.0, "attack_damage": 21.0, "attack_speed": 0.667, "attack_range": 500.0, "move_speed": 310.0,
		"armor": 0.0, "magic_resist": 0.0, "radius": 13.0, "xp": 31.0, "gold": 14.0, "ranged": true},
	"siege": {"max_hp": 835.0, "attack_damage": 37.5, "attack_speed": 1.0, "attack_range": 300.0, "move_speed": 310.0,
		"armor": 0.0, "magic_resist": 0.0, "radius": 22.0, "xp": 75.0, "gold": 50.0, "ranged": true},
	"super": {"max_hp": 1600.0, "attack_damage": 185.0, "attack_speed": 0.85, "attack_range": 170.0, "move_speed": 310.0,
		"armor": 100.0, "magic_resist": -30.0, "radius": 24.0, "xp": 75.0, "gold": 50.0, "ranged": false},
}

var lane := PackedVector2Array()
var wp := 1
var minion_type := "melee"
var think_t := 0.0


func setup(d: Dictionary) -> void:
	kind = "minion"
	team = int(d.team)
	minion_type = str(d.get("type", "melee"))
	var t: Dictionary = TYPES.get(minion_type, TYPES.melee)
	var upgrades := clampi(int(d.get("upgrades", 0)), 0, 25)
	for k in ["max_hp", "attack_damage", "attack_speed", "attack_range", "move_speed", "armor", "magic_resist"]:
		base_stats[k] = t[k]
	var ov = world.map.data.get("minion_stats", {})
	if ov is Dictionary and ov.get(minion_type) is Dictionary:
		for k in ov[minion_type]:
			base_stats[k] = float(ov[minion_type][k])
	base_stats.max_hp += upgrades * float({"melee": 21, "ranged": 14, "siege": 50, "super": 80}.get(minion_type, 0))
	base_stats.attack_damage += upgrades * (1.0 if minion_type == "melee" else 2.0)
	base_stats.hp_regen = 0.0
	base_radius = t.radius
	xp_value = t.xp
	gold_value = t.gold + (upgrades if minion_type in ["siege", "super"] else 0)
	base_stats.vision = 650.0
	color = Game.TEAM_COLORS[team].lerp(Color.WHITE, 0.15)
	attack_def = {"ranged": t.ranged, "speed": 900.0, "color": color.lightened(0.4), "size": 5.0, "sprite": "", "char": "", "on_hit": []}
	separate = true
	display_name = {"siege": "Cannon Minion", "super": "Super Minion"}.get(minion_type, "Minion")
	global_position = d.pos
	lane = world.map.lane(team, int(d.get("lane", 0)))


func _think(delta: float) -> void:
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.25 + randf() * 0.05
		if attack_target == null or not valid_target(attack_target) or attack_target.is_protected() or global_position.distance_to(attack_target.global_position) > 700.0:
			attack_target = _find_target()
	if attack_target != null or lane.size() < 2:
		move_goal = null
		return
	while wp < lane.size() - 1:
		var seg := lane[wp + 1] - lane[wp]
		if global_position.distance_to(lane[wp]) < 80.0 or (global_position - lane[wp]).dot(seg) > 0.0:
			wp += 1
		else:
			break
	move_goal = lane[wp]


func _find_target() -> Unit:
	var best: Unit = null
	var best_score := INF
	for u in world.units:
		if u.team == team or u.team > 1 or u.dead or not u.targetable() or u.is_ward or not u.visible_to(team):
			continue
		var d := global_position.distance_to(u.global_position)
		if d > maxf(480.0 + u.radius, attack_reach(u)):
			continue
		if u.is_structure and u.is_protected():
			continue
		var score := d
		if u.is_champion:
			score += 250.0
		elif u.is_structure:
			score += 500.0
		if score < best_score:
			best_score = score
			best = u
	return best


func _on_death() -> void:
	world.despawn_later(self, 0.4)


func attack_damage_against(t) -> float:
	return stats.attack_damage * (0.6 if t.is_structure or t.is_champion else 1.0)


func _draw_body() -> void:
	var c := body_color()
	var r := radius
	var f := facing
	if minion_type == "siege":
		draw_rect(Rect2(-r, -r * 0.55, r * 2.0, r * 1.1), c.darkened(0.35))
		draw_circle(Vector2(-r * 0.55, r * 0.45), r * 0.4, c)
		draw_circle(Vector2(r * 0.55, r * 0.45), r * 0.4, c)
		draw_line(Vector2(0, -r * 0.35), Vector2(f * r * 1.3, -r * 0.55), c.lightened(0.5), 7.0)
		return
	elif minion_type == "ranged":
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 1.3), Vector2(r * 0.95, r * 0.2), Vector2(0, r), Vector2(-r * 0.95, r * 0.2)]), c.darkened(0.4))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 1.12), Vector2(r * 0.7, r * 0.1), Vector2(0, r * 0.72), Vector2(-r * 0.7, r * 0.1)]), c)
		var orb := Vector2(f * r * 1.15, -r * 0.35)
		draw_line(Vector2(f * r * 0.55, r * 0.7), orb, Color(0.45, 0.32, 0.2), 2.0)
		draw_circle(orb, 4.5, Color(c.lightened(0.5), 0.35))
		draw_circle(orb, 2.8, c.lightened(0.75))
	else:
		draw_circle(Vector2.ZERO, r, c.darkened(0.4))
		draw_circle(Vector2(0, -r * 0.1), r * 0.85, c)
		if minion_type == "super":
			draw_arc(Vector2.ZERO, r * 0.68, 0.0, TAU, 24, c.lightened(0.7), 3.0, true)
		var swing := 0.0
		if windup_left > 0.0:
			swing = -0.75 * (1.0 - windup_left / windup_duration)
		elif anim == ANIM_ATTACK:
			swing = 1.0
		var hand := Vector2(f * r * 0.75, r * 0.1)
		var tip := hand + Vector2(f * cos(-1.1 + swing * 1.6), sin(-1.1 + swing * 1.6)) * r * 1.25
		draw_line(hand, tip, Color(0.88, 0.9, 0.95), 2.5)
		draw_line(hand + Vector2(0, -3), hand + Vector2(0, 3), Color(0.5, 0.4, 0.3), 2.0)
	draw_circle(Vector2(f * r * 0.32, -r * 0.3), 1.8, Color(0.05, 0.05, 0.08))
	draw_circle(Vector2(f * r * 0.02, -r * 0.3), 1.8, Color(0.05, 0.05, 0.08))


func bar_width() -> float:
	return 34.0


func bar_height() -> float:
	return 4.0
