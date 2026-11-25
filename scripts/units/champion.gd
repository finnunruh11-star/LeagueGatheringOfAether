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
const JUNGLE_BUFFS := ["crest_of_insight", "crest_of_cinders", "hand_of_baron", "aspect_of_the_elder"]

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
var amove_mode := "cursor"     # attack-move picks the enemy closest to its point ("cursor") or to you ("champion")
var move_dir := Vector2.ZERO   # WASD steering (host): walk this way while it isn't zero
var build: Array = []          # autobuy: the player's build (item ids, in order)
var autobuy := false
var _built := {}               # build items autobuy already finished (not bought again after selling)
var _shop_t := 0.0
var summoners: Array = []      # summoner spell ids (D / F)
var rune_state: RuneState
var rune_page: Dictionary = {}
var rune_biscuits := 0
var rune_hexflash := false
var rune_keystone := 0
var rune_shoes := false
var sum_cd := [0.0, 0.0]
var sum_cd_total := [1.0, 1.0]
var sum_recast := [false, false]   # the slot casts its recast right now (replicated)
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
var zeri_charge := 0.0
var bot_lane := 0
var bot_plan: Array = []
var bot_difficulty := "normal"  # brick / normal / scripting (see BotBrain)
var brain: BotBrain = null     # host: the bot AI while is_bot
var cs := 0                    # minions and summons killed (host)
var jungle_times := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # clients: replicated JUNGLE_BUFFS timers
var target_id := 0


