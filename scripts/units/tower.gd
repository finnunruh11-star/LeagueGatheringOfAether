class_name Tower
extends Unit
## Defensive tower or Nexus. Towers shoot minions first, champions last
## (unless a champion attacks an allied champion nearby). Destroy the enemy Nexus to win.

const TURRET_ART := preload("res://assets/structures/turret.svg")
const NEXUS_ART := preload("res://assets/structures/nexus.svg")
const CRYSTAL_ART := preload("res://assets/structures/crystal.svg")
const TURRET_ART_SIZE := Vector2(120, 140)
const NEXUS_ART_SIZE := Vector2(208, 146)
const NEXUS_CORE_Y := -77.0

var is_nexus := false
var is_inhibitor := false
var is_nexus_turret := false
var lane := 0
var order := 0
var think_t := 0.0
var ramp := 0
var last_target_id := 0
var target_id := 0
var glow: Sprite2D


func setup(d: Dictionary) -> void:
	kind = "tower"
	is_structure = true
	team = int(d.team)
	is_nexus = str(d.get("kind", "tower")) == "nexus"
	is_inhibitor = d.get("kind") == "inhibitor"
	is_nexus_turret = d.get("kind") == "nexus_turret"
	lane = int(d.get("lane", 0))
	order = int(d.get("order", 0))
	base_stats.hp_regen = 0.0
	base_stats.move_speed = 0.0
	base_stats.vision = 1095.0
	if is_nexus:
		base_stats.max_hp = 5500.0
		base_stats.hp_regen = 20.0
		base_stats.armor = 20.0
		base_stats.magic_resist = 0.0
		base_stats.attack_damage = 0.0
		base_radius = 62.0
		display_name = "Nexus"
	elif is_inhibitor:
		base_stats.max_hp = 4000.0
		base_stats.hp_regen = 15.0
		base_stats.armor = 20.0
		base_stats.magic_resist = 0.0
		base_stats.attack_damage = 0.0
		base_radius = 38.0
		gold_value = 50.0
		display_name = "Inhibitor"
	else:
		base_stats.max_hp = 2700.0 if is_nexus_turret else (5000.0 if order == 0 else (3600.0 if order == 1 else 3300.0))
		base_stats.armor = 40.0 if order == 0 and not is_nexus_turret else 55.0
		base_stats.magic_resist = base_stats.armor
		base_stats.attack_damage = 182.0 if order == 0 and not is_nexus_turret else 195.0
		base_stats.attack_speed = 0.833
		base_stats.attack_range = 750.0
		base_radius = 38.0
		display_name = "Nexus Turret" if is_nexus_turret else "Turret"
	var stat_key := "nexus_stats" if is_nexus else ("inhibitor_stats" if is_inhibitor else "tower_stats")
	var ov = world.map.data.get(stat_key, {})
	if ov is Dictionary:
		for k in ov:
			base_stats[k] = float(ov[k])
	color = Game.TEAM_COLORS[team]
	attack_def = {"ranged": true, "speed": 1300.0, "color": color.lightened(0.5), "size": 10.0, "sprite": "", "char": "", "on_hit": []}
	global_position = d.pos


func is_protected() -> bool:
	return world != null and world.is_protected(self)


func muzzle() -> Vector2:
	return global_position + Vector2(0, -radius * 1.75)


func _think(delta: float) -> void:
	if is_nexus or is_inhibitor:
		attack_target = null
		return
	if attack_target != null and (not valid_target(attack_target) or global_position.distance_to(attack_target.global_position) > attack_reach(attack_target)):
		attack_target = null
	think_t -= delta
	if attack_target == null and think_t <= 0.0:
		think_t = 0.2
		attack_target = _pick()
	target_id = attack_target.net_id if attack_target != null else 0
	if attack_target == null:
		last_target_id = 0
		ramp = 0


func _pick() -> Unit:
	var best: Unit = null
	var best_score := INF
	for u in world.units:
		if u.team == team or u.team > 1 or u.dead or u.is_structure or u.is_ward or not u.targetable() or not u.visible_to(team):
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
	if not is_nexus and not is_inhibitor and not dead and valid_target(attacker) and global_position.distance_to(attacker.global_position) <= attack_reach(attacker):
		attack_target = attacker


