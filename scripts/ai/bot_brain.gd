class_name BotBrain
extends RefCounted
## The bot AI of one champion (host only). Three difficulties (see PRESETS):
## - brick: barely plays. Slow reactions, no aim prediction, random skills, items and fights.
## - normal: a competent player. Last hits, trades, leads its skillshots, respects turrets,
##   sometimes dodges, recalls on time and follows a sensible build.
## - scripting: frame-perfect. Reads every visible cast, projectile, dash, zone and telegraph and
##   dodges it (with dashes, blinks, parries, stasis or Flash when walking isn't enough),
##   orb-walks and kites at exact range, predicts last hits from every attack in flight, tracks
##   enemy cooldowns, computes kill windows from all abilities/items/summoners after
##   resistances, only dives when it's safe, hides behind minions from hooks, adapts its build
##   to the enemy team and plays the map (defends, pushes while enemies are dead, recalls on time).
## Abilities are understood through BotKit profiles, so custom characters work too.

const SLOTS := ["q", "w", "e", "r"]
const LEVELS := ["brick", "normal", "scripting"]
const LABELS := {"brick": "Brick", "normal": "Normal", "scripting": "Scripting"}
const PRESETS := {
	"brick": {
		"think": 0.9, "jitter": 0.6, "micro": false, "dodge": 0.0, "react": 1.0, "read": false, "lead": 0.0, "aim_error": 150.0,
		"hit_min": 0.0, "cast_chance": 0.3, "last_hit": "none", "kite": false, "retreat_hp": 0.12, "track_cds": false,
		"summoners": "none", "items": "potions", "build": "random", "skills": "random", "macro": false, "harass": 0.0,
		"fight": "naive", "margin": 1.0, "trade": 0.0, "recall_gold": 1.0e9, "spacing": false, "farm_spells": false,
	},
	"normal": {
		"think": 0.28, "jitter": 0.12, "micro": false, "dodge": 0.45, "react": 0.3, "read": false, "lead": 0.8, "aim_error": 25.0,
		"hit_min": 0.3, "cast_chance": 1.0, "last_hit": "basic", "kite": true, "retreat_hp": 0.3, "track_cds": false,
		"summoners": "hint", "items": "basic", "build": "curated", "skills": "curated", "macro": false, "harass": 1.1,
		"fight": "estimate", "margin": 1.2, "trade": 0.15, "recall_gold": 1300.0, "spacing": true, "farm_spells": true,
	},
	"scripting": {
		"think": 0.15, "jitter": 0.0, "micro": true, "dodge": 1.0, "react": 0.0, "read": true, "lead": 1.0, "aim_error": 0.0,
		"hit_min": 0.5, "cast_chance": 1.0, "last_hit": "predict", "kite": true, "retreat_hp": 0.18, "track_cds": true,
		"summoners": "smart", "items": "smart", "build": "adaptive", "skills": "curated", "macro": true, "harass": 0.75,
		"fight": "full", "margin": 1.0, "trade": 0.03, "recall_gold": 0.0, "spacing": true, "farm_spells": true,
	},
}
const TOWER_SHARE := {"melee": 0.45, "ranged": 0.70, "siege": 0.14, "super": 0.07}

var me: Champion
var world: World
var difficulty := "normal"
var cfg: Dictionary = {}
var kit: Dictionary = {}

# perception (refreshed every decision)
var foes: Array = []          # visible enemy champions
var friends: Array = []       # living allied champions (not me)
var foe_units: Array = []     # visible enemy minions and summons
var ally_units: Array = []    # allied minions and summons
var foe_towers: Array = []    # living enemy structures
var ally_towers: Array = []
var seen := {}                # enemy champion net_id -> {pos, t} (last time we saw it)

# decisions
var mode := "lane"
var focus: Champion = null    # the enemy champion we fight
var atk: Unit = null          # what we attack whenever we can
var stand := Vector2.INF      # where we want to be (INF: chase `atk` / stay)
var lane_i := 0
var lane := PackedVector2Array()
var lane_cum := PackedFloat32Array()
var plan: Array = []
var think_t := 0.0

var _lane_for := -1
var _planned := false
var _push := false
var _dodge_dir := Vector2.ZERO
var _noticed := {}            # threat key -> {t, go}: when we first saw it and whether we react to it
var _traps := {}              # cast id -> {pos, r, until}: enemy traps we saw being placed
var _pinfo := {}              # projectile net_id -> {danger, explode}
var _rdanger := {}            # cast id -> danger
var _thr: Array = []
var _thr_time := -1.0
var _dmg_log: Array = []      # Vector2(time, damage taken)
var _last_ehp := -1.0
var _cache := {}              # per-decision memo (bursts, ranges...)
var _steroids := {}           # Vector3i(caster, profile, rank) -> [time, multipliers]
var _parts_memo := {}         # _parts of other champions, reused for 0.3s
var _gc_t := 0.0


static var cost_usec := 0
     # total time spent in bot AI (read by the AI test harness)


static func level_name(v) -> String:
	var s := str(v).to_lower()
	return s if PRESETS.has(s) else "normal"


func _init(c: Champion, level: String) -> void:
	me = c
	world = c.world
	difficulty = level_name(level)
	cfg = PRESETS[difficulty]
	kit = BotKit.char_kit(c.def)
	lane_i = c.bot_lane
	think_t = randf() * 0.3


# ------------------------------------------------------------------- tick ---

func tick(delta: float) -> void:
	if me.dead or world == null:
		return
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	cost_usec += Time.get_ticks_usec() - t0


func _tick(delta: float) -> void:
	_track_damage()
	if me.casting != null:
		# A channel (Teleport) is cancelled when something dangerous shows up.
		if me.casting.has("summoner") and difficulty != "brick" and (_foes_near(me.global_position, 900.0) > 0 or _taken(0.5) > 0.0):
			me.use_summoner(int(me.casting.summoner), me.global_position, 0)
		return
	if me.forced != null:
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = float(cfg.think) + randf() * float(cfg.jitter)
		# Nothing around: decide half as often (dodging and attacks stay frame-perfect).
		if mode in ["lane", "heal", "recall"] and _foes_near(me.global_position, 1600.0) == 0 and _thr.is_empty():
			think_t *= 2.0
		_think()
	if cfg.micro:
		_micro()
	elif cfg.dodge > 0.0 and me.recall_timer <= 0.0:
		var was := _dodge_dir != Vector2.ZERO
		if not _dodge() and was and _dodge_dir == Vector2.ZERO:
			me.move_dir = Vector2.ZERO


func dead_tick(_delta: float) -> void:
	_level_up()
	_shop()
	mode = "lane"
	focus = null
	atk = null
	stand = Vector2.INF


func _think() -> void:
	_cache.clear()
	_gc()
	_perceive()
	_level_up()
	if me.can_shop():
		_shop()
	_choose_lane()
	_reflexes()
	if me.recall_timer > 0.0:
		if _foes_near(me.global_position, 1100.0) > 0 or _danger_here() > 0.05:
			me._cancel_recall()
		else:
			return
	if not cfg.micro and _dodge_dir != Vector2.ZERO:
		return
	_decide()
	match mode:
		"heal":
			atk = null
			stand = world.map.spawn_point(me.team)
		"retreat":
			_do_retreat()
		"fight", "trade":
			_do_fight()
		"recall":
			_do_recall()
		"roam":
			_do_roam()
		_:
			_do_lane()
	_use_summoners()
	if cfg.items == "basic":
		_basic_items()
	if not cfg.micro:
		_apply()


func _gc() -> void:
	_gc_t -= float(cfg.think)
	if _gc_t > 0.0:
		return
	_gc_t = 5.0
	var now := world.time
	for k in _noticed.keys():
		if now - float(_noticed[k].t) > 8.0:
			_noticed.erase(k)
	for k in _traps.keys():
		if now > float(_traps[k].until) or not _trap_exists(_traps[k].pos):
			_traps.erase(k)
	_pinfo.clear()
	_parts_memo.clear()
	_steroids.clear()
	if _rdanger.size() > 200:
		_rdanger.clear()


# ------------------------------------------------------------- perception ---

func _perceive() -> void:
	foes.clear()
	friends.clear()
	foe_units.clear()
	ally_units.clear()
	foe_towers.clear()
	ally_towers.clear()
	for u in world.units:
		if u.dead or u == me:
			continue
		if u.is_structure:
			if u.team == me.team:
				ally_towers.append(u)
			else:
				foe_towers.append(u)
		elif u is Champion:
			if u.team == me.team:
				friends.append(u)
			elif world.can_see(u, me.team):
				foes.append(u)
				seen[u.net_id] = {"pos": u.global_position, "t": world.time}
		elif u is Dummy or u.is_ward:
			continue
		elif u.team == me.team:
			ally_units.append(u)
		elif u.targetable() and world.can_see(u, me.team):
			foe_units.append(u)


func _track_damage() -> void:
	var ehp := me.hp + me.shield
	if _last_ehp >= 0.0 and ehp < _last_ehp - 0.5:
		_dmg_log.append(Vector2(world.time, _last_ehp - ehp))
	_last_ehp = ehp
	while not _dmg_log.is_empty() and _dmg_log[0].x < world.time - 3.0:
		_dmg_log.pop_front()


## Damage taken in the last `window` seconds.
func _taken(window: float) -> float:
	var s := 0.0
	for v in _dmg_log:
		if v.x >= world.time - window:
			s += v.y
	return s


func _valid(u) -> bool:
	return u != null and is_instance_valid(u) and not u.dead


func _foes_near(p: Vector2, r: float) -> int:
	var n := 0
	for e in foes:
		if e.global_position.distance_to(p) <= r:
			n += 1
	return n


func _nearest_foe() -> Champion:
	var best: Champion = null
	var bd := INF
	for e in foes:
		var d := me.global_position.distance_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _alive(team_of_me: bool) -> int:
	var n := 0
	for c in world.champions.values():
		if not c.dead and (c.team == me.team) == team_of_me:
			n += 1
	return n


func _at_fountain() -> bool:
	return me.global_position.distance_to(world.map.spawn_point(me.team)) < world.map.fountain_radius


func _is_turret(t) -> bool:
	return t.is_structure and not t.is_nexus and not t.is_inhibitor and t.stats.attack_damage > 0.0


## Seconds of crowd control (or channel/cast) that keep `t` from moving.
func _cc_left(t: Unit) -> float:
	var left := 0.0
	for s in t.statuses:
		if s.type in ["stun", "root", "stasis"]:
			left = maxf(left, float(s.time))
	if t.forced != null and not t.forced.dash:
		left = maxf(left, float(t.forced.time))
	if t is Champion:
		if t.casting != null:
			left = maxf(left, float(t.casting.time))
		if t.recall_timer > 0.0:
			left = maxf(left, 0.35)
	for s in t.statuses:
		if s.type == "buff" and s.mult.has("move_speed") and float(s.mult.move_speed) <= 0.01:
			left = maxf(left, float(s.time))
	return left


## Where `t` will be in `dt` seconds if it keeps doing what it does.
func _predict(t: Unit, dt: float) -> Vector2:
	if dt <= 0.0:
		return t.global_position
	var stuck := _cc_left(t)
	if stuck >= dt:
		return t.global_position
	if t.forced != null:
		return t.global_position + t.forced.vel * minf(float(t.forced.time), dt)
	var p: Vector2 = t.global_position + t.velocity * (dt - stuck)
	if world.map.is_wall(p):
		p = t.global_position + t.velocity * (dt - stuck) * 0.4
	return world.map.clamp_inside(p)


# ------------------------------------------------------------------ lanes ---

func _choose_lane() -> void:
	var n := world.map.lane_count()
	if n == 0:
		return
	var want := posmod(me.bot_lane, n)
	if cfg.macro:
		# Mid game: group up where we pushed furthest (fewest enemy structures left) to siege together.
		var inhib_down := false
		var left := []
		left.resize(n)
		left.fill(0)
		for s in world.structures:
			if s.team != me.team and s.team <= 1:
				if s.dead and s.is_inhibitor:
					inhib_down = true
				elif not s.dead and s.lane >= 0 and s.lane < n:
					left[s.lane] += 1
		if (world.time > 840.0 or inhib_down) and n > 1:
			var best: int = want
			for l in n:
				if left[l] < left[best]:
					best = l
			want = best
		var threatened := _threatened_structure()
		if threatened != null and threatened.lane >= 0 and threatened.lane < n:
			want = threatened.lane
	_set_lane(want)


func _set_lane(i: int) -> void:
	if i == _lane_for:
		return
	_lane_for = i
	lane_i = i
	lane = world.map.lane(me.team, i)
	lane_cum = PackedFloat32Array()
	var acc := 0.0
	for k in lane.size():
		if k > 0:
			acc += lane[k].distance_to(lane[k - 1])
		lane_cum.append(acc)


## (progress along my lane from my base, distance from the lane)
func _lp(p: Vector2) -> Vector2:
	var bd := INF
	var bs := 0.0
	for k in range(1, lane.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, lane[k - 1], lane[k])
		var d := p.distance_to(q)
		if d < bd:
			bd = d
			bs = lane_cum[k - 1] + lane[k - 1].distance_to(q)
	return Vector2(bs, bd)


func _lane_at(s: float) -> Vector2:
	s = clampf(s, 0.0, lane_cum[lane_cum.size() - 1])
	for k in range(1, lane.size()):
		if s <= lane_cum[k]:
			return lane[k - 1].lerp(lane[k], (s - lane_cum[k - 1]) / maxf(lane_cum[k] - lane_cum[k - 1], 0.001))
	return lane[lane.size() - 1]


func _lane_info() -> Dictionary:
	var info := {"ally": -INF, "foe": INF, "tower": 300.0, "ally_n": 0, "foe_n": 0}
	for u in ally_units:
		if u is Minion:
			var pr := _lp(u.global_position)
			if pr.y < 650.0:
				info.ally = maxf(info.ally, pr.x)
				info.ally_n += 1
	for u in foe_units:
		if u is Minion:
			var pr := _lp(u.global_position)
			if pr.y < 650.0:
				info.foe = minf(info.foe, pr.x)
				info.foe_n += 1
	for t in ally_towers:
		if _is_turret(t):
			var pr := _lp(t.global_position)
			if pr.y < 900.0:
				info.tower = maxf(info.tower, pr.x)
	return info


