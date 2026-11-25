class_name SionKit
extends RefCounted

enum { ALIVE, RISING, ZOMBIE }
enum { IDLE, SMASH, CHARGE }

const FURNACE := "sion_furnace"
const SURGE := "sion_death_surge"
const SURGE_ABILITY := {"name": "Death Surge", "slot": "q", "targeting": "self",
	"range": 0.0, "cost": 0.0, "cost_type": "mana", "cooldown": 0.0, "cast_time": 0.0,
	"icon": null, "indicator": {}, "indicator_radius": 0.0, "auto_rank": false, "effects": [],
	"description": "Gain 50% movement speed, decaying over 2.5 seconds. Usable once per resurrection.",
	"short_description": "Gain a burst of movement speed. Usable once per resurrection."}
const Q_TIME := 2.0
const Q_MIN := 0.25
const R_TIME := 8.0
const DECAY_STEP := 0.264
const IMPACT_COLOR := Color("#eb7653")

var c: Champion
var form := ALIVE
var action := IDLE
var surge_used := false
var bonus_health := 0.0
var rise_left := 0.0
var decay_left := DECAY_STEP
var decay_ticks := 0
var elapsed := 0.0
var dir := Vector2.RIGHT
var steer := Vector2.RIGHT
var release_requested := false
var ctx := {}
var trampled := {}


func _init(champion: Champion) -> void:
	c = champion


func start_action(slot: String, cast_ctx: Dictionary) -> void:
	action = SMASH if slot == "q" else CHARGE
	ctx = cast_ctx
	elapsed = 0.0
	dir = ctx.dir
	steer = dir
	release_requested = false
	trampled.clear()
	c.move_goal = null
	c.attack_target = null
	c.amove = null
	c.path = PackedVector2Array()
	c.velocity = Vector2.ZERO
	c.face(c.global_position + dir * 100.0)
	if action == SMASH:
		c.cooldowns.q = 0.0
		c.begin_windup(Unit.ANIM_CAST, Q_TIME, dir)
		c.start_action(Unit.ANIM_CAST, 1, Q_TIME)
	else:
		c.cleanse(true)
		c.flags = c._compute_flags()


func interrupt_smash() -> void:
	if action != SMASH:
		return
	action = IDLE
	ctx = {}
	c.clear_windup()
	c.anim_lock = 0.0
	c.cooldowns.q = 2.0
	c.cd_total.q = 2.0


func release_smash() -> bool:
	if action != SMASH:
		return false
	release_requested = true
	if elapsed >= Q_MIN:
		_smash()
	return true


func tick_action(delta: float) -> void:
	if action == SMASH:
		if c.has_status("silence"):
			interrupt_smash()
			return
		elapsed = minf(elapsed + delta, Q_TIME)
		c.windup_left = Q_TIME - elapsed
		if elapsed >= Q_TIME - 0.00001 or (release_requested and elapsed >= Q_MIN - 0.00001) or (c.is_bot and elapsed >= 1.25):
			_smash()


func _smash() -> void:
	action = IDLE
	var ab: Dictionary = c.def.abilities.q
	c.cooldowns.q = c.ability_cooldown(ab, ctx)
	c.cd_total.q = maxf(c.cooldowns.q, 0.01)
	c.clear_windup()
	c.set_anim_lock(Unit.ANIM_CAST, 0.25)
	c.start_action(Unit.ANIM_CAST, Unit.ACT_RECAST, 0.0)
	var rank: int = ctx.rank
	var fraction := clampf((elapsed - Q_MIN) / (Q_TIME - Q_MIN), 0.0, 1.0)
	var low := Effects.num(ab.effects[0].on_hit[0].amount, ctx)
	var high := 65.0 * rank + 5.0 + (1.125 + 0.225 * rank) * float(c.stats.attack_damage)
	var amount := lerpf(low, high, fraction)
	var origin := c.global_position
	var reach: float = ctx.range
	c.world.fx("beam", {"from": origin, "to": origin + dir * reach, "width": 350.0,
		"color": IMPACT_COLOR, "team": c.team})
	for t: Unit in c.world.query_line(origin, origin + dir * reach, 200.0, c.team):
		var offset := t.global_position - origin
		var along := offset.dot(dir)
		var half_width := lerpf(100.0, 200.0, clampf(along / reach, 0.0, 1.0))
		if along < -t.radius or along > reach + t.radius or absf(offset.cross(dir)) > half_width + t.radius:
			continue
		if Effects._blocked(t, ctx):
			continue
		var mult := 0.6 if t is Minion else (1.5 if t is Monster else 1.0)
		t.take_damage(amount * mult, c, "physical", {"ability": "q", "aoe": true, "col": IMPACT_COLOR})
		if elapsed >= 1.0:
			_airborne(t, dir, lerpf(1.25, 2.5, elapsed - 1.0), ctx)
		else:
			Effects.run([{"type": "slow", "duration": 0.25, "amount": 0.8}], Effects.sub(ctx, {"target": t}))
	ctx = {}


