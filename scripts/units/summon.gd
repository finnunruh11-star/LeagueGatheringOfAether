class_name Summon
extends Unit
## A creature/turret created by the "summon" effect. Fights near its owner.

var owner_unit = null
var lifetime := 10.0
var max_life := 10.0
var stationary := false
var think_t := 0.0
var effect := {}
var sctx := {}
var tex: Texture2D = null


func setup(d: Dictionary) -> void:
	kind = "summon"
	team = int(d.team)
	display_name = str(d.get("name", "Summon"))
	color = d.get("color", Color.WHITE)
	stationary = bool(d.get("stationary", false))
	char_id = str(d.get("char", ""))
	var ranged := bool(d.get("ranged", false))
	base_stats.max_hp = 250.0
	base_stats.attack_damage = 20.0
	base_stats.attack_speed = 1.0
	base_stats.attack_range = 400.0 if ranged else 70.0
	base_stats.move_speed = 0.0 if stationary else 340.0
	base_stats.armor = 10.0
	base_stats.magic_resist = 10.0
	base_stats.hp_regen = 0.0
	var st = d.get("stats", {})
	if st is Dictionary:
		for k in st:
			base_stats[k] = float(st[k])
	base_radius = Content.BASE_RADIUS * float(d.get("size", 0.7))
	attack_def = {"ranged": ranged, "speed": 1000.0, "color": color.lightened(0.3), "size": 6.0, "sprite": "", "char": char_id, "on_hit": []}
	var spr := str(d.get("sprite", ""))
	if spr != "":
		tex = Content.char_texture(char_id, spr)
	is_ward = bool(d.get("ward", false))
	reveal = bool(d.get("reveal", false))
	if is_ward:
		stationary = true
		base_stats.attack_damage = 0.0
		base_stats.max_hp = float(st.get("max_hp", 4.0)) if st is Dictionary else 4.0
		base_stats.hp_regen = 0.0
		gold_value = 25.0
	separate = not stationary
	xp_value = 0.0 if is_ward else 15.0
	global_position = d.pos


func init_server(owner, duration: float, e: Dictionary, ctx: Dictionary) -> void:
	owner_unit = owner
	lifetime = duration
	max_life = duration
	effect = e
	sctx = ctx
	var oh = e.get("on_hit", [])
	attack_def.on_hit = oh if oh is Array else [oh]


func get_level() -> int:
	return owner_unit.get_level() if is_instance_valid(owner_unit) else 1


func can_move() -> bool:
	return not stationary and super.can_move()


func _think(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		die(null)
		return
	think_t -= delta
	if think_t > 0.0:
		return
	think_t = 0.2
	var o = owner_unit if is_instance_valid(owner_unit) and not owner_unit.dead else null
	var limit: float = (stats.attack_range + radius + 40.0) if stationary else 650.0
	if o != null and is_instance_valid(o.attack_target) and valid_target(o.attack_target) \
			and global_position.distance_to(o.attack_target.global_position) < limit + 150.0:
		attack_target = o.attack_target
	if attack_target != null and (not valid_target(attack_target) or global_position.distance_to(attack_target.global_position) > limit + 120.0):
		attack_target = null
	if attack_target == null:
		attack_target = world.nearest_enemy(global_position, team, limit, false, false)
	move_goal = null
	if attack_target == null and o != null and not stationary and global_position.distance_to(o.global_position) > 220.0:
		move_goal = o.global_position + Vector2(randf_range(-90, 90), randf_range(-90, 90))


func _on_death() -> void:
	if effect.has("on_death"):
		Effects.run(effect.on_death, Effects.sub(sctx, {"pos": global_position, "origin": global_position, "target": null}))
	world.despawn_later(self, 0.2)


func _draw_body() -> void:
	var c := color.lerp(Color.WHITE, 0.6) if flash > 0.0 else color
	if is_ward:
		var r := radius
		draw_line(Vector2(0, r * 0.2), Vector2(0, r * 1.1), Color(0.35, 0.3, 0.25), 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 1.2), Vector2(r * 0.75, -r * 0.2), Vector2(0, r * 0.5), Vector2(-r * 0.75, -r * 0.2)]), c.darkened(0.3))
		draw_circle(Vector2(0, -r * 0.3), r * 0.42, Color(0.95, 0.95, 0.9))
		draw_circle(Vector2(0, -r * 0.3), r * 0.22, c.lightened(0.2) if not reveal else Color(1, 0.3, 0.4))
		draw_circle(Vector2(0, -r * 0.3), r * 0.1, Color(0.05, 0.05, 0.08))
		draw_arc(Vector2.ZERO, r * 1.3, 0, TAU, 24, Color(team_color(), 0.5), 1.5, true)
		return
	if tex != null:
		var s := radius * 2.6 / maxf(tex.get_width(), tex.get_height())
		var size := Vector2(tex.get_width(), tex.get_height()) * s
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0 if facing < 0 else 1.0, 1.0))
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1.6, 1.6, 1.6) if flash > 0.0 else Color.WHITE)
		draw_set_transform(Vector2.ZERO)
		return
	if stationary:
		draw_rect(Rect2(-radius, -radius, radius * 2, radius * 2), c)
	else:
		draw_circle(Vector2.ZERO, radius, c)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 24, team_color(), 2.0, true)


func bar_width() -> float:
	return 36.0
