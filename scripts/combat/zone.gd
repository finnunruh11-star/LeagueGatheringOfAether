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


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if trap:
		return
	var p := CPUParticles2D.new()
	p.amount = clampi(int(radius / 7.0), 6, 36)
	p.lifetime = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.9
	p.direction = Vector2.UP
	p.spread = 15.0
	p.gravity = Vector2(0, -40)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.0
	p.color = color.lightened(0.3)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	p.material = Vfx.add_material()
	add_child(p)


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
	var a := 0.6 if trap and stealth else 1.0
	if tex != null:
		var s := radius * 2.0 / maxf(tex.get_width(), tex.get_height())
		var size := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1, 1, 1, a))
		return
	if trap:
		var armed := life >= arm_time
		var pulse := 0.5 + 0.5 * sin(life * 5.0)
		draw_circle(Vector2.ZERO, radius, Color(color, 0.1 * a))
		draw_circle(Vector2.ZERO, radius * 0.42, Color(color.darkened(0.3), 0.9 * a))
		for i in 10:
			var ang := i * TAU / 10.0
			var tip := Vector2.from_angle(ang) * radius * (0.82 if i % 2 == 0 else 0.6)
			draw_line(Vector2.from_angle(ang) * radius * 0.35, tip, Color(color.lightened(0.2), a), 3.0)
		draw_circle(Vector2.ZERO, radius * 0.18, Color(1, 0.3, 0.2, (0.5 + 0.5 * pulse) * a) if armed else Color(0.6, 0.6, 0.6, a))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(color, (0.6 if armed else 0.25) * a), 2.0, true)
		return
	var pulse := 0.5 + 0.5 * sin(life * 4.0)
	var fade := clampf(1.0 - life / maxf(duration, 0.01), 0.0, 1.0)
	var appear := clampf(life * 6.0, 0.0, 1.0)
	var r := radius * (0.6 + 0.4 * appear)
	draw_texture_rect(Vfx.glow(), Rect2(-r, -r, r * 2.0, r * 2.0), false, Color(color, 0.32 + 0.1 * pulse))
	draw_circle(Vector2.ZERO, r, Color(color, 0.1))
	var segs := 20
	for i in segs:
		var a0 := i * TAU / segs + life * 0.6
		draw_arc(Vector2.ZERO, r, a0, a0 + TAU / segs * 0.6, 4, Color(color.lightened(0.25), 0.9), 3.0, true)
	draw_arc(Vector2.ZERO, r * (0.5 + 0.12 * pulse), 0, TAU, 48, Color(color.lightened(0.2), 0.3), 2.0, true)
	draw_arc(Vector2.ZERO, r + 6.0, -PI / 2, -PI / 2 + TAU * fade, 48, Color(color, 0.5), 3.0, true)