func shield() -> Dictionary:
	return c.find_status(FURNACE, c)


func detonate(ab: Dictionary, cast_ctx: Dictionary) -> void:
	c.remove_status_id(FURNACE, c)
	cast_ctx.origin = c.global_position
	cast_ctx.pos = c.global_position
	Effects.run(ab.effects, cast_ctx)


func roar(ab: Dictionary, cast_ctx: Dictionary) -> void:
	var shot: Dictionary = ab.effects[0]
	var p := _missile(c.global_position, cast_ctx.dir, float(cast_ctx.range), float(shot.radius), true)
	p.swept_hit = _roar_first.bind(shot.on_hit, cast_ctx)


func _roar_first(t: Unit, effects: Array, cast_ctx: Dictionary) -> bool:
	if not is_instance_valid(c):
		return true
	if Effects._blocked(t, cast_ctx):
		return true
	var d: Vector2 = cast_ctx.dir
	var at := t.global_position
	var can_launch: bool = (t is Minion or (t is Monster and not t.epic)) and not t.crowd_control_immune()
	_roar_hit(t, effects, cast_ctx)
	if can_launch:
		var distance := 1350.0
		var wall := c.world.map.wall_distance(at, d, distance + t.pathing_radius())
		if wall < INF:
			distance = clampf(wall - t.pathing_radius(), 0.0, distance)
		if distance <= 0.0:
			return true
		if not t.dead:
			t.knockback(d * distance, distance / 1800.0)
		var p := _missile(at, d, distance, float(t.radius), true)
		p.hit_ids[t.net_id] = true
		p.pierce = -1
		p.swept_hit = _roar_hit.bind(effects, cast_ctx)
	return true


func _roar_hit(t: Unit, effects: Array, cast_ctx: Dictionary) -> bool:
	if is_instance_valid(c):
		Effects.run(effects, Effects.sub(cast_ctx, {"target": t, "pos": t.global_position}))
	return false


func _missile(at: Vector2, d: Vector2, distance: float, width: float, through_walls: bool) -> Projectile:
	var p: Projectile = c.world.spawn("projectile", {"pos": at, "dir": d, "team": c.team,
		"radius": minf(width * 0.42, 18.0), "color": IMPACT_COLOR})
	p.mode = "ability"
	p.speed = 1800.0
	p.max_dist = distance
	p.sweep_radius = width
	p.through_walls = through_walls
	return p


func steer_to(aim: Vector2) -> void:
	if action == CHARGE and aim.is_finite() and aim.distance_squared_to(c.global_position) > 16.0:
		steer = c.global_position.direction_to(aim)


