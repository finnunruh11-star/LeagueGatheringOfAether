class_name Effects
extends RefCounted
## Runs effect lists from character and item JSON. Host-only (clients just see results).
##
## Context ("ctx") keys: caster, team, target, pos, origin, dir, ability (display name),
## src_slot (q/w/e/r, passive, item, attack), rank, item, item_slot, char, color, range, i,
## plus event values (dmg, dtype, crit_hit, is_attack, ..., dmg_info, amount, cast_slot).
## Any number may be an expression ("60 + 0.8 * ap") or a per-rank array ([60, 90, 120]).
## Expressions can also call the helper functions in Env (has('x'), stacks('x'), ...).

const VARS := [
	"ad", "ap", "level", "hp", "max_hp", "missing_hp", "armor", "speed", "size",
	"t_hp", "t_max_hp", "t_missing_hp", "t_armor", "dist", "i", "time", "ally",
	"rank", "mana", "max_mana", "mr", "ms", "as", "bonus_as", "crit", "ah", "lethality",
	"bonus_ad", "base_ad", "bonus_hp", "base_hp", "bonus_armor", "bonus_mr", "ranged", "melee",
	"t_mr", "t_mana", "t_max_mana", "t_champion", "t_minion", "t_structure", "t_ranged", "t_level", "t_bonus_hp", "t_ms",
	"dmg", "dtype", "crit_hit", "is_attack", "is_ability", "is_dot", "is_aoe", "slot", "amount",
	"in_combat", "combat_time", "since_hit", "since_combat", "gold", "kills", "deaths", "assists", "energy", "legendaries", "moving",
	"cc", "t_self", "at_base", "t_summon",
]


## Functions usable inside expressions, e.g. "has('spellblade')" or "30 * t_stacks('kraken')".
class Env extends RefCounted:
	var ctx: Dictionary = {}

	func _u(k: String) -> Unit:
		var u = ctx.get(k)
		return u if is_instance_valid(u) and u is Unit else null

	func has(id: String) -> bool:
		var c := _u("caster")
		return c != null and not c.find_status(id).is_empty()

	func t_has(id: String) -> bool:
		var t := _u("target")
		return t != null and (not t.find_status(id, _u("caster")).is_empty() or t.has_status(id))

	func t_has_any(id: String) -> bool:
		var t := _u("target")
		return t != null and not t.find_status(id).is_empty()

	func stacks(id: String) -> float:
		var c := _u("caster")
		if c == null:
			return 0.0
		var s := c.find_status(id)
		return float(s.get("stacks", 1)) if not s.is_empty() else 0.0

	func t_stacks(id: String) -> float:
		var t := _u("target")
		if t == null:
			return 0.0
		var s := t.find_status(id, _u("caster"))
		return float(s.get("stacks", 1)) if not s.is_empty() else 0.0

	func counter(id: String) -> float:
		var c := _u("caster")
		return float(c.counters.get(id, 0.0)) if c is Champion else 0.0

	func stat(n: String) -> float:
		var c := _u("caster")
		return float(c.stats.get(n, 0.0)) if c != null else 0.0

	func t_stat(n: String) -> float:
		var t := _u("target")
		return float(t.stats.get(n, 0.0)) if t != null else 0.0

	func base(n: String) -> float:
		var c := _u("caster")
		return float(c.base_stats.get(n, 0.0)) if c != null else 0.0

	func bonus(n: String) -> float:
		var c := _u("caster")
		return float(c.stats.get(n, 0.0)) - float(c.base_stats.get(n, 0.0)) if c != null else 0.0

	## Allied champions near the caster (not counting the caster).
	func near_allies(r: float) -> int:
		return _count(r, true, true)

	## Enemy champions near the caster.
	func near_enemies(r: float) -> int:
		return _count(r, false, true)

	## Enemy units (champions, minions, summons) near the caster.
	func near_units(r: float) -> int:
		return _count(r, false, false)

	func _count(r: float, allies: bool, champs: bool) -> int:
		var c := _u("caster")
		if c == null or Game.world == null:
			return 0
		var n := 0
		for u in Game.world.units:
			if u == c or u.dead or u.is_structure or (champs and not u.is_champion) or (u.team == c.team) != allies:
				continue
			if u.global_position.distance_to(c.global_position) <= r:
				n += 1
		return n

	func cd(slot: String) -> float:
		var c := _u("caster")
		return float(c.cooldowns.get(slot, 0.0)) if c is Champion else 0.0

	## Full cooldown of the slot's last cast (for "refund X% of the ultimate's cooldown").
	func cd_total(slot: String) -> float:
		var c := _u("caster")
		return float(c.cd_total.get(slot, 0.0)) if c is Champion else 0.0

	## A stat before multipliers (stats_mult / buff multiply) were applied, e.g. Guinsoo's crit conversion.
	func pre(n: String) -> float:
		var c := _u("caster")
		return float(c.pre_mult.get(n, c.stats.get(n, 0.0))) if c != null else 0.0

	## The unit carrying the buff/mark whose trigger is running.
	func h_stat(n: String) -> float:
		var h := _u("holder")
		return float(h.stats.get(n, 0.0)) if h != null else 0.0

	func has_item(id: String) -> bool:
		var c := _u("caster")
		return c is Champion and c.has_item(id)

	func item_count(rarity: String) -> int:
		var c := _u("caster")
		return c.count_items(rarity) if c is Champion else 0