## An allied structure enemies are attacking right now (to defend it).
func _threatened_structure() -> Unit:
	var best: Unit = null
	var bs := 0.0
	for s in ally_towers:
		if s.is_nexus and s.lane < 0:
			continue
		var champs := _foes_near(s.global_position, 1000.0)
		var minions := 0
		for u in foe_units:
			if u.global_position.distance_to(s.global_position) < 800.0:
				minions += 1
		var score := champs * 3.0 + minions * 0.5
		if score >= 3.0 and score > bs and world.time - s.hurt_t < 3.0:
			bs = score
			best = s
	return best

# -------------------------------------------------------------- estimates ---

## Whether we know this champion's cooldowns (our own and allies' always; enemies' only when
## the difficulty tracks them - otherwise assume everything is ready).
func _knows_cds(c: Champion) -> bool:
	return c == me or c.team == me.team or cfg.track_cds


func _rank(c: Champion, slot: String) -> int:
	return int(c.ranks.get(slot, 0))


func _ready_slot(c: Champion, slot: String) -> bool:
	if _rank(c, slot) <= 0 or c.def.abilities.get(slot) == null:
		return false
	return not _knows_cds(c) or float(c.cooldowns.get(slot, 0.0)) <= 0.0


## Effective range of an ability profile for caster `c`.
func _reach_of(pr: Dictionary, c: Champion, rank: int) -> float:
	var key := Vector3i(1, c.net_id, int(pr.get("uid", 0)))
	if _cache.has(key):
		return _cache[key]
	var ctx := BotKit.ctx_for(pr, c, c, rank)
	var rng := Effects.num(pr.range, ctx, 700.0)
	var r := rng
	match pr.shape:
		"projectile":
			r = Effects.num(pr.prange, ctx, rng) if pr.prange != null else rng
		"area", "cone", "zone":
			r = float(pr.radius) if pr.at_self or pr.targeting == "self" else rng + float(pr.radius) * 0.5
		"beam":
			r = float(pr.length)
		"dash":
			r = Effects.num(pr.dash.get("distance"), ctx, 350.0) + maxf(float(pr.land_radius), c.attack_reach(me) * 0.5)
		"blink":
			r = rng + c.stats.attack_range
		"":
			r = c.attack_reach(me) if pr.targeting == "self" else rng
	_cache[key] = r
	return r


## Distance `c` can close instantly with ready dashes/blinks (and Flash when we track it).
func _mobility(c: Champion) -> float:
	var key := Vector3i(2, c.net_id, 0)
	if _cache.has(key):
		return _cache[key]
	var ck := BotKit.char_kit(c.def)
	var best := 0.0
	for slot in SLOTS:
		var pr = ck.get(slot)
		if pr == null or not pr.mobility or pr.dash_back or not _ready_slot(c, slot):
			continue
		best = maxf(best, _mob_dist(pr, c, _rank(c, slot)))
	if c != me and _knows_cds(c):
		for i in c.summoners.size():
			if str(c.summoners[i]) == "flash" and float(c.sum_cd[i]) <= 0.0:
				best = maxf(best, 400.0)
	_cache[key] = best
	return best


func _mob_dist(pr: Dictionary, c: Champion, rank: int) -> float:
	var ctx := BotKit.ctx_for(pr, c, c, rank)
	if not pr.dash.is_empty():
		return Effects.num(pr.dash.get("distance"), ctx, 350.0)
	return Effects.num(pr.range, ctx, 400.0)


## How close `e` can get to us and still hurt us right away.
func _threat_range(e: Champion) -> float:
	return e.attack_reach(me) + _mobility(e) + 40.0


## How much `e` scares us: its short burst relative to our health.
func _threat_weight(e: Champion) -> float:
	return clampf(_burst(e, me, 2.0) / maxf(me.hp + me.shield, 1.0), 0.2, 3.0)


## Attack speed and attack damage multipliers from a ready self-buff (Night Vigil, Goose Mode).
func _steroid(pr: Dictionary, c: Champion, rank: int) -> Vector2:
	var key := Vector3i(c.net_id, int(pr.get("uid", 0)), rank)
	var old = _steroids.get(key)
	if old != null and world.time - float(old[0]) < 1.0:
		return old[1]
	var out := Vector2.ONE
	var ctx := BotKit.ctx_for(pr, c, c, rank)
	for b in pr.buffs:
		var add: Dictionary = b.add
		var mul: Dictionary = b.multiply
		if add.has("bonus_attack_speed"):
			var bonus := float(c.stats.bonus_attack_speed)
			out.x *= (1.0 + bonus + Effects.num(add.bonus_attack_speed, ctx, 0.0)) / maxf(1.0 + bonus, 0.1)
		if mul.has("attack_damage"):
			out.y *= Effects.num(mul.attack_damage, ctx, 1.0)
		if add.has("attack_damage"):
			out.y *= 1.0 + Effects.num(add.attack_damage, ctx, 0.0) / maxf(c.stats.attack_damage, 1.0)
	_steroids[key] = [world.time, out]
	return out


## Damage champion `c` can deal to `t` within `window` seconds: ready abilities that can reach
## (after resistances), basic attacks (with ready steroids), and Ignite-like summoners.
func _burst(c: Champion, t: Unit, window: float) -> float:
	var pt := _parts(c, t)
	var d := c.global_position.distance_to(t.global_position)
	var reach_extra: float = c.stats.move_speed * window * 0.4 + _mobility(c)
	var total := 0.0
	for a in pt.abil:
		if d <= a.x + reach_extra:
			total += a.y
	var boost: Vector2 = pt.boost
	var gap := maxf(d - c.attack_reach(t), 0.0)
	var walk: float = gap / maxf(c.stats.move_speed - t.stats.move_speed * 0.6, 80.0)
	# Hard crowd control buys free hits: the target can't fight back or leave meanwhile.
	var swings: float = (maxf(window - walk, 0.0) + minf(float(pt.cc), window * 0.5)) * c.stats.attack_speed * boost.x + (0.6 if gap <= 0.0 else 0.0)
	total += float(pt.hit) * boost.y * swings
	total += float(pt.ign) * clampf(window / 5.0, 0.0, 1.0)
	return total


## The window-independent pieces of _burst, once per decision: [reach, damage] of each ready,
## affordable ability (recasts included), steroid multipliers, attack damage and Ignite.
func _parts(c: Champion, t: Unit) -> Dictionary:
	var key := Vector3i(3, c.net_id, t.net_id)
	if _cache.has(key):
		return _cache[key]
	# Other champions' numbers are reused for a moment (their state changes slowly).
	var old = _parts_memo.get(key)
	if c != me and old != null and world.time - float(old.t) < 0.3:
		_cache[key] = old
		return old
	var ck := BotKit.char_kit(c.def)
	var mana: float = c.mana
	var abil: Array[Vector2] = []
	var boost := Vector2.ONE
	var cc := 0.0
	var hit := BotKit.attack_damage(c, t)
	for slot in SLOTS:
		var pr = ck.get(slot)
		if pr == null or not _ready_slot(c, slot):
			continue
		var r := _rank(c, slot)
		var cost := c.ability_cost(c.def.abilities.get(slot))
		if c.uses_mana() and pr.cost_type != "health" and cost > mana:
			continue
		mana -= cost
		var dmg := BotKit.damage(pr, c, t, r) * _land_chance(pr, t)
		var rc = ck.get(slot + "+")
		if rc != null and not rc.dmg.is_empty():
			dmg += BotKit.damage(rc, c, t, r) * 2.0
		cc += (float(pr.cc.get("stun", 0.0)) + float(pr.cc.get("root", 0.0)) * 0.6) * _land_chance(pr, t)
		if pr.steroid:
			boost *= _steroid(pr, c, r)
			# A buff that replaces the basic attack (Night Vigil's pistol) changes the hit itself.
			for b in pr.buffs:
				if b.attack is Dictionary and b.attack.has("damage"):
					var bctx := BotKit.ctx_for(pr, c, t, r)
					var dt := Effects.damage_type(b.attack.get("damage_type"), bctx, "physical")
					hit = maxf(Effects.num(b.attack.damage, bctx, 0.0), 0.0) * BotKit.mitigation(c, t, dt)
					boost.y = 1.0
		if dmg > 0.0:
			abil.append(Vector2(_reach_of(pr, c, r), dmg))
	var pt := {"abil": abil, "boost": boost, "hit": hit, "ign": _ignite(c, t, 5.0), "cc": cc, "t": world.time}
	_cache[key] = pt
	_parts_memo[key] = pt
	return pt


## Share of a skillshot's damage expected to land on `t`: dodgeable shapes are discounted by how
## well `t` dodges (we know our own skill and other bots' difficulty; players are assumed decent).
func _land_chance(pr: Dictionary, t: Unit) -> float:
	var dodgeable: bool = pr.shape in ["projectile", "beam"] or (pr.shape in ["area", "zone", "trap"] and not pr.at_self and pr.targeting != "self")
	if not dodgeable or (pr.shape == "projectile" and pr.homing):
		return 1.0
	var skill := 0.35
	if t is Champion and t.is_bot and t.brain != null:
		skill = float(t.brain.cfg.dodge) * 0.65
	if _cc_left(t) > 0.5:
		skill = 0.0
	return 1.0 - skill


## Ready damaging unit-targeted summoner (Ignite) damage over `window`.
func _ignite(c: Champion, t: Unit, window: float) -> float:
	if not t.is_champion:
		return 0.0
	var total := 0.0
	for i in c.summoners.size():
		var sp = c.summoner_def(i)
		if sp == null or (_knows_cds(c) and float(c.sum_cd[i]) > 0.0) or str(sp.active.targeting) != "unit":
			continue
		var pr := BotKit.summoner_kit(sp.active, sp.id)
		if pr.damage and c.global_position.distance_to(t.global_position) < Effects.num(pr.range, {"caster": c}, 600.0) + 300.0:
			total += BotKit.damage(pr, c, t, c.level) * (clampf(window / 5.0, 0.0, 1.0) if pr.dot else 1.0)
	return total


func _tower_reach(t: Unit) -> float:
	return t.stats.attack_range + t.radius + me.radius


func _tower_shot(t: Unit) -> float:
	return t.stats.attack_damage * BotKit.mitigation(t, me, "physical")


## Tower damage against one of our minions/summons (towers deal a share of a minion's health).
func _tower_vs(t: Unit, u: Unit) -> float:
	if u is Minion:
		return u.stats.max_hp * float(TOWER_SHARE.get(u.minion_type, 0.45))
	return maxf(t.stats.attack_damage, u.stats.max_hp * 0.45) * BotKit.mitigation(t, u, "physical")


## Seconds the turret stays busy with our minions and summons before it would pick a champion.
func _tower_busy(t: Unit) -> float:
	if t.attack_target == me:
		return 0.0
	var key := Vector3i(4, t.net_id, 0)
	if _cache.has(key):
		return _cache[key]
	var shots := 0.0
	for u in ally_units:
		if u.global_position.distance_to(t.global_position) <= t.stats.attack_range + t.radius + u.radius:
			shots += ceilf(u.hp / maxf(_tower_vs(t, u), 1.0))
	var busy := shots / maxf(t.stats.attack_speed, 0.1)
	_cache[key] = busy
	return busy


## True if standing at `p` gets us shot by an enemy turret.
func _turret_danger(p: Vector2, margin := 20.0) -> bool:
	for t in _hot_turrets():
		if p.distance_to(t[0]) <= t[1] + margin:
			return true
	return false


## Enemy turrets near us that would shoot us (targeting us, or not busy with our minions).
func _hot_turrets() -> Array:
	var key := Vector3i(9, 0, 0)
	if _cache.has(key):
		return _cache[key]
	var out := []
	for t in foe_towers:
		if _is_turret(t) and t.global_position.distance_to(me.global_position) < 2600.0 and (t.attack_target == me or _tower_busy(t) < 1.5):
			out.append([t.global_position, _tower_reach(t)])
	_cache[key] = out
	return out


func _under_foe_turret(p: Vector2) -> Unit:
	for t in foe_towers:
		if _is_turret(t) and p.distance_to(t.global_position) <= _tower_reach(t):
			return t
	return null


## Damage we could take in the next `window` seconds from everything that can reach us.
func _threat_on_me(window: float) -> float:
	var key := Vector3i(5, int(window * 10.0), 0)
	if _cache.has(key):
		return _cache[key]
	var total := 0.0
	for e in foes:
		if e.global_position.distance_to(me.global_position) <= _threat_range(e) + e.stats.move_speed * window * 0.5:
			total += _burst(e, me, window)
	for t in foe_towers:
		if _is_turret(t) and (t.attack_target == me or (me.global_position.distance_to(t.global_position) <= _tower_reach(t) and _tower_busy(t) < window)):
			total += _tower_shot(t) * maxf(window * t.stats.attack_speed, 1.0) * 1.3
	for u in foe_units:
		if u.attack_target == me:
			total += BotKit.attack_damage(u, me) * u.stats.attack_speed * window
	_cache[key] = total
	return total


func _killable(t: Champion, window := 3.0) -> bool:
	return _burst(me, t, window) >= (t.hp + t.shield) * float(cfg.margin)


## A fight under the enemy turret is only worth it if we kill fast and survive the shots.
func _dive_ok(t: Unit) -> bool:
	var tw := _under_foe_turret(t.global_position)
	if tw == null:
		return true
	if difficulty == "brick":
		return randf() < 0.5
	var shots: float = 2.5 * tw.stats.attack_speed
	var tower: float = _tower_shot(tw) * shots * (1.0 + 0.15 * shots)
	if _tower_busy(tw) > 2.5:
		tower *= 0.3
	return _burst(me, t, 2.0) >= (t.hp + t.shield) * 1.1 and me.hp + me.shield > tower + _burst(t, me, 2.5) * 1.1


# -------------------------------------------------------------- decisions ---

func _decide() -> void:
	var prev := mode
	if _at_fountain() and _foes_near(me.global_position, 1300.0) == 0 \
			and (me.hp < me.stats.max_hp * 0.9 or (me.uses_mana() and me.mana < me.stats.max_mana * 0.7)):
		mode = "heal"
		return
	focus = _pick_focus()
	if _should_retreat():
		var stuck := _cornered()
		if stuck != null and not _at_fountain():
			focus = stuck
			mode = "fight"
			return
		mode = "retreat"
		return
	if focus != null:
		var f := _fight_eval(focus, prev == "fight", prev == "trade")
		if f == "kill":
			mode = "fight"
			return
		if f == "trade":
			mode = "trade"
			return
	if _should_recall():
		mode = "recall"
		return
	mode = "roam" if world.map.lane_count() == 0 else "lane"