func rush(delta: float) -> void:
	elapsed += delta
	if c.is_bot:
		var t := c.world.nearest_enemy(c.global_position, c.team, 1800.0, true)
		if t != null and dir.dot(c.global_position.direction_to(t.global_position)) > 0.3:
			steer_to(t.global_position)
	dir = dir.rotated(clampf(dir.angle_to(steer), -0.75 * delta, 0.75 * delta))
	var speed := lerpf(maxf(float(c.stats.move_speed), 350.0), 950.0, clampf(elapsed / 3.0, 0.0, 1.0))
	var from := c.global_position
	var motion := dir * speed * delta
	c.face(from + dir * 100.0)
	var col := c.move_and_collide(motion, true)
	var step := col.get_travel() if col != null else motion
	var stop := 1.0
	var collided := col != null
	var contacts := []
	for t: Unit in c.world.query_line(from, from + step, c.radius, c.team, "enemies", true):
		var offset := t.global_position - from
		var r := c.radius + t.radius
		var cross := offset.cross(dir)
		var distance := maxf(offset.dot(dir) - sqrt(maxf(r * r - cross * cross, 0.0)), 0.0)
		var frac := clampf(distance / maxf(step.length(), 0.001), 0.0, 1.0)
		if t.is_champion or t.is_structure:
			stop = minf(stop, frac)
			collided = true
		elif not trampled.has(t.net_id):
			contacts.append([t, frac])
	c.global_position = from + step * stop
	c.velocity = Vector2.ZERO
	c.set_anim_lock(Unit.ANIM_WALK, 0.06)
	for pair: Array in contacts:
		var t: Unit = pair[0]
		if float(pair[1]) <= stop and not c.dead:
			trampled[t.net_id] = true
			_r_damage(t, 5.0 if t is Minion else 1.0)
	if action == CHARGE and (collided or elapsed >= R_TIME):
		end_rush()


func end_rush() -> void:
	if action != CHARGE:
		return
	action = IDLE
	c.set_anim_lock(Unit.ANIM_CAST, 0.25)
	c.start_action(Unit.ANIM_CAST, Unit.ACT_RECAST + 3, 0.0)
	var at := c.global_position
	c.world.fx("ring", {"pos": at, "radius": 500.0, "color": IMPACT_COLOR, "team": c.team})
	for t: Unit in c.world.query(at, 500.0, c.team, "enemies", true):
		if not trampled.has(t.net_id):
			_r_damage(t, 5.0 if t is Minion else 1.0)
		if not t.is_structure and not Effects._blocked(t, ctx):
			if at.distance_to(t.global_position) <= 300.0 + t.radius:
				_airborne(t, dir, lerpf(0.75, 1.75, _rush_power()), ctx)
			else:
				Effects.run([{"type": "slow", "duration": 3.0, "amount": 0.35 + 0.05 * int(ctx.rank)}],
					Effects.sub(ctx, {"target": t}))
	ctx = {}


func _rush_power() -> float:
	return clampf(elapsed / 3.0, 0.0, 1.0)


func _r_damage(t: Unit, mult: float) -> void:
	if Effects._blocked(t, ctx):
		return
	var rank: int = ctx.rank
	var bonus_ad: float = c.stats.attack_damage - c.base_stats.attack_damage
	var amount := lerpf(150.0 * rank + 0.4 * bonus_ad, 400.0 * rank + 0.8 * bonus_ad, _rush_power())
	t.take_damage(amount * mult, c, "physical", {"ability": "r", "aoe": true, "col": IMPACT_COLOR})


static func _airborne(t: Unit, d: Vector2, duration: float, cast_ctx: Dictionary) -> void:
	if t.dead or t.crowd_control_immune():
		return
	var air_time := minf(0.5, duration)
	t.knockback(d * 6.0, air_time)
	var scaled := Effects._cc_time(t, {"duration": duration}, cast_ctx, duration)
	Effects.run([{"type": "stun", "duration": maxf(air_time, scaled), "ignore_tenacity": true}],
		Effects.sub(cast_ctx, {"target": t}))


func gain_health(victim: Unit) -> void:
	if c.ranks.w <= 0 or victim.team == c.team or victim.is_structure or victim.is_ward:
		return
	var big: bool = victim is Champion or (victim is Monster and victim.large) \
		or (victim is Minion and victim.minion_type in ["siege", "super"])
	if not (big or victim is Minion or victim is Monster or victim is Summon):
		return
	bonus_health += 15.0 if big else 4.0
	c.recompute_stats()


func begin_death() -> void:
	form = RISING
	action = IDLE
	ctx = {}
	rise_left = 1.5


