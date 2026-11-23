class_name Effects
extends RefCounted
## Runs ability effect lists from character JSON. Host-only (clients just see results).
##
## Context ("ctx") keys: caster, team, target, pos, origin, dir, ability, char,
## color, range, i. Any number in an effect may also be an expression string,
## e.g. "60 + 0.8 * ap + 0.1 * t_max_hp" (see VARS for the variable names).

const VARS := ["ad", "ap", "level", "hp", "max_hp", "missing_hp", "armor", "speed", "size",
	"t_hp", "t_max_hp", "t_missing_hp", "t_armor", "dist", "i", "time", "ally"]

static var _cache := {}
static var _bad := {}


static func num(v, ctx: Dictionary, def := 0.0) -> float:
	if v == null:
		return def
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is String:
		if v.is_valid_float():
			return v.to_float()
		if _bad.has(v):
			return def
		var e: Expression = _cache.get(v)
		if e == null:
			e = Expression.new()
			if e.parse(v, VARS) != OK:
				_bad[v] = true
				push_warning("Bad expression \"%s\": %s" % [v, e.get_error_text()])
				return def
			_cache[v] = e
		var r = e.execute(_values(ctx), null, false)
		if e.has_execute_failed():
			return def
		if r is bool:
			return 1.0 if r else 0.0
		if r is float or r is int:
			return float(r)
	return def