func _pick_focus() -> Champion:
	var best: Champion = null
	var bs := -INF
	for e in foes:
		if not e.targetable() or e.has_status("stasis"):
			continue
		var d := me.global_position.distance_to(e.global_position)
		if d > (650.0 if cfg.fight == "naive" else 1500.0):
			continue
		var dps: float = BotKit.attack_damage(me, e) * me.stats.attack_speed + 1.0
		var s: float = -(e.hp + e.shield) / dps - d / 400.0
		if e.attack_target == me:
			s += 2.0
		if e == focus:
			s += 1.0
		if s > bs:
			bs = s
			best = e
	return best


func _should_retreat() -> bool:
	var frac: float = me.hp / me.stats.max_hp
	if cfg.fight == "naive":
		return frac < float(cfg.retreat_hp) and (not foes.is_empty() or _taken(2.0) > 0.0)
	if frac < float(cfg.retreat_hp) and (_foes_near(me.global_position, 1400.0) > 0 or _taken(2.0) > 0.0):
		return not (focus != null and _killable(focus, 1.5) and _threat_on_me(1.5) < me.hp + me.shield)
	var threat := _threat_on_me(2.5)
	if threat >= (me.hp + me.shield) * 0.9:
		# Only flee from a real engage (someone in range or hitting us) - otherwise spacing is enough.
		var engaged := _taken(1.0) > 0.0
		for e in foes:
			if e.global_position.distance_to(me.global_position) <= e.attack_reach(me) + 60.0:
				engaged = true
		if engaged or threat >= (me.hp + me.shield) * 1.6:
			return not (focus != null and _fight_eval(focus, mode == "fight", false) == "kill")
	return false


## Whether to all-in `t`: our side's damage (abilities, attacks, summoners, our turret) against
## its health, and the enemies' damage against ours, over the next seconds.
func _fight_ok(t: Champion, committed: bool) -> bool:
	return _fight_eval(t, committed, false) == "kill"


## "kill": all-in, we kill `t` and survive. "trade": a short exchange that costs them clearly
## more (as a share of max health) than it costs us - it ends by itself once our burst is spent.
## "": stay out. Our side counts allies' and our turret's damage; theirs only spreads when an
## ally stands in front of us.
func _fight_eval(t: Champion, committed: bool, trading: bool) -> String:
	if cfg.fight == "naive":
		var ok: bool = me.global_position.distance_to(t.global_position) < 650.0 and me.hp / me.stats.max_hp >= t.hp / t.stats.max_hp - 0.1
		return "kill" if ok else ""
	if not t.targetable() or t.has_status("invulnerable"):
		return ""
	var key := Vector3i(10, t.net_id, int(committed) * 2 + int(trading))
	if _cache.has(key):
		return _cache[key]
	var out := ""
	if _dive_ok(t):
		# A target far from its turret can be chased down: give the kill more time.
		var safe_d := INF
		for tw in foe_towers:
			if _is_turret(tw):
				safe_d = minf(safe_d, t.global_position.distance_to(tw.global_position) - _tower_reach(tw))
		var window := 3.0 + (clampf((safe_d - 300.0) / maxf(t.stats.move_speed, 100.0), 0.0, 3.0) if cfg.fight == "full" else 0.0)
		var ours := _burst(me, t, window)
		var short := _burst(me, t, 2.0)
		for a in friends:
			if a.global_position.distance_to(t.global_position) < 1300.0:
				ours += _burst(a, t, window) * 0.8
				short += _burst(a, t, 2.0) * 0.8
		for tw in ally_towers:
			if _is_turret(tw) and tw.global_position.distance_to(t.global_position) < tw.stats.attack_range + tw.radius + t.radius:
				var tower: float = tw.stats.attack_damage * BotKit.mitigation(tw, t, "physical") * tw.stats.attack_speed
				ours += tower * window
				short += tower * 2.0
		var theirs := 0.0
		var theirs_short := 0.0
		for e in foes:
			if e.global_position.distance_to(t.global_position) < 1400.0 or e.global_position.distance_to(me.global_position) < _threat_range(e) + 300.0:
				theirs += _burst(e, me, window)
				theirs_short += _burst(e, me, 2.0)
		# Enemies hit whoever stands in front: their damage only spreads if an ally is closer to them.
		var front := 1.0
		for a in friends:
			if a.global_position.distance_to(me.global_position) < 1100.0 \
					and a.global_position.distance_to(t.global_position) < me.global_position.distance_to(t.global_position) - 150.0:
				front = 0.65
		theirs *= front
		theirs_short *= front
		var margin: float = float(cfg.margin) * (0.8 if committed else 1.0)
		var t_ehp := t.hp + t.shield
		var my_ehp := me.hp + me.shield
		if ours >= t_ehp * margin and theirs < my_ehp * 0.85:
			out = "kill"
		elif float(cfg.trade) > 0.0 and _under_foe_turret(t.global_position) == null and theirs_short < my_ehp * 0.55:
			var edge: float = short / t.stats.max_hp - theirs_short / me.stats.max_hp
			if edge >= float(cfg.trade) * (0.6 if trading else 1.0) and short >= t.stats.max_hp * 0.1:
				out = "trade"
	_cache[key] = out
	return out


func _should_recall() -> bool:
	if world.map.lane_count() == 0 or _at_fountain():
		return false
	var frac: float = me.hp / me.stats.max_hp
	if difficulty == "brick":
		return frac < 0.15
	var need: bool = frac < 0.35 or (me.uses_mana() and me.mana < me.stats.max_mana * 0.15)
	if need:
		return true
	if mode == "recall" and me.gold > 400.0:
		return true
	if difficulty == "normal":
		return me.gold >= float(cfg.recall_gold)
	# Scripting: go shopping when the next purchase is meaningful (we back off to safety first).
	if _alive(false) == 0 and frac > 0.4:
		return false
	var cost := _next_cost()
	if cost <= 0:
		return false
	return me.gold >= cost or me.gold >= 1250.0


func _next_cost() -> int:
	for id in plan:
		if Game.items.has(id) and not me.has_item(id):
			return int(me.price_for(id).cost)
	return 0

## Whether stepping to `p` is reasonable: no enemy champion there could burst most of our
## health (from its threat range), and no turret shoots us.
func _spot_safe(p: Vector2) -> bool:
	if _turret_danger(p, 0.0):
		return false
	if cfg.fight == "naive":
		return true
	var danger := 0.0
	for e in foes:
		if p.distance_to(e.global_position) <= _threat_range(e):
			danger += _burst(e, me, 2.5)
	return danger < (me.hp + me.shield) * (0.6 if cfg.read else 0.8)


## The enemy champion we can't get away from (in its range and at least as fast, and we have no
## ready dash or speed boost) - then fighting back beats dying with our back turned.
func _cornered() -> Champion:
	if cfg.fight == "naive":
		return null
	for c in _usable():
		if c.prof.escape and str(c.prof.dash.get("to", "")) != "target":
			return null
	var best: Champion = null
	var bd := INF
	for e in foes:
		if not e.targetable():
			continue
		var d := me.global_position.distance_to(e.global_position)
		var to_me: Vector2 = (me.global_position - e.global_position).normalized()
		var engaging: bool = e.attack_target == me or e.velocity.dot(to_me) > e.stats.move_speed * 0.5 or (_taken(0.6) > 0.0 and d < 600.0)
		var faster: bool = e.stats.move_speed >= me.stats.move_speed * 0.95 or _cc_left(me) > 0.3
		var reach: float = e.attack_reach(me) + 60.0 + (minf(_mobility(e), 450.0) if faster else 0.0)
		if engaging and d <= reach and (faster or d <= e.attack_reach(me) + 20.0) and d < bd:
			bd = d
			best = e
	return best


# -------------------------------------------------------------- behaviors ---

func _do_lane() -> void:
	if lane.is_empty():
		_do_roam()
		return
	var info := _lane_info()
	_push = _want_push(info)
	var anchor := _farm_anchor(info)
	var want := {}
	atk = null
	var lh := _last_hit()
	var poke := _poke_target()
	var siege: Unit = null
	var direct := false
	if lh.now != null:
		atk = lh.now
		anchor = _attack_spot(lh.now)
		direct = true
	elif lh.soon != null:
		anchor = _attack_spot(lh.soon)
		direct = true
	elif poke != null and _harass_ok(poke):
		atk = poke
		anchor = _kite_anchor(poke)
		want = {"unit": poke, "lo": me.stats.attack_range * 0.75, "hi": me.stats.attack_range - 15.0, "champ": true}
	else:
		siege = _siege_target()
		if siege != null and _siege_safe(siege):
			atk = siege
			anchor = _attack_spot(siege)
			direct = true
		elif _push or cfg.last_hit == "none":
			atk = _push_target()
			if atk != null:
				anchor = _attack_spot(atk)
				direct = true
	if poke != null:
		_cast_best("poke", poke)
	if siege != null and atk == siege:
		_cast_best("siege", siege)
	elif cfg.farm_spells and _push and foes.is_empty():
		_cast_best("farm", null)
	_travel(anchor)
	if direct:
		stand = anchor
	else:
		want.fear = 0.5 + 0.8 * (1.0 - me.hp / me.stats.max_hp)
		stand = _choose_spot(anchor, want)


## Push the wave when it's free: no enemy champion around, we outnumber them, the enemy laner is
## too hurt to contest, or their wave is hitting our turret.
func _want_push(info: Dictionary) -> bool:
	if cfg.last_hit == "none":
		return true
	if cfg.macro and _valid(focus) and focus.hp < focus.stats.max_hp * 0.35:
		return true
	if _foes_near(me.global_position, 1500.0) == 0:
		return true
	if cfg.macro and _alive(false) < _alive(true):
		return true
	return info.foe < INF and info.foe < info.tower + 400.0


## Where to stand in lane: at attack range behind the minion clash, or by our turret.
func _farm_anchor(info: Dictionary) -> Vector2:
	var my_r: float = me.stats.attack_range + me.radius + 15.0
	var s: float
	if info.foe < INF:
		if me.attack_def.ranged:
			s = info.foe - my_r * 0.92
		else:
			s = info.foe - 90.0
		if info.ally > -INF:
			s = minf(s, info.ally + (0.0 if me.attack_def.ranged else 60.0))
	elif info.ally > -INF:
		s = info.ally - 140.0
	else:
		s = info.tower - 180.0
	return _lane_at(maxf(s, 200.0))


## Last-hit choice: a minion our next attack kills ("now") or one that will be killable after
## the next swing ("soon", so we wait next to it instead of hitting something else).
func _last_hit() -> Dictionary:
	var out := {"now": null, "soon": null}
	if cfg.last_hit == "none":
		return out
	var best_now := INF
	var best_soon := INF
	var period := 1.0 / maxf(me.stats.attack_speed, 0.1)
	var spd := maxf(float(me.attack_def.speed), 100.0)
	for m in foe_units:
		if not (m is Minion):
			continue
		var d := me.global_position.distance_to(m.global_position)
		if d > 1100.0:
			continue
		var reach := me.attack_reach(m)
		var spot: Vector2 = m.global_position + (me.global_position - m.global_position).normalized() * minf(reach - 20.0, d)
		if not _spot_safe(spot):
			continue
		var walk := maxf(d - reach, 0.0) / maxf(me.stats.move_speed, 50.0)
		var fly := minf(d, reach) / spd if me.attack_def.ranged else 0.0
		var t_land := maxf(walk, me.attack_cd) + _windup(me) + fly
		if me.winding_attack == m:
			t_land = me.windup_left + fly
		var hit := BotKit.attack_damage(me, m)
		var hp := _hp_at(m, t_land)
		if hp <= 0.0:
			continue
		if hp <= hit:
			var s := t_land - float(m.gold_value) * 0.02
			if s < best_now:
				best_now = s
				out.now = m
		elif cfg.last_hit == "predict":
			var later := _hp_at(m, t_land + period)
			if later > 0.0 and later <= hit and t_land < best_soon:
				best_soon = t_land
				out.soon = m
	return out


## Predicted health of minion `m` in `t` seconds: attacks in flight, the swings of everyone
## hitting it ("predict"), or just their damage per second ("basic").
func _hp_at(m: Unit, t: float) -> float:
	var hp: float = m.hp + m.shield
	if cfg.last_hit != "predict":
		var dps := 0.0
		for a in _attackers().get(m.net_id, []):
			dps += a.w / a.y
		return hp - dps * t
	var flying: Dictionary = _flying()
	for f in flying.get(m.net_id, []):
		if f.x <= t:
			hp -= f.y * m._mitigation(m.stats.armor, null, true)
	for a in _attackers().get(m.net_id, []):
		var k: float = a.x
		var guard := 0
		while k + a.z <= t and guard < 30:
			hp -= a.w
			k += a.y
			guard += 1
	return hp


## Our units hitting each enemy, once per decision: target net_id -> [Vector4(first swing in,
## period, projectile flight time, damage)].
func _attackers() -> Dictionary:
	var key := Vector3i(8, 0, 0)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	for list in [ally_units, friends, ally_towers]:
		for u in list:
			var m = u.attack_target
			if not _valid(m) or m.team == me.team or not (m is Minion) or not u.can_attack():
				continue
			var dmg := _tower_vs(u, m) if u.is_structure else BotKit.attack_damage(u, m)
			var d: float = u.global_position.distance_to(m.global_position)
			var reach: float = u.attack_reach(m)
			var first: float = u.attack_cd + maxf(d - reach, 0.0) / maxf(u.stats.move_speed, 1.0) + _windup(u)
			if u.winding_attack == m:
				first = u.windup_left
			var fly: float = minf(d, reach) / maxf(float(u.attack_def.speed), 1.0) if u.attack_def.ranged else 0.0
			if not out.has(m.net_id):
				out[m.net_id] = []
			out[m.net_id].append(Vector4(first, 1.0 / maxf(u.stats.attack_speed, 0.05), fly, dmg))
	_cache[key] = out
	return out


## Basic attacks in flight, per target: net_id -> [Vector2(seconds until impact, damage)].
func _flying() -> Dictionary:
	var key := Vector3i(7, 0, 0)
	if _cache.has(key):
		return _cache[key]
	var out := {}
	for n in world.proj_layer.get_children():
		if n is Projectile and not n.done and n.mode == "attack" and is_instance_valid(n.target):
			var id: int = n.target.net_id
			if not out.has(id):
				out[id] = []
			out[id].append(Vector2(n.global_position.distance_to(n.target.global_position) / maxf(n.speed, 1.0), n.damage))
	_cache[key] = out
	return out