static var _cache := {}
static var _bad := {}
static var _failed := {}
static var _env: Env = null


static func num(v, ctx: Dictionary, def := 0.0) -> float:
	if v == null:
		return def
	if v is float or v is int:
		return float(v)
	if v is bool:
		return 1.0 if v else 0.0
	if v is Array:
		if v.is_empty():
			return def
		return num(v[clampi(int(ctx.get("rank", 1)) - 1, 0, v.size() - 1)], ctx, def)
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
		if _env == null:
			_env = Env.new()
		var prev := _env.ctx
		_env.ctx = ctx
		var r = e.execute(_values(ctx), _env, false)
		_env.ctx = prev
		if e.has_execute_failed():
			if not _failed.has(v):
				_failed[v] = true
				push_warning("Expression failed \"%s\": %s" % [v, e.get_error_text()])
			return def
		if r is bool:
			return 1.0 if r else 0.0
		if r is float or r is int:
			return float(r)
	return def


static func _values(ctx: Dictionary) -> Array:
	var c = ctx.get("caster")
	var t = ctx.get("target")
	var cv: bool = is_instance_valid(c) and c is Unit
	var tv: bool = is_instance_valid(t) and t is Unit
	var vals := []
	vals.resize(VARS.size())
	vals.fill(0.0)
	if cv:
		var s: Dictionary = c.stats
		var b: Dictionary = c.base_stats
		vals[0] = s.attack_damage
		vals[1] = s.ability_power
		vals[2] = float(c.get_level())
		vals[3] = c.hp
		vals[4] = s.max_hp
		vals[5] = s.max_hp - c.hp
		vals[6] = s.armor
		vals[7] = s.move_speed
		vals[8] = s.size
		vals[18] = c.mana
		vals[19] = s.max_mana
		vals[20] = s.magic_resist
		vals[21] = s.move_speed
		vals[22] = s.attack_speed
		vals[23] = s.bonus_attack_speed
		vals[24] = s.crit_chance
		vals[25] = s.ability_haste
		vals[26] = s.lethality
		vals[27] = s.attack_damage - b.attack_damage
		vals[28] = b.attack_damage
		vals[29] = s.max_hp - b.max_hp
		vals[30] = b.max_hp
		vals[31] = s.armor - b.armor
		vals[32] = s.magic_resist - b.magic_resist
		var rng: bool = c.attack_def.get("ranged", false)
		vals[33] = 1.0 if rng else 0.0
		vals[34] = 0.0 if rng else 1.0
		var now: float = Game.world.time if Game.world != null else 0.0
		vals[54] = 1.0 if c.in_combat() else 0.0
		vals[55] = now - c.combat_start if c.in_combat() else 0.0
		vals[56] = now - c.hurt_t
		vals[57] = now - c.combat_t
		if c is Champion:
			vals[58] = c.gold
			vals[59] = float(c.kills)
			vals[60] = float(c.deaths)
			vals[61] = float(c.assists)
			vals[62] = c.energy
			vals[63] = float(c.count_items("legendary"))
		vals[64] = 1.0 if c.velocity.length() > 20.0 else 0.0
	else:
		vals[2] = 1.0
		vals[4] = 1.0
		vals[8] = 1.0
	if tv:
		vals[9] = t.hp
		vals[10] = t.stats.max_hp
		vals[11] = t.stats.max_hp - t.hp
		vals[12] = t.stats.armor
		vals[35] = t.stats.magic_resist
		vals[36] = t.mana
		vals[37] = t.stats.max_mana
		vals[38] = 1.0 if t.is_champion else 0.0
		vals[39] = 1.0 if t is Minion else 0.0
		vals[40] = 1.0 if t.is_structure else 0.0
		vals[41] = 1.0 if t.attack_def.get("ranged", false) else 0.0
		vals[42] = float(t.get_level())
		vals[43] = t.stats.max_hp - t.base_stats.max_hp
		vals[44] = t.stats.move_speed
	else:
		vals[10] = 1.0
	vals[13] = c.global_position.distance_to(t.global_position) if cv and tv else 0.0
	vals[14] = float(ctx.get("i", 0))
	vals[15] = Game.world.time if Game.world != null else 0.0
	vals[16] = 1.0 if tv and int(t.team) == int(ctx.get("team", -1)) else 0.0
	vals[17] = float(ctx.get("rank", 1))
	vals[45] = float(ctx.get("dmg", 0.0))
	vals[46] = str(ctx.get("dtype", ""))
	vals[47] = 1.0 if ctx.get("crit_hit", false) else 0.0
	vals[48] = 1.0 if ctx.get("is_attack", false) else 0.0
	vals[49] = 1.0 if ctx.get("is_ability", false) else 0.0
	vals[50] = 1.0 if ctx.get("is_dot", false) else 0.0
	vals[51] = 1.0 if ctx.get("is_aoe", false) else 0.0
	vals[52] = str(ctx.get("cast_slot", ""))
	vals[53] = float(ctx.get("amount", 0.0))
	vals[65] = str(ctx.get("cc", ""))
	vals[66] = 1.0 if cv and tv and c == t else 0.0
	if cv and Game.world != null and Game.world.map != null:
		vals[67] = 1.0 if c.global_position.distance_to(Game.world.map.spawn_point(c.team)) <= Game.world.map.fountain_radius * 1.25 else 0.0
	vals[68] = 1.0 if tv and t is Summon else 0.0
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
	var rmult := float(ctx.get("rank_mult", 1.0))
	match type:
		"damage":
			var u := _unit(e, ctx)
			if u and not _blocked(u, ctx):
				var amt := num(e.get("amount"), ctx, 50.0) * rmult
				var hit := _hit(e, ctx, u)
				var c := _caster(ctx)
				if bool(e.get("can_crit", false)) and c and randf() < c.stats.crit_chance:
					amt *= c.stats.crit_damage
					hit.crit = true
				u.take_damage(amt, c, str(e.get("damage_type", "magic")), hit)
		"heal":
			var u := _unit(e, ctx)
			if u:
				var c := _caster(ctx)
				var amt := num(e.get("amount"), ctx, 50.0) * rmult
				if c:
					amt *= 1.0 + c.stats.get("heal_power", 0.0)
				var healed := u.heal(amt, c, bool(e.get("show", true)))
				if c and u != c and u.is_champion and healed > 0.0:
					c.trigger("heal_ally", u, null, {"amount": healed, "is_proc": bool(ctx.get("proc", false))})
		"shield":
			var u := _unit(e, ctx)
			if u:
				var c := _caster(ctx)
				var amt: float = num(e.get("amount"), ctx, 100.0) * rmult * (1.0 + u.stats.get("heal_received", 0.0))
				if c:
					amt *= 1.0 + c.stats.get("heal_power", 0.0)
				for s in u.statuses:
					if s.type == "shield_break":
						amt *= 1.0 - clampf(s.amount, 0.0, 1.0)
				_add(u, {"type": "shield", "amount": amt, "time": num(e.get("duration"), ctx, 3.0),
					"dtype": str(e.get("damage_type", "all"))}, e, ctx)
				if c and u != c and u.is_champion:
					c.trigger("shield_ally", u, null, {"amount": amt, "is_proc": bool(ctx.get("proc", false))})
		"shield_break":
			var u := _unit(e, ctx)
			if u:
				var f := clampf(num(e.get("amount"), ctx, 0.5), 0.0, 1.0)
				for s in u.statuses:
					if s.type == "shield":
						s.amount *= 1.0 - f
				var d := num(e.get("duration"), ctx, 0.0)
				if d > 0.0:
					_add(u, {"type": "shield_break", "amount": f, "time": d}, e, ctx)
		"fire_event":
			var c := _caster(ctx)
			if c:
				var ex := {"crit_hit": false, "onhit": true, "exclude": str(ctx.get("trigger_key", ""))}
				c.trigger(str(e.get("event", "attack")), ctx.get("target"), null, ex)
		"stun", "root", "silence":
			var u := _unit(e, ctx)
			if u and not _blocked(u, ctx):
				_add(u, {"type": type, "time": _cc_time(u, e, ctx, 1.0)}, e, ctx)
				_cc_event(type, u, ctx)
		"invulnerable", "stasis", "stealth", "untargetable":
			var u := _unit(e, ctx)
			if u:
				_add(u, {"type": type, "time": num(e.get("duration"), ctx, 1.0)}, e, ctx)
				if type == "stasis":
					u.attack_target = null
					u.move_goal = null
		"spellshield":
			var u := _unit(e, ctx)
			if u:
				_add(u, {"type": "spellshield", "time": num(e.get("duration"), ctx, 9999.0)}, e, ctx)
		"grievous":
			var u := _unit(e, ctx)
			if u and not _blocked(u, ctx):
				_add(u, {"type": "grievous", "amount": clampf(num(e.get("amount"), ctx, 0.4), 0.0, 1.0),
					"time": num(e.get("duration"), ctx, 3.0)}, e, ctx)
		"slow":
			var u := _unit(e, ctx)
			if u and not _blocked(u, ctx):
				_add(u, {"type": "slow", "amount": clampf(num(e.get("amount"), ctx, 0.3), 0.0, 1.0),
					"time": _cc_time(u, e, ctx, 2.0)}, e, ctx)
				_cc_event(type, u, ctx)
		"dot", "hot":
			var u := _unit(e, ctx)
			if u and (type == "hot" or not _blocked(u, ctx)):
				var iv := maxf(num(e.get("interval"), ctx, 0.5), 0.1)
				_add(u, {"type": type, "amount": num(e.get("amount"), ctx, 20.0) * rmult, "interval": iv, "tick": iv,
					"time": num(e.get("duration"), ctx, 3.0), "dtype": str(e.get("damage_type", "magic")), "col": _color(e, ctx),
					"src_slot": str(ctx.get("src_slot", "")), "item": str(ctx.get("item", "")), "raw": bool(e.get("raw", false))}, e, ctx)
		"buff":
			var u := _unit(e, ctx)
			if u and (u.team == int(ctx.get("team", -1)) or not _blocked(u, ctx)):
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
				var s := {"type": "buff", "add": add, "mult": mult, "time": num(e.get("duration"), ctx, 4.0)}
				if e.has("max_stacks"):
					s.per_add = add
					s.per_mult = mult
					s.max_stacks = int(num(e.max_stacks, ctx, 1.0))
					s.add_stacks = int(num(e.get("stacks"), ctx, 1.0))
					s.refresh = bool(e.get("refresh", true))
				if bool(e.get("hidden", false)):
					s.hidden = true
				if e.get("triggers") is Array:
					s.triggers = e.triggers
				_add(u, s, e, ctx)
		"mark":
			var u := _unit(e, ctx)
			if u:
				var s := {"type": "mark", "time": num(e.get("duration"), ctx, 5.0)}
				s.max_stacks = int(num(e.get("max_stacks"), ctx, 999.0))
				s.add_stacks = int(num(e.get("stacks"), ctx, 1.0))
				s.refresh = bool(e.get("refresh", true))
				if e.get("triggers") is Array:
					s.triggers = e.triggers
				var em := e.duplicate()
				if not em.has("id"):
					em.id = "mark"
				_add(u, s, em, ctx)
		"remove":
			var u := _unit(e, ctx)
			if u:
				if e.has("status"):
					var st := str(e.status)
					u.statuses = u.statuses.filter(func(s): return s.type != st)
					u.stats_dirty = true
				else:
					u.remove_status_id(str(e.get("id", "")), null if bool(e.get("any_source", false)) else _caster(ctx))
		"counter":
			var who = ctx.get("target") if str(e.get("target", "self")) == "target" else ctx.get("caster")
			if is_instance_valid(who) and who is Champion:
				who.change_counter(str(e.get("id", "counter")), e, ctx)
		"mana":
			var u := _unit(e, ctx)
			if u:
				u.restore_mana(num(e.get("amount"), ctx, 50.0))
		"gold":
			var ch := _champ(ctx)
			if ch:
				ch.add_gold(num(e.get("amount"), ctx, 10.0), _pos(e.get("at", "target"), ctx))
		"modify_damage":
			var info = ctx.get("dmg_info")
			if info is Dictionary:
				info.amount = maxf(float(info.amount) * num(e.get("mult"), ctx, 1.0) + num(e.get("add"), ctx, 0.0), 0.0)
		"transform":
			var c := _caster(ctx)
			if c is Champion:
				c.transform_item(int(ctx.get("item_slot", -1)), str(e.get("into", "")))
		"attack_reset":
			var c := _caster(ctx)
			if c:
				c.attack_cd = 0.0
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
				w.fx("telegraph", {"pos": center, "radius": radius, "color": col, "dur": delay, "team": int(ctx.get("team", 0))})
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
				w.fx("beam_warn", {"from": start, "to": end, "width": width, "color": col, "dur": delay, "team": int(ctx.get("team", 0))})
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
				c.change_cooldown(str(e.get("slot", "all")), num(e.get("amount"), ctx, 1.0), bool(e.get("reset", false)), bool(e.get("percent", false)))
		"item_cooldown":
			var c := _caster(ctx)
			if c is Champion:
				c.change_item_cooldown(str(e.get("item", "all")), num(e.get("amount"), ctx, 1.0), bool(e.get("reset", false)))
		"text":
			w.fx("text", {"pos": _pos(e.get("at", "target"), ctx) + Vector2(0, -50), "text": str(e.get("text", "!")),
				"color": _color(e, ctx, Color.WHITE), "size": int(num(e.get("size"), ctx, 28.0))})
		"sound":
			w.fx("sound", {"char": str(ctx.get("char", "")), "file": str(e.get("file", "")),
				"pos": _pos(e.get("at", "self"), ctx), "volume": num(e.get("volume"), ctx, 0.0)})
		"vfx":
			_vfx(e, ctx)
		_:
			push_warning("Unknown effect type '%s'" % type)