func attack_damage_against(t) -> float:
	ramp = ramp + 1 if t.net_id == last_target_id else 0
	last_target_id = t.net_id
	if t is Minion:
		var fraction: float = {"melee": 0.45, "ranged": 0.70, "siege": 0.14, "super": 0.07}[t.minion_type]
		return t.stats.max_hp * fraction * (1.0 + t.stats.armor / 100.0)
	if not t.is_champion:
		return maxf(stats.attack_damage, t.stats.max_hp * 0.45)
	return stats.attack_damage * (1.0 + 0.3 * mini(ramp, 5))


func net_state() -> PackedFloat32Array:
	var s := super.net_state()
	s.append(target_id)
	return s


func apply_net_state(s: PackedFloat32Array) -> void:
	var was_dead := dead
	super.apply_net_state(s)
	if dead != was_dead:
		collision_layer = 0 if dead else 1
	target_id = int(s[NET_BASE])


func _on_death() -> void:
	if is_inhibitor:
		world.schedule(300.0, _restore_inhibitor)


func _restore_inhibitor() -> void:
	dead = false
	flags = 0
	anim = ANIM_IDLE
	hp = stats.max_hp
	collision_layer = 1
	world.fx("announce", {"text": "%s Inhibitor respawned!" % Game.TEAM_NAMES[team], "color": team_color()})


func bar_width() -> float:
	return 156.0 if is_nexus else (90.0 if is_inhibitor else 106.0)


func bar_height() -> float:
	return 9.0


func bar_top() -> float:
	if is_inhibitor:
		return -radius * 2.35 - 10.0
	return -(142.0 if is_nexus else 114.0) * _art_scale() - 10.0


func _art_scale() -> float:
	return radius / (62.0 if is_nexus else 38.0)


func _ready() -> void:
	super._ready()
	if not is_inhibitor:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	glow = Sprite2D.new()
	glow.texture = Vfx.glow()
	glow.material = Vfx.add_material()
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.position = Vector2(0, NEXUS_CORE_Y * _art_scale()) if is_nexus else Vector2(0, -radius * 1.75)
	add_child(glow)


func _process(delta: float) -> void:
	super._process(delta)
	glow.visible = not dead
	var pulse := 0.5 + 0.5 * sin(life * (2.0 if is_nexus else 3.0))
	glow.modulate = Color(team_color().lightened(0.2), 0.45 + 0.25 * pulse)
	glow.scale = Vector2.ONE * radius * (3.2 if is_nexus else 1.9) / 64.0 * (0.9 + 0.15 * pulse)
	if is_nexus:
		glow.position.y = _nexus_core().y


func _draw_body() -> void:
	var tc := team_color()
	var r := radius
	if dead:
		for st in [[Vector2(-0.4, 0.2), 0.45], [Vector2(0.35, 0.3), 0.4], [Vector2(0, -0.1), 0.5], [Vector2(0.5, -0.25), 0.3]]:
			draw_circle(st[0] * r, st[1] * r, Color(0.32, 0.32, 0.35))
			draw_circle(st[0] * r + Vector2(-2, -3), st[1] * r * 0.6, Color(0.42, 0.42, 0.45))
		return
	var c := tc.lerp(Color.WHITE, 0.55) if flash > 0.0 else tc
	var stone := Color(0.42, 0.42, 0.47) if flash <= 0.0 else Color(0.8, 0.8, 0.85)
	if is_nexus:
		_draw_nexus_art(c)
	elif is_inhibitor:
		draw_circle(Vector2(0, r * 0.15), r * 1.05, stone.darkened(0.35))
		draw_circle(Vector2.ZERO, r * 0.95, stone)
		draw_arc(Vector2.ZERO, r * 0.78, life * 0.6, life * 0.6 + TAU, 48, Color(c, 0.7), 3.0, true)
		for i in 6:
			var a := i * TAU / 6.0 + life * 0.6
			draw_circle(Vector2.from_angle(a) * r * 0.78, 4.0, c.lightened(0.4))
		var h := r * (1.25 + 0.06 * sin(life * 2.0))
		var crystal := PackedVector2Array([Vector2(0, -h), Vector2(r * 0.42, -r * 0.2), Vector2(0, r * 0.35), Vector2(-r * 0.42, -r * 0.2)])
		draw_colored_polygon(crystal, c.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -h), Vector2(r * 0.42, -r * 0.2), Vector2(0, -r * 0.05)]), c.lightened(0.35))
	else:
		_draw_turret_art(c)


