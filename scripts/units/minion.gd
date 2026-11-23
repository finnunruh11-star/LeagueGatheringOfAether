class_name Minion
extends Unit
## Lane minion: walks its lane and fights whatever enemy is closest.

const TYPES := {
	"melee": {"max_hp": 430.0, "attack_damage": 14.0, "attack_speed": 1.0, "attack_range": 50.0, "move_speed": 270.0,
		"armor": 10.0, "radius": 15.0, "xp": 32.0, "ranged": false},
	"ranged": {"max_hp": 280.0, "attack_damage": 24.0, "attack_speed": 0.75, "attack_range": 360.0, "move_speed": 270.0,
		"armor": 0.0, "radius": 13.0, "xp": 26.0, "ranged": true},
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
	var sc := float(d.get("scale", 1.0))
	for k in ["max_hp", "attack_damage", "attack_speed", "attack_range", "move_speed", "armor"]:
		base_stats[k] = t[k]
	var ov = world.map.data.get("minion_stats", {})
	if ov is Dictionary and ov.get(minion_type) is Dictionary:
		for k in ov[minion_type]:
			base_stats[k] = float(ov[minion_type][k])
	base_stats.max_hp *= sc
	base_stats.attack_damage *= sc
	base_stats.hp_regen = 0.0
	base_radius = t.radius
	xp_value = t.xp
	color = Game.TEAM_COLORS[team].lerp(Color.WHITE, 0.15)
	attack_def = {"ranged": t.ranged, "speed": 900.0, "color": color.lightened(0.4), "size": 5.0, "sprite": "", "char": "", "on_hit": []}
	separate = true
	display_name = "Minion"
	global_position = d.pos
	lane = world.map.lane(team, int(d.get("lane", 0)))


func _think(delta: float) -> void:
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.25 + randf() * 0.05
		if attack_target == null or not valid_target(attack_target) or global_position.distance_to(attack_target.global_position) > 700.0:
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
		if u.team == team or u.dead or not u.targetable():
			continue
		var d := global_position.distance_to(u.global_position)
		if d > 480.0 + u.radius:
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


func _draw_body() -> void:
	var c := color.lerp(Color.WHITE, 0.6) if flash > 0.0 else color
	if minion_type == "ranged":
		var r := radius * 1.15
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)]), c)
	else:
		draw_circle(Vector2.ZERO, radius, c)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 20, c.darkened(0.45), 2.0)


func bar_width() -> float:
	return 34.0
