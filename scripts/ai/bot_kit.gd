class_name BotKit
extends RefCounted
## What the bots know about abilities, characters and items. An ability's effect tree is read the
## way a player reads its tooltip: damage, crowd control, shape and timing, mobility, defense,
## support... (a "profile"). Also holds the curated builds and skill orders of the bundled
## characters. Used by BotBrain; everything here is static and cached per definition.

## How much a crowd control effect is worth, as a fraction of a full health bar.
const CC_WEIGHT := {"stun": 0.55, "pull": 0.6, "root": 0.4, "silence": 0.2, "knockback": 0.3, "slow": 0.12}
const OFFENSIVE_STATS := ["attack_damage", "ability_power", "bonus_attack_speed", "attack_speed", "attack_range", "crit_chance",
	"lethality", "armor_pen", "magic_pen", "magic_pen_percent", "damage_mult", "size", "omnivamp", "lifesteal"]

## Items (in order) for the bundled characters. "@tank_boots", "@defense" and "@antiheal" are
## picked against the enemy team when the bot shops ("scripting"), or a default otherwise.
const BUILDS := {
	"sir_bonk": {"start": ["dorans_shield", "health_potion"],
		"items": ["goredrinker", "@tank_boots", "black_cleaver", "@antiheal", "deaths_dance", "steraks_gage", "@defense"]},
	"honk_lord": {"start": ["dorans_blade", "health_potion"],
		"items": ["trinity_force", "@tank_boots", "black_cleaver", "@antiheal", "steraks_gage", "deaths_dance", "@defense"]},
	"gizmo": {"start": ["dorans_blade", "health_potion"],
		"items": ["galeforce", "berserkers_greaves", "kraken_slayer", "@antiheal", "runaans_hurricane", "lord_dominiks_regards", "guardian_angel"]},
	"ember": {"start": ["dorans_ring", "health_potion", "health_potion"],
		"items": ["ludens_tempest", "sorcerers_shoes", "shadowflame", "@antiheal", "zhonyas_hourglass", "rabadons_deathcap", "void_staff"]},
	"mender": {"start": ["dorans_ring", "health_potion", "health_potion"],
		"items": ["liandrys_anguish", "sorcerers_shoes", "rylais_crystal_scepter", "@antiheal", "zhonyas_hourglass", "rabadons_deathcap", "void_staff"],
		"support": ["moonstone_renewer", "ionian_boots_of_lucidity", "redemption", "ardent_censer", "mikaels_blessing", "zhonyas_hourglass"]},
	"clorinde": {"start": ["dorans_blade", "health_potion"],
		"items": ["guinsoos_rageblade", "berserkers_greaves", "blade_of_the_ruined_king", "@antiheal", "nashors_tooth", "wits_end", "guardian_angel"]},
}
## Which basic ability to max first (R is always taken when possible).
const SKILL_ORDER := {
	"sir_bonk": ["q", "e", "w"], "honk_lord": ["q", "e", "w"], "gizmo": ["q", "w", "e"],
	"ember": ["q", "w", "e"], "mender": ["q", "w", "e"], "clorinde": ["e", "q", "w"],
}
const ROLE_START := {"mage": ["dorans_ring", "health_potion", "health_potion"], "marksman": ["dorans_blade", "health_potion"],
	"bruiser": ["dorans_shield", "health_potion"]}

static var _chars := {}
static var _items := {}
static var _sums := {}
static var _uid := 0
## Short-lived memo of damage estimates (expressions are slow): Vector4i key -> Vector2(time, value).
static var _memo := {}
const MEMO_TTL := 0.5


# --------------------------------------------------------------- analysis ---

