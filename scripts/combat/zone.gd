class_name Zone
extends Node2D
## Lingering area ("zone": ticks effects on units inside) or "trap" (fires once
## when an enemy steps on it). Zones can follow the caster to act as auras.

var world: World
var net_id := 0
var puppet := false
var team := 0
var radius := 150.0
var color := Color(1, 0.5, 0.2)
var trap := false
var stealth := false
var duration := 4.0
var tex: Texture2D = null
var life := 0.0

var effect := {}
var ctx := {}
var follow = null
var interval := 0.5
var tick := 0.0
var arm_time := 0.6
var affects := "enemies"
var hits_structures := false

var net_from := Vector2.ZERO
var net_to := Vector2.ZERO
var net_t := 1.0


func setup(d: Dictionary) -> void:
	global_position = d.pos
	team = int(d.team)
	radius = float(d.get("radius", 150.0))
	color = d.get("color", color)
	trap = bool(d.get("trap", false))
	stealth = bool(d.get("hidden", false))
	duration = float(d.get("duration", 4.0))
	var spr := str(d.get("sprite", ""))
	if spr != "":
		tex = Content.char_texture(str(d.get("char", "")), spr)
	net_from = global_position
	net_to = global_position


func init_server(e: Dictionary, c: Dictionary) -> void:
	effect = e
	ctx = c
	interval = maxf(Effects.num(e.get("interval"), c, 0.5), 0.05)
	arm_time = Effects.num(e.get("arm_time"), c, 0.6)
	affects = str(e.get("affects", "enemies"))
	hits_structures = bool(e.get("hits_structures", false))
	if bool(e.get("follow", false)):
		follow = c.get("caster")


func _physics_process(delta: float) -> void:
	if puppet or world == null or world.ended:
		return
	life += delta
	if follow != null:
		if is_instance_valid(follow) and not follow.dead:
			global_position = follow.global_position
		else:
			world.despawn(self)
			return
	if trap:
		if life >= arm_time:
			for u in world.query(global_position, radius, team, affects, false):
				Effects.run(effect.get("effects"), Effects.sub(ctx, {"target": u, "pos": global_position, "origin": global_position}))
				world.fx("blast", {"pos": global_position, "radius": radius * 1.5, "color": color})
				world.despawn(self)
				return
	else:
		tick -= delta
		if tick <= 0.0:
			tick += interval
			for u in world.query(global_position, radius, team, affects, hits_structures):
				Effects.run(effect.get("effects"), Effects.sub(ctx, {"target": u, "pos": global_position, "origin": global_position}))
	if life >= duration:
		if effect.has("on_expire"):
			Effects.run(effect.on_expire, Effects.sub(ctx, {"pos": global_position, "origin": global_position, "target": null}))
		world.despawn(self)


func net_state() -> PackedFloat32Array:
	return PackedFloat32Array([global_position.x, global_position.y])


func apply_net_state(s: PackedFloat32Array) -> void:
	net_from = global_position
	net_to = Vector2(s[0], s[1])
	net_t = 0.0


func _process(delta: float) -> void:
	if puppet:
		life += delta
		net_t = minf(net_t + delta / World.SNAP_DT, 1.0)
		global_position = net_from.lerp(net_to, net_t)
	queue_redraw()


func _draw() -> void:
	var enemy_view: bool = world != null and team != world.local_team
	if trap and stealth and enemy_view:
		return
	var a := 0.55 if trap and stealth else 1.0
	if tex != null:
		var s := radius * 2.0 / maxf(tex.get_width(), tex.get_height())
		var size := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1, 1, 1, a))
		return
	if trap:
		var armed := life >= arm_time
		draw_circle(Vector2.ZERO, radius * 0.45, Color(color, 0.8 * a))
		for i in 8:
			var ang := i * TAU / 8.0
			draw_line(Vector2.from_angle(ang) * radius * 0.35, Vector2.from_angle(ang) * radius * 0.75, Color(color.darkened(0.3), a), 3.0)
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(color, (0.5 if armed else 0.2) * a), 2.0)
	else:
		var pulse := 0.04 * sin(life * 6.0)
		draw_circle(Vector2.ZERO, radius, Color(color, 0.16 + pulse))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(color, 0.6), 3.0, true)
		var fade := clampf(1.0 - life / maxf(duration, 0.01), 0.0, 1.0)
		draw_arc(Vector2.ZERO, radius * 0.92, -PI / 2, -PI / 2 + TAU * fade, 48, Color(color, 0.35), 2.0)