## Wind-up of a basic attack of `u` (see Unit._act): the hit leaves this long after it starts.
func _windup(u: Unit) -> float:
	return minf(0.45, 1.0 / maxf(u.stats.attack_speed, 0.05) * (0.32 if u.is_champion else 0.40))


func _push_target() -> Unit:
	var best: Unit = null
	var bs := INF
	for m in foe_units:
		var d := me.global_position.distance_to(m.global_position)
		if d > me.attack_reach(m) + 450.0 or _turret_danger(m.global_position, -me.stats.attack_range) or not _spot_safe(_attack_spot(m)):
			continue
		var s: float = m.hp + d * 0.3
		if s < bs:
			bs = s
			best = m
	return best


func _poke_target() -> Champion:
	var best: Champion = null
	var bd := INF
	for e in foes:
		if not e.targetable() or e.has_status("invulnerable"):
			continue
		var d := me.global_position.distance_to(e.global_position)
		if d < bd and d < me.attack_reach(e) + 600.0:
			bd = d
			best = e
	return best


## Auto-attack the enemy champion when the trade is worth it and no turret punishes us.
func _harass_ok(e: Champion) -> bool:
	if float(cfg.harass) <= 0.0 or not e.targetable():
		return false
	var d := me.global_position.distance_to(e.global_position)
	if d > me.attack_reach(e) + 80.0:
		return false
	for t in foe_towers:
		if _is_turret(t) and t.global_position.distance_to(e.global_position) < t.stats.attack_range + 300.0 \
				and _attack_spot(e).distance_to(t.global_position) <= _tower_reach(t) + 30.0:
			return false
	if me.attack_def.ranged and d > e.attack_reach(me) + _mobility(e) + 30.0:
		return true
	var mine: float = BotKit.attack_damage(me, e) * me.stats.attack_speed * 2.0 / e.stats.max_hp
	var theirs: float = _burst(e, me, 2.0) / me.stats.max_hp
	return mine >= theirs * float(cfg.harass)


## Next enemy structure along our lane we can damage (not protected).
func _siege_target() -> Unit:
	var best: Unit = null
	var bs := INF
	for t in foe_towers:
		if t.is_protected():
			continue
		var pr := _lp(t.global_position)
		if pr.y > 1000.0 or t.global_position.distance_to(me.global_position) > 1800.0:
			continue
		if pr.x < bs:
			bs = pr.x
			best = t
	return best


func _siege_safe(t: Unit) -> bool:
	if _foes_near(me.global_position, 1000.0) > _alive_near_allies():
		return false
	if not _is_turret(t):
		return true
	if t.attack_target == me:
		return false
	var need := 1.2 if cfg.macro else 2.5
	if cfg.macro and _alive(false) == 0:
		need = 0.6
	return _tower_busy(t) >= need


func _alive_near_allies() -> int:
	var n := 0
	for a in friends:
		if a.global_position.distance_to(me.global_position) < 1200.0:
			n += 1
	return n


func _do_fight() -> void:
	var t := focus
	if not _valid(t):
		mode = "lane"
		_do_lane()
		return
	var d := me.global_position.distance_to(t.global_position)
	if mode == "trade" and d > me.attack_reach(t) + _mobility(me) + 250.0:
		# A trade doesn't chase: farm instead and wait for the next window.
		mode = "lane"
		_do_lane()
		return
	_cast_best("kill" if _killable(t, 2.5) else "fight", t)
	atk = t
	if me.attack_def.ranged and cfg.spacing:
		var lo: float = me.stats.attack_range * (0.85 if _mobility(t) <= 0.0 and not t.attack_def.ranged else 0.7)
		stand = _choose_spot(_kite_anchor(t), {"unit": t, "lo": lo, "hi": me.stats.attack_range - 15.0, "fear": 0.25,
			"dive": mode == "fight", "champ": true})
	else:
		stand = Vector2.INF


func _do_retreat() -> void:
	var home := _safe_point()
	var chaser := _nearest_foe()
	atk = null
	if chaser != null:
		var d := me.global_position.distance_to(chaser.global_position)
		var chased: bool = d < chaser.attack_reach(me) + 150.0 or (_taken(1.5) > 0.0 and d < _threat_range(chaser) + 100.0)
		if chased and (me.hp < me.stats.max_hp * 0.5 or _threat_on_me(2.0) >= me.hp + me.shield):
			_cast_best("escape", chaser)
		# Ranged champions shoot back while backing off.
		if cfg.kite and me.attack_def.ranged and d <= me.attack_reach(chaser) and cfg.fight != "naive":
			atk = chaser
	stand = home if cfg.fight != "naive" else world.map.spawn_point(me.team)
	if world.map.lane_count() > 0 and _foes_near(me.global_position, 1300.0) == 0 and _taken(1.5) <= 0.0 \
			and _danger_here() <= 0.0 and not _at_fountain():
		mode = "recall"
		_do_recall()


func _do_recall() -> void:
	atk = null
	var near_minions := 0
	for u in foe_units:
		if u.global_position.distance_to(me.global_position) < 700.0:
			near_minions += 1
	if _foes_near(me.global_position, 1300.0) > 0 or _taken(1.0) > 0.0 or near_minions > 0:
		stand = _safe_point()
		return
	stand = Vector2.INF
	me.move_goal = null
	me.move_dir = Vector2.ZERO
	me.attack_target = null
	if me.recall_timer <= 0.0:
		me.start_recall()


## Maps without lanes (Training Arena): hunt the nearest enemy champion, poke when not winning.
func _do_roam() -> void:
	var e := focus if _valid(focus) else _nearest_foe()
	if e == null:
		atk = null
		var last := Vector2.INF
		var lt := -INF
		for id in seen:
			var c = world.entities.get(id)
			if c != null and not c.dead and float(seen[id].t) > lt:
				lt = float(seen[id].t)
				last = seen[id].pos
		stand = last if last != Vector2.INF and world.time - lt < 8.0 else world.map.size * 0.5
		return
	_cast_best("poke", e)
	atk = e if _harass_ok(e) or cfg.fight == "naive" else null
	var keep := maxf(_threat_range(e) + 60.0, me.attack_reach(e) - 20.0) if cfg.spacing else me.attack_reach(e)
	var dir := (me.global_position - e.global_position).normalized()
	stand = _choose_spot(e.global_position + dir * keep, {"unit": e, "lo": keep - e.radius - me.radius - 40.0,
		"hi": keep - e.radius - me.radius + 40.0, "champ": true})


## Fountain-side shortcut: Teleport toward a far away lane.
func _travel(anchor: Vector2) -> void:
	if anchor.distance_to(me.global_position) < 4000.0 or not foes.is_empty() or me.hp < me.stats.max_hp * 0.85:
		return
	if cfg.summoners == "none":
		return
	for i in me.summoners.size():
		var sp = me.summoner_def(i)
		var ab = me.summoner_ability(i)
		if sp == null or ab == null or str(ab.get("bot", sp.bot)) != "travel" or me.sum_cd[i] > 0.0 or not me.can_use_summoner(ab):
			continue
		var best: Unit = null
		var bd := anchor.distance_to(me.global_position) - 1500.0
		var cands: Array = ally_towers.duplicate()
		if world.time >= 600.0:
			cands += ally_units.filter(func(u): return u is Minion)
		for s in cands:
			if s.is_nexus:
				continue
			var d: float = s.global_position.distance_to(anchor)
			if d < bd:
				bd = d
				best = s
		if best != null and me.use_summoner(i, best.global_position, best.net_id):
			return


func _safe_point() -> Vector2:
	var home := world.map.spawn_point(me.team)
	var my_d := me.global_position.distance_to(home)
	var best := home
	var bd := INF
	for t in ally_towers:
		if not _is_turret(t):
			continue
		if t.global_position.distance_to(home) >= my_d - 150.0:
			continue
		var d := me.global_position.distance_to(t.global_position)
		if d < bd:
			bd = d
			best = t.global_position + (home - t.global_position).normalized() * 220.0
	return best


# ------------------------------------------------------------ positioning ---