# ----------------------------------------------------------------- helpers ---

static func _unit(e: Dictionary, ctx: Dictionary) -> Unit:
	var who := str(e.get("target", "target"))
	var u = ctx.get("target")
	if who == "self" or who == "caster":
		u = ctx.get("caster")
	elif who == "holder":
		u = ctx.get("holder", ctx.get("caster"))
	if is_instance_valid(u) and u is Unit and not u.dead:
		return u
	return null


static func _caster(ctx: Dictionary) -> Unit:
	var c = ctx.get("caster")
	if is_instance_valid(c) and c is Unit:
		return c
	return null


## The champion that gets credit for the caster (summons credit their owner).
static func _champ(ctx: Dictionary) -> Champion:
	var c := _caster(ctx)
	if c is Summon and is_instance_valid(c.owner_unit):
		c = c.owner_unit
	return c if c is Champion else null


static func _add(u: Unit, s: Dictionary, e: Dictionary, ctx: Dictionary) -> void:
	if e.has("id"):
		s.id = str(e.id)
	u.add_status(s, _caster(ctx), _key(e, ctx))
	if Game.debug_log and s.type != "dot" and s.type != "hot":
		print("[status] t=%.2f %s gets %s%s %.2fs %s" % [Game.world.time, u.display_name, s.type, (":" + s.id) if s.has("id") else "",
			s.get("time", 0.0), str(s.get("amount", "")) if s.has("amount") else str(s.get("add", "")) + str(s.get("mult", ""))])


