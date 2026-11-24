class_name Champion
extends Unit
## A player (or bot) controlled character built from a character definition.
## Also owns everything per-player: ability ranks, mana, gold and items.

const MAX_LEVEL := 21
const SKILL_POINT_LEVELS := 18
const SLOTS := ["q", "w", "e", "r"]
const ITEM_SLOTS := 6
const SELL_RATIO := 0.7
## Events that item/passive effects can't set off again (no infinite proc chains) unless the
## trigger has "procs": true.
const PROC_GUARDED := ["deal_damage", "deal_damage_pre", "heal_ally", "shield_ally", "buff_ally"]

var peer := 0
var def := {}
var player_name := ""
var is_bot := false
var cooldowns := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
var cd_total := {"q": 1.0, "w": 1.0, "e": 1.0, "r": 1.0}
var recasts := {}              # host: slot -> {until, charges (-1 = unlimited), status} while its recast is available
var recast_left := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}     # seconds the recast stays available (replicated)
var recast_charges := {"q": 0, "w": 0, "e": 0, "r": 0}         # recasts left, -1 = unlimited (replicated)
var ranks := {"q": 0, "w": 0, "e": 0, "r": 0}
var skill_points := 1
var level := 1
var xp := 0.0
var xp_frac := 0.0
var kills := 0
var deaths := 0
var assists := 0
var gold := 0.0
var energy := 0.0
var items: Array = [null, null, null, null, null, null]  # {id, n, cd, cd_total}
var counters := {}
var respawn_timer := 0.0
var recall_timer := 0.0
var casting = null
var amove = null
var trig_list: Array = []      # [{tr, key, src, slot, name, color}]
var trig_by_event := {}
var trigger_counts := {}
var trigger_cds := {}
var trigger_cd_total := {}
var slot_keys: Array = [[], [], [], [], [], []]   # item slot -> its trigger keys (passive cooldown display)
var interval_timers := {}
var _trigger_depth := 0
var _dynamic_stats := false
var _dyn_t := 0.0
var _energy_pos := Vector2.INF
var bot_t := 0.0
var bot_lane := 0
var bot_wp := 1
var bot_plan: Array = []
var target_id := 0


func setup(d: Dictionary) -> void:
	kind = "champion"
	is_champion = true
	peer = int(d.peer)
	team = int(d.team)
	char_id = str(d.character)
	player_name = str(d.get("name", "Player"))
	is_bot = bool(d.get("bot", false))
	bot_lane = int(d.get("lane", 0))
	def = Game.characters.get(char_id, {})
	if def.is_empty():
		def = {"id": char_id, "name": "???", "color": Color.MAGENTA, "stats": Content.DEFAULT_STATS.duplicate(),
			"per_level": {}, "attack": attack_def, "passive": {"name": "", "description": "", "triggers": [], "icon": null},
			"abilities": {}, "sprite": null, "portrait": null}
	display_name = def.name
	color = def.color
	base_stats = def.stats.duplicate()
	base_radius = Content.BASE_RADIUS
	attack_def = def.attack
	sprite_info = def.sprite
	global_position = d.pos
	gold = float(d.get("gold", 0.0))
	_rebuild_triggers()


func get_level() -> int:
	return level


func label() -> String:
	return "%s (%s)" % [player_name, display_name]


func uses_mana() -> bool:
	return stats.max_mana > 0.0


# --------------------------------------------------------------- commands ---

func command(cmd: String, args: Array) -> void:
	match cmd:
		"rank_up":
			if args.size() > 0 and args[0] is String:
				rank_up(args[0])
			return
		"buy":
			if args.size() > 0 and args[0] is String:
				var err := buy(args[0])
				if err != "":
					world.fx("notice", {"peer": peer, "text": err})
			return
		"sell":
			if args.size() > 0 and (args[0] is int or args[0] is float):
				var err := sell(int(args[0]))
				if err != "":
					world.fx("notice", {"peer": peer, "text": err})
			return
		"swap_items":
			if args.size() > 1 and (args[0] is int or args[0] is float) and (args[1] is int or args[1] is float):
				var a := clampi(int(args[0]), 0, ITEM_SLOTS - 1)
				var b := clampi(int(args[1]), 0, ITEM_SLOTS - 1)
				var tmp = items[a]
				items[a] = items[b]
				items[b] = tmp
				_items_changed()
			return
		"cheat":
			if args.size() > 0 and args[0] is String and world.cheats_allowed():
				cheat(args[0])
			return
		"autopilot":
			is_bot = args.size() > 0 and bool(args[0])
			return
		"item":
			if args.size() >= 3 and (args[0] is int or args[0] is float) and args[1] is Vector2 and (args[2] is int or args[2] is float):
				use_item(int(args[0]), args[1], int(args[2]))
			return
	if dead:
		return
	match cmd:
		"move":
			if args.size() > 0 and args[0] is Vector2:
				move_goal = world.map.clamp_inside(args[0])
				attack_target = null
				amove = null
				_cancel_recall()
		"attack":
			if args.size() > 0 and (args[0] is int or args[0] is float):
				var t = world.entities.get(int(args[0]))
				if t is Unit and valid_target(t):
					attack_target = t
					move_goal = null
					amove = null
					_cancel_recall()
		"amove":
			if args.size() > 0 and args[0] is Vector2:
				amove = world.map.clamp_inside(args[0])
				move_goal = null
				attack_target = null
				_cancel_recall()
		"stop":
			move_goal = null
			attack_target = null
			amove = null
			path = PackedVector2Array()
		"cast":
			if args.size() >= 3 and args[0] is String and args[1] is Vector2 and (args[2] is int or args[2] is float):
				cast(args[0], args[1], int(args[2]))
		"recall":
			start_recall()