static func _blank() -> Dictionary:
	_uid += 1
	return {"uid": _uid, "slot": "", "name": "", "targeting": "direction", "range": 700.0, "cast_time": 0.0, "cost": 0.0, "cost_type": "mana",
		"auto_rank": false, "shape": "", "speed": 900.0, "width": 12.0, "prange": null, "pierce": false, "homing": false,
		"count": 1, "affects": "enemies", "explode": 0.0, "radius": 0.0, "land_radius": 0.0, "angle": 360.0, "at_self": false,
		"area_delay": 0.0, "length": 0.0, "dash": {}, "blink": false, "zone_dur": 0.0, "summon": {}, "dmg": [], "cc": {},
		"self_heal": [], "ally_heal": [], "self_shield": [], "ally_shield": [], "invuln": 0.0, "stasis": 0.0, "evade": false,
		"cleanse_self": false, "cleanse_ally": false, "steroid": false, "buffs": [], "ms_buff": 0.0, "ally_buff": false,
		"debuff": false, "bond": false, "hits": [], "dash_hits": false, "dot": false, "attack_reset": false, "requires": null,
		"recast": {}}


## Profile of one ability (or item active / summoner spell): a summary of its effects.
static func analyze(ab) -> Dictionary:
	var p := _blank()
	if not (ab is Dictionary):
		_finish(p)
		return p
	p.slot = str(ab.get("slot", ""))
	p.name = str(ab.get("name", ""))
	p.targeting = str(ab.get("targeting", "direction"))
	p.range = ab.get("range", 700.0)
	p.cast_time = ab.get("cast_time", 0.0)
	p.cost = ab.get("cost", 0.0)
	p.cost_type = str(ab.get("cost_type", "mana"))
	p.auto_rank = bool(ab.get("auto_rank", false))
	p.requires = ab.get("requires")
	var top := "self"
	if p.targeting == "unit":
		top = "enemy"
	elif p.targeting == "ally":
		top = "ally"
	_walk(ab.get("effects", []), p, _state(top, top != "enemy"), 0)
	if ab.get("recast") is Dictionary:
		p.recast = analyze(ab.recast)
	_finish(p)
	return p


## Profile of a plain effect list run on an enemy (basic-attack on-hit, passive procs).
static func analyze_list(list, mult := 1.0) -> Dictionary:
	var p := _blank()
	var st := _state("enemy", false)
	if mult != 1.0:
		st.mults = [mult]
	_walk(list, p, st, 0)
	_finish(p)
	return p


static func _state(tgt: String, covers_self: bool) -> Dictionary:
	return {"tgt": tgt, "mults": [], "conds": [], "delay": 0.0, "dur": 0.0, "anchor": "pos", "covers_self": covers_self, "hit": -1}