static func _hit(e: Dictionary, ctx: Dictionary, u: Unit) -> Dictionary:
	var from: Vector2 = ctx.get("origin", u.global_position)
	var ang: float = (u.global_position - from).angle() if from.distance_to(u.global_position) > 1.0 else Vector2(ctx.get("dir", Vector2.RIGHT)).angle()
	return {"vfx": str(e.get("vfx", "ability")), "col": _color(e, ctx), "dir": ang,
		"ability": str(ctx.get("src_slot", "")), "item": str(ctx.get("item", "")), "aoe": bool(ctx.get("aoe", false)),
		"proc": bool(ctx.get("proc", false)), "onhit": bool(e.get("onhit", ctx.get("onhit", false))),
		"attack": bool(e.get("attack", false)), "raw": bool(e.get("raw", false))}


static func _cc_time(u: Unit, e: Dictionary, ctx: Dictionary, def: float) -> float:
	var d := num(e.get("duration"), ctx, def)
	if u.team != int(ctx.get("team", -99)) and not bool(e.get("ignore_tenacity", false)):
		d *= 1.0 - clampf(u.stats.get("tenacity", 0.0), 0.0, 0.9)
	return d


static func _cc_event(type: String, u: Unit, ctx: Dictionary) -> void:
	var c := _caster(ctx)
	if c and u.is_champion and u.team != c.team:
		c.trigger("cc_applied", u, null, {"cc": type})