## Spot next to `u` at our attack range, on our side.
func _attack_spot(u: Unit) -> Vector2:
	var d := me.global_position.distance_to(u.global_position)
	var reach := me.attack_reach(u) - 25.0
	if d <= reach:
		return me.global_position
	var dir := (me.global_position - u.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = (world.map.spawn_point(me.team) - u.global_position).normalized()
	return u.global_position + dir * maxf(reach, 10.0)


func _kite_anchor(t: Unit) -> Vector2:
	if not me.attack_def.ranged:
		return t.global_position
	var dir := (me.global_position - t.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = (world.map.spawn_point(me.team) - t.global_position).normalized()
	return t.global_position + dir * (me.attack_reach(t) - 30.0)


## Best spot near `anchor`: weighs the distance to the anchor, attack range to a unit, enemy
## turrets, enemy champions' threat ranges, minion aggro, hook lines and known danger zones.
func _choose_spot(anchor: Vector2, want := {}) -> Vector2:
	if anchor == Vector2.INF:
		return anchor
	if not cfg.spacing or me.global_position.distance_to(anchor) > 1100.0:
		return anchor
	var cands := [anchor, me.global_position]
	if stand != Vector2.INF and stand.distance_to(anchor) < 300.0:
		cands.append(stand)
	var n := 10 if cfg.micro else 8
	for k in n:
		var dir := Vector2.from_angle(TAU * k / n + 0.2)
		cands.append(anchor + dir * 110.0)
		cands.append(anchor + dir * 240.0)
	var best := anchor
	var bc := INF
	for p in cands:
		var c := _spot_cost(p, anchor, want)
		if p == stand:
			c -= 3.0
		if c < bc:
			bc = c
			best = p
	return best


## Per-decision inputs of _spot_cost, pre-filtered around `anchor`: turrets [pos, reach, state],
## enemy champions' threat [pos, range, weight], ready hook-like skillshots [pos, range, width,
## value, blockers], minions that may aggro, and lingering threat shapes (zones, traps...).
func _spot_ctx(anchor: Vector2) -> Dictionary:
	var key := Vector3i(6, int(anchor.x), int(anchor.y))
	if _cache.has(key):
		return _cache[key]
	var towers := []
	for tw in foe_towers:
		if _is_turret(tw) and tw.global_position.distance_to(anchor) < _tower_reach(tw) + 400.0:
			# state: 0 = shoots us, 1 = busy long enough for us to stand there, 2 = busy only for a siege
			var busy := _tower_busy(tw)
			var state := 0 if tw.attack_target == me or busy < 1.2 else (2 if busy < 2.5 else 1)
			towers.append([tw.global_position, _tower_reach(tw) + 25.0, state])
	var threat := []
	var hooks := []
	for e in foes:
		if e.global_position.distance_to(anchor) > 1800.0:
			continue
		threat.append([e.global_position, _threat_range(e), _threat_weight(e)])
		if not cfg.read:
			continue
		var ck := BotKit.char_kit(e.def)
		for slot in SLOTS:
			var pr = ck.get(slot)
			if pr != null and pr.blockable and pr.hard and _ready_slot(e, slot):
				var rng := _reach_of(pr, e, _rank(e, slot)) + 100.0
				if e.global_position.distance_to(anchor) > rng + 300.0:
					continue
				var blockers := []
				for u in ally_units:
					if u.global_position.distance_to(e.global_position) < rng:
						blockers.append(Vector3(u.global_position.x, u.global_position.y, u.radius))
				hooks.append([e.global_position, rng, float(pr.width), 35.0 * (1.0 + float(pr.cc_value)), blockers])
	var aggro := PackedVector2Array()
	if me.level < 10:
		for m in foe_units:
			if m is Minion and (m.attack_target == null or m.attack_target == me) and m.global_position.distance_to(anchor) < 800.0:
				aggro.append(m.global_position)
	var shapes := []
	if cfg.read:
		for th in _threats():
			if str(th.k) != "proj" and Vector2(th.p).distance_to(anchor) < float(th.r) + 400.0 + float(th.get("len", 0.0)):
				shapes.append(th)
	var sc := {"towers": towers, "threat": threat, "hooks": hooks, "aggro": aggro, "shapes": shapes}
	_cache[key] = sc
	return sc


func _spot_cost(p: Vector2, anchor: Vector2, want: Dictionary) -> float:
	if world.map.is_wall(p):
		return INF
	var sc := _spot_ctx(anchor)
	var c := p.distance_to(anchor) * 0.12 + p.distance_to(me.global_position) * 0.02
	var u = want.get("unit")
	if _valid(u):
		var d: float = p.distance_to(u.global_position) - u.radius - me.radius
		var lo: float = want.get("lo", 0.0)
		var hi: float = want.get("hi", 0.0)
		if d < lo:
			c += (lo - d) * 0.6
		elif d > hi:
			c += (d - hi) * 0.6
	var dive: bool = want.get("dive", false)
	var siege: bool = want.get("siege", false)
	var champ: bool = want.get("champ", false)
	for tw in sc.towers:
		var d: float = p.distance_to(tw[0])
		if d >= tw[1]:
			continue
		if dive:
			c += 30.0
		elif tw[2] == 1 and not champ:
			c += 0.0 if siege else 40.0
		elif tw[2] == 2 and siege and not champ:
			c += 15.0
		else:
			c += 2500.0 + (tw[1] - d) * 4.0
	var fear: float = want.get("fear", 1.0)
	for e in sc.threat:
		var d: float = p.distance_to(e[0])
		if d < e[1]:
			c += (e[1] - d) * 0.3 * fear * e[2]
	if not siege and not champ:
		for m in sc.aggro:
			if p.distance_to(m) < 480.0:
				c += 6.0
	for h in sc.hooks:
		if p.distance_to(h[0]) <= h[1] and not _covered(h[0], p, h[2], h[4]):
			c += h[3]
	for th in sc.shapes:
		if _hits(th, p, Vector2.ZERO):
			c += 300.0 * float(th.danger)
	if cfg.read:
		# Walls and corners leave no room to dodge.
		for k in 8:
			if world.map.is_wall(p + Vector2.from_angle(TAU * k / 8.0) * 170.0):
				c += 7.0
	return c


func _covered(a: Vector2, b: Vector2, width: float, blockers: Array) -> bool:
	var seg := b - a
	var l := seg.length()
	if l < 1.0:
		return false
	var dir := seg / l
	for u in blockers:
		var rel := Vector2(u.x, u.y) - a
		var s := rel.dot(dir)
		if s > 30.0 and s < l - 20.0 and absf(rel.cross(dir)) <= width + u.z:
			return true
	return false


# ------------------------------------------------------------- execution ---

func _can_hit(u) -> bool:
	return _valid(u) and me.valid_target(u) and not (u.is_structure and u.is_protected())


## Think-rate execution (brick / normal): attack or walk toward the chosen spot.
func _apply() -> void:
	me.amove = null
	if _can_hit(atk):
		var d := me.global_position.distance_to(atk.global_position)
		var reach := me.attack_reach(atk)
		if not cfg.kite or not me.attack_def.ranged or stand == Vector2.INF or d > reach + 30.0 \
				or me.attack_cd <= float(cfg.think) * 0.6:
			me.move_dir = Vector2.ZERO
			me.move_goal = null
			me.attack_target = atk
			return
	if stand != Vector2.INF:
		_move_to(stand, false)
	elif _can_hit(atk):
		me.move_dir = Vector2.ZERO
		me.attack_target = atk
	else:
		_stop()


## Frame-perfect execution (scripting): dodge, then start an attack the instant it's ready and the
## target is in range, and walk to the chosen spot between attacks (never while winding up).
func _micro() -> void:
	if me.recall_timer > 0.0 or me.casting != null or me.forced != null:
		return
	me.amove = null
	if _dodge():
		# Standing still for an attack wind-up would walk us into the hit.
		me.attack_target = null
		return
	if _can_hit(atk) and me.can_attack() and me.attack_cd <= 0.0 \
			and me.global_position.distance_to(atk.global_position) <= me.attack_reach(atk):
		if not me.attack_def.ranged or stand == Vector2.INF or stand.distance_to(me.global_position) < 12.0:
			me.attack_target = atk
			me.move_goal = null
			return
		me.move_dir = (stand - me.global_position).normalized()
		me.move_goal = null
		me.attack_target = atk
		return
	if stand != Vector2.INF:
		_move_to(stand, true)
	elif _can_hit(atk):
		me.move_dir = Vector2.ZERO
		me.attack_target = atk
	elif mode != "recall":
		_stop()


func _move_to(p: Vector2, steer: bool) -> void:
	me.attack_target = null
	var to := p - me.global_position
	if to.length() < 10.0:
		me.move_dir = Vector2.ZERO
		me.move_goal = null
		return
	if steer and to.length() < 450.0 and world.map.has_los(me.global_position, p):
		me.move_goal = null
		me.move_dir = to.normalized()
		return
	me.move_dir = Vector2.ZERO
	if me.move_goal == null or (me.move_goal as Vector2).distance_to(p) > 25.0:
		me.move_goal = world.map.clamp_inside(p)


func _stop() -> void:
	me.move_dir = Vector2.ZERO
	me.move_goal = null
	me.attack_target = null

# ---------------------------------------------------------------- threats ---

## Whether we react to a threat yet: each one is noticed once, rolls the difficulty's dodge
## chance, and is only acted on after the reaction time.
func _noticed_ok(key: String) -> bool:
	var n = _noticed.get(key)
	if n == null:
		n = {"t": world.time, "go": randf() < float(cfg.dodge)}
		_noticed[key] = n
	return n.go and world.time - float(n.t) >= float(cfg.react)


## Everything dangerous we can see coming, as shapes in time (relative seconds t0..t1):
## enemy skillshots in flight, telegraphed areas and beams, and with "read" also the hit
## shapes of enemy casts (delayed blasts, beams, dash landings, auras), dashes in progress,
## enemy zones and traps we saw being placed.
func _threats() -> Array:
	if _thr_time == world.time:
		return _thr
	_thr_time = world.time
	_thr = []
	if cfg.dodge <= 0.0:
		return _thr
	var now := world.time
	var mr: float = me.radius + 6.0
	var me_p := me.global_position
	for n in world.proj_layer.get_children():
		if not (n is Projectile) or n.done or n.mode != "ability" or n.team == me.team or n.target != null or n.affects == "allies":
			continue
		if not (n.effect.has("on_hit") or n.effect.has("on_end")) or n.global_position.distance_to(me_p) > 2000.0:
			continue
		var key := "p%d" % n.net_id
		if not _noticed_ok(key):
			continue
		var info := _proj_info(n)
		var v: Vector2 = n.dir * n.speed
		var rem: float = maxf(n.max_dist - n.traveled, 0.0) / maxf(n.speed, 1.0)
		if n.returning:
			var c = n.ctx.get("caster")
			if not is_instance_valid(c):
				continue
			v = (c.global_position - n.global_position).normalized() * n.speed
			rem = n.global_position.distance_to(c.global_position) / maxf(n.speed, 1.0)
		var r: float = maxf(n.radius, float(info.explode) * 0.45) + mr
		_thr.append({"k": "proj", "p": n.global_position, "v": v, "t0": 0.0, "t1": rem, "r": r, "danger": info.danger, "key": key})
		if float(info.explode) > 0.0 and not n.returning:
			_thr.append({"k": "circle", "p": n.global_position + v * rem, "v": Vector2.ZERO, "t0": rem, "t1": rem + 0.05,
				"r": float(info.explode) + mr, "danger": float(info.danger) * 0.8, "key": key})
	for w in world.bot_warns:
		if int(w.team) == me.team or float(w.t) < now:
			continue
		var key := "w%d" % int(w.id)
		if not _noticed_ok(key):
			continue
		var t0: float = float(w.t) - now
		if w.kind == "circle":
			_thr.append({"k": "circle", "p": w.pos, "v": Vector2.ZERO, "t0": t0, "t1": t0 + 0.05, "r": float(w.r) + mr, "danger": 0.35, "key": key})
		else:
			var seg: Vector2 = w.to - w.from
			_thr.append({"k": "line", "p": w.from, "d": seg.normalized(), "len": seg.length(), "t0": t0, "t1": t0 + 0.05,
				"r": float(w.r) + mr, "danger": 0.4, "key": key})
	if not cfg.read:
		return _thr
	for rec in world.bot_casts:
		_cast_threats(rec)
	for e in foes:
		var f = e.forced
		if f != null and f.dash and f.e.has("on_hit") and float(f.time) > 0.0:
			var key := "d%d" % e.net_id
			if _noticed_ok(key):
				_thr.append({"k": "proj", "p": e.global_position, "v": f.vel, "t0": 0.0, "t1": float(f.time), "r": e.radius + 10.0 + mr,
					"danger": 0.3, "key": key})
	for z in world.zone_layer.get_children():
		if not (z is Zone) or z.team == me.team or z.trap or z.affects == "allies":
			continue
		var left: float = z.duration - z.life
		if left <= 0.0 or z.global_position.distance_to(me_p) > 1500.0:
			continue
		var zv := Vector2.ZERO
		if is_instance_valid(z.follow):
			zv = z.follow.velocity
		_thr.append({"k": "circle", "p": z.global_position, "v": zv, "t0": 0.0, "t1": minf(left, 2.0), "r": z.radius + mr,
			"danger": 0.2, "key": "z%d" % z.net_id})
	for k in _traps:
		var tr: Dictionary = _traps[k]
		_thr.append({"k": "circle", "p": tr.pos, "v": Vector2.ZERO, "t0": 0.0, "t1": 3.0, "r": float(tr.r) + mr, "danger": 0.5, "key": "t" + str(k)})
	return _thr


func _proj_info(n: Projectile) -> Dictionary:
	if _pinfo.has(n.net_id):
		return _pinfo[n.net_id]
	var info := {"danger": 0.2, "explode": Content._find_radius(n.effect.get("on_end"))}
	var c = n.ctx.get("caster")
	var slot := str(n.ctx.get("src_slot", ""))
	if is_instance_valid(c) and c is Champion and slot in SLOTS:
		var ck := BotKit.char_kit(c.def)
		var pr = ck.get(slot)
		var rc = ck.get(slot + "+")
		if rc != null and str(n.ctx.get("ability", "")) == str(rc.name):
			pr = rc
		if pr != null:
			info.danger = BotKit.damage(pr, c, me, _rank(c, slot)) / maxf(me.hp + me.shield, 1.0) + float(pr.cc_value)
	elif slot == "summoner":
		info.danger = 0.3
	_pinfo[n.net_id] = info
	return info


func _rec_prof(rec: Dictionary) -> Dictionary:
	var c = rec.c
	if str(rec.item) != "":
		return BotKit.item_kit(str(rec.item))
	var ck := BotKit.char_kit(c.def)
	var pr = ck.get(str(rec.slot) + ("+" if rec.recast else ""), ck.get(str(rec.slot)))
	return pr if pr != null else {}


## Hit shapes of an enemy cast we saw (delayed areas, beams, dash landings, auras around them).
func _cast_threats(rec: Dictionary) -> void:
	var c = rec.c
	if not is_instance_valid(c) or c.team == me.team:
		return
	var age: float = world.time - float(rec.t)
	if age > 4.0:
		return
	var pr := _rec_prof(rec)
	if pr.is_empty():
		return
	var key := "c%d" % int(rec.id)
	if pr.shape == "trap" and not _traps.has(rec.id) and not _noticed.has(key) and world.can_see(c, me.team):
		_traps[rec.id] = {"pos": rec.pos, "r": float(pr.radius), "until": float(rec.t) + float(pr.zone_dur)}
	if pr.hits.is_empty() or not _noticed_ok(key):
		return
	if not _rdanger.has(rec.id):
		_rdanger[rec.id] = BotKit.damage(pr, c, me, maxi(_rank(c, str(rec.slot)), c.level if str(rec.item) != "" else 1)) \
			/ maxf(me.hp + me.shield, 1.0) + float(pr.cc_value)
	var danger: float = _rdanger[rec.id]
	var mr: float = me.radius + 6.0
	var start: float = float(rec.t) + float(rec.ct)
	for h in pr.hits:
		var t0: float = start + float(h.delay) - world.time
		var t1: float = t0 + float(h.dur)
		if t1 < 0.0 or (t0 <= 0.02 and float(h.dur) <= 0.0) or t0 > 2.5:
			continue
		var center := Vector2.INF
		var vel := Vector2.ZERO
		match str(h.anchor):
			"caster":
				center = c.global_position
				vel = c.velocity
			"origin":
				center = rec.from
			"pos":
				center = rec.pos
			"target":
				if _valid(rec.target):
					center = rec.target.global_position
			"land":
				center = _landing(rec, pr)
		if center == Vector2.INF:
			continue
		var th := {"t0": maxf(t0, 0.0), "t1": maxf(t1, 0.0), "danger": danger if (h.cc or h.dmg) else danger * 0.3, "key": key}
		match str(h.kind):
			"circle":
				th.k = "circle"
				th.p = center
				th.v = vel
				th.r = float(h.radius) + mr
			"cone":
				th.k = "cone"
				th.p = center
				th.d = rec.dir
				th.r = float(h.radius) + me.radius
				th.ang = deg_to_rad(float(h.angle)) * 0.5
			"line":
				th.k = "line"
				th.p = center
				th.d = rec.dir
				th.len = float(h.length)
				th.r = float(h.width) + mr
		if th.has("k"):
			_thr.append(th)


func _landing(rec: Dictionary, pr: Dictionary) -> Vector2:
	var c = rec.c
	if c.forced != null and c.forced.dash:
		return c.global_position + c.forced.vel * float(c.forced.time)
	var dist := Effects.num(pr.dash.get("distance"), BotKit.ctx_for(pr, c, c, maxi(_rank(c, str(rec.slot)), 1)), 350.0)
	var from: Vector2 = rec.from
	var dir: Vector2 = rec.dir
	match str(pr.dash.get("to", "aim")):
		"direction":
			return from + dir * dist
		"back", "backward", "backwards":
			return from - dir * dist
		"target":
			return rec.target.global_position if _valid(rec.target) else rec.pos
	var to: Vector2 = rec.pos - from
	return from + to.limit_length(dist)


func _trap_exists(p: Vector2) -> bool:
	for z in world.zone_layer.get_children():
		if z is Zone and z.trap and z.team != me.team and z.global_position.distance_to(p) < 60.0:
			return true
	return false


## Whether walking from `p0` with velocity `v` runs into threat `th` while it is active.
func _hits(th: Dictionary, p0: Vector2, v: Vector2) -> bool:
	match str(th.k):
		"proj", "circle":
			var a: Vector2 = p0 - th.p
			var b: Vector2 = v - th.v
			var t: float = th.t0
			var bb := b.length_squared()
			if bb > 0.0001:
				t = clampf(-a.dot(b) / bb, float(th.t0), float(th.t1))
			return (a + b * t).length() <= float(th.r)
		"line":
			var e: Vector2 = th.p + th.d * float(th.len)
			for t in [float(th.t0), (float(th.t0) + float(th.t1)) * 0.5, float(th.t1)]:
				var q: Vector2 = p0 + v * t
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, th.p, e)) <= float(th.r):
					return true
			return false
		"cone":
			for t in [float(th.t0), float(th.t1)]:
				var q: Vector2 = p0 + v * t - th.p
				var l := q.length()
				if l <= float(th.r) and (l <= me.radius or absf(Vector2(th.d).angle_to(q)) <= float(th.ang) + asin(minf(me.radius / l, 1.0))):
					return true
			return false
	return false


func _hit_time(th: Dictionary, p0: Vector2) -> float:
	if str(th.k) == "proj":
		var a: Vector2 = p0 - th.p
		var b: Vector2 = -th.v
		var bb := b.length_squared()
		return clampf(-a.dot(b) / bb, 0.0, float(th.t1)) if bb > 0.0001 else 0.0
	return float(th.t0)


func _danger_for(threats: Array, p0: Vector2, v: Vector2) -> float:
	var s := 0.0
	for th in threats:
		if _hits(th, p0, v):
			s += float(th.danger)
	return s


## Danger of standing still right here.
func _danger_here() -> float:
	return _danger_for(_threats(), me.global_position, Vector2.ZERO)