static func _walk(list, p: Dictionary, st: Dictionary, depth: int) -> void:
	if depth > 14 or list == null:
		return
	if list is Dictionary:
		list = [list]
	if not (list is Array):
		return
	for e in list:
		if not (e is Dictionary):
			continue
		var type := str(e.get("type", ""))
		var who := str(e.get("target", "target"))
		var tgt: String = "self" if who in ["self", "caster", "holder"] else st.tgt
		var s := st.duplicate()
		if e.has("if"):
			s.conds = st.conds + [e.get("if")]
		if e.has("chance"):
			s.mults = st.mults + [e.get("chance")]
		var foe: bool = tgt == "enemy" or tgt == "any"
		match type:
			"damage":
				if foe:
					p.dmg.append({"amount": e.get("amount", 50.0), "dtype": e.get("damage_type"), "mults": s.mults, "conds": s.conds, "dflt": 50.0})
					_mark(p, s, false)
			"dot":
				if foe:
					p.dmg.append({"amount": e.get("amount", 20.0), "dtype": str(e.get("damage_type", "magic")),
						"mults": s.mults + [e.get("duration", 3.0)], "conds": s.conds, "dflt": 20.0})
					p.dot = true
					_mark(p, s, false)
			"stun", "root", "silence":
				if foe:
					p.cc[type] = maxf(float(p.cc.get(type, 0.0)), _n(e.get("duration"), 1.0))
					_mark(p, s, true)
			"slow":
				if foe:
					p.cc.slow = maxf(float(p.cc.get("slow", 0.0)), _n(e.get("amount"), 0.3))
					_mark(p, s, false)
			"knockback", "pull":
				if foe:
					p.cc[type] = maxf(float(p.cc.get(type, 0.0)), _n(e.get("distance"), 220.0))
					_mark(p, s, true)
			"heal", "shield":
				var h := {"amount": e.get("amount", 50.0 if type == "heal" else 100.0), "mults": s.mults, "conds": s.conds,
					"dflt": 50.0 if type == "heal" else 100.0}
				if tgt == "self":
					p["self_" + type].append(h)
				elif tgt == "ally" or tgt == "any":
					p["ally_" + type].append(h)
					if s.covers_self:
						p["self_" + type].append(h)
			"invulnerable", "stasis":
				if tgt == "self":
					var key := "invuln" if type == "invulnerable" else "stasis"
					p[key] = maxf(float(p[key]), _n(e.get("duration"), 1.0))
			"untargetable", "stealth", "spellshield":
				if tgt == "self":
					p.evade = true
			"cleanse":
				if tgt == "self":
					p.cleanse_self = true
				elif tgt == "ally" or tgt == "any":
					p.cleanse_ally = true
					if s.covers_self:
						p.cleanse_self = true
			"buff":
				_buff(e, p, tgt, s)
			"bond_of_life":
				if tgt == "self":
					p.bond = true
			"attack_reset":
				p.attack_reset = true
			"projectile":
				var aff := str(e.get("affects", "enemies"))
				if p.shape == "":
					p.shape = "projectile"
					p.speed = _n(e.get("speed"), 900.0)
					p.width = _n(e.get("radius"), 12.0)
					p.prange = e.get("range")
					var pr = e.get("pierce", false)
					p.pierce = (pr is bool and pr) or ((pr is float or pr is int) and pr != 0)
					p.homing = bool(e.get("homing", false))
					p.count = int(_n(e.get("count"), 1.0))
					p.affects = aff
					p.explode = Content._find_radius(e.get("on_end"))
				var sh := s.duplicate()
				sh.tgt = _affects(aff)
				sh.covers_self = false
				sh.hit = -1
				_walk(e.get("on_hit"), p, sh, depth + 1)
				var se := s.duplicate()
				se.anchor = "proj_end"
				se.hit = -1
				_walk(e.get("on_end"), p, se, depth + 1)
			"area":
				var aff := str(e.get("affects", "enemies"))
				var at := str(e.get("at", "pos"))
				var ang := _n(e.get("angle"), 360.0)
				var rad := _n(e.get("radius"), 150.0) + _n(e.get("scatter"), 0.0)
				var adel := _n(e.get("delay"), 0.0)
				var self_at: bool = at in ["self", "caster"] or (at == "pos" and st.anchor == "pos" and p.targeting == "self")
				if p.shape == "":
					p.shape = "cone" if ang < 359.0 else "area"
					p.radius = rad
					p.angle = ang
					p.at_self = self_at
					p.area_delay = s.delay + adel
					p.affects = aff
				elif p.shape == "dash" and st.anchor == "land" and p.land_radius <= 0.0:
					p.land_radius = rad
				var sa := s.duplicate()
				sa.tgt = _affects(aff)
				sa.covers_self = self_at and aff != "enemies"
				sa.delay = s.delay + adel
				if _n(e.get("scatter"), 0.0) > 0.0:
					sa.mults = s.mults + [0.45]
				var anchor := "caster" if at in ["self", "caster"] else ("target" if at == "target" else str(st.anchor))
				if anchor == "pos" and p.targeting == "self":
					anchor = "origin"
				sa.hit = -1
				# Areas telegraphed with their own "delay" are read from the telegraph instead.
				if adel <= 0.0 and aff != "allies":
					p.hits.append({"kind": "cone" if ang < 359.0 else "circle", "anchor": anchor, "radius": rad, "angle": ang,
						"delay": s.delay, "dur": s.dur, "cc": false, "dmg": false})
					sa.hit = p.hits.size() - 1
				_walk(e.get("effects"), p, sa, depth + 1)
			"beam":
				var aff := str(e.get("affects", "enemies"))
				var length := _n(e.get("length"), _n(p.range, 800.0))
				var width := _n(e.get("width"), 70.0)
				if p.shape == "":
					p.shape = "beam"
					p.length = length
					p.width = width * 0.5
					p.area_delay = s.delay + _n(e.get("delay"), 0.0)
					p.affects = aff
				var sb := s.duplicate()
				sb.tgt = _affects(aff)
				sb.covers_self = false
				sb.hit = -1
				if _n(e.get("delay"), 0.0) <= 0.0 and aff != "allies":
					p.hits.append({"kind": "line", "anchor": "caster", "length": length, "width": width * 0.5, "delay": s.delay,
						"dur": s.dur, "cc": false, "dmg": false})
					sb.hit = p.hits.size() - 1
				_walk(e.get("effects"), p, sb, depth + 1)
			"dash":
				if p.shape == "":
					p.shape = "dash"
				if p.dash.is_empty():
					p.dash = {"to": str(e.get("to", "aim")), "distance": e.get("distance", 350.0), "speed": e.get("speed", 1400.0)}
				var sd := s.duplicate()
				sd.tgt = _affects(str(e.get("affects", "enemies")))
				sd.covers_self = false
				sd.hit = -1
				var nd: int = p.dmg.size()
				var nc: int = p.cc.size()
				_walk(e.get("on_hit"), p, sd, depth + 1)
				if p.dmg.size() > nd or p.cc.size() > nc:
					p.dash_hits = true
				var sl := s.duplicate()
				sl.anchor = "land"
				sl.hit = -1
				sl.delay = s.delay + _n(e.get("distance"), 350.0) / maxf(_n(e.get("speed"), 1400.0), 50.0)
				_walk(e.get("on_end"), p, sl, depth + 1)
			"teleport", "blink", "swap":
				if p.shape == "":
					p.shape = "blink"
				p.blink = true
			"zone", "trap":
				var aff := str(e.get("affects", "enemies"))
				if p.shape == "":
					p.shape = type
					p.radius = _n(e.get("radius"), 60.0 if type == "trap" else 160.0)
					p.zone_dur = _n(e.get("duration"), 30.0 if type == "trap" else 4.0)
					p.affects = aff
				var sz := s.duplicate()
				sz.tgt = _affects(aff)
				sz.covers_self = aff != "enemies" and (str(e.get("at", "pos")) in ["self", "caster"] or p.targeting == "self")
				sz.hit = -1
				if type == "zone":
					var ticks := _n(e.get("duration"), 4.0) / maxf(_n(e.get("interval"), 0.5), 0.05)
					sz.mults = s.mults + [maxf(ticks * 0.5, 1.0)]
				_walk(e.get("effects"), p, sz, depth + 1)
			"summon":
				if p.shape == "":
					p.shape = "summon"
				if p.summon.is_empty():
					p.summon = {"count": e.get("count", 1), "duration": e.get("duration", 10.0), "stationary": bool(e.get("stationary", false)),
						"ranged": bool(e.get("ranged", false)), "ward": bool(e.get("ward", false))}
			"delay":
				var sdl := s.duplicate()
				sdl.delay = s.delay + _n(e.get("time", e.get("duration")), 1.0)
				_walk(e.get("effects"), p, sdl, depth + 1)
			"repeat":
				var srp := s.duplicate()
				srp.mults = s.mults + [e.get("count", 3.0)]
				srp.dur = s.dur + maxf(_n(e.get("count"), 3.0) - 1.0, 0.0) * _n(e.get("interval"), 0.25)
				_walk(e.get("effects"), p, srp, depth + 1)
			"random":
				var opts = e.get("options", [])
				if opts is Array and not opts.is_empty():
					var sr := s.duplicate()
					sr.mults = s.mults + [1.0 / opts.size()]
					for o in opts:
						_walk(o, p, sr, depth + 1)