## Spell shields block the first enemy ability effect (and the rest of that hit).
static func _blocked(u: Unit, ctx: Dictionary) -> bool:
	if u.team == int(ctx.get("team", -99)):
		return false
	var key := "_blocked_%d" % u.net_id
	if ctx.has(key):
		return ctx[key]
	var blocked := false
	if str(ctx.get("src_slot", "")) in ["q", "w", "e", "r"] and u.has_status("spellshield"):
		u.statuses = u.statuses.filter(func(s): return s.type != "spellshield")
		Game.world.fx("text", {"pos": u.global_position + Vector2(0, -60), "text": "Blocked!", "color": Color(0.8, 0.65, 1.0), "size": 22})
		Game.world.fx("ring", {"pos": u.global_position, "radius": u.radius + 30.0, "color": Color(0.8, 0.65, 1.0)})
		u.trigger("spellshield_pop", _caster(ctx))
		blocked = true
	ctx[key] = blocked
	return blocked


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
	if s == "holder":
		var h = ctx.get("holder")
		if is_instance_valid(h):
			return h.global_position
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


static func _vfx(e: Dictionary, ctx: Dictionary) -> void:
	var w = Game.world
	var col := _color(e, ctx)
	var kind := str(e.get("kind", "ring"))
	match kind:
		"line", "beam":
			w.fx(kind, {"from": _pos(e.get("from", "caster"), ctx), "to": _pos(e.get("to", "target"), ctx), "color": col,
				"width": num(e.get("width"), ctx, 14.0), "vfx": str(e.get("vfx", ""))})
		"blast":
			w.fx("blast", {"pos": _pos(e.get("at", "target"), ctx), "radius": num(e.get("radius"), ctx, 100.0), "color": col,
				"angle": 360.0, "dir": Vector2.RIGHT, "vfx": str(e.get("vfx", ""))})
		_:
			w.fx("ring", {"pos": _pos(e.get("at", "target"), ctx), "radius": num(e.get("radius"), ctx, 80.0), "color": col})