func cast(slot: String, aim: Vector2, tid: int) -> bool:
	var ab = active_ability(slot)
	if ab == null or int(ranks.get(slot, 0)) <= 0 or dead or cooldowns.get(slot, 0.0) > 0.0 or not can_cast() or casting != null:
		return false
	var is_recast := recasts.has(slot) and not is_same(ab, def.abilities.get(slot))
	var ctx := _make_ctx(ab, aim, tid)
	if ctx.is_empty():
		return false
	var cost := ability_cost(ab, ctx)
	ctx.cost_paid = cost if ab.cost_type != "health" else 0.0  # "amount" in cast triggers = mana spent
	if cost > 0.0:
		if ab.cost_type == "health":
			if hp <= cost:
				return false
			hp -= cost
		else:
			if mana < cost:
				return false
			mana -= cost
	var cd := ability_cooldown(ab, ctx)
	cooldowns[slot] = cd
	cd_total[slot] = maxf(cd, 0.01)
	if is_recast:
		_spend_recast(slot)
	_cancel_recall()
	face(ctx.pos)
	var ct := Effects.num(ab.cast_time, ctx, 0.0)
	if ct > 0.0:
		casting = {"ab": ab, "ctx": ctx, "time": ct}
		set_anim_lock(ANIM_CAST, ct)
	else:
		set_anim_lock(ANIM_CAST, 0.25)
		_execute(ab, ctx)
	return true


## Mana (or health) cost at the ability's current rank. Manaless champions pay nothing.
func ability_cost(ab: Dictionary, ctx := {}) -> float:
	if ab.cost_type != "health" and not uses_mana():
		return 0.0
	if ctx.is_empty():
		ctx = {"caster": self, "rank": maxi(int(ranks.get(ab.slot, 1)), 1)}
	return maxf(Effects.num(ab.cost, ctx, 0.0), 0.0)


static func sell_value(it: Dictionary) -> int:
	return int(floorf(float(it.cost) * SELL_RATIO + 0.001))


## Whether you can afford an ability's mana (or health) cost right now.
func can_pay(ab: Dictionary) -> bool:
	var cost := ability_cost(ab)
	if cost <= 0.0:
		return true
	return hp > cost if ab.cost_type == "health" else mana >= cost


func ability_cooldown(ab: Dictionary, ctx := {}) -> float:
	var r := maxi(int(ranks.get(ab.slot, 1)), 1)
	if ctx.is_empty():
		ctx = {"caster": self, "rank": r}
	var cd := Effects.num(ab.cooldown, ctx, 6.0)
	if ab.get("auto_rank", false):
		cd *= 1.0 - (0.08 if ab.slot == "r" else 0.05) * (r - 1)
	return maxf(cd * 100.0 / (100.0 + maxf(stats.ability_haste, -50.0)) * stats.cooldown_mult, 0.0)