func setup(d: Dictionary) -> void:
	kind = "champion"
	is_champion = true
	peer = int(d.peer)
	team = int(d.team)
	char_id = str(d.character)
	player_name = str(d.get("name", "Player"))
	is_bot = bool(d.get("bot", false))
	bot_difficulty = BotBrain.level_name(d.get("difficulty", "normal"))
	bot_lane = int(d.get("lane", 0))
	def = Game.characters.get(char_id, {})
	if def.is_empty():
		def = {"id": char_id, "name": "???", "color": Color.MAGENTA, "stats": Content.DEFAULT_STATS.duplicate(),
			"per_level": {}, "attack": attack_def, "passive": {"name": "", "description": "", "triggers": [], "icon": null},
			"abilities": {}, "sprite": null, "portrait": null}
	display_name = def.name
	color = def.color
	base_stats = def.stats.duplicate()
	base_radius = def.get("gameplay_radius", Content.CHAMPION_GAMEPLAY_RADIUS)
	base_pathing_radius = def.get("pathing_radius", Content.CHAMPION_PATH_RADIUS)
	base_selection_radius = def.get("selection_radius", Content.CHAMPION_SELECTION_RADIUS)
	attack_def = def.attack
	sprite_info = def.sprite
	global_position = d.pos
	if char_id == "zeri" and def.abilities.has("q"):
		ranks.q = 1
		skill_points = 0
		zeri_charge = 100.0
	gold = float(d.get("gold", 0.0))
	if Runes.valid(d.get("runes")):
		rune_page = Runes.canonical(d.runes)
		if not puppet:
			rune_state = RuneState.new(self, rune_page)
	summoners = []
	for s in d.get("summoners", []):
		if Game.summoners.has(str(s)) and summoners.size() < 2:
			summoners.append(str(s))
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
		"rune":
			if rune_state == null or args.is_empty() or not args[0] is String or not rune_state.action(args[0], args.slice(1)):
				world.fx("notice", {"peer": peer, "text": "Rune action unavailable for this target or at this time"})
			return
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
			is_bot = args.size() > 0 and args[0] is bool and args[0]
			if args.size() > 1 and args[1] is String:
				bot_difficulty = BotBrain.level_name(args[1])
			if not is_bot:
				move_dir = Vector2.ZERO
			return
		"item":
			if args.size() >= 3 and (args[0] is int or args[0] is float) and args[1] is Vector2 and (args[2] is int or args[2] is float):
				use_item(int(args[0]), args[1], int(args[2]))
			return
		"summoner":
			if args.size() >= 3 and (args[0] is int or args[0] is float) and args[1] is Vector2 and (args[2] is int or args[2] is float):
				use_summoner(int(args[0]), args[1], int(args[2]))
			return
		"steer":
			if args.size() > 0 and args[0] is Vector2:
				var d: Vector2 = args[0]
				move_dir = d.limit_length(1.0) if d.is_finite() else Vector2.ZERO
				if move_dir != Vector2.ZERO and not dead:
					if casting != null and casting.ctx.get("hexflash", false):
						casting = null
						clear_windup()
					cancel_attack_windup()
					move_goal = null
					amove = null
					attack_target = null
					path = PackedVector2Array()
					_cancel_recall()
			return
		"build":
			if args.size() > 0 and args[0] is Array:
				var old := build
				build = []
				for id in args[0]:
					if id is String and Game.items.has(id) and build.size() < 12 and not build.has(id):
						build.append(id)
						if not old.has(id):
							_built.erase(id)  # added (again) to the build: autobuy may buy it again
				_shop_t = 0.0
			return
		"autobuy":
			autobuy = args.size() > 0 and args[0] is bool and args[0]
			_shop_t = 0.0
			return
	if dead:
		return
	if casting != null and casting.ctx.get("hexflash", false) and cmd in ["move", "attack", "amove", "stop"]:
		casting = null
		clear_windup()
	match cmd:
		"move":
			if args.size() > 0 and args[0] is Vector2:
				cancel_attack_windup()
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
				cancel_attack_windup()
				var p: Vector2 = world.map.clamp_inside(args[0])
				amove_mode = "champion" if args.size() > 1 and str(args[1]) == "champion" else "cursor"
				move_goal = null
				_cancel_recall()
				var t := amove_pick(p, 40.0)
				if t != null:
					attack_target = t
					amove = p if move_dir == Vector2.ZERO else null
				elif move_dir == Vector2.ZERO:
					attack_target = null
					amove = p
		"stop":
			cancel_attack_windup()
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
	if ab == null or int(ranks.get(slot, 0)) <= 0 or dead or cooldowns.get(slot, 0.0) > 0.0 or casting != null:
		return false
	if char_id == "zeri" and slot == "e" and has_status("root"):
		return false
	var over_attacks := bool(ab.get("cancels_attacks", false))
	var during_dash: bool = char_id == "zeri" and slot in ["w", "r"] and forced != null \
		and forced.dash and forced.ctx.get("src_slot") == "e"
	if not can_cast(over_attacks, during_dash):
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
	cancel_attack_windup(over_attacks)
	if over_attacks:
		recovery_lock = 0.0
	face(ctx.pos)
	var ct := Effects.num(ab.cast_time, ctx, 0.0)
	var variant := (ACT_RECAST if is_recast else 1) + SLOTS.find(slot)
	world.note_cast(self, slot, is_recast, "", ctx, ct)
	if ab.get("start_effects") is Array:
		Effects.run(ab.start_effects, ctx)
	if ct > 0.0:
		casting = {"ab": ab, "ctx": ctx, "time": ct}
		var marker: Vector2 = ctx.dir * ctx.range if ab.targeting == "direction" else ctx.pos - global_position
		begin_windup(ANIM_CAST, ct, Vector2.ZERO if ab.targeting == "self" else ctx.dir, marker)
		start_action(ANIM_CAST, variant, ct)
	else:
		set_anim_lock(ANIM_CAST, 0.25)
		start_action(ANIM_CAST, variant, 0.0)
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
	if char_id == "zeri" and ab.slot == "q":
		return cd
	if ab.get("auto_rank", false):
		cd *= 1.0 - (0.08 if ab.slot == "r" else 0.05) * (r - 1)
	var haste: float = stats.ability_haste
	if rune_state != null:
		if ab.slot == "r" and rune_state.has(8106): haste += 6 + 5 * rune_state.unique.size()
		if ab.slot != "r" and rune_state.has(9105): haste += mini(floori(int(rune_state.state.get("legend", 0)) / 25.0), 10) * 1.5
		if ab.slot == "r" and rune_state.has(8243): cd *= 0.95 - 0.02 * int(rune_state.state.get("hat", 0))
	return maxf(cd * 100.0 / (100.0 + maxf(haste, -50.0)) * stats.cooldown_mult, 0.0)