static func _area_now(e: Dictionary, ctx: Dictionary, center: Vector2, radius: float, col: Color) -> void:
	var w = Game.world
	if w == null:
		return
	var angle := num(e.get("angle"), ctx, 360.0)
	var dir: Vector2 = ctx.get("dir", Vector2.RIGHT)
	if bool(e.get("show", true)):
		w.fx("blast", {"pos": center, "radius": radius, "color": col, "angle": angle, "dir": dir, "vfx": str(e.get("vfx", ""))})
	var cone := deg_to_rad(angle) * 0.5
	var filter := str(e.get("filter", ""))
	var skip = ctx.get("target") if bool(e.get("exclude_target", false)) else null
	var caster = ctx.get("caster")
	var targets := []
	for u in w.query(center, radius, int(ctx.get("team", 0)), str(e.get("affects", "enemies")), bool(e.get("hits_structures", false))):
		if u == skip or (bool(e.get("exclude_self", false)) and u == caster):
			continue
		if angle < 359.0:
			var to: Vector2 = u.global_position - center
			if to.length() > u.radius and absf(dir.angle_to(to)) > cone:
				continue
		match filter:
			"champions":
				if not u.is_champion:
					continue
			"minions", "non_champions":
				if u.is_champion:
					continue
		targets.append(u)
	var max_t := int(num(e.get("max_targets"), ctx, 0.0))
	match str(e.get("sort", "")):
		"nearest":
			targets.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) < b.global_position.distance_squared_to(center))
		"farthest":
			targets.sort_custom(func(a, b): return a.global_position.distance_squared_to(center) > b.global_position.distance_squared_to(center))
		"lowest_hp":
			targets.sort_custom(func(a, b): return a.hp < b.hp)
		"lowest_hp_percent":
			targets.sort_custom(func(a, b): return a.hp / a.stats.max_hp < b.hp / b.stats.max_hp)
		"champions_first":
			targets.sort_custom(func(a, b): return int(a.is_champion) > int(b.is_champion))
		"random":
			targets.shuffle()
	if max_t > 0 and targets.size() > max_t:
		targets.resize(max_t)
	for u in targets:
		run(e.get("effects"), sub(ctx, {"target": u, "pos": center, "origin": center, "aoe": true}))