static func _buff(e: Dictionary, p: Dictionary, tgt: String, s: Dictionary) -> void:
	var add = e.get("add", {})
	var mul = e.get("multiply", {})
	if not (add is Dictionary):
		add = {}
	if not (mul is Dictionary):
		mul = {}
	if tgt == "self":
		var offensive: bool = e.get("attack") is Dictionary
		for k in add:
			if k in OFFENSIVE_STATS and _n(add[k], 1.0) > 0.0:
				offensive = true
			if k == "move_speed_bonus":
				p.ms_buff = maxf(p.ms_buff, _n(add[k], 0.0))
		for k in mul:
			if k in OFFENSIVE_STATS and _n(mul[k], 1.0) > 1.0:
				offensive = true
			if k == "move_speed" and _n(mul[k], 1.0) > 1.0:
				p.ms_buff = maxf(p.ms_buff, _n(mul[k], 1.0) - 1.0)
		if offensive:
			p.steroid = true
			p.buffs.append({"add": add, "multiply": mul, "attack": e.get("attack"), "duration": e.get("duration", 4.0), "conds": s.conds})
	elif tgt == "ally" or tgt == "any":
		p.ally_buff = true
	elif tgt == "enemy":
		p.debuff = true


static func _mark(p: Dictionary, s: Dictionary, cc: bool) -> void:
	var i := int(s.get("hit", -1))
	if i < 0 or i >= p.hits.size():
		return
	if cc:
		p.hits[i].cc = true
	else:
		p.hits[i].dmg = true


