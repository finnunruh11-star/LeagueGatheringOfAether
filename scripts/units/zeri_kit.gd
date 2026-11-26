class_name ZeriKit
extends RefCounted

const OVERCHARGE := "zeri_overcharge"
const HYPERCHARGE := "zeri_hypercharge"
const LIGHTNING_ROUNDS := "zeri_lightning_rounds"
const COLOR := Color("#a9f35c")
const ATTACK_SPEED_RATIO := 0.625
const TERRAIN_STEP := 4.0


static func finish_attack_speed(st: Dictionary) -> void:
	var raw: float = st.attack_speed + ATTACK_SPEED_RATIO * st.bonus_attack_speed
	st.attack_damage += maxf(raw - st.attack_speed_cap, 0.0) / ATTACK_SPEED_RATIO * 60.0
	st.attack_speed = clampf(raw, 0.05, st.attack_speed_cap) + float(st.get("zeri_overcharge_as", 0.0)) * ATTACK_SPEED_RATIO


static func cast(c: Champion, ab: Dictionary, ctx: Dictionary) -> void:
	match ab.slot:
		"q": _burst(c, ab, ctx)
		"w": _pulse(c, ab, ctx)
		"e": _surge(c, ab, ctx)
		"r": _nova(c, ab, ctx)


static func zap(c: Champion, t: Unit) -> void:
	var charged := c.zeri_charge >= 100.0
	var level := mini(c.level, 18)
	var progress := (level - 1) / 17.0
	var ctx := {"caster": c, "team": c.team, "target": t, "src_slot": "q" if charged else "passive"}
	c.trigger("cast", c, t.global_position, {"cast_slot": "passive", "amount": 0.0})
	if t.is_ward:
		t.take_damage(1.0, c, "magic", {"attack": true})
		return
	var ap: float = c.stats.ability_power
	var hit := {"ability": "passive", "spell": true, "col": COLOR, "targeted": true}
	if charged:
		c.zeri_charge = 0.0
		if Effects._blocked(t, ctx):
			return
		var health_damage := 0.0 if t.is_structure else lerpf(0.01, 0.11, progress) * float(t.stats.max_hp)
		if t is Monster:
			health_damage = minf(health_damage, 300.0)
		t.take_damage(75.0 + 85.0 * progress + 1.1 * ap + health_damage, c, "magic", hit)
		_champion_hit(c, t)
	else:
		if c.zeri_charge >= 10.0:
			c.zeri_charge -= 10.0
		var growth := (level - 1) * (0.6675 + 0.0175 * level) / 17.0
		var execute := lerpf(70.0, 160.0, progress) + 0.2 * ap
		var amount := lerpf(10.0, 25.0, growth) + 0.03 * ap
		if not t.is_structure and t.hp < execute and not t.statuses.any(func(s): return s.type == "shield" and s.amount > 0.0):
			hit.raw = true
			t.take_damage(execute, c, "true", hit)
		else:
			t.take_damage(amount, c, "magic", hit)


static func _burst(c: Champion, ab: Dictionary, ctx: Dictionary) -> void:
	c.zeri_charge = minf(c.zeri_charge + 10.0, 100.0)
	var shot: Dictionary = ab.effects[0]
	var rounds := c.find_status(LIGHTNING_ROUNDS)
	var empowered := not rounds.is_empty()
	var overcharged := not c.find_status(OVERCHARGE).is_empty()
	var count := 3 if overcharged else 7
	var crit: bool = randf() < c.stats.crit_chance
	var crit_mult: float = c.stats.crit_damage if crit else 1.0
	var burst := {
		"primary": 0, "crit": crit, "crit_mult": crit_mult, "overcharged": overcharged,
		"physical": Effects.num(shot.on_hit[0].amount, ctx, 0.0) * crit_mult / count,
		"magic": Effects.num(rounds.get("bonus"), {"caster": c, "rank": int(c.ranks.e)}, 0.0) * crit_mult / count,
		"secondary": float(rounds.get("secondary", 1.0)), "chain": 0.4 * float(c.stats.attack_damage) * crit_mult,
	}
	var speed := 3400.0 if overcharged else float(shot.speed)
	var spread := deg_to_rad(2.0 if overcharged else 5.0)
	for i in count:
		var d: Vector2 = ctx.dir.rotated(lerpf(-spread * 0.5, spread * 0.5, float(i) / (count - 1)))
		var p := _projectile(c, ctx.origin, d, speed, float(shot.radius), float(ctx.range), COLOR)
		p.through_walls = true
		p.hits_structures = true
		p.pierce = -1 if empowered else 0
		p.swept_hit = _round_hit.bind(c, burst)


