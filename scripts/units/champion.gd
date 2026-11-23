class_name Champion
extends Unit
## A player (or bot) controlled character built from a character definition.

const MAX_LEVEL := 18
const SLOTS := ["q", "w", "e", "r"]

var peer := 0
var def := {}
var player_name := ""
var is_bot := false
var cooldowns := {"q": 0.0, "w": 0.0, "e": 0.0, "r": 0.0}
var cd_total := {"q": 1.0, "w": 1.0, "e": 1.0, "r": 1.0}
var level := 1
var xp := 0.0
var xp_frac := 0.0
var kills := 0
var deaths := 0
var respawn_timer := 0.0
var recall_timer := 0.0
var casting = null
var amove = null
var trigger_counts := {}
var trigger_cds := {}
var interval_timers := {}
var _trigger_depth := 0
var bot_t := 0.0
var bot_lane := 0
var bot_wp := 1
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


func get_level() -> int:
	return level


func label() -> String:
	return "%s (%s)" % [player_name, display_name]


# --------------------------------------------------------------- commands ---

func command(cmd: String, args: Array) -> void:
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
		"autopilot":
			is_bot = args.size() > 0 and bool(args[0])


func cast(slot: String, aim: Vector2, tid: int) -> bool:
	var ab = def.abilities.get(slot)
	if ab == null or dead or cooldowns.get(slot, 0.0) > 0.0 or not can_cast() or casting != null:
		return false
	var ctx := _make_ctx(ab, aim, tid)
	if ctx.is_empty():
		return false
	var cd := maxf(Effects.num(ab.cooldown, ctx, 6.0) * stats.cooldown_mult, 0.0)
	cooldowns[slot] = cd
	cd_total[slot] = maxf(cd, 0.01)
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


func _execute(ab: Dictionary, ctx: Dictionary) -> void:
	if dead:
		return
	ctx.origin = global_position
	world.fx("cast", {"p": global_position, "c": color, "v": net_id, "d": Vector2(ctx.dir).angle(), "s": ab.slot})
	Effects.run(ab.effects, ctx)
	trigger("cast", self, ctx.pos, {"slot": ab.slot})


func _make_ctx(ab: Dictionary, aim: Vector2, tid: int) -> Dictionary:
	var ctx := {"caster": self, "team": team, "ability": ab.name, "char": char_id, "color": color,
		"origin": global_position, "target": self, "i": 0}
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
	return not t.dead and t.targetable() and not t.is_structure and (t.team != team) == enemy


func change_cooldown(slot: String, amount: float, reset: bool) -> void:
	for s in SLOTS:
		if slot == "all" or slot == s:
			cooldowns[s] = 0.0 if reset else maxf(cooldowns[s] - amount, 0.0)


# ---------------------------------------------------------------- passive ---

func trigger(event: String, target = null, pos = null, extra := {}, only := -1) -> bool:
	if puppet or _trigger_depth > 2 or def.is_empty():
		return false
	var fired := false
	var trigs: Array = def.passive.triggers
	for i in trigs.size():
		var tr: Dictionary = trigs[i]
		if (only >= 0 and i != only) or str(tr.get("on", "")) != event or trigger_cds.get(i, 0.0) > 0.0:
			continue
		if event == "low_health" and hp > stats.max_hp * float(tr.get("threshold", 0.3)):
			continue
		if tr.has("every"):
			trigger_counts[i] = int(trigger_counts.get(i, 0)) + 1
			if int(trigger_counts[i]) % maxi(int(tr.every), 1) != 0:
				continue
		if tr.has("chance") and randf() > float(tr.chance):
			continue
		var tgt = target if is_instance_valid(target) else self
		var tpos: Vector2 = pos if pos is Vector2 else tgt.global_position
		var ctx := {"caster": self, "team": team, "ability": str(def.passive.name), "char": char_id, "color": color,
			"origin": global_position, "target": tgt, "pos": tpos, "range": 600.0, "i": int(trigger_counts.get(i, 0)),
			"dir": (tpos - global_position).normalized() if tpos.distance_to(global_position) > 1.0 else Vector2(facing, 0)}
		ctx.merge(extra, true)
		if tr.has("if") and Effects.num(tr["if"], ctx, 1.0) == 0.0:
			continue
		trigger_cds[i] = float(tr.get("cooldown", 0.0))
		_trigger_depth += 1
		Effects.run(tr.get("effects"), ctx)
		_trigger_depth -= 1
		fired = true
	return fired