static func _affects(aff: String) -> String:
	match aff:
		"allies":
			return "ally"
		"all":
			return "any"
	return "enemy"


static func _finish(p: Dictionary) -> void:
	p.damage = not p.dmg.is_empty()
	p.hard = p.cc.has("stun") or p.cc.has("root") or p.cc.has("pull") or p.cc.has("knockback")
	var dash_to := str(p.dash.get("to", ""))
	p.dash_back = dash_to in ["back", "backward", "backwards"]
	p.mobility = not p.dash.is_empty() or p.blink
	p.engage = (p.shape == "dash" and not p.dash_back and (p.damage or p.hard)) or (p.shape == "blink" and p.damage)
	p.escape = p.mobility or p.ms_buff >= 0.15
	p.defensive = p.invuln > 0.0 or p.stasis > 0.0 or not p.self_shield.is_empty() or not p.self_heal.is_empty() or p.evade or p.cleanse_self
	p.support = not p.ally_heal.is_empty() or not p.ally_shield.is_empty() or p.ally_buff or p.cleanse_ally
	p.blockable = p.shape == "projectile" and not p.pierce and not p.homing
	p.farm = p.damage and (p.pierce or (p.shape in ["area", "cone", "zone"] and p.radius >= 110.0) or p.explode >= 90.0 or int(p.count) > 2)
	var cc_value := 0.0
	for k in p.cc:
		cc_value += float(CC_WEIGHT.get(k, 0.1)) * (maxf(float(p.cc[k]), 0.5) if k in ["stun", "root", "silence"] else 1.0)
	p.cc_value = cc_value


## A number from a raw value without a context (expressions -> default, rank arrays -> last rank).
static func _n(v, def: float) -> float:
	if v is Array:
		if v.is_empty():
			return def
		v = v[v.size() - 1]
	if v is float or v is int:
		return float(v)
	if v is String and v.is_valid_float():
		return v.to_float()
	return def


# ------------------------------------------------------------ characters ---

## Profiles for a character: q/w/e/r (+ "q+" etc. for recasts) and "procs" (per-attack passives/on-hit).
static func char_kit(def: Dictionary) -> Dictionary:
	var id := str(def.get("id", ""))
	var c = _chars.get(id)
	if c != null and is_same(c.def, def):
		return c.kit
	var kit := {}
	var abilities = def.get("abilities", {})
	if abilities is Dictionary:
		for slot in abilities:
			var ab = abilities[slot]
			kit[slot] = analyze(ab)
			if ab is Dictionary and ab.get("recast") is Dictionary:
				kit[slot + "+"] = kit[slot].recast
	var procs := []
	var atk = def.get("attack", {})
	if atk is Dictionary and atk.get("on_hit") is Array and not atk.on_hit.is_empty():
		procs.append(analyze_list(atk.on_hit))
	var passive = def.get("passive", {})
	if passive is Dictionary:
		for t in passive.get("triggers", []):
			if t is Dictionary and str(t.get("on", "")) == "attack":
				var mult := 1.0 / maxf(float(t.get("every", 1)), 1.0)
				if t.has("chance"):
					mult *= _n(t.chance, 1.0)
				procs.append(analyze_list(t.get("effects", []), mult))
	kit["procs"] = procs
	_chars[id] = {"def": def, "kit": kit}
	return kit