static func _values(ctx: Dictionary) -> Array:
	var c = ctx.get("caster")
	var t = ctx.get("target")
	var cv := is_instance_valid(c)
	var tv := is_instance_valid(t)
	var vals := []
	if cv:
		vals.append_array([c.stats.attack_damage, c.stats.ability_power, float(c.get_level()), c.hp,
			c.stats.max_hp, c.stats.max_hp - c.hp, c.stats.armor, c.stats.move_speed, c.stats.size])
	else:
		vals.append_array([0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	if tv:
		vals.append_array([t.hp, t.stats.max_hp, t.stats.max_hp - t.hp, t.stats.armor])
	else:
		vals.append_array([0.0, 1.0, 0.0, 0.0])
	vals.append(c.global_position.distance_to(t.global_position) if cv and tv else 0.0)
	vals.append(float(ctx.get("i", 0)))
	vals.append(Game.world.time if Game.world != null else 0.0)
	vals.append(1.0 if tv and int(t.team) == int(ctx.get("team", -1)) else 0.0)
	return vals


static func run(list, ctx: Dictionary) -> void:
	if list == null or Game.world == null:
		return
	if list is Dictionary:
		list = [list]
	if not (list is Array):
		return
	if int(ctx.get("_depth", 0)) > 16:
		return
	for e in list:
		if e is Dictionary:
			_one(e, ctx)


static func sub(ctx: Dictionary, changes := {}) -> Dictionary:
	var c := ctx.duplicate()
	c["_depth"] = int(ctx.get("_depth", 0)) + 1
	c.merge(changes, true)
	return c


static func _one(e: Dictionary, ctx: Dictionary) -> void:
	var w = Game.world
	if e.has("chance") and randf() > num(e["chance"], ctx, 1.0):
		return
	if e.has("if") and num(e["if"], ctx, 1.0) == 0.0:
		return
	var type := str(e.get("type", ""))
	match type:
		"damage":
			var u := _unit(e, ctx)
			if u:
				u.take_damage(num(e.get("amount"), ctx, 50.0), _caster(ctx), str(e.get("damage_type", "magic")))
		"heal":
			var u := _unit(e, ctx)
			if u:
				u.heal(num(e.get("amount"), ctx, 50.0), _caster(ctx))
		"shield":
			var u := _unit(e, ctx)
			if u:
				u.add_status({"type": "shield", "amount": num(e.get("amount"), ctx, 100.0),
					"time": num(e.get("duration"), ctx, 3.0)}, _caster(ctx), _key(e, ctx))
		"stun", "root", "silence", "invulnerable":
			var u := _unit(e, ctx)
			if u:
				u.add_status({"type": type, "time": num(e.get("duration"), ctx, 1.0)}, _caster(ctx), _key(e, ctx))
		"slow":
			var u := _unit(e, ctx)
			if u:
				u.add_status({"type": "slow", "amount": clampf(num(e.get("amount"), ctx, 0.3), 0.0, 1.0),
					"time": num(e.get("duration"), ctx, 2.0)}, _caster(ctx), _key(e, ctx))
		"dot", "hot":
			var u := _unit(e, ctx)
			if u:
				var iv := maxf(num(e.get("interval"), ctx, 0.5), 0.1)
				u.add_status({"type": type, "amount": num(e.get("amount"), ctx, 20.0), "interval": iv, "tick": iv,
					"time": num(e.get("duration"), ctx, 3.0), "dtype": str(e.get("damage_type", "magic"))},
					_caster(ctx), _key(e, ctx))
		"buff":
			var u := _unit(e, ctx)
			if u:
				var add := {}
				var mult := {}
				var ra = e.get("add", {})
				var rm = e.get("multiply", {})
				if ra is Dictionary:
					for k in ra:
						add[k] = num(ra[k], ctx, 0.0)
				if rm is Dictionary:
					for k in rm:
						mult[k] = num(rm[k], ctx, 1.0)
				u.add_status({"type": "buff", "add": add, "mult": mult, "time": num(e.get("duration"), ctx, 4.0)},
					_caster(ctx), _key(e, ctx))
		"cleanse":
			var u := _unit(e, ctx)
			if u:
				u.cleanse()
		"knockback", "pull":
			_knockback(type, e, ctx)
		"dash":
			_dash(e, ctx)
		"teleport", "blink":
			_teleport(e, ctx)
		"swap":
			var c := _caster(ctx)
			var u := _unit(e, ctx)
			if c and u and u != c and not u.is_structure and not c.dead:
				var a := c.global_position
				c.teleport(u.global_position)
				u.teleport(a)
				w.fx("line", {"from": a, "to": c.global_position, "color": _color(e, ctx)})
		"projectile":
			_projectile(e, ctx)
		"area":
			var center := _pos(e.get("at", "pos"), ctx)
			var scatter := num(e.get("scatter"), ctx, 0.0)
			if scatter > 0.0:
				center += Vector2.from_angle(randf() * TAU) * sqrt(randf()) * scatter
			var radius := num(e.get("radius"), ctx, 150.0)
			var delay := num(e.get("delay"), ctx, 0.0)
			var col := _color(e, ctx)
			if delay > 0.0:
				w.fx("telegraph", {"pos": center, "radius": radius, "color": col, "dur": delay})
				var c2 := sub(ctx)
				w.schedule(delay, func(): _area_now(e, c2, center, radius, col))
			else:
				_area_now(e, ctx, center, radius, col)
		"beam":
			var start := _pos(e.get("from", "caster"), ctx)
			var dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
			var length := num(e.get("length"), ctx, num(ctx.get("range"), ctx, 800.0))
			var width := num(e.get("width"), ctx, 70.0)
			var delay := num(e.get("delay"), ctx, 0.0)
			var col := _color(e, ctx)
			var end := start + dir * length
			if delay > 0.0:
				w.fx("beam_warn", {"from": start, "to": end, "width": width, "color": col, "dur": delay})
				var c2 := sub(ctx)
				w.schedule(delay, func(): _beam_now(e, c2, start, end, width, col))
			else:
				_beam_now(e, ctx, start, end, width, col)
		"zone", "trap":
			var trap := type == "trap"
			var z = w.spawn("zone", {
				"pos": _pos(e.get("at", "pos"), ctx), "team": int(ctx.get("team", 0)),
				"radius": num(e.get("radius"), ctx, 60.0 if trap else 160.0), "color": _color(e, ctx),
				"trap": trap, "hidden": bool(e.get("hidden", trap)),
				"duration": num(e.get("duration"), ctx, 30.0 if trap else 4.0),
				"sprite": str(e.get("sprite", "")), "char": str(ctx.get("char", "")),
			})
			z.init_server(e, sub(ctx))
		"summon":
			_summon(e, ctx)
		"delay":
			var c2 := sub(ctx)
			w.schedule(num(e.get("time", e.get("duration")), ctx, 1.0), func(): run(e.get("effects"), c2))
		"repeat":
			var n := clampi(int(num(e.get("count"), ctx, 3.0)), 1, 200)
			var iv := num(e.get("interval"), ctx, 0.25)
			for k in n:
				var c2 := sub(ctx, {"i": k})
				if k == 0 or iv <= 0.0:
					run(e.get("effects"), c2)
				else:
					w.schedule(iv * k, func(): run(e.get("effects"), c2))
		"random":
			var opts = e.get("options", [])
			if opts is Array and not opts.is_empty():
				run(opts[randi() % opts.size()], sub(ctx))
		"cooldown":
			var c := _caster(ctx)
			if c is Champion:
				c.change_cooldown(str(e.get("slot", "all")), num(e.get("amount"), ctx, 1.0), bool(e.get("reset", false)))
		"text":
			w.fx("text", {"pos": _pos(e.get("at", "target"), ctx) + Vector2(0, -50), "text": str(e.get("text", "!")),
				"color": _color(e, ctx, Color.WHITE), "size": int(num(e.get("size"), ctx, 28.0))})
		"sound":
			w.fx("sound", {"char": str(ctx.get("char", "")), "file": str(e.get("file", "")),
				"pos": _pos(e.get("at", "self"), ctx), "volume": num(e.get("volume"), ctx, 0.0)})
		_:
			push_warning("Unknown effect type '%s'" % type)


# ----------------------------------------------------------------- helpers ---

static func _unit(e: Dictionary, ctx: Dictionary) -> Unit:
	var who := str(e.get("target", "target"))
	var u = ctx.get("caster") if who == "self" or who == "caster" else ctx.get("target")
	if is_instance_valid(u) and u is Unit and not u.dead:
		return u
	return null


static func _caster(ctx: Dictionary) -> Unit:
	var c = ctx.get("caster")
	if is_instance_valid(c) and c is Unit:
		return c
	return null


static func _pos(spec, ctx: Dictionary) -> Vector2:
	var s := str(spec)
	if s == "self" or s == "caster":
		var c = ctx.get("caster")
		if is_instance_valid(c):
			return c.global_position
		return ctx.get("origin", Vector2.ZERO)
	if s == "target":
		var t = ctx.get("target")
		if is_instance_valid(t):
			return t.global_position
	if s == "origin":
		return ctx.get("origin", Vector2.ZERO)
	return ctx.get("pos", ctx.get("origin", Vector2.ZERO))


static func _key(e: Dictionary, ctx: Dictionary) -> String:
	if bool(e.get("stack", false)):
		return ""
	var c = ctx.get("caster")
	var cid: int = c.net_id if is_instance_valid(c) else 0
	if e.has("id"):
		return "%d:%s" % [cid, e.id]
	return "%d:%s:%s" % [cid, ctx.get("ability", ""), e.get("type", "")]


static func _color(e: Dictionary, ctx: Dictionary, fallback := Color(1, 0.6, 0.2)) -> Color:
	return Content.parse_color(e.get("color"), ctx.get("color", fallback))


static func _area_now(e: Dictionary, ctx: Dictionary, center: Vector2, radius: float, col: Color) -> void:
	var w = Game.world
	if w == null:
		return
	var angle := num(e.get("angle"), ctx, 360.0)
	var dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
	w.fx("blast", {"pos": center, "radius": radius, "color": col, "angle": angle, "dir": dir})
	var cone := deg_to_rad(angle) * 0.5
	for u in w.query(center, radius, int(ctx.get("team", 0)), str(e.get("affects", "enemies")), bool(e.get("hits_structures", false))):
		if angle < 359.0:
			var to: Vector2 = u.global_position - center
			if to.length() > u.radius and absf(dir.angle_to(to)) > cone:
				continue
		run(e.get("effects"), sub(ctx, {"target": u, "pos": center, "origin": center}))


static func _beam_now(e: Dictionary, ctx: Dictionary, start: Vector2, end: Vector2, width: float, col: Color) -> void:
	var w = Game.world
	if w == null:
		return
	w.fx("beam", {"from": start, "to": end, "width": width, "color": col})
	for u in w.query_line(start, end, width * 0.5, int(ctx.get("team", 0)), str(e.get("affects", "enemies")), bool(e.get("hits_structures", false))):
		run(e.get("effects"), sub(ctx, {"target": u, "pos": u.global_position, "origin": start}))


static func _knockback(type: String, e: Dictionary, ctx: Dictionary) -> void:
	var u := _unit(e, ctx)
	if u == null or u.is_structure:
		return
	var c := _caster(ctx)
	var dist := num(e.get("distance"), ctx, 220.0)
	var dur := maxf(num(e.get("duration"), ctx, 0.25), 0.05)
	var dir: Vector2
	if type == "pull":
		var to: Vector2 = (c.global_position if c else _pos("origin", ctx)) - u.global_position
		dir = to.normalized()
		var max_d := maxf(to.length() - u.radius - (c.radius if c else 0.0) - 4.0, 0.0)
		dist = minf(dist if e.has("distance") else INF, max_d)
	else:
		dir = (u.global_position - _pos(e.get("from", "origin"), ctx)).normalized()
		if dir == Vector2.ZERO:
			dir = ctx.get("dir", Vector2.RIGHT)
	if dist > 0.0:
		u.knockback(dir * dist, dur)


static func _dash(e: Dictionary, ctx: Dictionary) -> void:
	var c := _caster(ctx)
	if c == null or c.dead or c.is_structure:
		return
	var dist := num(e.get("distance"), ctx, 350.0)
	var speed := maxf(num(e.get("speed"), ctx, 1400.0), 50.0)
	var dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
	var length := dist
	match str(e.get("to", "aim")):
		"aim", "cursor", "pos":
			var to: Vector2 = ctx.get("pos", c.global_position) - c.global_position
			if to.length() > 5.0:
				dir = to.normalized()
				length = minf(to.length(), dist)
		"back", "backward", "backwards":
			dir = -dir
		"target":
			var t = ctx.get("target")
			if is_instance_valid(t) and t != c:
				var to2: Vector2 = t.global_position - c.global_position
				dir = to2.normalized()
				length = maxf(to2.length() - t.radius - c.radius, 0.0)
	c.start_dash(dir, length, speed, e, sub(ctx))


static func _teleport(e: Dictionary, ctx: Dictionary) -> void:
	var w = Game.world
	var c := _caster(ctx)
	if c == null or c.dead:
		return
	var to: Vector2 = ctx.get("pos", c.global_position)
	match str(e.get("to", "pos")):
		"target":
			var t = ctx.get("target")
			if is_instance_valid(t) and t != c:
				var d: Vector2 = (t.global_position - c.global_position).normalized()
				to = t.global_position + d * (t.radius + c.radius + 6.0)
		"home", "base", "spawn":
			to = w.map.spawn_point(c.team)
	to = w.map.nearest_open(to)
	var col := _color(e, ctx)
	w.fx("line", {"from": c.global_position, "to": to, "color": col})
	w.fx("ring", {"pos": c.global_position, "radius": 50.0, "color": col})
	c.teleport(to)
	w.fx("ring", {"pos": to, "radius": 70.0, "color": col})


static func _projectile(e: Dictionary, ctx: Dictionary) -> void:
	var w = Game.world
	var count := clampi(int(num(e.get("count"), ctx, 1.0)), 1, 64)
	var spread := deg_to_rad(num(e.get("spread"), ctx, 0.0 if count == 1 else 30.0))
	var start := _pos(e.get("from", "caster"), ctx)
	var base_dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
	var homing_target = null
	if bool(e.get("homing", false)):
		var t = ctx.get("target")
		if is_instance_valid(t) and t is Unit and t != ctx.get("caster") and not t.dead:
			homing_target = t
		else:
			homing_target = w.nearest_enemy(ctx.get("pos", start), int(ctx.get("team", 0)), 400.0)
	for k in count:
		var ang := 0.0
		if count > 1:
			if spread >= TAU - 0.01:
				ang = TAU * k / count
			else:
				ang = -spread * 0.5 + spread * k / (count - 1)
		var d := base_dir.rotated(ang)
		var p = w.spawn("projectile", {
			"pos": start, "dir": d, "radius": num(e.get("radius"), ctx, 12.0), "color": _color(e, ctx),
			"sprite": str(e.get("sprite", "")), "char": str(ctx.get("char", "")),
		})
		p.init_ability(e, sub(ctx), d, homing_target)


static func _summon(e: Dictionary, ctx: Dictionary) -> void:
	var w = Game.world
	var count := clampi(int(num(e.get("count"), ctx, 1.0)), 1, 20)
	var st := {}
	var raw_stats = e.get("stats", {})
	if raw_stats is Dictionary:
		for k in raw_stats:
			st[k] = num(raw_stats[k], ctx, 0.0)
	var center := _pos(e.get("at", "pos"), ctx)
	for k in count:
		var at := center
		if count > 1:
			at += Vector2.from_angle(TAU * k / count) * 45.0
		var s = w.spawn("summon", {
			"pos": w.map.nearest_open(at), "team": int(ctx.get("team", 0)), "name": str(e.get("name", "Summon")),
			"color": _color(e, ctx), "stats": st, "ranged": bool(e.get("ranged", false)),
			"size": num(e.get("size"), ctx, 0.7), "sprite": str(e.get("sprite", "")),
			"char": str(ctx.get("char", "")), "stationary": bool(e.get("stationary", false)),
		})
		s.init_server(_caster(ctx), num(e.get("duration"), ctx, 10.0), e, sub(ctx))