static func _round_hit(t: Unit, c: Champion, burst: Dictionary) -> bool:
	if not is_instance_valid(c):
		return true
	var first := int(burst.primary) == 0
	if first:
		burst.primary = t.net_id
		c.trigger("attack_launch", t, null, {"crit_hit": burst.crit})
	var primary: bool = t.net_id == burst.primary
	if t.is_ward and not first:
		return true
	var hit := {"attack": first, "onhit": primary, "crit": burst.crit, "vfx": "twinkle", "col": COLOR,
		"exclude_unique": "mana_charge"}
	t.take_damage(float(burst.physical) * (1.0 if primary else float(burst.secondary)), c, "physical", hit)
	if primary and not t.is_ward and burst.magic > 0.0:
		t.take_damage(float(burst.magic), c, "magic", {"crit": burst.crit, "col": COLOR})
	if first and not c.dead:
		c.on_attack_hit(t, burst.crit)
		_champion_hit(c, t, burst.crit)
		if burst.overcharged and not t.is_structure and not t.is_ward:
			_chain(c, t, burst)
	return t.is_ward


static func _chain(c: Champion, first: Unit, burst: Dictionary) -> void:
	var last := first
	var seen := {first.net_id: true}
	for i in 4:
		var next: Unit = null
		var best := INF
		for u: Unit in c.world.query(last.global_position, 650.0, c.team):
			if seen.has(u.net_id) or not u.visible_to(c.team):
				continue
			var distance := last.global_position.distance_squared_to(u.global_position)
			if distance < best:
				best = distance
				next = u
		if next == null:
			break
		seen[next.net_id] = true
		c.world.fx("beam", {"from": last.global_position, "to": next.global_position, "width": 10.0, "color": COLOR, "team": c.team})
		next.take_damage(burst.chain, c, "physical", {"crit": burst.crit, "proc": true, "col": COLOR})
		last = next


static func _pulse(c: Champion, ab: Dictionary, ctx: Dictionary) -> void:
	var shot: Dictionary = ab.effects[0]
	var p := _projectile(c, ctx.origin, ctx.dir, float(shot.speed), float(shot.radius), float(ctx.range), COLOR)
	p.through_walls = false  # terrain stops the pulse and fires the wall laser
	p.swept_hit = _pulse_hit.bind(c, shot.on_hit, ctx, false)
	p.swept_wall = _wall_laser.bind(c, shot.on_hit, ctx)


static func _pulse_hit(t: Unit, c: Champion, effects: Array, ctx: Dictionary, beam: bool) -> bool:
	if not is_instance_valid(c):
		return true
	var hit_ctx := Effects.sub(ctx, {"target": t, "pos": t.global_position, "aoe": beam})
	if Effects._blocked(t, hit_ctx):
		return true
	var crit := beam and (t.is_champion or t is Monster)
	var amount := Effects.num(effects[0].amount, hit_ctx, 0.0)
	if crit:
		amount *= 1.0 + 0.5 * (float(c.stats.crit_damage) - 1.0)
	var dealt := t.take_damage(amount, c, "physical", {"ability": "w", "aoe": beam, "crit": crit, "col": COLOR})
	Effects.run([effects[1]], hit_ctx)
	if dealt > 0.0:
		_champion_hit(c, t, crit)
	return true


static func _wall_laser(start: Vector2, c: Champion, effects: Array, ctx: Dictionary) -> void:
	if not is_instance_valid(c):
		return
	var w := c.world
	var end := start + Vector2(ctx.dir) * 1500.0
	w.fx("beam_warn", {"from": start, "to": end, "width": 200.0, "color": COLOR, "dur": 0.85, "team": c.team})
	w.schedule(0.85, func():
		if not is_instance_valid(c):
			return
		w.fx("beam", {"from": start, "to": end, "width": 200.0, "color": COLOR, "team": c.team})
		for t: Unit in w.query_line(start, end, 100.0, c.team):
			_pulse_hit(t, c, effects, ctx, true)
	)