func _execute(ab: Dictionary, ctx: Dictionary) -> void:
	if dead:
		return
	if char_id != "zeri" or ab.slot != "w":
		ctx.origin = global_position
	world.fx("cast", {"p": global_position, "c": color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": ab.slot})
	if rune_state != null:
		if rune_state.has(8359):
			rune_state.state.klepto = 1
			rune_state.state.klepto_end = world.time + 10.0
		if rune_state.ready(8226) and uses_mana() and ab.cost_type != "health":
			rune_state.proc(8226, 60.0)
			restore_mana(float(ctx.get("cost_paid", 0.0)))
			restore_mana((stats.max_mana - mana) * 0.08)
		if ab.slot == "r" and rune_state.has(8243): rune_state.count("hat", 1, 5)
		var ally = ctx.get("target")
		if ally is Champion and ally != self and ally.team == team and rune_state.has(8465):
			rune_state.state["guard_%d" % ally.net_id] = world.time + 2.5
	if char_id == "zeri":
		ZeriKit.cast(self, ab, ctx)
	else:
		Effects.run(ab.effects, ctx)
	trigger("cast", self, ctx.pos, {"cast_slot": ab.slot, "amount": float(ctx.get("cost_paid", 0.0)),
		"exclude_unique": "spellblade_charge" if char_id == "zeri" and ab.slot == "q" else ""})
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
			var structs := bool(ab.get("structures", false))
			var t = world.entities.get(tid)
			if not (t is Unit and (_unit_ok(t, enemy) or (structs and t.is_structure and not t.dead and (t.team != team) == enemy))):
				t = world.pick_unit(aim, team, enemy, 100.0, structs)
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
	var excl_unique := str(extra.get("exclude_unique", ""))
	for r in list:
		var tr: Dictionary = r.tr
		if (only != "" and r.key != only) or trigger_cds.get(r.key, 0.0) > 0.0 or (excl != "" and r.key == excl):
			continue
		if excl_unique != "" and tr.get("unique") == excl_unique:
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
		trigger_cds[r.key] = Effects.num(tr.get("cooldown", 0.0), ctx, 0.0) * (100.0 / (100.0 + stats.item_haste) if is_item else 1.0)
		if r.src == "guardian_angel" and has_page_rune(8324):
			trigger_cds[r.key] *= 0.85
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
	if rune_state != null and rune_state.has(8021):
		rune_state.state.fleet = minf(float(rune_state.state.get("fleet", 0.0)) + 6.0, 100.0)
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
	if rune_state != null:
		rune_state.on_kill(victim)
	var p: Vector2 = victim.global_position if is_instance_valid(victim) else global_position
	if victim is Minion or victim is Monster or (victim is Summon and not victim.is_ward):
		cs += 1
	trigger("kill", victim, p)
	if victim is Champion:
		trigger("champion_kill", victim, p)


func on_takedown(victim, assist: bool) -> void:
	if rune_state != null:
		rune_state.takedown(victim)
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
	if it.rarity == "boots" and id != "boots" and has_page_rune(8304) and (rune_state.state.get("shoes", false) if rune_state != null else rune_shoes):
		var boots_slot := used.any(func(slot): return items[slot] != null and items[slot].id == "boots")
		if boots_slot: discount += 50
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
	if it.rarity == "boots" and has_page_rune(8304) and not (rune_state.state.get("shoes", false) if rune_state != null else rune_shoes):
		return "Magical Footwear: wait for your free boots"
	var fee := 0 if gold >= p.cost else 50
	var credit := 0.0
	if has_page_rune(8323) and world.time >= 120.0:
		credit = 150.0 + 5.0 * floorf(world.time / 60.0)
	if gold + credit + 0.01 < p.cost + (fee if credit > 0.0 and gold >= 0.0 else 0):
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
	if gold >= 0.0 and gold < p.cost:
		gold -= 50.0
	gold -= p.cost
	if rune_state != null and rune_state.has(8321) and Game.items[id].rarity == "legendary":
		add_gold(Game.items[id].cost * 0.08)
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
	if attack_action_locked():
		return false
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
	var cd: float = maxf(Effects.num(ab.cooldown, ctx, 60.0), 0.0) * 100.0 / (100.0 + stats.item_haste)
	if has_page_rune(8324) and inst.id in ["zhonyas_hourglass", "gargoyle_stoneplate"]:
		cd *= 0.85
	inst.cd = cd
	inst.cd_total = maxf(cd, 0.01)
	_cancel_recall()
	if ab.targeting != "self":
		face(ctx.pos)
	world.fx("cast", {"p": global_position, "c": it.color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": "item"})
	world.note_cast(self, "item", false, str(inst.id), ctx, 0.0)
	Effects.run(ab.effects, ctx)
	if rune_state != null and (str(inst.id).ends_with("_potion") or str(inst.id).begins_with("elixir_")):
		rune_state.sustain(0.0, true)
	if ab.get("consume", false) and items[slot] == inst:
		inst.n -= 1
		if inst.n <= 0 and it.charges <= 0:
			items[slot] = null
			_items_changed()
	trigger("item_used", self, ctx.pos, {"cast_slot": ctx.item})
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
	if rune_state != null:
		rune_state.stats(st, mult)


# -------------------------------------------------------------- summoners ---

func summoner_def(i: int):
	return Game.summoners.get(summoners[i]) if i >= 0 and i < summoners.size() else null


func has_page_rune(id: int) -> bool:
	return id in rune_page.get("major", []) or id in rune_page.get("minor", [])


## The ability a summoner slot casts right now: its recast while you have the recast's status.
func summoner_ability(i: int):
	var sp = summoner_def(i)
	if sp == null:
		return null
	if sp.id == "flash" and sum_cd[i] > 0.0 and rune_hexflash:
		var hex: Dictionary = sp.active.duplicate()
		hex.name = "Hexflash"
		hex.cast_time = 2.0
		hex.range = 275.0
		return hex
	return sp.recast if sp.recast != null and sum_recast[i] else sp.active


## Cooldown after summoner haste (works like ability haste).
func summoner_cooldown(i: int, ctx := {}) -> float:
	var sp = summoner_def(i)
	if sp == null:
		return 0.0
	if ctx.is_empty():
		ctx = {"caster": self, "target": self, "rank": level}
	var cd := maxf(Effects.num(sp.active.cooldown, ctx, 300.0), 0.0)
	return cd * 100.0 / (100.0 + maxf(stats.get("summoner_haste", 0.0), -50.0))


## Summoner spells work while silenced or rooted - not while stunned (unless "while_cc", e.g.
## Cleanse), dead (unless "while_dead"), knocked up or dashing, in stasis or channeling.
func can_use_summoner(ab: Dictionary) -> bool:
	if dead:
		return bool(ab.get("while_dead", false))
	if attack_action_locked() or has_status("stasis") or forced != null or casting != null:
		return false
	return not has_status("stun") or bool(ab.get("while_cc", false))


func use_summoner(i: int, aim: Vector2, tid: int) -> bool:
	var sp = summoner_def(i)
	if sp == null:
		return false
	if casting != null and int(casting.get("summoner", -1)) == i:
		_refund_channel(i)  # pressing a channeling spell again cancels it
		casting = null
		return false
	var ab = summoner_ability(i)
	var hex: bool = sp.id == "flash" and sum_cd[i] > 0.0 and rune_hexflash
	if hex and (rune_state == null or not rune_state.ready(8306) or world.time - combat_t < 10):
		return false
	var is_recast: bool = ab != sp.active
	if not can_use_summoner(ab) or (not is_recast and sum_cd[i] > 0.0):
		return false
	var ctx := _make_ctx(ab, aim, tid)
	if ctx.is_empty():
		return false
	ctx.ability = ab.name
	ctx.src_slot = "summoner"
	ctx.summoner = sp.id
	ctx.summoner_slot = i
	ctx.hexflash = hex
	ctx.rank = level
	ctx.color = sp.color
	ctx.erase("rank_mult")
	if ab.has("requires") and Effects.num(ab.requires, ctx, 1.0) == 0.0:
		world.fx("notice", {"peer": peer, "text": "%s can't be used on that" % ab.name})
		return false
	if not is_recast:
		var cd := summoner_cooldown(i, ctx)
		sum_cd[i] = cd
		sum_cd_total[i] = maxf(cd, 0.01)
	if hex:
		rune_state.proc(8306, 20.0)
	_cancel_recall()
	cancel_attack_windup()
	if ab.targeting != "self":
		face(ctx.pos)
	if ab.get("start_effects") is Array:
		Effects.run(ab.start_effects, ctx)
	var ct := Effects.num(ab.cast_time, ctx, 0.0)
	if ct > 0.0:
		casting = {"ab": ab, "ctx": ctx, "time": ct, "summoner": i}
		set_anim_lock(ANIM_CAST, ct)
		start_action(ANIM_CAST, ACT_CHANNEL, ct)
	else:
		_run_summoner(ab, ctx)
	return true


func _run_summoner(ab: Dictionary, ctx: Dictionary) -> void:
	ctx.origin = global_position
	world.fx("cast", {"p": global_position, "c": ctx.color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": "summoner"})
	if ctx.summoner == "smite" and rune_state != null and rune_state.has(8360) and int(rune_state.state.get("swaps", 0)) >= 2:
		var upgraded: Array = ab.effects.duplicate(true)
		for effect in upgraded:
			if effect.get("type") == "damage": effect.amount = 900
		Effects.run(upgraded, ctx)
	else:
		Effects.run(ab.effects, ctx)
	trigger("summoner", self, ctx.pos, {"cast_slot": str(ctx.summoner)})
	if rune_state != null and not ctx.get("hexflash", false):
		rune_state.used_summoner(int(ctx.summoner_slot))


## A channeled spell (Teleport) is done. It fails if its target died meanwhile.
func _finish_channel(c: Dictionary) -> void:
	var t = c.ctx.get("target")
	if t != self and (not is_instance_valid(t) or (t is Unit and t.dead)):
		_refund_channel(int(c.summoner))
		world.fx("notice", {"peer": peer, "text": "%s was cancelled" % c.ab.name})
		return
	_run_summoner(c.ab, c.ctx)


## An interrupted or cancelled channel gives back half of its cooldown.
func _refund_channel(i: int) -> void:
	if casting != null and casting.ctx.get("hexflash", false):
		return
	if i >= 0 and i < 2:
		sum_cd[i] = minf(sum_cd[i], sum_cd_total[i] * 0.5)


func _tick_summoners(delta: float) -> void:
	rune_hexflash = rune_state != null and rune_state.ready(8306) and world.time - combat_t >= 10.0
	for i in 2:
		if sum_cd[i] > 0.0:
			sum_cd[i] = maxf(sum_cd[i] - delta, 0.0)
		var sp = summoner_def(i)
		sum_recast[i] = sp != null and sp.recast != null and not find_status(sp.recast.status).is_empty()


# ---------------------------------------------------------------- autobuy ---

## Buys the player's build (or the recommended one) whenever you can shop. Items it already
## finished are not bought again (e.g. after selling them, or components used up by a recipe).
func _autobuy(delta: float) -> void:
	_shop_t -= delta
	if _shop_t > 0.0:
		return
	_shop_t = 0.5
	if Game.items.is_empty() or not can_shop():
		return
	if build.is_empty() and bot_plan.is_empty():
		bot_plan = recommended_build(def)
	var todo := []
	for id in (build if not build.is_empty() else bot_plan):
		if has_item(id) or built_into(id):
			_built[id] = true
		elif not _built.has(id):
			todo.append(id)
	var done := []
	shop_toward(todo, done)
	for id in done:
		_built[id] = true


## True if an item you own was built from `id` (its recipe used `id` up, e.g. Sheen -> Lich Bane).
func built_into(id: String) -> bool:
	for inst in items:
		if inst != null and _recipe_has(inst.id, id):
			return true
	return false


func _recipe_has(parent: String, id: String) -> bool:
	var it = Game.items.get(parent)
	if it == null:
		return false
	for c in it.from:
		if c == id or _recipe_has(c, id):
			return true
	return false


## Buys toward the first item of `plan` you don't own (the item, or its most expensive affordable
## component) while gold allows. Returns the items that can't be bought at all (rules, not gold).
## `done` collects plan items bought completely: they aren't picked again in this pass even if a
## later item used them up (Sheen, then Lich Bane).
func shop_toward(plan: Array, done: Array) -> Array:
	var skip := []
	for attempt in 8:
		var goal := ""
		for id in plan:
			if not has_item(id) and Game.items.has(id) and not skip.has(id) and not done.has(id):
				goal = id
				break
		if goal == "":
			return skip
		var step := _bot_step(goal)
		var err := check_buy(goal) if step == "" else buy(step)
		if err.begins_with("Not enough gold") or err.begins_with("Your inventory"):
			return skip
		if step == "" or err != "":
			skip.append(goal)
		elif step == goal:
			done.append(goal)
	return skip


## "mage", "marksman" or "bruiser" - for bot builds, the recommended build and default summoners.
static func role_of(d: Dictionary) -> String:
	var st = d.get("stats", {})
	if st is Dictionary and (float(st.get("ability_power", 0.0)) >= 25.0 or float(st.get("max_mana", 0.0)) > 0.0):
		return "mage"
	var atk = d.get("attack", {})
	if atk is Dictionary and bool(atk.get("ranged", false)):
		return "marksman"
	return "bruiser"


## A simple build for the character's role: boots, a mythic, tier-2 boots, then legendaries.
## Bots `shuffle` it for variety; otherwise it's always the same (the shop's recommended build).
static func recommended_build(d: Dictionary, shuffle := false) -> Array:
	var role := role_of(d)
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
	for list in [mythics, legend]:
		if shuffle:
			list.shuffle()
		else:
			list.sort_custom(func(a, b): return Game.items[a].cost > Game.items[b].cost or (Game.items[a].cost == Game.items[b].cost and a < b))
	var plan := []
	var boots: String = {"mage": "sorcerers_shoes", "marksman": "berserkers_greaves", "bruiser": "plated_steelcaps"}[role]
	if Game.items.has("boots"):
		plan.append("boots")
	if not mythics.is_empty():
		plan.append(mythics[0])
	if Game.items.has(boots):
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


# ------------------------------------------------------------------- gold ---

func add_gold(amount: float, at = null) -> void:
	if amount == 0.0 or puppet:
		return
	gold = gold + amount if gold < 0.0 and amount >= 0.0 else maxf(gold + amount, 0.0)
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
			sum_cd = [0.0, 0.0]
			mana = stats.max_mana
		"ranks":
			max_ranks()


# ------------------------------------------------------------------ think ---

func _think(delta: float) -> void:
	if rune_state != null:
		rune_state.tick(delta)
	for s in SLOTS:
		if cooldowns[s] > 0.0:
			cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	_tick_summoners(delta)
	if autobuy and not is_bot:
		_autobuy(delta)
	if not recasts.is_empty():
		_update_recasts()
	_tick_items(delta)
	if _energy_pos != Vector2.INF:
		var distance := global_position.distance_to(_energy_pos)
		energy = minf(energy + distance / 24.0, 100.0)
		if char_id == "zeri":
			zeri_charge = minf(zeri_charge + distance / 40.0, 100.0)
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
		if not casting.has("summoner"):
			windup_left = casting.time
		if casting.time <= 0.0:
			var c = casting
			casting = null
			if c.has("summoner"):
				_finish_channel(c)
			else:
				clear_windup()
				set_anim_lock(ANIM_CAST, 0.16)
				_execute(c.ab, c.ctx)
	if recall_timer > 0.0:
		recall_timer -= delta
		if recall_timer <= 0.0:
			var from := global_position
			teleport(world.map.spawn_point(team))
			world.fx("blink", {"from": from, "to": global_position, "color": Color(0.5, 0.7, 1.0), "noline": true})
	if is_bot:
		_bot().tick(delta)
	if amove != null:
		if attack_target == null:
			attack_target = amove_pick(amove, 120.0)
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
	if (casting != null and not _zeri_nova_casting()) or recall_timer > 0.0 or has_status("stasis"):
		velocity = Vector2.ZERO
		return
	if move_dir != Vector2.ZERO and attack_target == null and not attack_starting and not attack_action_locked():
		velocity = Vector2.ZERO
		if can_move():
			velocity = move_dir * stats.move_speed
			face(global_position + move_dir * 10.0)
		return
	super._act(delta)


## WASD steering: an attack command interrupts it for one attack, then you keep walking.
func perform_attack(t: Unit, elapsed_windup: float) -> void:
	if char_id == "zeri":
		ZeriKit.zap(self, t)
	else:
		super.perform_attack(t, elapsed_windup)
	if move_dir != Vector2.ZERO:
		attack_target = null
		amove = null


func _zeri_nova_casting() -> bool:
	return char_id == "zeri" and casting != null and not casting.has("summoner") and casting.ab.slot == "r"


func can_attack() -> bool:
	return not _zeri_nova_casting() and super.can_attack()


func attack_reach(t) -> float:
	if char_id == "zeri":
		return float(base_stats.attack_range) + radius + t.radius
	return super.attack_reach(t)


func attack_windup_ratio() -> float:
	return 0.15625 if char_id == "zeri" else super.attack_windup_ratio()


func _finish_attack_speed(st: Dictionary) -> void:
	if char_id == "zeri":
		ZeriKit.finish_attack_speed(st)
	else:
		super._finish_attack_speed(st)


## An attack that will set off an "every N attacks" passive gets its own swing animation.
func _attack_variant() -> int:
	for r in trig_by_event.get("attack", []):
		var tr: Dictionary = r.tr
		if not tr.has("every") or trigger_cds.get(r.key, 0.0) > 0.0:
			continue
		var n := maxi(int(Effects.num(tr.every, {"caster": self, "rank": level}, 1.0)), 1)
		if n > 1 and (int(trigger_counts.get(r.key, 0)) + 1) % n == 0:
			_last_swing = world.time
			return ACT_FINISHER
	return super._attack_variant()


## Attack-move target: a visible enemy within attack range (+ `pad`), the one closest to `p` (or
## to you with amove_mode "champion"). Wards are skipped; towers count.
func amove_pick(p: Vector2, pad: float) -> Unit:
	var best: Unit = null
	var bd := INF
	var from := global_position if amove_mode == "champion" else p
	for u in world.units:
		if u.team == team or u.dead or u.is_ward or not u.targetable() or not u.visible_to(team):
			continue
		if global_position.distance_to(u.global_position) > attack_reach(u) + pad:
			continue
		var d: float = from.distance_to(u.global_position) - u.radius
		if d < bd:
			bd = d
			best = u
	return best


func start_recall() -> void:
	if dead or recall_timer > 0.0 or casting != null or attack_action_locked():
		return
	cancel_attack_windup()
	recall_timer = 4.0 if not find_status("hand_of_baron").is_empty() else 8.0
	move_goal = null
	attack_target = null
	amove = null
	path = PackedVector2Array()


func _cancel_recall() -> void:
	recall_timer = 0.0


func _interrupted() -> void:
	super._interrupted()
	recall_timer = 0.0
	if casting != null:
		if casting.has("summoner"):
			_refund_channel(int(casting.summoner))
		casting = null
		clear_windup()


func gain_xp(amount: float) -> void:
	if level >= MAX_LEVEL:
		return
	xp += amount
	while level < MAX_LEVEL and xp >= xp_to_next():
		xp -= xp_to_next()
		_level_up()


func xp_to_next() -> float:
	return 280.0 + 100.0 * (level - 1)


func _level_up() -> void:
	level += 1
	if level <= SKILL_POINT_LEVELS:
		skill_points += 1
	var growth := 0.65 + 0.035 * level
	if char_id != "zeri" or level <= 18:
		for k in def.per_level:
			base_stats[k] = float(base_stats.get(k, 0.0)) + def.per_level[k] * growth
	recompute_stats()
	world.fx("levelup", {"p": global_position, "l": level, "v": net_id})
	trigger("level_up", self)


func _on_death() -> void:
	deaths += 1
	casting = null
	recall_timer = 0.0
	amove = null
	energy = 0.0
	zeri_charge = 0.0
	for slot in recasts.keys():
		_close_recast(slot)
	respawn_timer = world.respawn_time(level)
	trigger("death", self)


func _dead_process(delta: float) -> void:
	for s in SLOTS:
		cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	_tick_summoners(delta)
	if autobuy and not is_bot:
		_autobuy(delta)
	_tick_items(delta)
	respawn_timer -= delta
	if is_bot:
		_bot().dead_tick(delta)
	if respawn_timer <= 0.0:
		respawn()


func respawn() -> void:
	dead = false
	statuses = statuses.filter(func(s): return s.get("persist", false))
	teleport(world.map.spawn_point(team) + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
	if char_id == "zeri":
		zeri_charge = 100.0
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana
	flags = 0
	world.fx("spawn", {"p": global_position, "c": team_color(), "r": radius * 2.0})
	if world.jungle != null:
		world.jungle.sync_team_buffs(self)
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
	s.append_array([sum_cd[0], sum_cd[1], sum_cd_total[0], sum_cd_total[1], 1.0 if sum_recast[0] else 0.0, 1.0 if sum_recast[1] else 0.0])
	s.append_array(jungle_buff_times())
	if char_id == "zeri":
		s.append(zeri_charge)
	var spell_codes := Game.summoners.keys()
	spell_codes.sort()
	for i in 2:
		s.append(spell_codes.find(summoners[i]) if i < summoners.size() else -1)
	s.append(float(rune_state.state.get("biscuits", 0)) if rune_state != null else 0.0)
	s.append(1.0 if rune_hexflash else 0.0)
	s.append(rune_state.rotation[rune_state.rotation_index] if rune_state != null and rune_state.keystone == 8358 else 0)
	s.append(1.0 if rune_state != null and rune_state.state.get("shoes", false) else 0.0)
	return s


## Seconds left on Crest of Insight, Crest of Cinders, Hand of Baron and Aspect of the Elder.
func jungle_buff_times() -> PackedFloat32Array:
	if puppet:
		return jungle_times
	var out := PackedFloat32Array()
	for id in JUNGLE_BUFFS:
		out.append(maxf(float(find_status(id).get("time", 0.0)), 0.0))
	return out


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
	o += 8
	if o + 6 <= s.size():
		sum_cd = [s[o], s[o + 1]]
		sum_cd_total = [s[o + 2], s[o + 3]]
		sum_recast = [s[o + 4] > 0.5, s[o + 5] > 0.5]
	o += 6
	if o + JUNGLE_BUFFS.size() <= s.size():
		jungle_times = s.slice(o, o + JUNGLE_BUFFS.size())
	if char_id == "zeri" and o + JUNGLE_BUFFS.size() < s.size():
		zeri_charge = s[o + JUNGLE_BUFFS.size()]
	o += JUNGLE_BUFFS.size() + (1 if char_id == "zeri" else 0)
	if o + 6 <= s.size():
		var spell_codes := Game.summoners.keys()
		spell_codes.sort()
		summoners.clear()
		for i in 2:
			var code := int(s[o + i])
			if code >= 0 and code < spell_codes.size():
				summoners.append(spell_codes[code])
		rune_biscuits = int(s[o + 2])
		rune_hexflash = s[o + 3] > 0.5
		rune_keystone = int(s[o + 4])
		rune_shoes = s[o + 5] > 0.5
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
	var r := Content.CHAMPION_ART_HEIGHT * 0.5 * float(stats.size)
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


func bar_top() -> float:
	return super.bar_top() if sprite != null else -Content.CHAMPION_ART_HEIGHT * 0.5 * stats.size - 16.0


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
	if char_id == "zeri":
		var battery := Rect2(-w * 0.5, top + bar_height() + 6.0, w, 3.0)
		n.draw_rect(battery.grow(1.0), Color(0.04, 0.06, 0.04, 0.9))
		battery.size.x *= zeri_charge / 100.0
		n.draw_rect(battery, Color.GREEN_YELLOW if zeri_charge >= 100.0 else Color.DARK_SEA_GREEN)
	var lx := -w * 0.5 - 20.0
	n.draw_rect(Rect2(lx, top - 3, 17, 15), Color(0.06, 0.06, 0.09, 0.95))
	n.draw_rect(Rect2(lx, top - 3, 17, 15), ring_color(), false, 1.0)
	n.draw_string(font, Vector2(lx, top + 9), str(level), HORIZONTAL_ALIGNMENT_CENTER, 17, 12, Color(1, 0.9, 0.5))
	n.draw_string_outline(font, Vector2(-90, top - 6), player_name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 4, Color(0, 0, 0, 0.85))
	n.draw_string(font, Vector2(-90, top - 6), player_name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, ring_color().lightened(0.55))


# -------------------------------------------------------------------- bot ---

## The bot AI (created on first use, or again when the difficulty changed).
func _bot() -> BotBrain:
	if brain == null or brain.difficulty != bot_difficulty:
		brain = BotBrain.new(self, bot_difficulty)
	return brain


## Next thing to buy toward item `id`: the item itself, or its most expensive affordable component.
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