func rise() -> void:
	form = ZOMBIE
	c.dead = false
	c.flags = 0
	c.anim = Unit.ANIM_IDLE
	c.anim_lock = 0.0
	c.attack_cd = 0.0
	c.last_champion_hit = null
	c.last_champion_hit_time = -INF
	c.recompute_stats()
	c.hp = c.stats.max_hp
	decay_left = DECAY_STEP
	decay_ticks = 0
	surge_used = false
	c.world.fx("spawn", {"p": c.global_position, "c": IMPACT_COLOR, "r": c.radius * 2.0})


func decay(delta: float) -> void:
	c.respawn_timer = maxf(c.respawn_timer - delta, 0.0)
	decay_left -= delta
	while decay_left <= 0.0 and not c.dead:
		decay_left += DECAY_STEP
		var base := lerpf(2.3, 24.4, (mini(c.level, 18) - 1) / 17.0) + 0.02 * float(c.stats.max_hp)
		c.hp -= base * (1.0 + 0.7 * decay_ticks)
		decay_ticks += 1
		if c.hp <= 0.0:
			c.die()


func death_surge() -> bool:
	if form != ZOMBIE or surge_used or c.dead:
		return false
	surge_used = true
	c.add_status({"type": "buff", "id": SURGE, "time": 2.5,
		"add": {"move_speed_bonus": 0.5}, "mult": {}}, c, SURGE)
	c.world.fx("ring", {"pos": c.global_position, "radius": c.radius * 1.6, "color": IMPACT_COLOR, "team": c.team})
	return true


func draw_body() -> void:
	var facing := Vector2.from_angle(c.face_angle)
	var side := facing.orthogonal()
	var col := c.body_color()
	if form == ZOMBIE:
		col = col.lerp(Color("#ed8a43"), 0.45)
	var r := 48.0 * float(c.stats.size)
	var step := sin(c.life * (19.0 if action == CHARGE else 12.0)) * (r * 0.16) if c.anim == Unit.ANIM_WALK else 0.0
	for sign_dir in [-1.0, 1.0]:
		var foot := side * r * 0.35 * float(sign_dir) + facing * (step * float(sign_dir) - r * 0.5)
		c.draw_circle(foot, r * 0.26, Color("#332328"))
	c.draw_colored_polygon(PackedVector2Array([-facing * r * 0.7 - side * r * 0.51,
		facing * r * 0.24 - side * r, facing * r * 0.5 - side * r * 0.55,
		facing * r * 0.5 + side * r * 0.55, facing * r * 0.24 + side * r,
		-facing * r * 0.7 + side * r * 0.51]), col.darkened(0.32))
	c.draw_circle(facing * r * 0.2, r * 0.45, col.lightened(0.22))
	c.draw_line(facing * r * 0.48 - side * r * 0.2, facing * r * 0.48 + side * r * 0.2, IMPACT_COLOR.lightened(0.4), 4.0, true)
	var arm := side * r * 0.78
	var blade := arm + facing * r * (1.15 if action != SMASH else 0.48)
	c.draw_line(arm - facing * r * 0.45, blade, Color("#5e3931"), 8.0, true)
	c.draw_colored_polygon(PackedVector2Array([blade - side * r * 0.34 - facing * r * 0.25,
		blade - side * r * 0.34 + facing * r * 0.28, blade + side * r * 0.43 + facing * r * 0.24,
		blade + side * r * 0.24 - facing * r * 0.32]), Color("#a5a2a3"))


func draw_action() -> void:
	if action == SMASH:
		var d := c.windup_dir
		var side := d.orthogonal()
		var reach: float = c.def.abilities.q.range
		var points := PackedVector2Array([-side * 100.0, d * reach - side * 200.0,
			d * reach + side * 200.0, side * 100.0])
		var ready := c.windup_left <= Q_TIME - 1.0
		c.draw_colored_polygon(points, Color(IMPACT_COLOR, 0.27 if ready else 0.13))
		points.append(points[0])
		c.draw_polyline(points, Color(IMPACT_COLOR, 0.9 if ready else 0.55), 4.0, true)
	elif action == CHARGE:
		var d := Vector2.from_angle(c.face_angle)
		for i in [-1.0, 1.0]:
			var start := d.orthogonal() * c.radius * 0.7 * float(i)
			c.draw_line(start, start - d * 145.0, Color(IMPACT_COLOR, 0.63), 9.0, true)