static func item_kit(id: String) -> Dictionary:
	var it = Game.items.get(id)
	if it == null or it.active == null:
		return {}
	var c = _items.get(id)
	if c != null and is_same(c.ab, it.active):
		return c.kit
	var kit := analyze(it.active)
	kit.consumable = bool(it.consumable)
	kit.hot = _has_type(it.active.get("effects"), "hot")
	_items[id] = {"ab": it.active, "kit": kit}
	return kit


static func summoner_kit(ab: Dictionary, key: String) -> Dictionary:
	var c = _sums.get(key)
	if c != null and is_same(c.ab, ab):
		return c.kit
	var kit := analyze(ab)
	_sums[key] = {"ab": ab, "kit": kit}
	return kit


static func _has_type(list, type: String) -> bool:
	if list is Dictionary:
		list = [list]
	if not (list is Array):
		return false
	for e in list:
		if e is Dictionary:
			if str(e.get("type", "")) == type:
				return true
			for k in Content.NESTED_KEYS:
				if _has_type(e.get(k), type):
					return true
	return false


# -------------------------------------------------------------- estimates ---

## Evaluation context for a profile at a rank (rank_mult for automatically scaling abilities).
static func ctx_for(p: Dictionary, caster: Unit, target: Unit, rank: int) -> Dictionary:
	var ctx := {"caster": caster, "target": target, "team": caster.team, "rank": maxi(rank, 1), "i": 0}
	if bool(p.get("auto_rank", false)) and str(p.get("slot", "")) in ["q", "w", "e", "r"]:
		ctx.rank_mult = 1.0 + (0.5 if p.slot == "r" else 0.25) * (maxi(rank, 1) - 1)
	return ctx


## Damage the ability would deal to `target` after resistances (all of its hits landing).
static func damage(p: Dictionary, caster: Unit, target: Unit, rank: int) -> float:
	if p.is_empty() or p.dmg.is_empty() or not is_instance_valid(target) or not is_instance_valid(caster):
		return 0.0
	var key := Vector4i(int(p.get("uid", 0)), caster.net_id, target.net_id, rank)
	var m := _memo_get(key)
	if m >= 0.0:
		return m
	var ctx := ctx_for(p, caster, target, rank)
	var rm := float(ctx.get("rank_mult", 1.0))
	var total := 0.0
	for d in p.dmg:
		if not _conds_ok(d.conds, ctx):
			continue
		var a := Effects.num(d.amount, ctx, d.dflt) * rm
		for mm in d.mults:
			a *= Effects.num(mm, ctx, 1.0)
		total += maxf(a, 0.0) * mitigation(caster, target, Effects.damage_type(d.dtype, ctx, "magic"))
	_memo_set(key, total)
	return total


static func _now() -> float:
	return Game.world.time if Game.world != null else 0.0


static func _memo_get(key: Vector4i) -> float:
	var v = _memo.get(key)
	if v != null and _now() - v.x <= MEMO_TTL and _now() >= v.x:
		return v.y
	return -1.0


static func _memo_set(key: Vector4i, value: float) -> void:
	if _memo.size() > 6000:
		_memo.clear()
	_memo[key] = Vector2(_now(), value)


## Healing (or shielding) of a profile list ("self_heal", "ally_shield"...) on `target`.
static func amount(p: Dictionary, key: String, caster: Unit, target: Unit, rank: int) -> float:
	if p.is_empty() or not p.has(key) or not is_instance_valid(caster):
		return 0.0
	var ctx := ctx_for(p, caster, target if is_instance_valid(target) else caster, rank)
	var rm := float(ctx.get("rank_mult", 1.0))
	var total := 0.0
	for h in p[key]:
		if not _conds_ok(h.conds, ctx):
			continue
		var a := Effects.num(h.amount, ctx, h.dflt) * rm
		for m in h.mults:
			a *= Effects.num(m, ctx, 1.0)
		total += maxf(a, 0.0)
	return total * (1.0 + float(caster.stats.get("heal_power", 0.0)))