## Steps out of every threat we can still walk out of (each frame for "scripting"). Returns
## true while dodging. When walking isn't enough, uses a parry/stasis, a dash, a blink or Flash.
func _dodge() -> bool:
	if cfg.dodge <= 0.0 or me.forced != null or me.casting != null:
		return false
	var threats := _threats()
	if threats.is_empty():
		_dodge_dir = Vector2.ZERO
		return false
	var p0 := me.global_position
	var mobile := me.can_move()
	var ms: float = me.stats.move_speed if mobile else 0.0
	var plan_v := _plan_velocity() if mobile else Vector2.ZERO
	var cur := _danger_for(threats, p0, plan_v)
	if cur < 0.02:
		_dodge_dir = Vector2.ZERO
		return false
	var pref := plan_v.normalized()
	var best_v := Vector2.ZERO
	var best := _danger_for(threats, p0, Vector2.ZERO)
	if mobile:
		for k in 16:
			var dir := Vector2.from_angle(TAU * k / 16.0)
			var dn := _danger_for(threats, p0, dir * ms)
			var probe := p0 + dir * minf(ms * 0.35, 120.0)
			if world.map.is_wall(probe):
				dn += 1.0
			elif _turret_danger(probe):
				dn += 0.6
			dn -= dir.dot(pref) * 0.003
			if _dodge_dir != Vector2.ZERO and dir.dot(_dodge_dir) > 0.92:
				dn -= 0.004
			if dn < best:
				best = dn
				best_v = dir * ms
	if best >= 0.3 and cfg.read and _emergency(threats, best):
		return true
	if best >= cur - 0.005:
		_dodge_dir = Vector2.ZERO
		return false
	_dodge_dir = best_v.normalized()
	me.move_goal = null
	me.move_dir = _dodge_dir
	if best_v == Vector2.ZERO:
		me.attack_target = null
	return true


## The velocity our current plan would have (walking to `stand`, or chasing `atk`).
func _plan_velocity() -> Vector2:
	var ms: float = me.stats.move_speed
	if stand != Vector2.INF:
		var to := stand - me.global_position
		return to.normalized() * ms if to.length() > 10.0 else Vector2.ZERO
	if _valid(atk) and me.global_position.distance_to(atk.global_position) > me.attack_reach(atk):
		return (atk.global_position - me.global_position).normalized() * ms
	return Vector2.ZERO if cfg.micro else me.velocity


## Walking can't avoid a serious hit: parry/stasis through it, dash or blink away, or Flash.
func _emergency(threats: Array, residual: float) -> bool:
	var first := INF
	for th in threats:
		if _hits(th, me.global_position, Vector2.ZERO):
			first = minf(first, _hit_time(th, me.global_position))
	if first == INF:
		return false
	var lethal := residual >= 1.0
	var usable := _usable()
	for c in usable:
		var pr: Dictionary = c.prof
		var cover := maxf(float(pr.invuln), float(pr.stasis))
		if cover <= 0.0 or first > cover - 0.06:
			continue
		if float(pr.stasis) > 0.0 and not lethal and residual < 0.8:
			continue
		if residual < 0.4:
			continue
		var t := _nearest_foe()
		var aim := _predict(t, cover) if t != null else me.global_position + Vector2(me.facing, 0) * 100.0
		if _fire(c, aim, t.net_id if t != null else 0):
			return true
	if residual < 0.4:
		return false
	for c in usable:
		var pr: Dictionary = c.prof
		if not pr.mobility or str(pr.dash.get("to", "")) == "target":
			continue
		var dest := _escape_spot(threats, _mob_dist(pr, me, int(c.rank)))
		if dest == Vector2.INF:
			continue
		var aim := dest
		if pr.dash_back:
			aim = me.global_position * 2.0 - dest
		if _fire(c, aim, 0):
			return true
	if residual >= 0.75 and cfg.summoners == "smart":
		var i := _summoner_with("escape")
		if i >= 0:
			var dest := _escape_spot(threats, 400.0)
			if dest != Vector2.INF and me.use_summoner(i, dest, 0):
				return true
	return false


func _escape_spot(threats: Array, dist: float) -> Vector2:
	var safe := (_safe_point() - me.global_position).normalized()
	var best := Vector2.INF
	var bs := INF
	for k in 12:
		var dir := Vector2.from_angle(TAU * k / 12.0)
		var q := world.map.nearest_open(me.global_position + dir * dist)
		var dn := _danger_for(threats, q, Vector2.ZERO)
		if _turret_danger(q):
			dn += 0.8
		for e in foes:
			if q.distance_to(e.global_position) < e.attack_reach(me):
				dn += 0.1
		dn -= dir.dot(safe) * 0.05
		if dn < bs:
			bs = dn
			best = q
	return best if bs < 0.25 else Vector2.INF

# --------------------------------------------------------------- abilities ---

func _prof(slot: String) -> Dictionary:
	if float(me.recast_left.get(slot, 0.0)) > 0.0 and kit.has(slot + "+"):
		return kit[slot + "+"]
	return kit.get(slot, {})


## Abilities (and, for "scripting", item actives) usable right now.
func _usable() -> Array:
	var out := []
	if me.can_cast() and me.casting == null:
		for slot in SLOTS:
			var ab = me.active_ability(slot)
			if ab == null or _rank(me, slot) <= 0 or me.cooldowns[slot] > 0.0 or not me.can_pay(ab):
				continue
			out.append({"kind": "ability", "slot": slot, "prof": _prof(slot), "ab": ab, "rank": _rank(me, slot)})
	if cfg.items == "smart" and not me.has_status("stasis"):
		for i in Champion.ITEM_SLOTS:
			var it = me.item_def(i)
			if it == null or it.active == null or it.consumable or me.items[i].cd > 0.0:
				continue
			if it.charges > 0 and int(me.items[i].n) <= 0:
				continue
			var pr := BotKit.item_kit(str(me.items[i].id))
			if not pr.is_empty():
				out.append({"kind": "item", "slot": i, "prof": pr, "ab": it.active, "rank": me.level})
	return out


func _fire(c: Dictionary, aim: Vector2, tid: int) -> bool:
	var pr: Dictionary = c.prof
	if float(cfg.aim_error) > 0.0 and pr.targeting != "self" and pr.targeting != "unit" and pr.targeting != "ally":
		aim += Vector2.from_angle(randf() * TAU) * randf() * float(cfg.aim_error)
	if c.kind == "item":
		return me.use_item(int(c.slot), aim, tid)
	return me.cast(str(c.slot), aim, tid)


## Casts the best ability for `intent` (kill / fight / poke / escape / farm / siege) if it is
## worth it. "scripting" chains instant abilities in the same frame.
func _cast_best(intent: String, t) -> void:
	if randf() > float(cfg.cast_chance) or me.casting != null or me.forced != null:
		return
	var tries := 3 if cfg.micro else 1
	for k in tries:
		var best := {}
		var bs := 0.0
		var cands := _usable()
		if difficulty == "brick":
			cands.shuffle()
		for c in cands:
			var v := _evaluate(c, intent, t)
			var s: float = v.get("score", 0.0)
			if difficulty == "brick" and s > 0.0:
				best = v
				best.c = c
				bs = 1.0
				break
			if s > bs:
				bs = s
				best = v
				best.c = c
		if best.is_empty() or bs < _threshold(intent):
			return
		if not _fire(best.c, best.aim, int(best.get("tid", 0))):
			return
		if me.casting != null or me.forced != null:
			return


func _threshold(intent: String) -> float:
	match intent:
		"kill":
			return 0.04
		"fight":
			return 0.08
		"poke":
			return 0.08
		"farm":
			return 0.3
	return 0.2


func _evaluate(c: Dictionary, intent: String, t) -> Dictionary:
	var best := {"score": 0.0}
	match intent:
		"kill", "fight", "poke":
			best = _better(best, _offense(c, t, intent))
			if intent != "poke":
				best = _better(best, _defense(c))
			best = _better(best, _support(c))
		"escape":
			best = _better(best, _escape(c, t))
			best = _better(best, _defense(c))
		"farm":
			best = _better(best, _farm(c))
		"siege":
			best = _better(best, _siege_cast(c, t))
	if c.kind == "ability" and me.uses_mana() and float(best.score) > 0.0:
		var cost := me.ability_cost(c.ab)
		var reserve := 0.0
		match intent:
			"poke":
				reserve = 0.3
			"farm":
				reserve = 0.5
			"siege":
				reserve = 0.4
		if me.mana - cost < me.stats.max_mana * reserve:
			best.score = 0.0
	return best


func _better(a: Dictionary, b: Dictionary) -> Dictionary:
	return b if float(b.get("score", 0.0)) > float(a.get("score", 0.0)) else a


## Damage, crowd control, engages and self-buffs against enemy champion `t`.
func _offense(c: Dictionary, t, intent: String) -> Dictionary:
	if not _valid(t) or not t.targetable() or t.has_status("invulnerable"):
		return {}
	var pr: Dictionary = c.prof
	var slot := str(c.slot)
	var rank: int = c.rank
	if intent == "poke" and (slot == "r" or (pr.mobility and not pr.bond) or not pr.summon.is_empty() or pr.stasis > 0.0):
		return {}
	var d: float = me.global_position.distance_to(t.global_position)
	var ctx := BotKit.ctx_for(pr, me, t, rank)
	var rng := Effects.num(pr.range, ctx, 700.0)
	var ct := Effects.num(pr.cast_time, ctx, 0.0)
	var ehp: float = maxf(t.hp + t.shield, 1.0)
	var dmg := BotKit.damage(pr, me, t, rank)
	var cc: float = float(pr.cc_value) if t.is_champion else 0.0
	if cc > 0.0 and _cc_left(t) > 0.35:
		cc *= 0.25
	if t.has_status("spellshield") and c.kind == "ability":
		# Pop the spell shield with the cheapest thing we have, keep the real spells.
		return {"score": 0.13 if dmg > 0.0 and cc <= 0.0 else 0.0, "aim": t.global_position, "tid": t.net_id}
	var value := dmg / ehp + cc
	if dmg >= ehp * 0.98:
		value += 1.0
	# Parries / stasis: only worth it when a hit is about to land.
	if pr.invuln > 0.0 or pr.stasis > 0.0:
		if not _incoming_hit(maxf(pr.invuln, pr.stasis) - 0.05):
			return {}
		value += 0.4
	# Bond of Life lunges (Clorinde): the payoff depends on the Bond built up.
	if pr.bond and pr.mobility:
		var tier := 2 if me.bond >= me.stats.max_hp else (1 if me.bond > 0.0 else 0)
		value = [0.03, 0.2, 0.9][tier] + (0.3 if float(me.recast_left.get(slot, 9.0)) < 0.7 and me.bond > 0.0 else 0.0)
	if pr.targeting == "self":
		return _self_offense(pr, t, d, value, intent, ct)
	if pr.targeting == "unit":
		if d > rng + t.radius + me.radius + 30.0:
			return {}
		return {"score": value, "aim": t.global_position, "tid": t.net_id}
	if pr.shape == "summon":
		if intent == "poke" or d > rng + 600.0:
			return {}
		return {"score": 0.35, "aim": me.global_position + (t.global_position - me.global_position).limit_length(minf(rng, d * 0.5)),
			"tid": t.net_id}
	if pr.shape == "trap":
		return _trap_value(pr, t, d, rng, value)
	if pr.shape == "blink":
		if intent != "kill" or d <= me.attack_reach(t) or d > rng + me.attack_reach(t) - 30.0:
			return {}
		var land: Vector2 = t.global_position + (me.global_position - t.global_position).normalized() * (me.attack_reach(t) - 40.0)
		if _turret_danger(land) and not _dive_ok(t):
			return {}
		return {"score": 0.5 + value, "aim": land, "tid": t.net_id}
	if pr.shape == "dash" or (pr.mobility and not pr.dash.is_empty() and pr.shape in ["area", "cone"] and pr.dash_back):
		return _dash_value(c, pr, t, d, ctx, ct, value, intent)
	var shot := _aim(pr, t, rng, ct, ctx)
	if not shot.get("ok", false):
		return {}
	var chance: float = shot.chance
	var need: float = float(cfg.hit_min) * ({"poke": 1.0, "fight": 0.7, "kill": 0.4}.get(intent, 1.0) as float)
	if chance < need:
		return {}
	if pr.cc.has("pull") and intent == "poke" and not _fight_ok(t, false) and _under_ally_turret() == null:
		return {}
	if pr.cc.has("knockback") and not me.attack_def.ranged and intent != "poke" and dmg < ehp:
		value *= 0.5
	if pr.dash_back and intent == "kill":
		return {}
	if intent == "poke" and c.kind == "ability":
		# Cheap, fast spells are meant to be spammed.
		var cd := me.ability_cooldown(c.ab)
		value += 0.06 * clampf((10.0 - cd) / 6.0, 0.0, 1.0)
	return {"score": value * chance, "aim": shot.pos, "tid": t.net_id}


## Self-cast abilities in a fight: area around us, steroids (attack speed, size, range), speed.
func _self_offense(pr: Dictionary, t: Unit, d: float, value: float, intent: String, ct: float) -> Dictionary:
	var v := 0.0
	var gives_range := false
	for b in pr.buffs:
		if b.attack is Dictionary and bool(b.attack.get("ranged", false)):
			gives_range = true
	if pr.steroid and (intent != "poke" or gives_range):
		var reach := me.attack_reach(t) + (300.0 if gives_range and not me.attack_def.ranged else 0.0) + 150.0
		if d <= reach:
			v += 0.35
	if pr.ms_buff >= 0.1 and intent == "kill" and d > me.attack_reach(t) + 40.0 and d < 900.0:
		v += 0.3
	var r: float = pr.radius
	if r > 0.0 and value > 0.0:
		var p := _predict(t, ct + float(pr.area_delay))
		if me.global_position.distance_to(p) <= r + t.radius * 0.5:
			v += value
	if not pr.summon.is_empty() and intent != "poke" and d < 700.0:
		v += 0.35
	if v <= 0.0:
		return {}
	return {"score": v, "aim": t.global_position, "tid": me.net_id}