static func _surge(c: Champion, ab: Dictionary, ctx: Dictionary) -> void:
	c.attack_cd = 0.0
	c.change_cooldown("q", 0.0, true)
	var effect: Dictionary = ab.effects[0].duplicate()
	effect.precise_distance = true
	effect.phase_terrain = false  # Spark Surge stops at terrain unless it rides over it (below)
	var rounds: Dictionary = ab.lightning_rounds
	var length := Effects.num(effect.distance, ctx, 300.0)
	var speed := Effects.num(effect.speed, ctx, 930.0)
	var dir: Vector2 = ctx.dir
	var from := c.global_position
	var entry := c.world.map.wall_distance(from, dir, 50.0)
	if entry < INF:
		var exit := _ride_exit(c, from, dir, entry)
		if exit > 0.0:
			length = exit
			effect.phase_terrain = true
	c.start_dash(dir, length, speed, effect, ctx)
	c.add_status({"type": "buff", "id": LIGHTNING_ROUNDS, "time": float(rounds.duration) + length / speed,
		"add": {}, "mult": {}, "bonus": rounds.bonus_damage,
		"secondary": Effects.num(rounds.secondary_multiplier, ctx, 0.8)}, c, LIGHTNING_ROUNDS)
	c.trigger("dash", c, from + dir * length)


static func _ride_exit(c: Champion, from: Vector2, dir: Vector2, entry: float) -> float:
	var map := c.world.map
	var path_radius := c.pathing_radius()
	var last_wall := entry
	var side := dir.orthogonal() * path_radius
	var d := entry + TERRAIN_STEP
	while d <= 3000.0:
		var p := from + dir * d
		if p.x < path_radius or p.y < path_radius or p.x > map.size.x - path_radius or p.y > map.size.y - path_radius:
			break
		if map.is_wall(p) or map.is_wall(p + side) or map.is_wall(p - side):
			last_wall = d
		elif d - last_wall >= path_radius and not map.is_wall(p + dir * path_radius):
			return d
		d += TERRAIN_STEP
	return 0.0


static func _nova(c: Champion, ab: Dictionary, ctx: Dictionary) -> void:
	var area: Dictionary = ab.effects[0]
	var at := c.global_position
	var radius: float = area.radius
	var targets := c.world.query(at, radius, c.team)
	c.world.fx("ring", {"pos": at, "radius": radius, "color": COLOR, "team": c.team})
	if targets.any(func(t: Unit) -> bool: return t.is_champion):
		c.add_status({"type": "buff", "id": OVERCHARGE, "time": 5.0,
			"add": {"move_speed_bonus": 0.15, "zeri_overcharge_as": 0.30}, "mult": {}}, c, OVERCHARGE)
	for t: Unit in targets:
		var hit_ctx := Effects.sub(ctx, {"target": t, "pos": at, "aoe": true})
		if not Effects._blocked(t, hit_ctx):
			Effects.run(area.effects, hit_ctx)
			_champion_hit(c, t, false, false)


static func _champion_hit(c: Champion, t: Unit, crit := false, extend := true) -> void:
	if c.dead or not t.is_champion:
		return
	c.change_cooldown("e", 1.5 if crit else 0.5, false)
	var ult := c.find_status(OVERCHARGE)
	if ult.is_empty() or not extend:
		return
	ult.time = minf(float(ult.time) + 2.5, 5.0)
	c.add_status({"type": "buff", "id": HYPERCHARGE, "time": 2.5, "max_stacks": 100000,
		"add_stacks": 3 if crit else 1, "per_add": {"move_speed_bonus": 0.015}, "per_mult": {}}, c, HYPERCHARGE)


static func _projectile(c: Champion, from: Vector2, dir: Vector2, speed: float, width: float, distance: float, color: Color) -> Projectile:
	var p: Projectile = c.world.spawn("projectile", {"pos": from, "dir": dir, "team": c.team, "radius": 4.0, "color": color})
	p.mode = "ability"
	p.speed = speed
	p.max_dist = distance
	p.sweep_radius = width
	return p