static func _conds_ok(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if Effects.num(c, ctx, 1.0) == 0.0:
			return false
	return true


## Multiplier from armor / magic resist (and damage amplifiers) for a hit of `dtype`.
static func mitigation(src: Unit, t: Unit, dtype: String) -> float:
	var m: float = float(src.stats.get("damage_mult", 1.0)) * float(t.stats.get("damage_taken_mult", 1.0))
	if dtype == "physical":
		return m * t._mitigation(t.stats.armor, src, true)
	if dtype == "magic":
		return m * t._mitigation(t.stats.magic_resist, src, false)
	return m


## Expected damage of one basic attack on `t` (crits averaged, on-hit procs and passives included).
static func attack_damage(c: Unit, t: Unit) -> float:
	if not is_instance_valid(c) or not is_instance_valid(t):
		return 0.0
	var a: Dictionary = c.attack_def
	if not (c is Champion) and not a.has("damage") and not a.has("damage_type"):
		# Minions, turrets and summons: plain physical hits.
		var raw: float = c.attack_damage_against(t) if c is Minion else c.stats.attack_damage
		return raw * (1.0 + float(c.stats.crit_chance) * (float(c.stats.crit_damage) - 1.0)) * mitigation(c, t, "physical")
	var key := Vector4i(-1, c.net_id, t.net_id, 0)
	var m := _memo_get(key)
	if m >= 0.0:
		return m
	var dmg: float = c.stats.attack_damage
	var actx := c.attack_ctx(t, a)
	if a.has("damage"):
		dmg = maxf(Effects.num(a.damage, actx, dmg), 0.0)
	elif c is Minion:
		dmg = c.attack_damage_against(t)
	dmg *= 1.0 + float(c.stats.crit_chance) * (float(c.stats.crit_damage) - 1.0)
	var total := dmg * mitigation(c, t, Effects.damage_type(a.get("damage_type"), actx, "physical"))
	if c is Champion:
		var kit := char_kit(c.def)
		for pr in kit.get("procs", []):
			total += damage(pr, c, t, c.level)
	_memo_set(key, total)
	return total


## Rough magic share of a champion's damage (for picking armor or magic resist).
static func magic_share(c: Champion) -> float:
	var kit := char_kit(c.def)
	var phys := float(c.stats.attack_damage) * 2.5
	var mag := 0.0
	for slot in ["q", "w", "e", "r"]:
		var p = kit.get(slot)
		if p == null:
			continue
		var ctx := ctx_for(p, c, c, maxi(int(c.ranks.get(slot, 1)), 1))
		for d in p.dmg:
			var a := Effects.num(d.amount, ctx, d.dflt)
			if Effects.damage_type(d.dtype, ctx, "magic") == "physical":
				phys += a
			else:
				mag += a
	return mag / maxf(phys + mag, 1.0)


## True if a champion heals itself or allies meaningfully (anti-heal items are worth it).
static func heals(c: Champion) -> bool:
	var kit := char_kit(c.def)
	for slot in kit:
		var p = kit[slot]
		if p is Dictionary and not p.get("ally_heal", []).is_empty():
			return true
	return float(c.stats.get("lifesteal", 0.0)) + float(c.stats.get("omnivamp", 0.0)) >= 0.15


## Basic abilities in the order to max them: curated for known characters, otherwise by damage
## (and crowd control / healing) per second of cooldown.
static func skill_priority(c: Champion) -> Array:
	var order = SKILL_ORDER.get(c.char_id)
	if order is Array:
		return order
	var kit := char_kit(c.def)
	var scored := []
	for slot in ["q", "w", "e"]:
		var p = kit.get(slot)
		var ab = c.def.abilities.get(slot)
		if p == null or ab == null:
			continue
		var ctx := {"caster": c, "target": c, "rank": 5}
		var cd := maxf(Effects.num(ab.cooldown, ctx, 6.0), 1.0)
		var v := 0.0
		for d in p.dmg:
			v += Effects.num(d.amount, ctx, d.dflt)
		v += float(p.cc_value) * 200.0 + (amount(p, "ally_heal", c, c, 5) + amount(p, "self_shield", c, c, 5)) * 0.6
		scored.append([v / cd, slot])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	return scored.map(func(x): return x[1])