func on_attack_hit(t) -> void:
	trigger("attack", t)


func on_damaged(amount: float, src) -> void:
	_cancel_recall()
	trigger("damaged", src)
	if not dead and hp < stats.max_hp * 0.5:
		trigger("low_health", self)


func on_kill(victim) -> void:
	var p: Vector2 = victim.global_position if is_instance_valid(victim) else global_position
	trigger("kill", self, p)
	if victim is Champion:
		trigger("champion_kill", self, p)


func _cheat_death() -> bool:
	if trigger("lethal", self):
		hp = maxf(hp, 1.0)
		return true
	return false

# ------------------------------------------------------------------ think ---

func _think(delta: float) -> void:
	for s in SLOTS:
		if cooldowns[s] > 0.0:
			cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	for k in trigger_cds:
		trigger_cds[k] -= delta
	var trigs: Array = def.passive.triggers
	for i in trigs.size():
		if str(trigs[i].get("on", "")) == "interval":
			interval_timers[i] = float(interval_timers.get(i, 0.0)) + delta
			if interval_timers[i] >= maxf(float(trigs[i].get("interval", 5.0)), 0.1):
				interval_timers[i] = 0.0
				trigger("interval", self, null, {}, i)
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


func _act(delta: float) -> void:
	if casting != null or recall_timer > 0.0:
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
	respawn_timer = world.respawn_time(level)


func _dead_process(delta: float) -> void:
	for s in SLOTS:
		cooldowns[s] = maxf(cooldowns[s] - delta, 0.0)
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn()


func respawn() -> void:
	dead = false
	statuses.clear()
	teleport(world.map.spawn_point(team) + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
	recompute_stats()
	hp = stats.max_hp
	flags = 0
	world.fx("spawn", {"p": global_position, "c": team_color(), "r": radius * 2.0})
	trigger("spawn", self)


# ---------------------------------------------------------------- network ---

func net_state() -> PackedFloat32Array:
	var s := super.net_state()
	var f := flags
	if recall_timer > 0.0:
		f |= F_RECALL
	if casting != null:
		f |= F_CAST
	s[5] = f
	var tid := 0
	if is_instance_valid(attack_target):
		tid = attack_target.net_id
	s.append_array([level, xp / xp_to_next(), respawn_timer, recall_timer, kills, deaths, tid,
		cooldowns.q, cooldowns.w, cooldowns.e, cooldowns.r, cd_total.q, cd_total.w, cd_total.e, cd_total.r,
		stats.attack_range, stats.move_speed, stats.attack_damage, stats.ability_power])
	return s


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


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not puppet:
		xp_frac = xp / xp_to_next()
		if recall_timer > 0.0:
			flags |= F_RECALL


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
	var lx := -bar_width() * 0.5 - 20.0
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
	var home := world.map.spawn_point(team)
	if global_position.distance_to(home) < world.map.fountain_radius and hp < stats.max_hp * 0.9:
		move_goal = null
		attack_target = null
		amove = null
		return
	if hp < stats.max_hp * 0.28:
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


func _bot_cast(foe: Unit) -> void:
	var order := SLOTS.duplicate()
	order.shuffle()
	var d := global_position.distance_to(foe.global_position)
	for slot in order:
		var ab = def.abilities.get(slot)
		if ab == null or cooldowns[slot] > 0.0:
			continue
		var rng := Effects.num(ab.range, {"caster": self, "target": foe}, 700.0)
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
