class_name Projectile
extends Node2D
## Basic-attack bolts (homing) and ability projectiles (straight, homing or boomerang).

var world: World
var net_id := 0
var puppet := false
var team := 0
var radius := 8.0
var color := Color.WHITE
var tex: Texture2D = null
var dir := Vector2.RIGHT

var mode := "attack"
var source = null
var target = null
var damage := 0.0
var speed := 1000.0
var effect := {}
var ctx := {}
var max_dist := 800.0
var traveled := 0.0
var hit_ids := {}
var pierce := 0
var returning := false
var affects := "enemies"
var hits_structures := false
var through_walls := false
var last_hit = null
var done := false

var net_from := Vector2.ZERO
var net_to := Vector2.ZERO
var net_t := 1.0


func setup(d: Dictionary) -> void:
	global_position = d.pos
	dir = d.get("dir", Vector2.RIGHT)
	radius = float(d.get("radius", 8.0))
	color = d.get("color", Color.WHITE)
	var spr := str(d.get("sprite", ""))
	if spr != "":
		tex = Content.char_texture(str(d.get("char", "")), spr)
	net_from = global_position
	net_to = global_position
	rotation = dir.angle()


func init_attack(src, tgt, dmg: float, spd: float) -> void:
	mode = "attack"
	source = src
	team = src.team
	target = tgt
	damage = dmg
	speed = spd


func init_ability(e: Dictionary, c: Dictionary, d: Vector2, homing_target) -> void:
	mode = "ability"
	effect = e
	ctx = c
	dir = d
	team = int(c.get("team", 0))
	speed = maxf(Effects.num(e.get("speed"), c, 900.0), 10.0)
	max_dist = Effects.num(e.get("range"), c, float(c.get("range", 800.0)))
	var p = e.get("pierce", false)
	if p is bool:
		pierce = -1 if p else 0
	elif p is float or p is int:
		pierce = int(p)
	affects = str(e.get("affects", "enemies"))
	hits_structures = bool(e.get("hits_structures", false))
	through_walls = bool(e.get("through_walls", false))
	target = homing_target


func _physics_process(delta: float) -> void:
	if puppet or world == null or world.ended or done:
		return
	if mode == "attack":
		_attack_step(delta)
		return
	if target != null:
		if not is_instance_valid(target) or target.dead:
			_finish()
			return
		var to: Vector2 = target.global_position - global_position
		if to.length() <= speed * delta + target.radius:
			global_position = target.global_position
			_hit(target)
			_finish()
			return
		dir = to.normalized()
		global_position += dir * speed * delta
		rotation = dir.angle()
		return
	if returning:
		var c = ctx.get("caster")
		if not is_instance_valid(c) or c.dead:
			_finish()
			return
		var back: Vector2 = c.global_position - global_position
		if back.length() <= speed * delta + c.radius:
			_finish()
			return
		dir = back.normalized()
	var step := dir * speed * delta
	global_position += step
	traveled += step.length()
	rotation = dir.angle()
	if not through_walls and world.map.is_wall(global_position):
		_finish()
		return
	for u in world.query(global_position, radius, team, affects, hits_structures):
		if u == ctx.get("caster") or hit_ids.has(u.net_id):
			continue
		hit_ids[u.net_id] = true
		_hit(u)
		if done:
			return
		if pierce == 0:
			_finish()
			return
		if pierce > 0:
			pierce -= 1
	if not returning and traveled >= max_dist:
		if bool(effect.get("returns", false)):
			returning = true
			hit_ids.clear()
		else:
			_finish()


func _attack_step(delta: float) -> void:
	if not is_instance_valid(target) or target.dead:
		world.despawn(self)
		return
	var to: Vector2 = target.global_position - global_position
	var step := speed * delta
	if to.length() <= step + target.radius * 0.5:
		if is_instance_valid(source):
			source.land_attack(target, damage)
		else:
			target.take_damage(damage, null, "physical")
		world.despawn(self)
		return
	dir = to.normalized()
	global_position += dir * step
	rotation = dir.angle()


func _hit(u) -> void:
	last_hit = u
	Effects.run(effect.get("on_hit"), Effects.sub(ctx, {"target": u, "pos": global_position, "origin": global_position - dir * 40.0}))


func _finish() -> void:
	if done:
		return
	done = true
	if effect.has("on_end"):
		var t = last_hit if is_instance_valid(last_hit) else null
		Effects.run(effect.on_end, Effects.sub(ctx, {"target": t, "pos": global_position, "origin": global_position}))
	world.despawn(self)


func net_state() -> PackedFloat32Array:
	return PackedFloat32Array([global_position.x, global_position.y, rotation])


func apply_net_state(s: PackedFloat32Array) -> void:
	net_from = global_position
	net_to = Vector2(s[0], s[1])
	net_t = 0.0
	rotation = s[2]


func _process(delta: float) -> void:
	if puppet:
		net_t = minf(net_t + delta / World.SNAP_DT, 1.0)
		global_position = net_from.lerp(net_to, net_t)


func _draw() -> void:
	if tex != null:
		var s := radius * 2.6 / maxf(tex.get_width(), tex.get_height())
		var size := Vector2(tex.get_width(), tex.get_height()) * s
		draw_texture_rect(tex, Rect2(-size * 0.5, size), false)
		return
	draw_line(Vector2(-radius * 3.0, 0), Vector2.ZERO, Color(color, 0.35), radius * 1.3)
	draw_circle(Vector2.ZERO, radius, color)
	draw_circle(Vector2.ZERO, radius * 0.5, color.lightened(0.6))