func _execute(ab: Dictionary, ctx: Dictionary) -> void:
	if dead:
		return
	ctx.origin = global_position
	world.fx("cast", {"p": global_position, "c": color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": ab.slot})
	Effects.run(ab.effects, ctx)
	trigger("cast", self, ctx.pos, {"cast_slot": ab.slot, "amount": float(ctx.get("cost_paid", 0.0))})
	if ab.get("recast") is Dictionary and not dead:
		_open_recast(ab, ctx)


# ---------------------------------------------------------------- recasts ---

## The ability a slot casts right now: its "recast" while that is available.
func active_ability(slot: String):
	var ab = def.abilities.get(slot)
	if ab != null and ab.get("recast") is Dictionary and float(recast_left.get(slot, 0.0)) > 0.0:
		return ab.recast
	return ab


## After casting an ability with a "recast", the slot casts the recast for `window` seconds
## (or while you have its `status`) up to `charges` times. Its full cooldown waits until then.
func _open_recast(ab: Dictionary, ctx: Dictionary) -> void:
	var rc: Dictionary = ab.recast
	var status := str(rc.get("status", ""))
	var window := Effects.num(rc.get("window"), ctx, 1.0e9 if status != "" else 3.0)
	var charges := int(Effects.num(rc.get("charges"), ctx, 1.0))
	recasts[ab.slot] = {"until": world.time + window, "charges": charges if charges > 0 else -1, "status": status}
	recast_charges[ab.slot] = recasts[ab.slot].charges
	var gap := ability_cooldown(rc, ctx)
	cooldowns[ab.slot] = gap
	cd_total[ab.slot] = maxf(gap, 0.01)
	_update_recasts()


func _spend_recast(slot: String) -> void:
	var r: Dictionary = recasts[slot]
	if int(r.charges) > 0:
		r.charges = int(r.charges) - 1
		recast_charges[slot] = r.charges
		if int(r.charges) == 0:
			_close_recast(slot)


func _update_recasts() -> void:
	for slot in recasts.keys():
		var r: Dictionary = recasts[slot]
		var left: float = r.until - world.time
		if r.status != "":
			var s := find_status(r.status)
			left = minf(left, float(s.time)) if not s.is_empty() else 0.0
		if left <= 0.0:
			_close_recast(slot)
		else:
			recast_left[slot] = left


## The recast is over: the ability's full cooldown starts now.
func _close_recast(slot: String) -> void:
	recasts.erase(slot)
	recast_left[slot] = 0.0
	recast_charges[slot] = 0
	var ab = def.abilities.get(slot)
	if ab != null:
		var cd := ability_cooldown(ab)
		cooldowns[slot] = cd
		cd_total[slot] = maxf(cd, 0.01)


func _make_ctx(ab: Dictionary, aim: Vector2, tid: int) -> Dictionary:
	var r := maxi(int(ranks.get(ab.slot, 1)), 1)
	var ctx := {"caster": self, "team": team, "ability": ab.name, "char": char_id, "color": color,
		"origin": global_position, "target": self, "i": 0, "rank": r, "src_slot": ab.slot}
	if ab.get("auto_rank", false) and ab.slot in SLOTS:
		ctx.rank_mult = 1.0 + (0.5 if ab.slot == "r" else 0.25) * (r - 1)
	var rng := Effects.num(ab.range, ctx, 700.0)
	ctx.range = rng
	var to := aim - global_position
	var dir := to.normalized() if to.length() > 1.0 else Vector2(facing, 0)
	ctx.dir = dir
	match ab.targeting:
		"self":
			ctx.pos = global_position
		"unit", "ally":
			var enemy: bool = ab.targeting == "unit"
			var t = world.entities.get(tid)
			if not (t is Unit and _unit_ok(t, enemy)):
				t = world.pick_unit(aim, team, enemy, 100.0, false)
			if t == null or global_position.distance_to(t.global_position) > rng + t.radius + radius + 40.0:
				return {}
			ctx.target = t
			ctx.pos = t.global_position
			if t != self:
				ctx.dir = (t.global_position - global_position).normalized()
		_:
			ctx.pos = global_position + dir * minf(to.length(), rng)
	return ctx


func _unit_ok(t: Unit, enemy: bool) -> bool:
	return not t.dead and t.targetable() and not t.is_structure and (t.team != team) == enemy and t.visible_to(team)


## slot: q/w/e/r, "all" or "basic" (q, w and e). percent: reduce by that fraction of the remaining time.
func change_cooldown(slot: String, amount: float, reset: bool, percent := false) -> void:
	for s in SLOTS:
		if slot == "all" or slot == s or (slot == "basic" and s != "r"):
			if reset:
				cooldowns[s] = 0.0
			elif percent:
				cooldowns[s] = maxf(cooldowns[s] * (1.0 - amount), 0.0)
			else:
				cooldowns[s] = maxf(cooldowns[s] - amount, 0.0)


func change_item_cooldown(item_id: String, amount: float, reset: bool) -> void:
	for inst in items:
		if inst != null and (item_id == "all" or inst.id == item_id):
			inst.cd = 0.0 if reset else maxf(inst.cd - amount, 0.0)


## Puts an item's active on cooldown (shown on its slot).
func set_item_cooldown(item_id: String, amount: float) -> void:
	for inst in items:
		if inst != null and inst.id == item_id:
			inst.cd = maxf(amount, 0.0)
			inst.cd_total = maxf(amount, 0.01)


## Puts a passive trigger on cooldown (item slots show their passives' cooldowns).
func set_trigger_cooldown(key: String, amount: float) -> void:
	if key == "":
		return
	trigger_cds[key] = maxf(amount, 0.0)
	trigger_cd_total[key] = maxf(amount, 0.01)


# ------------------------------------------------------------------ ranks ---

func can_rank_up(slot: String) -> bool:
	var ab = def.abilities.get(slot)
	if ab == null or skill_points <= 0:
		return false
	var r := int(ranks.get(slot, 0))
	if r >= int(ab.max_rank):
		return false
	var ul: Array = ab.unlock_levels
	var need := int(ul[r]) if r < ul.size() else 1
	return level >= need


func rank_up(slot: String) -> bool:
	if not can_rank_up(slot):
		return false
	ranks[slot] += 1
	skill_points -= 1
	world.fx("rankup", {"v": net_id, "s": slot})
	trigger("rank_up", self, null, {"cast_slot": slot})
	return true


func max_ranks() -> void:
	for s in SLOTS:
		var ab = def.abilities.get(s)
		if ab != null:
			ranks[s] = int(ab.max_rank)
	skill_points = 0


# ---------------------------------------------------------------- passive ---

## Collects the character passive's triggers plus every owned item's passives.
## Passives with the same "unique" name (default: item id + index) don't stack.
func _rebuild_triggers() -> void:
	trig_list = []
	slot_keys = [[], [], [], [], [], []]
	var seen := {}
	var ptr: Array = def.passive.triggers
	for i in ptr.size():
		trig_list.append({"tr": ptr[i], "key": "p%d" % i, "src": "passive", "slot": -1, "name": str(def.passive.name), "color": color})
	for slot in ITEM_SLOTS:
		var inst = items[slot]
		if inst == null:
			continue
		var it = Game.items.get(inst.id)
		if it == null:
			continue
		for j in it.passives.size():
			var p: Dictionary = it.passives[j]
			if not p.has("on"):
				continue
			var key := "%s#%d" % [inst.id, j]
			var u := str(p.get("unique", key))
			if seen.has(u):
				continue
			seen[u] = true
			slot_keys[slot].append(key)
			trig_list.append({"tr": p, "key": key, "src": inst.id, "slot": slot, "name": it.name, "color": it.color})
	trig_by_event = {}
	for r in trig_list:
		var ev := str(r.tr.on)
		if not trig_by_event.has(ev):
			trig_by_event[ev] = []
		trig_by_event[ev].append(r)


func trigger(event: String, target = null, pos = null, extra := {}, only := "") -> bool:
	if puppet or _trigger_depth > 3:
		return false
	var list = trig_by_event.get(event)
	if list == null:
		return _status_triggers(event, target, pos, extra) if only == "" else false
	var fired := false
	var excl := str(extra.get("exclude", ""))
	for r in list:
		var tr: Dictionary = r.tr
		if (only != "" and r.key != only) or trigger_cds.get(r.key, 0.0) > 0.0 or (excl != "" and r.key == excl):
			continue
		if extra.get("is_proc", false) and event in PROC_GUARDED and not tr.get("procs", false):
			continue
		if event == "low_health" and hp > stats.max_hp * float(tr.get("threshold", 0.3)):
			continue
		var tgt = target if is_instance_valid(target) else self
		var tpos: Vector2 = pos if pos is Vector2 else tgt.global_position
		var is_item: bool = r.src != "passive"
		var ctx := {"caster": self, "team": team, "ability": r.name, "char": char_id, "color": r.color,
			"origin": global_position, "target": tgt, "pos": tpos, "range": 600.0, "i": int(trigger_counts.get(r.key, 0)),
			"dir": (tpos - global_position).normalized() if tpos.distance_to(global_position) > 1.0 else Vector2(facing, 0),
			"rank": level, "proc": true, "src_slot": "item" if is_item else "passive",
			"item": r.src if is_item else "", "item_slot": r.slot, "trigger_key": r.key}
		ctx.merge(extra, true)
		if extra.has("dmg_info"):
			ctx.dmg = float(extra.dmg_info.amount)
		if tr.has("if") and Effects.num(tr["if"], ctx, 1.0) == 0.0:
			continue
		if tr.has("every"):
			trigger_counts[r.key] = int(trigger_counts.get(r.key, 0)) + 1
			ctx.i = trigger_counts[r.key]
			if int(trigger_counts[r.key]) % maxi(int(Effects.num(tr.every, ctx, 1.0)), 1) != 0:
				continue
		if tr.has("chance") and randf() > Effects.num(tr.chance, ctx, 1.0):
			continue
		trigger_cds[r.key] = Effects.num(tr.get("cooldown", 0.0), ctx, 0.0)
		trigger_cd_total[r.key] = trigger_cds[r.key]
		if Game.debug_log and event != "interval":
			print("[proc] t=%.2f %s: %s '%s' on %s" % [world.time, display_name, r.key, str(tr.get("name", r.name)), event])
		_trigger_depth += 1
		Effects.run(tr.get("effects"), ctx)
		_trigger_depth -= 1
		fired = true
	if only == "" and _status_triggers(event, target, pos, extra):
		fired = true
	return fired


## Buffs/marks can carry their own "triggers" while they last (e.g. "your next 3 attacks
## stun", Ardent Censer). They run as the status' giver, aimed at the event's target.
func _status_triggers(event: String, target, pos, extra: Dictionary) -> bool:
	var fired := false
	for s in statuses.duplicate():
		var trs = s.get("triggers")
		if not (trs is Array):
			continue
		for j in trs.size():
			var tr = trs[j]
			if not (tr is Dictionary) or str(tr.get("on", "")) != event:
				continue
			var key := "s:%s:%d:%d" % [s.key, int(s.get("trig_sig", 0)), j]
			if trigger_cds.get(key, 0.0) > 0.0:
				continue
			if extra.get("is_proc", false) and event in PROC_GUARDED and not tr.get("procs", false):
				continue
			var giver = s.source if is_instance_valid(s.source) else null
			if giver == null or (giver.dead and giver != self):
				continue
			var tgt = target if is_instance_valid(target) else self
			var tpos: Vector2 = pos if pos is Vector2 else tgt.global_position
			var ctx := {"caster": giver, "team": giver.team, "ability": str(s.get("id", "buff")), "char": giver.char_id,
				"color": giver.color, "origin": global_position, "target": tgt, "pos": tpos, "range": 600.0, "holder": self,
				"dir": (tpos - global_position).normalized() if tpos.distance_to(global_position) > 1.0 else Vector2(facing, 0),
				"rank": giver.get_level(), "proc": true, "src_slot": "item" if s.has("item") else "passive",
				"item": str(s.get("item", "")), "i": int(s.get("fired", 0))}
			ctx.merge(extra, true)
			if extra.has("dmg_info"):
				ctx.dmg = float(extra.dmg_info.amount)
			if tr.has("if") and Effects.num(tr["if"], ctx, 1.0) == 0.0:
				continue
			s.fired = int(s.get("fired", 0)) + 1
			if tr.has("every") and int(s.fired) % maxi(int(Effects.num(tr.every, ctx, 1.0)), 1) != 0:
				continue
			trigger_cds[key] = Effects.num(tr.get("cooldown", 0.0), ctx, 0.0)
			_trigger_depth += 1
			Effects.run(tr.get("effects"), ctx)
			_trigger_depth -= 1
			fired = true
			var charges := int(Effects.num(tr.get("charges", 0), ctx, 0.0))
			if bool(tr.get("consume", false)) or (charges > 0 and int(s.fired) >= charges):
				statuses.erase(s)
				stats_dirty = true
				break
	return fired


func on_attack_hit(t, crit := false) -> void:
	energy = minf(energy + 6.0, 100.0)
	if energy >= 100.0 and trig_by_event.has("energized"):
		energy = 0.0
		trigger("energized", t, null, {"crit_hit": crit, "onhit": true})
	trigger("attack", t, null, {"crit_hit": crit, "onhit": true})


func on_damaged(_amount: float, src) -> void:
	_cancel_recall()
	trigger("damaged", src)
	if not dead and hp < stats.max_hp * 0.5:
		trigger("low_health", self)


func on_kill(victim) -> void:
	var p: Vector2 = victim.global_position if is_instance_valid(victim) else global_position
	trigger("kill", victim, p)
	if victim is Champion:
		trigger("champion_kill", victim, p)


func on_takedown(victim, assist: bool) -> void:
	if assist:
		assists += 1
	trigger("takedown", victim, victim.global_position if is_instance_valid(victim) else global_position, {"amount": 0.0 if assist else 1.0})


func _cheat_death() -> bool:
	if trigger("lethal", self):
		hp = maxf(hp, 1.0)
		return true
	return false


func change_counter(id: String, e: Dictionary, ctx: Dictionary) -> void:
	var v := float(counters.get(id, 0.0))
	if e.has("set"):
		v = Effects.num(e.set, ctx, 0.0)
	v += Effects.num(e.get("add"), ctx, 0.0)
	if e.has("mult"):
		v *= Effects.num(e.mult, ctx, 1.0)
	if e.has("max"):
		v = minf(v, Effects.num(e.max, ctx, v))
	v = maxf(v, Effects.num(e.get("min"), ctx, 0.0))
	counters[id] = v
	stats_dirty = true


# ------------------------------------------------------------------ items ---

func item_def(slot: int):
	if slot < 0 or slot >= ITEM_SLOTS or items[slot] == null:
		return null
	return Game.items.get(items[slot].id)


func has_item(id: String) -> bool:
	for inst in items:
		if inst != null and inst.id == id:
			return true
	return false


func count_items(rarity: String) -> int:
	var n := 0
	for inst in items:
		if inst != null:
			var it = Game.items.get(inst.id)
			if it != null and (rarity == "" or it.rarity == rarity):
				n += 1
	return n


func can_shop() -> bool:
	if dead or world.map.data.get("shop_anywhere", false) or world.cheats_allowed():
		return true
	return global_position.distance_to(world.map.spawn_point(team)) <= world.map.fountain_radius * 1.25


## What buying `id` would cost right now, after the value of owned components
## it would use up. Returns {cost, uses: [item slots consumed]}.
func price_for(id: String) -> Dictionary:
	var it = Game.items.get(id)
	if it == null:
		return {"cost": 999999, "uses": []}
	var used := []
	var discount := _discount(it, used)
	return {"cost": maxi(it.cost - discount, 0), "uses": used}


func _discount(it: Dictionary, used: Array) -> int:
	var total := 0
	for c in it.from:
		var found := -1
		for s in ITEM_SLOTS:
			if items[s] != null and items[s].id == c and not used.has(s):
				found = s
				break
		if found >= 0:
			used.append(found)
			total += int(Game.items[c].cost)
		elif Game.items.has(c):
			total += _discount(Game.items[c], used)
	return total


## Returns "" if the purchase is allowed, otherwise the reason why not.
func check_buy(id: String) -> String:
	var it = Game.items.get(id)
	if it == null or not it.buyable:
		return "That item can't be bought"
	if not can_shop():
		return "You can only shop in your base (or while dead)"
	if level < int(it.min_level):
		return "Requires level %d" % int(it.min_level)
	var p := price_for(id)
	if gold + 0.01 < p.cost:
		return "Not enough gold (%d needed)" % p.cost
	var uses: Array = p.uses
	for s in ITEM_SLOTS:
		var inst = items[s]
		if inst == null or uses.has(s):
			continue
		var other = Game.items.get(inst.id)
		if other == null:
			continue
		if it.rarity == "mythic" and other.rarity == "mythic":
			return "You can only own one Mythic item"
		if not (inst.id == id and it.stack > 1):
			for g in it.groups:
				if other.groups.has(g):
					return "You can only own one %s item" % str(g).replace("_", " ").capitalize()
		if it.rarity == "boots" and other.rarity == "boots":
			return "You can only own one pair of boots"
		if inst.id == id and it.limit > 0 and _count_id(id, uses) >= it.limit:
			return "You can only own %d of that" % it.limit
	if _stack_slot(id) < 0 and _free_slot(uses) < 0:
		return "Your inventory is full"
	return ""


func _count_id(id: String, skip: Array) -> int:
	var n := 0
	for s in ITEM_SLOTS:
		if items[s] != null and items[s].id == id and not skip.has(s):
			n += int(items[s].n)
	return n


func _stack_slot(id: String) -> int:
	var it = Game.items.get(id)
	if it == null or it.stack <= 1:
		return -1
	for s in ITEM_SLOTS:
		if items[s] != null and items[s].id == id and int(items[s].n) < it.stack:
			return s
	return -1


func _free_slot(freed: Array = []) -> int:
	for s in ITEM_SLOTS:
		if items[s] == null:
			return s
	return freed[0] if not freed.is_empty() else -1


func buy(id: String) -> String:
	var err := check_buy(id)
	if err != "":
		return err
	var p := price_for(id)
	gold -= p.cost
	var stack := _stack_slot(id)
	if stack >= 0:
		items[stack].n += 1
	else:
		var freed: Array = p.uses
		freed.sort()
		for s in freed:
			items[s] = null
		var slot: int = freed[0] if not freed.is_empty() else _free_slot()
		items[slot] = new_instance(id)
	_items_changed()
	world.fx("buy", {"v": net_id, "i": id})
	trigger("buy", self, null, {"amount": float(p.cost)})
	return ""


func new_instance(id: String) -> Dictionary:
	var it = Game.items.get(id)
	var n: int = it.charges if it != null and it.charges > 0 else 1
	return {"id": id, "n": n, "cd": 0.0, "cd_total": 1.0}


func sell(slot: int) -> String:
	var it = item_def(slot)
	if it == null:
		return ""
	if not can_shop():
		return "You can only sell in your base (or while dead)"
	gold += sell_value(it)
	items[slot].n -= 1
	if items[slot].n <= 0 or it.charges > 0:
		items[slot] = null
	_items_changed()
	return ""


## Replaces an item (e.g. Tear of the Goddess line upgrades, jungle pets evolving).
func transform_item(slot: int, into: String) -> void:
	if slot < 0 or slot >= ITEM_SLOTS or items[slot] == null or not Game.items.has(into):
		return
	items[slot] = new_instance(into)
	_items_changed()
	world.fx("text", {"pos": global_position + Vector2(0, -90), "text": Game.items[into].name + "!", "color": Color(1, 0.85, 0.4), "size": 22})


func _items_changed() -> void:
	_rebuild_triggers()
	_dynamic_stats = false
	for inst in items:
		if inst != null:
			var it = Game.items.get(inst.id)
			if it != null and it.dynamic:
				_dynamic_stats = true
	stats_dirty = true


func use_item(slot: int, aim: Vector2, tid: int) -> bool:
	var it = item_def(slot)
	if it == null or it.active == null or has_status("stasis") or (dead and not it.active.get("while_dead", false)):
		return false
	var inst: Dictionary = items[slot]
	if inst.cd > 0.0 or (it.charges > 0 and int(inst.n) <= 0):
		return false
	var ab: Dictionary = it.active
	var ctx := _make_ctx(ab, aim, tid)
	if ctx.is_empty():
		return false
	ctx.ability = it.name
	ctx.src_slot = "item"
	ctx.item = inst.id
	ctx.item_slot = slot
	ctx.rank = level
	ctx.color = it.color
	ctx.erase("rank_mult")
	if ab.has("requires") and Effects.num(ab.requires, ctx, 1.0) == 0.0:
		world.fx("notice", {"peer": peer, "text": "%s can't be used on that" % it.name})
		return false
	var cd := maxf(Effects.num(ab.cooldown, ctx, 60.0), 0.0)
	inst.cd = cd
	inst.cd_total = maxf(cd, 0.01)
	_cancel_recall()
	if ab.targeting != "self":
		face(ctx.pos)
	world.fx("cast", {"p": global_position, "c": it.color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": "item"})
	Effects.run(ab.effects, ctx)
	if ab.get("consume", false) and items[slot] == inst:
		inst.n -= 1
		if inst.n <= 0 and it.charges <= 0:
			items[slot] = null
			_items_changed()
	trigger("item_used", self, ctx.pos, {"cast_slot": inst.id})
	return true


func _extra_stats(st: Dictionary, mult: Dictionary) -> void:
	var legendary := 0
	var mythic = null
	for inst in items:
		if inst == null:
			continue
		var it = Game.items.get(inst.id)
		if it == null:
			continue
		if it.rarity == "legendary":
			legendary += 1
		elif it.rarity == "mythic":
			mythic = it
		for k in it.stats:
			var v = it.stats[k]
			st[k] = float(st.get(k, 0.0)) + (v if v is float else Effects.num(v, {"caster": self, "target": self, "rank": level}, 0.0))
		for k in it.stats_mult:
			var v = it.stats_mult[k]
			mult[k] = float(mult.get(k, 1.0)) * (v if v is float else Effects.num(v, {"caster": self, "target": self, "rank": level}, 1.0))
	if mythic != null and legendary > 0:
		for k in mythic.mythic_stats:
			var v = mythic.mythic_stats[k]
			st[k] = float(st.get(k, 0.0)) + legendary * (v if v is float else Effects.num(v, {"caster": self, "target": self, "rank": level}, 0.0))


# ------------------------------------------------------------------- gold ---

func add_gold(amount: float, at = null) -> void:
	if amount == 0.0 or puppet:
		return
	gold = maxf(gold + amount, 0.0)
	if amount >= 1.0 and at is Vector2:
		world.fx("gold", {"peer": peer, "p": at, "a": amount})


func cheat(what: String) -> void:
	match what:
		"level":
			if level < MAX_LEVEL:
				xp = 0.0
				_level_up()
		"gold":
			gold += 1000.0
		"cd":
			change_cooldown("all", 0.0, true)
			change_item_cooldown("all", 0.0, true)
			mana = stats.max_mana
		"ranks":
			max_ranks()


# ------------------------------------------------------------------ think ---

func _think(delta: float) -> void:
	for s in SLOTS:
		if cooldowns[s] > 0.0:
			cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	if not recasts.is_empty():
		_update_recasts()
	_tick_items(delta)
	if _energy_pos != Vector2.INF:
		energy = minf(energy + global_position.distance_to(_energy_pos) / 24.0, 100.0)
	_energy_pos = global_position
	if _dynamic_stats:
		_dyn_t -= delta
		if _dyn_t <= 0.0:
			_dyn_t = 0.25
			stats_dirty = true
	for r in trig_by_event.get("interval", []):
		interval_timers[r.key] = float(interval_timers.get(r.key, 0.0)) + delta
		if interval_timers[r.key] >= maxf(float(r.tr.get("interval", 5.0)), 0.1):
			interval_timers[r.key] = 0.0
			trigger("interval", self, null, {}, r.key)
	if casting != null:
		casting.time -= delta
		if casting.time <= 0.0:
			var c = casting
			casting = null
			_execute(c.ab, c.ctx)
	if recall_timer > 0.0:
		recall_timer -= delta
		if recall_timer <= 0.0:
			var from := global_position
			teleport(world.map.spawn_point(team))
			world.fx("blink", {"from": from, "to": global_position, "color": Color(0.5, 0.7, 1.0), "noline": true})
	if is_bot:
		_bot_think(delta)
	if amove != null:
		if attack_target == null:
			attack_target = world.nearest_enemy(global_position, team, stats.attack_range + radius + 120.0, false, true)
		if attack_target == null:
			move_goal = amove
			if global_position.distance_to(amove) < 12.0:
				amove = null


func _tick_items(delta: float) -> void:
	for k in trigger_cds:
		trigger_cds[k] -= delta
	var home := -1.0
	for inst in items:
		if inst == null:
			continue
		if inst.cd > 0.0:
			inst.cd = maxf(inst.cd - delta, 0.0)
		var it = Game.items.get(inst.id)
		if it != null and it.refill and int(inst.n) < it.charges:
			if home < 0.0:
				home = global_position.distance_to(world.map.spawn_point(team))
			if home <= world.map.fountain_radius * 1.25:
				inst.n = it.charges


func _act(delta: float) -> void:
	if casting != null or recall_timer > 0.0 or has_status("stasis"):
		velocity = Vector2.ZERO
		return
	super._act(delta)


func start_recall() -> void:
	if dead or recall_timer > 0.0 or casting != null:
		return
	recall_timer = 4.0
	move_goal = null
	attack_target = null
	amove = null
	path = PackedVector2Array()


func _cancel_recall() -> void:
	recall_timer = 0.0


func _interrupted() -> void:
	recall_timer = 0.0
	casting = null


func gain_xp(amount: float) -> void:
	if level >= MAX_LEVEL:
		return
	xp += amount
	while level < MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		_level_up()


func xp_to_next() -> float:
	return 100.0 + 45.0 * (level - 1)


func _level_up() -> void:
	level += 1
	if level <= SKILL_POINT_LEVELS:
		skill_points += 1
	for k in def.per_level:
		base_stats[k] = float(base_stats.get(k, 0.0)) + def.per_level[k]
	recompute_stats()
	world.fx("levelup", {"p": global_position, "l": level, "v": net_id})
	trigger("level_up", self)


func _on_death() -> void:
	deaths += 1
	casting = null
	recall_timer = 0.0
	amove = null
	energy = 0.0
	for slot in recasts.keys():
		_close_recast(slot)
	respawn_timer = world.respawn_time(level)
	trigger("death", self)


func _dead_process(delta: float) -> void:
	for s in SLOTS:
		cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	_tick_items(delta)
	respawn_timer -= delta
	if is_bot:
		_bot_shop()
	if respawn_timer <= 0.0:
		respawn()


func respawn() -> void:
	dead = false
	statuses = statuses.filter(func(s): return s.get("persist", false))
	teleport(world.map.spawn_point(team) + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana
	flags = 0
	world.fx("spawn", {"p": global_position, "c": team_color(), "r": radius * 2.0})
	trigger("spawn", self)


# ---------------------------------------------------------------- network ---

const HUD_STATS := ["attack_speed", "armor", "magic_resist", "ability_haste", "crit_chance", "lethality", "armor_pen",
	"magic_pen", "magic_pen_percent", "lifesteal", "omnivamp", "tenacity", "heal_power", "hp_regen", "mana_regen", "crit_damage"]


func net_state() -> PackedFloat32Array:
	var s := super.net_state()
	var f := flags
	if recall_timer > 0.0:
		f |= F_RECALL
	if casting != null:
		f |= F_CAST
	if energy >= 100.0 and trig_by_event.has("energized"):
		f |= F_ENERGIZED
	s[5] = f
	var tid := 0
	if is_instance_valid(attack_target):
		tid = attack_target.net_id
	s.append_array([level, xp / xp_to_next(), respawn_timer, recall_timer, kills, deaths, tid,
		cooldowns.q, cooldowns.w, cooldowns.e, cooldowns.r, cd_total.q, cd_total.w, cd_total.e, cd_total.r,
		stats.attack_range, stats.move_speed, stats.attack_damage, stats.ability_power,
		mana, stats.max_mana, gold, skill_points, ranks.q, ranks.w, ranks.e, ranks.r, assists, energy])
	for i in ITEM_SLOTS:
		if items[i] == null:
			s.append_array([0, 0, 0, 1])
		else:
			var v := item_view(i)
			s.append_array([Game.item_index.get(items[i].id, 0), v[0], v[1], v[2]])
	for k in HUD_STATS:
		var v: float = stats.get(k, 0.0)
		if k == "hp_regen":
			v *= 1.0 + stats.hp_regen_percent
		elif k == "mana_regen":
			v *= 1.0 + stats.mana_regen_percent
		s.append(v)
	for k in SLOTS:
		s.append_array([recast_left[k], recast_charges[k]])
	return s


## What an item slot shows: [count or stacks, cooldown, cooldown total]. Items without an
## active show their passive's cooldown; items with "display" show that number.
func item_view(i: int) -> Array:
	var inst = items[i]
	if inst == null:
		return [0, 0.0, 1.0]
	if puppet:
		return [inst.n, inst.cd, inst.cd_total]
	var it = Game.items.get(inst.id)
	var n = inst.n
	var cd: float = inst.cd
	var tot: float = inst.cd_total
	if it != null:
		if it.display != null:
			n = int(Effects.num(it.display, {"caster": self, "target": self, "rank": level}, 0.0))
		if it.active == null:
			for k in slot_keys[i]:
				var r: float = trigger_cds.get(k, 0.0)
				if r > cd:
					cd = r
					tot = maxf(trigger_cd_total.get(k, r), 0.01)
	return [n, cd, tot]


func apply_net_state(s: PackedFloat32Array) -> void:
	super.apply_net_state(s)
	var b := NET_BASE
	level = int(s[b])
	xp_frac = s[b + 1]
	respawn_timer = s[b + 2]
	recall_timer = s[b + 3]
	kills = int(s[b + 4])
	deaths = int(s[b + 5])
	target_id = int(s[b + 6])
	for i in 4:
		cooldowns[SLOTS[i]] = s[b + 7 + i]
		cd_total[SLOTS[i]] = s[b + 11 + i]
	stats.attack_range = s[b + 15]
	stats.move_speed = s[b + 16]
	stats.attack_damage = s[b + 17]
	stats.ability_power = s[b + 18]
	mana = s[b + 19]
	stats.max_mana = s[b + 20]
	gold = s[b + 21]
	skill_points = int(s[b + 22])
	for i in 4:
		ranks[SLOTS[i]] = int(s[b + 23 + i])
	assists = int(s[b + 27])
	energy = s[b + 28]
	var o := b + 29
	var changed := false
	for i in ITEM_SLOTS:
		var idx := int(s[o + i * 4])
		var id: String = Game.item_ids[idx - 1] if idx > 0 and idx <= Game.item_ids.size() else ""
		if id == "":
			if items[i] != null:
				changed = true
			items[i] = null
		else:
			if items[i] == null or items[i].id != id:
				changed = true
				items[i] = {"id": id, "n": 1, "cd": 0.0, "cd_total": 1.0}
			items[i].n = int(s[o + i * 4 + 1])
			items[i].cd = s[o + i * 4 + 2]
			items[i].cd_total = s[o + i * 4 + 3]
	o += ITEM_SLOTS * 4
	for i in HUD_STATS.size():
		if o + i < s.size():
			stats[HUD_STATS[i]] = s[o + i]
	o += HUD_STATS.size()
	if o + 8 <= s.size():
		for i in 4:
			recast_left[SLOTS[i]] = s[o + i * 2]
			recast_charges[SLOTS[i]] = int(s[o + i * 2 + 1])
	if changed:
		_rebuild_triggers()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not puppet:
		xp_frac = xp / xp_to_next()
		if recall_timer > 0.0:
			flags |= F_RECALL
		if energy >= 100.0 and trig_by_event.has("energized"):
			flags |= F_ENERGIZED


# ---------------------------------------------------------------- drawing ---

func _draw_body() -> void:
	var c := body_color()
	var r := radius
	draw_circle(Vector2.ZERO, r, c.darkened(0.45))
	draw_circle(Vector2(0, -r * 0.08), r * 0.88, c)
	draw_circle(Vector2(-r * 0.32, -r * 0.4), r * 0.3, c.lightened(0.4))
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, team_color().lightened(0.1), 3.0, true)
	var tip := Vector2(facing * r * 1.25, 0)
	draw_colored_polygon(PackedVector2Array([tip, Vector2(facing * r * 0.85, -r * 0.28), Vector2(facing * r * 0.85, r * 0.28)]), team_color().lightened(0.2))
	var initials := display_name.substr(0, 2)
	draw_string(ThemeDB.fallback_font, Vector2(-r, 6.0 * stats.size), initials, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(16 * stats.size), Color(0, 0, 0, 0.7))


func bar_width() -> float:
	return 78.0


func bar_height() -> float:
	return 9.0


func icon_y(top: float) -> float:
	return top - 30.0


func _draw_overlay(n: Node2D) -> void:
	super._draw_overlay(n)
	if dead:
		return
	var top := bar_top()
	var font := ThemeDB.fallback_font
	var w := bar_width()
	if stats.max_mana > 0.0:
		var mr := Rect2(-w * 0.5, top + bar_height() + 1.0, w, 3.0)
		n.draw_rect(mr.grow(1.0), Color(0.04, 0.04, 0.07, 0.9))
		n.draw_rect(Rect2(mr.position, Vector2(w * clampf(mana / stats.max_mana, 0.0, 1.0), mr.size.y)), Color(0.35, 0.6, 1.0))
	var lx := -w * 0.5 - 20.0
	n.draw_rect(Rect2(lx, top - 3, 17, 15), Color(0.06, 0.06, 0.09, 0.95))
	n.draw_rect(Rect2(lx, top - 3, 17, 15), ring_color(), false, 1.0)
	n.draw_string(font, Vector2(lx, top + 9), str(level), HORIZONTAL_ALIGNMENT_CENTER, 17, 12, Color(1, 0.9, 0.5))
	n.draw_string_outline(font, Vector2(-90, top - 6), player_name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color(0, 0, 0, 0.85))
	n.draw_string(font, Vector2(-90, top - 6), player_name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, ring_color().lightened(0.55))


# -------------------------------------------------------------------- bot ---

func _bot_think(delta: float) -> void:
	bot_t -= delta
	if bot_t > 0.0 or casting != null or forced != null:
		return
	bot_t = 0.25 + randf() * 0.15
	_bot_level_up()
	var home := world.map.spawn_point(team)
	var at_home := global_position.distance_to(home) < world.map.fountain_radius
	if at_home:
		_bot_shop()
	if at_home and (hp < stats.max_hp * 0.9 or (uses_mana() and mana < stats.max_mana * 0.6)):
		move_goal = null
		attack_target = null
		amove = null
		return
	if hp < stats.max_hp * 0.28 or (not at_home and gold >= 1400.0 and world.map.lane_count() > 0
			and world.nearest_enemy(global_position, team, 1100.0, true) == null):
		amove = null
		attack_target = null
		if recall_timer <= 0.0:
			if world.nearest_enemy(global_position, team, 900.0, true) == null:
				start_recall()
			else:
				move_goal = home
		return
	if recall_timer > 0.0:
		return
	_bot_items()
	var foe := world.nearest_enemy(global_position, team, 850.0, true)
	if foe != null:
		_bot_cast(foe)
		if not _under_enemy_tower(foe.global_position) or hp > stats.max_hp * 0.75:
			attack_target = foe
			amove = null
			move_goal = null
			return
	var near := world.nearest_enemy(global_position, team, 650.0, false, true)
	if near != null and (not near.is_structure or _allied_minions_near(near.global_position)):
		attack_target = near
		amove = null
		return
	if world.map.lane_count() == 0:
		var any := world.nearest_enemy(global_position, team, 5000.0, false, false)
		amove = any.global_position if any != null else world.map.spawn_point(1 - team)
		return
	var lane := world.map.lane(team, bot_lane % world.map.lane_count())
	var nearest := 0
	for i in lane.size():
		if global_position.distance_to(lane[i]) < global_position.distance_to(lane[nearest]):
			nearest = i
	var goal: Vector2 = global_position.move_toward(lane[mini(nearest + 1, lane.size() - 1)], 500.0)
	if _under_enemy_tower(goal) and not _allied_minions_near(goal):
		amove = null
		move_goal = null
		return
	amove = goal


func _bot_level_up() -> void:
	var guard := 0
	while skill_points > 0 and guard < 8:
		guard += 1
		var done := false
		var order := ["r", "q", "w", "e"]
		for s in ["q", "w", "e"]:
			if int(ranks[s]) == 0 and can_rank_up(s):
				order = [s]
				break
		for s in order:
			if can_rank_up(s):
				rank_up(s)
				done = true
				break
		if not done:
			return


func _bot_cast(foe: Unit) -> void:
	var order := SLOTS.duplicate()
	order.shuffle()
	var d := global_position.distance_to(foe.global_position)
	for slot in order:
		var ab = active_ability(slot)
		if ab == null or cooldowns[slot] > 0.0 or int(ranks[slot]) <= 0 or not can_pay(ab):
			continue
		var rng := Effects.num(ab.range, {"caster": self, "target": foe, "rank": ranks[slot]}, 700.0)
		match ab.targeting:
			"self":
				if d > maxf(ab.indicator_radius, 320.0) + 40.0:
					continue
			"ally":
				if hp > stats.max_hp * 0.7:
					continue
				if cast(slot, global_position, net_id):
					return
				continue
			_:
				if d > rng + 60.0:
					continue
		if cast(slot, foe.global_position + foe.velocity * 0.25, foe.net_id):
			return


## Bots use potions when hurt and fire offensive actives at nearby enemy champions.
func _bot_items() -> void:
	var foe := world.nearest_enemy(global_position, team, 600.0, true)
	for i in ITEM_SLOTS:
		var it = item_def(i)
		if it == null or it.active == null or items[i].cd > 0.0:
			continue
		if it.consumable:
			if hp < stats.max_hp * 0.55 and not has_status("hot"):
				use_item(i, global_position, net_id)
			continue
		if foe == null:
			continue
		var ab: Dictionary = it.active
		match ab.targeting:
			"ally":
				if hp < stats.max_hp * 0.5:
					use_item(i, global_position, net_id)
			"self":
				if hp < stats.max_hp * 0.4 or randf() < 0.3:
					use_item(i, foe.global_position, foe.net_id)
			_:
				use_item(i, foe.global_position, foe.net_id)


## Bots pick a simple build for their role the first time they shop, then buy
## the next item (or its most expensive affordable component) whenever possible.
func _bot_shop() -> void:
	if Game.items.is_empty() or not can_shop():
		return
	if bot_plan.is_empty():
		bot_plan = _bot_make_plan()
	for attempt in 6:
		var goal := ""
		for id in bot_plan:
			if not has_item(id) and Game.items.has(id):
				goal = id
				break
		if goal == "":
			return
		var step := _bot_step(goal)
		if step == "":
			if check_buy(goal).begins_with("Not enough gold") or check_buy(goal).begins_with("Your inventory"):
				return
			bot_plan.erase(goal)
			continue
		var err := buy(step)
		if err != "":
			if err.begins_with("Not enough gold") or err.begins_with("Your inventory"):
				return
			bot_plan.erase(goal)


func _bot_step(id: String) -> String:
	if price_for(id).cost <= gold and check_buy(id) == "":
		return id
	var best := ""
	var best_cost := 0
	for c in Game.items[id].from:
		if has_item(c):
			continue
		var s := _bot_step(c)
		if s != "" and int(Game.items[s].cost) > best_cost:
			best = s
			best_cost = int(Game.items[s].cost)
	return best


func _bot_make_plan() -> Array:
	var role := "bruiser"
	if float(def.stats.get("ability_power", 0.0)) >= 25.0 or float(def.stats.get("max_mana", 0.0)) > 0.0:
		role = "mage"
	elif attack_def.ranged:
		role = "marksman"
	var want: String = {"mage": "SpellDamage", "marksman": "CriticalStrike", "bruiser": "Health"}[role]
	var also: String = {"mage": "SpellDamage", "marksman": "AttackSpeed", "bruiser": "Damage"}[role]
	var mythics := []
	var legend := []
	for id in Game.items:
		var it = Game.items[id]
		if not it.buyable or not it.tags.has(want):
			continue
		if it.rarity == "mythic":
			mythics.append(id)
		elif it.rarity == "legendary" and (it.tags.has(also) or role == "mage"):
			legend.append(id)
	mythics.shuffle()
	legend.shuffle()
	var plan := []
	var boots: String = {"mage": "sorcerers_shoes", "marksman": "berserkers_greaves", "bruiser": "plated_steelcaps"}[role]
	if Game.items.has("boots"):
		plan.append("boots")
	if not mythics.is_empty():
		plan.append(mythics[0])
	plan.append(boots)
	var groups := {}
	for id in legend:
		var gs: Array = Game.items[id].groups
		var clash := false
		for g in gs:
			if groups.has(g):
				clash = true
		if clash:
			continue
		for g in gs:
			groups[g] = true
		plan.append(id)
		if plan.size() >= 7:
			break
	return plan


func _under_enemy_tower(p: Vector2) -> bool:
	for t in world.structures:
		if t.team != team and not t.dead and not t.is_nexus and t.global_position.distance_to(p) < t.stats.attack_range + t.radius + 90.0:
			return true
	return false


func _allied_minions_near(p: Vector2) -> bool:
	for u in world.units:
		if u is Minion and u.team == team and not u.dead and u.global_position.distance_to(p) < 600.0:
			return true
	return false