static func _beam_now(e: Dictionary, ctx: Dictionary, start: Vector2, end: Vector2, width: float, col: Color) -> void:
	var w = Game.world
	if w == null:
		return
	w.fx("beam", {"from": start, "to": end, "width": width, "color": col, "vfx": str(e.get("vfx", ""))})
	for u in w.query_line(start, end, width * 0.5, int(ctx.get("team", 0)), str(e.get("affects", "enemies")), bool(e.get("hits_structures", false))):
		run(e.get("effects"), sub(ctx, {"target": u, "pos": u.global_position, "origin": start, "aoe": true}))


static func _knockback(type: String, e: Dictionary, ctx: Dictionary) -> void:
	var u := _unit(e, ctx)
	if u == null or u.is_structure or _blocked(u, ctx):
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
		_cc_event(type, u, ctx)


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
	w.fx("blink", {"from": c.global_position, "to": to, "color": _color(e, ctx)})
	c.teleport(to)


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
			if count == 1:
				base_dir = (t.global_position - start).normalized()
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
			"ward": bool(e.get("ward", false)), "reveal": bool(e.get("reveal", false)),
		})
		s.init_server(_caster(ctx), num(e.get("duration"), ctx, 10.0), e, sub(ctx))
		w.fx("spawn", {"p": s.global_position, "c": s.color, "r": s.radius})