func _draw_turret_art(c: Color) -> void:
	var s := _art_scale()
	var core := Vector2(0, -radius * 1.75)
	var stone_tint := Color(1.15, 1.15, 1.15) if flash > 0.0 else Color.WHITE
	draw_texture_rect(TURRET_ART, Rect2(core - Vector2(60, 47) * s, TURRET_ART_SIZE * s), false, stone_tint)
	var energy := c.lightened(0.35 if target_id != 0 else 0.18)
	draw_arc(core, 11.5 * s, 0.0, TAU, 32, Color(energy, 0.8), 1.6 * s, true)
	_draw_crystal(core, Vector2(16, 22) * s, energy)
	_draw_crystal(core + Vector2(0, 32) * s, Vector2(12, 21) * s, c)


func _nexus_core() -> Vector2:
	return Vector2(0, NEXUS_CORE_Y + sin(life * 1.9) * 5.0) * _art_scale()


func _draw_nexus_art(c: Color) -> void:
	var s := _art_scale()
	var core := _nexus_core()
	var stone_tint := Color(1.15, 1.15, 1.15) if flash > 0.0 else Color.WHITE
	draw_texture_rect(NEXUS_ART, Rect2(Vector2(-104, -101) * s, NEXUS_ART_SIZE * s), false, stone_tint)
	var orbit := core + Vector2(0, 14) * s
	_draw_nexus_orbit(orbit, c, false)
	_draw_crystal(core, Vector2(73, 110) * s, c.lightened(0.28))
	_draw_nexus_orbit(orbit, c, true)
	_draw_crystal(Vector2(0, 15) * s, Vector2(15, 20) * s, c.lightened(0.35))
	for side in [-1.0, 1.0]:
		_draw_crystal(Vector2(82 * side, -57) * s, Vector2(12, 16) * s, c)


func _draw_crystal(center: Vector2, dimensions: Vector2, tint: Color) -> void:
	draw_texture_rect(CRYSTAL_ART, Rect2(center - dimensions * 0.5, dimensions), false, tint)


func _draw_nexus_orbit(center: Vector2, c: Color, front: bool) -> void:
	var radii := Vector2(58, 18) * _art_scale()
	var start := 0.0 if front else PI
	var color := Color(c.lightened(0.5), 0.75 if front else 0.42)
	var points := PackedVector2Array()
	for i in 25:
		points.append(center + Vector2.from_angle(start + PI * i / 24.0) * radii)
	draw_polyline(points, color, 2.0 * _art_scale(), true)
	for i in 3:
		var offset := Vector2.from_angle(fposmod(life * 0.9 + TAU * i / 3.0, TAU)) * radii
		if (offset.y >= 0.0) == front:
			_draw_crystal(center + offset, Vector2(11, 15) * _art_scale(), c.lightened(0.5))


## Range warning and targeting line (not affected by hit squash).
func _draw_extra() -> void:
	var lc = world.local_champion if world != null else null
	if dead or is_nexus or is_inhibitor or lc == null or lc.dead or team == lc.team:
		return
	var reach := attack_reach(lc)
	var d := global_position.distance_to(lc.global_position)
	if d > reach + 350.0:
		return
	var hot: bool = target_id != 0 and target_id == lc.net_id
	var pulse := 0.5 + 0.5 * sin(life * 12.0)
	var col := Color(1, 0.22, 0.18, 0.55 + 0.4 * pulse) if hot else Color(team_color(), 0.18 + 0.4 * clampf(1.0 - (d - reach) / 350.0, 0.0, 1.0))
	draw_arc(Vector2.ZERO, reach, 0, TAU, 96, col, 4.0 if hot else 2.0, true)
	if hot:
		var from := Vector2(0, -radius * 1.75)
		var to: Vector2 = lc.global_position - global_position
		draw_line(from, to, Color(1, 0.2, 0.15, 0.35 + 0.35 * pulse), 6.0)
		draw_line(from, to, Color(1, 0.75, 0.7, 0.8), 2.0)