func _dash_value(c: Dictionary, pr: Dictionary, t: Unit, d: float, ctx: Dictionary, ct: float, value: float, intent: String) -> Dictionary:
	var dist := Effects.num(pr.dash.get("distance"), ctx, 350.0)
	if pr.dash_back:
		# Rocket-jump style: blast what's next to us and jump away - a peel / kite tool.
		if pr.radius > 0.0 and d <= pr.radius + t.radius and intent != "kill" and (not t.attack_def.ranged or me.hp < me.stats.max_hp * 0.5):
			return {"score": value + 0.3, "aim": t.global_position, "tid": t.net_id}
		return {}
	if intent == "poke" and not pr.bond and value < 1.0:
		return {}
	var speed := maxf(Effects.num(pr.dash.get("speed"), ctx, 1400.0), 50.0)
	var p := _predict(t, (ct + minf(d, dist) / speed) * float(cfg.lead))
	var to := p - me.global_position
	var land: Vector2
	var aim := p
	match str(pr.dash.get("to", "aim")):
		"target":
			land = p
		"direction":
			land = me.global_position + to.normalized() * dist
		_:
			land = me.global_position + to.limit_length(dist)
	var hit_path: bool = pr.dash_hits and to.length() <= dist + t.radius + me.radius
	var hit_land: bool = pr.land_radius > 0.0 and land.distance_to(p) <= pr.land_radius + t.radius * 0.5
	var in_reach := land.distance_to(p) <= me.attack_reach(t) + 10.0
	if not (hit_path or hit_land or (in_reach and d > me.attack_reach(t) + 40.0)):
		return {}
	if _turret_danger(land) and not _dive_ok(t):
		return {}
	var v := (value if (hit_path or hit_land) else 0.0)
	if d > me.attack_reach(t) + 40.0 and intent != "poke":
		v += 0.25
	if pr.bond:
		v = value if hit_path else 0.0
	return {"score": v, "aim": aim, "tid": t.net_id}


func _trap_value(pr: Dictionary, t: Unit, d: float, rng: float, value: float) -> Dictionary:
	if _cc_left(t) >= 0.75 and d <= rng + pr.radius:
		return {"score": 0.6 + value, "aim": t.global_position, "tid": t.net_id}
	var toward: Vector2 = (me.global_position - t.global_position).normalized()
	if t.velocity.dot(toward) > t.stats.move_speed * 0.6 and d < 500.0:
		return {"score": 0.3, "aim": me.global_position + (t.global_position - me.global_position) * 0.3, "tid": t.net_id}
	return {}


## Aim point and hit chance for a skillshot at `t`: intercept for projectiles, the predicted
## position for delayed areas/beams, and a minion-block check for projectiles that stop.
func _aim(pr: Dictionary, t: Unit, rng: float, ct: float, ctx: Dictionary) -> Dictionary:
	var from := me.global_position
	var lead := float(cfg.lead)
	match pr.shape:
		"projectile":
			var hit := _intercept(from, t, maxf(float(pr.speed), 50.0), ct)
			var p: Vector2 = t.global_position.lerp(hit.pos, lead)
			var reach := Effects.num(pr.prange, ctx, rng) if pr.prange != null else rng
			if from.distance_to(p) > reach + t.radius * 0.5:
				return {}
			if pr.blockable and _blocked(from, p, float(pr.width), t, str(pr.affects), float(pr.explode)):
				return {}
			return {"ok": true, "pos": p, "chance": _chance(t, float(hit.time), float(pr.width) + t.radius)}
		"cone", "area", "zone":
			var delay := ct + float(pr.area_delay)
			var p := _predict(t, delay * lead)
			if pr.at_self:
				if from.distance_to(p) > float(pr.radius) + t.radius * 0.5:
					return {}
				return {"ok": true, "pos": p, "chance": 1.0 if delay <= 0.05 else _chance(t, delay, float(pr.radius) - from.distance_to(p) + t.radius)}
			var land := from + (p - from).limit_length(rng)
			var room := float(pr.radius) + t.radius * 0.5 - land.distance_to(p)
			if room <= 0.0:
				return {}
			if pr.shape == "zone":
				return {"ok": true, "pos": land, "chance": clampf(room / maxf(pr.radius, 1.0) + 0.3, 0.0, 1.0)}
			return {"ok": true, "pos": land, "chance": _chance(t, delay, room)}
		"beam":
			var delay := ct + float(pr.area_delay)
			var p := _predict(t, delay * lead)
			if from.distance_to(p) > float(pr.length) + t.radius * 0.5:
				return {}
			return {"ok": true, "pos": p, "chance": _chance(t, delay, float(pr.width) + t.radius)}
	if from.distance_to(t.global_position) <= rng + t.radius:
		return {"ok": true, "pos": t.global_position, "chance": 1.0}
	return {}


func _intercept(from: Vector2, t: Unit, speed: float, delay: float) -> Dictionary:
	var p0 := _predict(t, delay)
	var v: Vector2 = Vector2.ZERO if _cc_left(t) > delay + 0.3 else t.velocity
	var d := p0 - from
	var a := v.dot(v) - speed * speed
	var b := 2.0 * d.dot(v)
	var c := d.dot(d)
	var tt := d.length() / speed
	if absf(a) > 0.001:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var s := sqrt(disc)
			var best := INF
			for x in [(-b - s) / (2.0 * a), (-b + s) / (2.0 * a)]:
				if x > 0.0 and x < best:
					best = x
			if best < INF:
				tt = best
	return {"pos": p0 + v * tt, "time": tt + delay}


## Chance that `t` fails to move `room` units out of the way in `time` seconds. Bots are
## judged by their difficulty (a brick never dodges), players by a typical reaction time.
func _chance(t: Unit, time: float, room: float) -> float:
	var stuck := _cc_left(t)
	if stuck >= time:
		return 1.0
	var react := 0.25
	var dodges := 0.65
	if t is Champion and t.is_bot and t.brain != null:
		react = float(t.brain.cfg.react)
		dodges = float(t.brain.cfg.dodge)
	if t.velocity.length() < 5.0 and not (t is Champion and t.is_bot):
		dodges *= 0.85
	var avail := time - stuck - react
	if avail <= 0.0 or dodges <= 0.0:
		return 1.0
	var geo := clampf(room / maxf(t.stats.move_speed * avail, 1.0), 0.0, 1.0)
	return geo + (1.0 - geo) * (1.0 - dodges)


## A projectile that stops at the first unit would hit something else before `t`.
func _blocked(from: Vector2, to: Vector2, width: float, t: Unit, affects: String, explode: float) -> bool:
	var seg := to - from
	var l := seg.length()
	if l < 1.0:
		return false
	var dir := seg / l
	var ts := (t.global_position - from).dot(dir)
	var list: Array = foe_units.duplicate()
	for e in foes:
		if e != t:
			list.append(e)
	if affects == "all":
		list += ally_units
		list += friends
	for u in list:
		if u == t or not u.targetable():
			continue
		var rel: Vector2 = u.global_position - from
		var s := rel.dot(dir)
		if s <= 0.0 or s >= ts:
			continue
		if absf(rel.cross(dir)) <= width + u.radius:
			if explode > 0.0 and u.global_position.distance_to(t.global_position) < explode * 0.75:
				continue
			return true
	return false


## An enemy attack or spell will land on us within `window` seconds.
func _incoming_hit(window: float) -> bool:
	for e in foes:
		if e.attack_target == me and e.global_position.distance_to(me.global_position) <= e.attack_reach(me) + 10.0 and e.attack_cd <= window:
			return true
	for th in _threats():
		if _hits(th, me.global_position, Vector2.ZERO) and _hit_time(th, me.global_position) <= window:
			return true
	return false


## Shields and heals on ourselves while we are taking (or about to take) damage.
func _defense(c: Dictionary) -> Dictionary:
	var pr: Dictionary = c.prof
	if pr.bond or (pr.self_shield.is_empty() and pr.self_heal.is_empty()):
		return {}
	if pr.targeting != "self" and pr.targeting != "ally" and not pr.at_self:
		return {}
	var incoming := maxf(_taken(1.5), _threat_on_me(1.5) * 0.5)
	if incoming <= 0.0 and me.hp > me.stats.max_hp * 0.6:
		return {}
	var rank: int = c.rank
	var sh := BotKit.amount(pr, "self_shield", me, me, rank)
	var hl := minf(BotKit.amount(pr, "self_heal", me, me, rank), me.stats.max_hp - me.hp)
	var v: float = (minf(sh, incoming * 1.5 + 60.0) + hl) / me.stats.max_hp
	if pr.ms_buff > 0.1 and mode == "retreat":
		v += 0.2
	return {"score": v * 2.0, "aim": me.global_position, "tid": me.net_id}


## Heals, shields and cleanses for allies (and us), weighted by how much they need it.
func _support(c: Dictionary) -> Dictionary:
	var pr: Dictionary = c.prof
	if not pr.support:
		return {}
	var rank: int = c.rank
	var ctx := BotKit.ctx_for(pr, me, me, rank)
	var rng := Effects.num(pr.range, ctx, 700.0)
	var team: Array = [me] + friends
	if pr.targeting == "self":
		var total := 0.0
		for a in team:
			if a == me or a.global_position.distance_to(me.global_position) <= float(pr.radius) + a.radius:
				total += _need(pr, a, rank)
		return {"score": total, "aim": me.global_position, "tid": me.net_id}
	var best := {}
	var bs := 0.0
	for a in team:
		var d: float = me.global_position.distance_to(a.global_position)
		var v := 0.0
		if pr.targeting == "ally":
			if d > rng + a.radius + me.radius:
				continue
			v = _need(pr, a, rank)
		elif pr.shape == "projectile":
			if a == me or d > (Effects.num(pr.prange, ctx, rng) if pr.prange != null else rng):
				continue
			if _blocked_ally(me.global_position, a.global_position, float(pr.width), a):
				continue
			v = _need(pr, a, rank) * 0.85
		elif pr.shape in ["zone", "area"]:
			if d > rng + float(pr.radius) * 0.5:
				continue
			for b in team:
				if b.global_position.distance_to(a.global_position) <= float(pr.radius):
					v += _need(pr, b, rank)
		if v > bs:
			bs = v
			best = {"score": v, "aim": a.global_position, "tid": a.net_id}
	return best


func _need(pr: Dictionary, a: Unit, rank: int) -> float:
	var fighting: bool = a.in_combat() or world.time - a.hurt_t < 2.0
	if not fighting and a.hp > a.stats.max_hp * 0.7:
		return 0.0
	var heal := minf(BotKit.amount(pr, "ally_heal", me, a, rank), a.stats.max_hp - a.hp)
	var shield := BotKit.amount(pr, "ally_shield", me, a, rank) * (1.0 if fighting else 0.2)
	var v: float = (heal + shield * 0.7) / a.stats.max_hp * (1.5 if fighting else 0.6)
	if pr.cleanse_ally and (a.has_status("stun") or a.has_status("root")):
		v += 0.5
	return v


## Something of the other team stands in the way of a skillshot meant for ally `a`.
func _blocked_ally(from: Vector2, to: Vector2, width: float, a: Unit) -> bool:
	var seg := to - from
	var l := seg.length()
	if l < 1.0:
		return false
	var dir := seg / l
	for list in [foe_units, foes, ally_units, friends]:
		for u in list:
			if u == a or u == me:
				continue
			var rel: Vector2 = u.global_position - from
			var s := rel.dot(dir)
			if s > 0.0 and s < l - a.radius and absf(rel.cross(dir)) <= width + u.radius:
				return true
	return false


## Getting away from `chaser`: dashes/blinks toward safety, speed boosts, slowing or stopping it.
func _escape(c: Dictionary, chaser) -> Dictionary:
	var pr: Dictionary = c.prof
	var safe := _safe_point()
	var dir := (safe - me.global_position).normalized()
	if pr.mobility:
		if str(pr.dash.get("to", "")) == "target":
			return {}
		var dest := world.map.nearest_open(me.global_position + dir * _mob_dist(pr, me, int(c.rank)))
		if _turret_danger(dest):
			return {}
		var aim := dest
		if pr.dash_back:
			aim = me.global_position - dir * 120.0
		return {"score": 0.55, "aim": aim, "tid": 0}
	if pr.ms_buff >= 0.15:
		return {"score": 0.45, "aim": me.global_position, "tid": me.net_id}
	if _valid(chaser):
		if pr.shape == "trap":
			return {"score": 0.35, "aim": me.global_position, "tid": 0}
		if pr.hard or pr.cc.has("slow"):
			var o := _offense(c, chaser, "fight")
			if float(o.get("score", 0.0)) > 0.0:
				o.score = float(o.score) + 0.3
				return o
		if not pr.summon.is_empty():
			return {"score": 0.25, "aim": me.global_position + (chaser.global_position - me.global_position).limit_length(150.0), "tid": 0}
	return {}


## Wave clear: the aim that hits (and kills) the most enemy minions.
func _farm(c: Dictionary) -> Dictionary:
	var pr: Dictionary = c.prof
	if not pr.farm or c.kind == "item" or str(c.slot) == "r":
		return {}
	var rank: int = c.rank
	var ctx := BotKit.ctx_for(pr, me, me, rank)
	var rng := Effects.num(pr.range, ctx, 700.0)
	var near := []
	for m in foe_units:
		if m is Minion and me.global_position.distance_to(m.global_position) <= rng + float(pr.radius) + 50.0:
			near.append(m)
	if near.size() < 3:
		return {}
	var best := {}
	var bs := 0.0
	for m in near:
		var aim: Vector2 = m.global_position
		var hits := 0
		var kills := 0
		for o in near:
			if _farm_hits(pr, aim, o):
				hits += 1
				if BotKit.damage(pr, me, o, rank) >= o.hp:
					kills += 1
		var s := 0.08 * hits + 0.25 * kills
		if hits >= 3 and s > bs:
			bs = s
			best = {"score": s, "aim": aim, "tid": m.net_id}
	return best


func _farm_hits(pr: Dictionary, aim: Vector2, o: Unit) -> bool:
	var from := me.global_position
	var at: Vector2 = from if pr.at_self or pr.targeting == "self" else aim
	match pr.shape:
		"projectile", "beam":
			var dir := (aim - from).normalized()
			var rel: Vector2 = o.global_position - from
			if pr.explode > 0.0 and not pr.pierce:
				return o.global_position.distance_to(aim) <= float(pr.explode)
			return rel.dot(dir) > 0.0 and absf(rel.cross(dir)) <= float(pr.width) + o.radius
		"cone":
			var rel: Vector2 = o.global_position - from
			return rel.length() <= float(pr.radius) and absf((aim - from).angle_to(rel)) <= deg_to_rad(float(pr.angle)) * 0.5
	return o.global_position.distance_to(at) <= float(pr.radius) + o.radius * 0.5


## While hitting a structure: summons tank the shots, steroids speed it up.
func _siege_cast(c: Dictionary, t) -> Dictionary:
	var pr: Dictionary = c.prof
	if not _valid(t):
		return {}
	if not pr.summon.is_empty() and not bool(pr.summon.get("ward", false)):
		var aim: Vector2 = t.global_position + (me.global_position - t.global_position).normalized() * 250.0
		return {"score": 0.4, "aim": aim, "tid": 0}
	return {}

