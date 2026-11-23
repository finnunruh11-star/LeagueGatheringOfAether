class_name Tower
extends Unit
## Defensive tower or Nexus. Towers shoot minions first, champions last
## (unless a champion attacks an allied champion nearby). Destroy the enemy Nexus to win.

var is_nexus := false
var lane := 0
var order := 0
var think_t := 0.0
var ramp := 0
var last_target_id := 0
var target_id := 0


func setup(d: Dictionary) -> void:
	kind = "tower"
	is_structure = true
	team = int(d.team)
	is_nexus = str(d.get("kind", "tower")) == "nexus"
	lane = int(d.get("lane", 0))
	order = int(d.get("order", 0))
	base_stats.hp_regen = 0.0
	base_stats.move_speed = 0.0
	if is_nexus:
		base_stats.max_hp = 4500.0
		base_stats.armor = 30.0
		base_stats.attack_damage = 0.0
		base_radius = 62.0
		display_name = "Nexus"
	else:
		base_stats.max_hp = 2600.0
		base_stats.armor = 45.0
		base_stats.attack_damage = 150.0
		base_stats.attack_speed = 0.83
		base_stats.attack_range = 480.0
		base_radius = 38.0
		xp_value = 120.0
		display_name = "Tower"
	color = Game.TEAM_COLORS[team]
	attack_def = {"ranged": true, "speed": 1300.0, "color": color.lightened(0.5), "size": 10.0, "sprite": "", "char": "", "on_hit": []}
	global_position = d.pos


func is_protected() -> bool:
	return world != null and world.is_protected(self)


func _think(delta: float) -> void:
	if is_nexus:
		attack_target = null
		return
	if attack_target != null and (not valid_target(attack_target) or global_position.distance_to(attack_target.global_position) > attack_reach(attack_target)):
		attack_target = null
	think_t -= delta
	if attack_target == null and think_t <= 0.0:
		think_t = 0.2
		attack_target = _pick()
	target_id = attack_target.net_id if attack_target != null else 0


func _pick() -> Unit:
	var best: Unit = null
	var best_score := INF
	for u in world.units:
		if u.team == team or u.dead or u.is_structure or not u.targetable():
			continue
		var d := global_position.distance_to(u.global_position)
		if d > attack_reach(u):
			continue
		var score := d + (2000.0 if u.is_champion else 0.0)
		if score < best_score:
			best_score = score
			best = u
	return best


func aggro(attacker: Unit) -> void:
	if not is_nexus and not dead and valid_target(attacker) and global_position.distance_to(attacker.global_position) <= attack_reach(attacker):
		attack_target = attacker


func attack_damage_against(t) -> float:
	if not t.is_champion:
		return maxf(stats.attack_damage, t.stats.max_hp * 0.45)
	ramp = ramp + 1 if t.net_id == last_target_id else 0
	last_target_id = t.net_id
	return stats.attack_damage * (1.0 + 0.3 * mini(ramp, 5))


func net_state() -> PackedFloat32Array:
	var s := super.net_state()
	s.append(target_id)
	return s


func apply_net_state(s: PackedFloat32Array) -> void:
	super.apply_net_state(s)
	target_id = int(s[NET_BASE])


func bar_width() -> float:
	return 130.0 if is_nexus else 90.0


func _draw_body() -> void:
	var tc := team_color()
	if dead:
		draw_circle(Vector2.ZERO, radius * 0.8, Color(0.3, 0.3, 0.32))
		draw_circle(Vector2(radius * 0.3, -radius * 0.2), radius * 0.35, Color(0.38, 0.38, 0.4))
		return
	var c := tc.lerp(Color.WHITE, 0.5) if flash > 0.0 else tc
	if is_nexus:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(Vector2.from_angle(i * TAU / 6.0) * radius)
		draw_colored_polygon(pts, c.darkened(0.3))
		draw_circle(Vector2.ZERO, radius * 0.55, c)
		draw_circle(Vector2.ZERO, radius * 0.3 + sin(life * 3.0) * 3.0, c.lightened(0.5))
	else:
		draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), Color(0.25, 0.27, 0.3))
		draw_rect(Rect2(-radius * 0.65, -radius * 1.4, radius * 1.3, radius * 1.6), c.darkened(0.2))
		draw_circle(Vector2(0, -radius * 1.2), radius * 0.4, c.lightened(0.3))
	# Range ring when the local champion is close.
	var lc = world.local_champion if world != null else null
	if not is_nexus and lc != null and not lc.dead and team != lc.team:
		var reach: float = stats.attack_range + radius
		if global_position.distance_to(lc.global_position) < reach + 350.0:
			var hot: bool = target_id != 0 and target_id == lc.net_id
			draw_arc(Vector2.ZERO, reach, 0, TAU, 96, Color(1, 0.25, 0.2, 0.75) if hot else Color(tc, 0.35), 3.0 if hot else 2.0, true)
			if hot:
				draw_line(Vector2(0, -radius * 1.2), lc.global_position - global_position, Color(1, 0.2, 0.2, 0.7), 3.0)