# ------------------------------------------------------------ survival ---

## Potions, and when a lot of damage is coming: heal/barrier, shields, stasis, cleanse, Flash.
func _reflexes() -> void:
	_potion()
	if difficulty == "brick":
		return
	var ehp := me.hp + me.shield
	var taken := _taken(1.0)
	if foes.is_empty() and taken <= 0.0:
		return
	var incoming := maxf(taken * 1.3, _threat_on_me(1.2) * (0.7 if cfg.track_cds else 0.5))
	var hard_cc := me.has_status("stun") or me.has_status("root")
	if hard_cc and incoming > ehp * 0.3:
		_cleanse()
	if incoming >= ehp or (me.hp < me.stats.max_hp * 0.2 and taken > 0.0):
		_save(incoming >= ehp)


func _potion() -> void:
	if _at_fountain() or me.has_status("hot"):
		return
	var limit := 0.4 if difficulty == "brick" else 0.65
	if me.hp > me.stats.max_hp * limit or me.stats.max_hp - me.hp < 120.0:
		return
	for i in Champion.ITEM_SLOTS:
		var it = me.item_def(i)
		if it == null or it.active == null or not it.consumable or me.items[i].cd > 0.0:
			continue
		if BotKit.item_kit(str(me.items[i].id)).get("hot", false) and me.use_item(i, me.global_position, me.net_id):
			return


func _cleanse() -> void:
	var i := _summoner_with("cleanse")
	if i >= 0 and me.use_summoner(i, me.global_position, me.net_id):
		return
	for c in _usable():
		if c.prof.cleanse_self and _fire(c, me.global_position, me.net_id):
			return


func _save(lethal: bool) -> void:
	var i := _summoner_with("defend")
	if i >= 0 and me.use_summoner(i, me.global_position, me.net_id):
		return
	for c in _usable():
		var pr: Dictionary = c.prof
		if pr.stasis > 0.0 and (lethal or cfg.items == "smart"):
			if _fire(c, me.global_position, me.net_id):
				return
		elif pr.invuln > 0.0 and _incoming_hit(pr.invuln):
			var t := _nearest_foe()
			if _fire(c, _predict(t, pr.invuln) if t != null else me.global_position, t.net_id if t != null else 0):
				return
		elif not pr.bond and (not pr.self_shield.is_empty() or not pr.self_heal.is_empty()) and pr.targeting in ["self", "ally"]:
			if _fire(c, me.global_position, me.net_id):
				return
	if lethal and cfg.summoners == "smart" and _foes_near(me.global_position, 700.0) > 0:
		var f := _summoner_with("escape")
		if f >= 0:
			var dest := world.map.nearest_open(me.global_position + (_safe_point() - me.global_position).normalized() * 400.0)
			me.use_summoner(f, dest, 0)


func _under_ally_turret() -> Unit:
	for t in ally_towers:
		if _is_turret(t) and me.global_position.distance_to(t.global_position) <= t.stats.attack_range + t.radius:
			return t
	return null


# -------------------------------------------------------------- summoners ---

## Index of a ready summoner spell with this "bot" hint (see MODDING.md), or -1.
func _summoner_with(hint: String) -> int:
	if cfg.summoners == "none":
		return -1
	for i in me.summoners.size():
		var sp = me.summoner_def(i)
		var ab = me.summoner_ability(i)
		if sp == null or ab == null or str(ab.get("bot", sp.bot)) != hint:
			continue
		if (me.sum_cd[i] > 0.0 and ab == sp.active) or not me.can_use_summoner(ab):
			continue
		return i
	return -1


func _use_summoners() -> void:
	if cfg.summoners == "none":
		return
	for i in me.summoners.size():
		var sp = me.summoner_def(i)
		var ab = me.summoner_ability(i)
		if sp == null or ab == null:
			continue
		var recast: bool = ab != sp.active
		if (me.sum_cd[i] > 0.0 and not recast) or not me.can_use_summoner(ab):
			continue
		var hint := str(ab.get("bot", sp.bot))
		if cfg.summoners == "smart":
			if _smart_summoner(i, ab, hint):
				return
		elif _hint_summoner(i, ab, hint):
			return


## "scripting": summoner spells used for kills, saves, chases and objectives.
func _smart_summoner(i: int, ab: Dictionary, hint: String) -> bool:
	var t := focus if _valid(focus) and mode == "fight" else null
	var rng := Effects.num(ab.get("range", 700.0), {"caster": me, "target": me, "rank": me.level}, 700.0)
	match hint:
		"escape":
			# Flash in for a kill that is otherwise just out of reach.
			if t != null and _killable(t, 2.0) and _dive_ok(t):
				var d := me.global_position.distance_to(t.global_position)
				var reach := me.attack_reach(t)
				if d > reach + 60.0 and d < reach + rng - 40.0 and t.velocity.dot(t.global_position - me.global_position) > 0.0:
					return me.use_summoner(i, t.global_position + (me.global_position - t.global_position).normalized() * (reach - 50.0), 0)
		"defend":
			for a in friends:
				if a.global_position.distance_to(me.global_position) < 800.0 and a.hp < a.stats.max_hp * 0.2 and world.time - a.hurt_t < 1.0:
					return me.use_summoner(i, me.global_position, me.net_id)
		"kill":
			if t != null and me.global_position.distance_to(t.global_position) <= rng + t.radius + me.radius:
				var ign := _ignite(me, t, 5.0)
				var ehp := t.hp + t.shield
				var burst := _burst(me, t, 2.5) - _ignite(me, t, 2.5)
				if (burst < ehp and burst + ign * 0.8 >= ehp) or ehp <= ign * 0.7 or (BotKit.heals(t) and t.hp < t.stats.max_hp * 0.6):
					return me.use_summoner(i, t.global_position, t.net_id)
		"fight":
			if str(ab.get("targeting", "")) == "unit":
				var worst: Champion = null
				var wv := 0.0
				for e in foes:
					if e.global_position.distance_to(me.global_position) > rng + e.radius + me.radius:
						continue
					var v := _burst(e, me, 2.5)
					if v > wv:
						wv = v
						worst = e
				if worst != null and (wv > (me.hp + me.shield) * 0.6 or (t != null and worst == t and _killable(t))):
					return me.use_summoner(i, worst.global_position, worst.net_id)
			elif t != null:
				var pr := BotKit.summoner_kit(ab, "fight")
				var shot := _aim(pr, t, rng, 0.0, BotKit.ctx_for(pr, me, t, me.level))
				if shot.get("ok", false) and float(shot.chance) >= 0.6 and me.global_position.distance_to(t.global_position) > 450.0:
					return me.use_summoner(i, shot.pos, t.net_id)
		"dash":
			if t != null and _killable(t, 2.0) and _dive_ok(t):
				return me.use_summoner(i, t.global_position, t.net_id)
		"chase":
			if t != null and _killable(t) and me.global_position.distance_to(t.global_position) > me.attack_reach(t) + 120.0:
				return me.use_summoner(i, me.global_position, me.net_id)
			if mode == "retreat" and _foes_near(me.global_position, 600.0) > 0:
				return me.use_summoner(i, me.global_position, me.net_id)
		"mana":
			if me.uses_mana() and me.mana < me.stats.max_mana * 0.2 and not _at_fountain():
				return me.use_summoner(i, me.global_position, me.net_id)
		"smite":
			for u in foe_units:
				if u.is_ward or u.hp > 600.0 or me.global_position.distance_to(u.global_position) > rng + u.radius + me.radius:
					continue
				var worth: bool = (u is Minion and u.minion_type in ["siege", "super"]) or (u is Summon and mode == "fight")
				if worth and me.use_summoner(i, u.global_position, u.net_id):
					return true
	return false


## "normal": summoner spells by their "bot" hint, like a decent player would.
func _hint_summoner(i: int, ab: Dictionary, hint: String) -> bool:
	var rng := Effects.num(ab.get("range", 700.0), {"caster": me, "target": me, "rank": me.level}, 700.0)
	var foe := world.nearest_enemy(me.global_position, me.team, clampf(rng, 600.0, 1200.0) + 100.0, true)
	var fd := me.global_position.distance_to(foe.global_position) if foe != null else INF
	var low: bool = me.hp < me.stats.max_hp * 0.3
	var target: Unit = null
	var aim := me.global_position
	match hint:
		"escape":
			if low and fd < 450.0:
				target = me
				aim = me.global_position + (me.global_position - foe.global_position).normalized() * 400.0
		"defend":
			if low and fd < 900.0:
				target = me
		"kill":
			if foe != null and fd <= rng + 40.0 and foe.hp < foe.stats.max_hp * 0.3:
				target = foe
		"fight":
			if foe != null and fd <= rng and (me.in_combat() or foe.hp < foe.stats.max_hp * 0.5):
				target = foe
				aim = foe.global_position + foe.velocity * 0.3
		"dash":
			if not low:
				target = me
		"cleanse":
			if fd < 900.0 and (me.has_status("stun") or me.has_status("root") or me.has_status("slow")):
				target = me
		"mana":
			if me.uses_mana() and me.mana < me.stats.max_mana * 0.25:
				target = me
		"chase":
			if foe != null and fd < 900.0 and (low or foe.hp < foe.stats.max_hp * 0.4):
				target = me
		"smite":
			for u in foe_units:
				if u is Minion and u.minion_type == "siege" and u.hp <= 600.0 and me.global_position.distance_to(u.global_position) <= rng + u.radius:
					target = u
					break
	if target == null:
		return false
	if aim == me.global_position and target != me:
		aim = target.global_position
	return me.use_summoner(i, aim, target.net_id)


## "normal": item actives fired at a nearby enemy champion or when hurt.
func _basic_items() -> void:
	var foe := world.nearest_enemy(me.global_position, me.team, 600.0, true)
	if foe == null:
		return
	for i in Champion.ITEM_SLOTS:
		var it = me.item_def(i)
		if it == null or it.active == null or it.consumable or me.items[i].cd > 0.0:
			continue
		match str(it.active.targeting):
			"ally":
				if me.hp < me.stats.max_hp * 0.5:
					me.use_item(i, me.global_position, me.net_id)
			"self":
				if me.hp < me.stats.max_hp * 0.4 or (mode == "fight" and BotKit.item_kit(str(me.items[i].id)).damage):
					me.use_item(i, foe.global_position, foe.net_id)
			_:
				if mode == "fight":
					me.use_item(i, foe.global_position, foe.net_id)


# --------------------------------------------------------------- shopping ---

func _shop() -> void:
	if Game.items.is_empty() or not me.can_shop():
		return
	if not _planned:
		plan = _make_plan()
		_planned = true
	for attempt in 3:
		var done := []
		var skip := me.shop_toward(plan, done)
		for id in done + skip:
			plan.erase(id)
		if plan.is_empty() or me._free_slot() >= 0 or not _sell_junk():
			break


## Sells a starter item or consumable to make room for the build (full inventory).
func _sell_junk() -> bool:
	for i in Champion.ITEM_SLOTS:
		var it = me.item_def(i)
		if it != null and it.rarity in ["starter", "consumable"]:
			return me.sell(i) == ""
	return false


func _make_plan() -> Array:
	if cfg.build == "random":
		return Champion.recommended_build(me.def, true)
	var role := Champion.role_of(me.def)
	var fresh := world.time < 90.0 and me.count_items("") == 0
	var out := []
	var b = BotKit.BUILDS.get(me.char_id)
	if b == null:
		if fresh:
			out += BotKit.ROLE_START.get(role, [])
		out += Champion.recommended_build(me.def)
	else:
		if fresh:
			out += b.start
		var items: Array = b.items
		if b.has("support") and _lane_partner():
			items = b.support
		for id in items:
			var r := _resolve(str(id), role)
			if r != "" and not out.has(r):
				out.append(r)
	return out.filter(func(id): return Game.items.has(id))


## Another allied champion shares our lane (supports build for the team then).
func _lane_partner() -> bool:
	var n := world.map.lane_count()
	for c in world.champions.values():
		if c != me and c.team == me.team and (n <= 1 or posmod(c.bot_lane, n) == posmod(me.bot_lane, n)):
			return true
	return false


## Picks a situational item: boots/defense against the enemy team's damage type, anti-heal
## against healing ("adaptive" only; other builds use defaults and skip anti-heal).
func _resolve(id: String, role: String) -> String:
	if not id.begins_with("@"):
		return id
	var adaptive: bool = cfg.build == "adaptive"
	var magic := 0.5
	var heal := false
	var cc := 0
	var n := 0
	for c in world.champions.values():
		if c.team == me.team:
			continue
		n += 1
		magic += BotKit.magic_share(c)
		heal = heal or BotKit.heals(c)
		var ck := BotKit.char_kit(c.def)
		for slot in SLOTS:
			if ck.has(slot) and ck[slot].hard:
				cc += 1
	magic = (magic - 0.5) / n if n > 0 else 0.5
	match id:
		"@tank_boots":
			return "mercurys_treads" if adaptive and (magic > 0.5 or cc >= 3) else "plated_steelcaps"
		"@defense":
			if not adaptive:
				return "thornmail"
			if magic > 0.5:
				return "spirit_visage" if role == "bruiser" else "force_of_nature"
			return "thornmail" if heal else "randuins_omen"
		"@antiheal":
			if not adaptive or not heal:
				return ""
			return {"marksman": "mortal_reminder", "mage": "morellonomicon"}.get(role, "chempunk_chainsword")
	return ""


# ----------------------------------------------------------------- skills ---

func _level_up() -> void:
	var guard := 0
	while me.skill_points > 0 and guard < 8:
		guard += 1
		var done := false
		for s in _skill_order():
			if me.can_rank_up(s):
				me.rank_up(s)
				done = true
				break
		if not done:
			return


## R first, one point in every basic ability, then max them in the character's order.
func _skill_order() -> Array:
	if cfg.skills == "random":
		var o := SLOTS.duplicate()
		o.shuffle()
		return o
	var order := ["r"]
	var pri := BotKit.skill_priority(me)
	for s in pri:
		if _rank(me, s) == 0:
			order.append(s)
	for s in pri:
		if not order.has(s):
			order.append(s)
	for s in ["q", "w", "e"]:
		if not order.has(s):
			order.append(s)
	return order
