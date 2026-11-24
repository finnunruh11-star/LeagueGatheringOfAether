class_name Unit
extends CharacterBody2D
## Base for everything with health: champions, minions, towers, summons, dummies.
## The host simulates units; on clients they are "puppets" that follow snapshots.

enum { ANIM_IDLE, ANIM_WALK, ANIM_ATTACK, ANIM_CAST, ANIM_DEAD }
const ANIM_NAMES := ["idle", "walk", "attack", "cast", "death"]

const F_STUN := 1
const F_ROOT := 2
const F_SLOW := 4
const F_SILENCE := 8
const F_INVULN := 16
const F_DEAD := 32
const F_BUFF := 64
const F_DOT := 128
const F_RECALL := 256
const F_CAST := 512
const F_AIR := 1024
const F_HOT := 2048
const F_PROTECTED := 4096
const F_STASIS := 8192
const F_STEALTH := 16384
const F_SPELLSHIELD := 32768
const F_GRIEVOUS := 65536
const F_ENERGIZED := 131072
const F_UNTARGETABLE := 262144
const NET_BASE := 9
const HARD_CC := ["stun", "root", "slow", "silence", "dot", "grievous"]
const CC_TYPES := ["stun", "root", "slow", "silence"]
const COMBAT_TIME := 3.0

var world: World
var net_id := 0
var puppet := false
var kind := "unit"
var team := 0
var display_name := ""
var color := Color.WHITE
var char_id := ""
var is_structure := false
var is_champion := false
var separate := false
var xp_value := 0.0
var gold_value := 0.0
var is_ward := false        # wards: take 1 damage per basic attack, ignored by minions/towers
var reveal := false         # reveals stealthed enemies inside its vision (control wards)

var base_stats := Content.DEFAULT_STATS.duplicate()
var stats := Content.DEFAULT_STATS.duplicate()
var pre_mult := {}          # stats before multipliers (only filled when some multiplier applies)
var hp := 100.0
var mana := 0.0
var shield := 0.0
var flags := 0
var dead := false
var statuses: Array = []
var stats_dirty := true
var base_radius := 20.0
var radius := 20.0
var combat_t := -100.0      # last time this unit dealt/took champion damage
var combat_start := -100.0
var hurt_t := -100.0        # last time this unit took any damage
var damagers := {}          # champion net_id -> last time it damaged this unit (assists)

var move_goal = null
var attack_target = null
var attack_cd := 0.0
var attack_def := {"ranged": false, "speed": 1000.0, "color": Color.WHITE, "size": 6.0, "sprite": "", "char": "", "on_hit": []}
var forced = null
var path := PackedVector2Array()
var path_goal := Vector2.INF
var path_timer := 0.0
var facing := 1.0
var anim := ANIM_IDLE
var anim_lock := 0.0
var anim_lock_kind := ANIM_IDLE
var last_champion_hit = null
var last_champion_hit_time := -100.0

var net_from := Vector2.ZERO
var net_to := Vector2.ZERO
var net_t := 1.0

var sprite_info = null
var sprite: AnimatedSprite2D = null
var overlay: DrawNode
var collider: CollisionShape2D
var flash := 0.0
var life := 0.0
var squash := 0.0
var kick := Vector2.ZERO
var hp_ghost := 0.0
var _ghost_hold := 0.0
var _prev_hp := 0.0
var _last_pos := Vector2.INF
var _afterimage_t := 0.0
var _was_shielded := false
var status_fx: CPUParticles2D = null


func setup(_d: Dictionary) -> void:
	pass


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1 if is_structure else 0
	collision_mask = 1
	collider = CollisionShape2D.new()
	collider.shape = CircleShape2D.new()
	add_child(collider)
	if sprite_info != null:
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = sprite_info.frames
		sprite.position = sprite_info.offset
		sprite.play("idle")
		add_child(sprite)
	overlay = DrawNode.new()
	overlay.z_index = 40
	overlay.draw_func = _draw_overlay
	add_child(overlay)
	net_from = global_position
	net_to = global_position
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana


# ------------------------------------------------------------ simulation ---

func _physics_process(delta: float) -> void:
	if puppet or world == null or world.ended or not world.started:
		return
	life += delta
	if dead:
		_dead_process(delta)
		return
	_update_statuses(delta)
	if dead:
		return
	if stats_dirty:
		recompute_stats()
	hp = minf(hp + stats.hp_regen * (1.0 + stats.hp_regen_percent) * delta, stats.max_hp)
	if stats.max_mana > 0.0:
		mana = minf(mana + stats.mana_regen * (1.0 + stats.mana_regen_percent) * delta, stats.max_mana)
	attack_cd = maxf(attack_cd - delta, 0.0)
	anim_lock = maxf(anim_lock - delta, 0.0)
	_think(delta)
	if dead:
		return
	if forced != null:
		_forced_process(delta)
	elif not is_structure:
		_act(delta)
		if separate:
			_separate()
		move_and_slide()
	else:
		_act(delta)
	_update_anim()
	flags = _compute_flags()


func _think(_delta: float) -> void:
	pass


func _dead_process(_delta: float) -> void:
	pass


func _act(delta: float) -> void:
	velocity = Vector2.ZERO
	if attack_target != null and not valid_target(attack_target):
		attack_target = null
	if attack_target != null:
		var d := global_position.distance_to(attack_target.global_position)
		if d <= attack_reach(attack_target):
			face(attack_target.global_position)
			if attack_cd <= 0.0 and can_attack():
				perform_attack(attack_target)
			return
		if can_move():
			_move_toward(attack_target.global_position, delta, true)
		return
	if move_goal != null and can_move():
		if _move_toward(move_goal, delta, false):
			move_goal = null


## Moves along a path toward goal. Returns true when arrived.
func _move_toward(goal: Vector2, delta: float, chasing: bool) -> bool:
	path_timer -= delta
	if path.is_empty() or path_goal.distance_to(goal) > (50.0 if chasing else 4.0) or (chasing and path_timer <= 0.0):
		path = world.map.find_path(global_position, goal)
		path_goal = goal
		path_timer = 0.3
	while path.size() > 0 and global_position.distance_to(path[0]) < 6.0:
		path.remove_at(0)
	if path.is_empty():
		return true
	var to := path[0] - global_position
	var spd: float = stats.move_speed
	velocity = to / delta if to.length() < spd * delta else to.normalized() * spd
	face(path[0])
	return false


func _separate() -> void:
	var push := Vector2.ZERO
	for u in world.units:
		if u == self or u.dead or not u.separate:
			continue
		var d: Vector2 = global_position - u.global_position
		var min_d: float = radius + u.radius
		var l: float = d.length()
		if l < min_d:
			push += (d / l if l > 0.01 else Vector2.from_angle(randf() * TAU)) * (min_d - l)
	velocity += push * 6.0


func attack_reach(t) -> float:
	return stats.attack_range + radius + t.radius


func valid_target(t) -> bool:
	return is_instance_valid(t) and not t.dead and t.team != team and t.targetable() and t.visible_to(team)


func targetable() -> bool:
	return not dead and flags & (F_STASIS | F_UNTARGETABLE) == 0


## Stealthed units (and, with fog of war, unseen ones) can't be clicked or auto-targeted by enemies.
func visible_to(t: int) -> bool:
	if t == team or world == null:
		return true
	return world.can_see(self, t)


func face(p: Vector2) -> void:
	if absf(p.x - global_position.x) > 2.0:
		facing = signf(p.x - global_position.x)


func get_level() -> int:
	return 1


func is_protected() -> bool:
	return false


func has_status(t: String) -> bool:
	for s in statuses:
		if s.type == t:
			return true
	return false


## A status applied by an effect with this "id" (optionally only from `src`).
func find_status(id: String, src = null) -> Dictionary:
	for s in statuses:
		if (s.get("id", "") == id or s.type == id) and (src == null or s.source == src):
			return s
	return {}


func remove_status_id(id: String, src = null) -> void:
	var before := statuses.size()
	statuses = statuses.filter(func(s): return not (s.get("id", "") == id and (src == null or s.source == src)))
	if statuses.size() != before:
		stats_dirty = true


func can_move() -> bool:
	return not dead and not is_structure and forced == null and stats.move_speed > 0.0 and not has_status("stun") \
		and not has_status("root") and not has_status("stasis")


func can_attack() -> bool:
	return not dead and forced == null and stats.attack_damage > 0.0 and not has_status("stun") and not has_status("stasis")


func can_cast() -> bool:
	return not dead and forced == null and not has_status("stun") and not has_status("silence") and not has_status("stasis")


func trigger(_event: String, _target = null, _pos = null, _extra := {}, _only := "") -> bool:
	return false


func in_combat() -> bool:
	return world != null and world.time - combat_t < COMBAT_TIME


func enter_combat() -> void:
	if not in_combat():
		combat_start = world.time
	combat_t = world.time


# ---------------------------------------------------------------- attacks ---

func perform_attack(t: Unit) -> void:
	attack_cd = 1.0 / maxf(stats.attack_speed, 0.05)
	set_anim_lock(ANIM_ATTACK, minf(0.3, attack_cd * 0.8))
	var dmg := attack_damage_against(t)
	var crit: bool = stats.crit_chance > 0.0 and randf() < stats.crit_chance
	if crit:
		dmg *= stats.crit_damage
	trigger("attack_launch", t, null, {"crit_hit": crit})
	if attack_def.ranged:
		var p = world.spawn("projectile", {
			"pos": muzzle(), "dir": (t.global_position - global_position).normalized(), "team": team,
			"radius": attack_def.size * (1.4 if crit else 1.0), "color": attack_def.color, "sprite": attack_def.sprite, "char": attack_def.char,
		})
		p.init_attack(self, t, dmg, attack_def.speed, crit)
	else:
		land_attack(t, dmg, crit)


## Where ranged attacks leave from.
func muzzle() -> Vector2:
	return global_position + Vector2(facing * radius * 0.6, -radius * 0.3)


func attack_damage_against(_t) -> float:
	return stats.attack_damage


## Visual style of this unit's basic-attack hits (see Vfx / World._hit_fx).
func attack_hit_style() -> String:
	var v := str(attack_def.get("hit_vfx", ""))
	if v != "":
		return v
	if is_structure:
		return "burst"
	if attack_def.ranged:
		return "twinkle" if is_champion else "spark"
	return "slash" if is_champion or self is Summon else "spark"


func land_attack(t, dmg: float, crit := false) -> void:
	if not is_instance_valid(t) or t.dead:
		return
	var dir: Vector2 = t.global_position - global_position
	t.take_damage(dmg, self, "physical", {"vfx": attack_hit_style(), "col": attack_def.color, "dir": dir.angle(), "attack": true, "crit": crit})
	if not attack_def.on_hit.is_empty():
		var c := attack_ctx(t)
		c.crit_hit = crit
		c.onhit = true
		Effects.run(attack_def.on_hit, c)
	on_attack_hit(t, crit)


func attack_ctx(t) -> Dictionary:
	var tp: Vector2 = t.global_position if is_instance_valid(t) else global_position
	return {"caster": self, "team": team, "target": t, "pos": tp, "origin": global_position, "src_slot": "attack",
		"dir": (tp - global_position).normalized(), "ability": "attack", "char": char_id, "color": color, "range": stats.attack_range}


func on_attack_hit(_t, _crit := false) -> void:
	pass


func on_damaged(_amount: float, _src) -> void:
	pass


func on_kill(_victim) -> void:
	pass


# ------------------------------------------------------------ health/CC ---

## Deals damage after resistances, shields and item/passive hooks. `hit` describes the hit:
## vfx/col/dir (visuals) and flags attack, crit, ability (slot), item, dot, aoe, proc, onhit, raw.
func take_damage(amount: float, source = null, dtype := "physical", hit := {}) -> float:
	if dead or puppet or amount <= 0.0:
		return 0.0
	if flags & (F_STASIS | F_INVULN) or has_status("invulnerable") or has_status("stasis") or is_protected():
		return 0.0
	var src = source if is_instance_valid(source) and source != self else null
	var raw := bool(hit.get("raw", false))
	if is_ward:
		amount = 1.0 if hit.get("attack", false) else 0.0
		raw = true
	if not raw:
		if src != null:
			amount *= src.stats.get("damage_mult", 1.0)
		amount *= stats.get("damage_taken_mult", 1.0)
		if dtype == "physical":
			amount *= _mitigation(stats.armor, src, true)
		elif dtype == "magic":
			amount *= _mitigation(stats.magic_resist, src, false)
		# Item/passive hooks see the damage after armor/MR and may change it.
		var info := {"amount": amount}
		var vars := _hit_vars(hit, amount, dtype)
		vars["dmg_info"] = info
		if src != null:
			src.trigger("deal_damage_pre", self, null, vars)
		vars.dmg = info.amount
		trigger("take_damage_pre", src, null, vars)
		amount = maxf(info.amount, 0.0)
	if amount <= 0.0 or dead:
		return 0.0
	var dealt := amount
	for s in statuses:
		if s.type == "shield" and amount > 0.0 and (str(s.get("dtype", "all")) == "all" or s.dtype == dtype):
			var a := minf(s.amount, amount)
			s.amount -= a
			amount -= a
	hp -= amount
	flash = 0.12
	hurt_t = world.time
	var credit = src
	if src != null:
		if src is Summon and is_instance_valid(src.owner_unit):
			credit = src.owner_unit
		var vamp: float = src.stats.get("omnivamp", 0.0)
		if hit.get("attack", false) or hit.get("onhit", false):
			vamp += src.stats.get("lifesteal", 0.0)
		if vamp > 0.0 and not is_structure:
			src.heal(dealt * vamp, src, false)
		if credit.is_champion:
			last_champion_hit = credit
			last_champion_hit_time = world.time
			damagers[credit.net_id] = world.time
			if is_champion:
				credit.enter_combat()
				enter_combat()
	world.on_damage(self, dealt, src, dtype, hit)
	if src != null:
		src.trigger("deal_damage", self, null, _hit_vars(hit, dealt, dtype))
	if not dead:
		trigger("take_damage", src, null, _hit_vars(hit, dealt, dtype))
		if hit.get("attack", false) and src != null:
			trigger("attacked", src, null, _hit_vars(hit, dealt, dtype))
	if dead:
		return dealt
	if hp <= 0.0 and not _cheat_death():
		die(src)
	elif not dead:
		on_damaged(dealt, src)
	return dealt


func _hit_vars(hit: Dictionary, amount: float, dtype: String) -> Dictionary:
	var ab := str(hit.get("ability", ""))
	return {"dmg": amount, "dtype": dtype, "crit_hit": bool(hit.get("crit", false)), "is_attack": bool(hit.get("attack", false)),
		"is_ability": ab in ["q", "w", "e", "r"], "is_dot": bool(hit.get("dot", false)), "is_aoe": bool(hit.get("aoe", false)),
		"is_proc": bool(hit.get("proc", false)), "hit_item": str(hit.get("item", "")), "onhit": bool(hit.get("onhit", false))}


## Damage multiplier from armor / magic resist after the attacker's penetration.
func _mitigation(resist: float, src, physical: bool) -> float:
	var r := resist
	if src != null and r > 0.0:
		if physical:
			r *= 1.0 - clampf(src.stats.get("armor_pen", 0.0), 0.0, 1.0)
			var leth: float = src.stats.get("lethality", 0.0)
			if leth > 0.0:
				r = maxf(r - leth * (0.6 + 0.4 * minf(src.get_level(), 18) / 18.0), 0.0)
		else:
			r *= 1.0 - clampf(src.stats.get("magic_pen_percent", 0.0), 0.0, 1.0)
			r = maxf(r - src.stats.get("magic_pen", 0.0), 0.0)
	return 100.0 / (100.0 + r) if r >= 0.0 else 2.0 - 100.0 / (100.0 - r)


func _cheat_death() -> bool:
	return false


## Heals after healing modifiers (heal_received, grievous wounds). Returns the amount healed.
func heal(amount: float, _source = null, show := true) -> float:
	if dead or puppet or amount <= 0.0:
		return 0.0
	amount *= 1.0 + stats.get("heal_received", 0.0)
	var g := 0.0
	for s in statuses:
		if s.type == "grievous":
			g = maxf(g, s.amount)
	amount *= 1.0 - clampf(g, 0.0, 1.0)
	var before := hp
	hp = minf(hp + amount, stats.max_hp)
	if Game.debug_log and hp - before >= 0.5:
		print("[heal] t=%.2f %s +%.1f (raw %.1f)" % [world.time, display_name, hp - before, amount])
	if show and hp - before >= 1.0 and (is_champion or self is Summon):
		world.fx("heal", {"p": global_position, "a": hp - before, "v": net_id, "r": radius})
	return hp - before


func restore_mana(amount: float) -> void:
	if dead or puppet or stats.max_mana <= 0.0:
		return
	mana = clampf(mana + amount, 0.0, stats.max_mana)


func die(killer = null) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	statuses.clear()
	forced = null
	attack_target = null
	move_goal = null
	velocity = Vector2.ZERO
	shield = 0.0
	anim = ANIM_DEAD
	flags = F_DEAD
	if is_structure:
		collision_layer = 0
	world.fx("death", {"p": global_position, "r": radius, "c": color, "k": kind, "v": net_id})
	world.on_unit_died(self, killer if is_instance_valid(killer) else null)
	damagers.clear()
	_on_death()


func _on_death() -> void:
	pass


func add_status(s: Dictionary, source = null, key := "") -> void:
	if dead or puppet:
		return
	if is_structure and not s.type in ["shield", "buff", "hot", "mark"]:
		return
	if s.type in CC_TYPES and (has_status("stasis") or has_status("invulnerable")) and source != self:
		return
	s["source"] = source if is_instance_valid(source) else null
	s["key"] = key
	stats_dirty = true
	if key != "":
		for i in statuses.size():
			var old: Dictionary = statuses[i]
			if old.key == key and old.type == s.type:
				if s.has("tick") and old.has("tick"):
					s.tick = minf(s.tick, old.tick)
				if s.has("max_stacks"):
					s.stacks = mini(int(old.get("stacks", 0)) + int(s.get("add_stacks", 1)), int(s.max_stacks))
					_apply_stacks(s)
					if not bool(s.get("refresh", true)):
						s.time = old.time
				statuses[i] = s
				return
	if s.has("max_stacks"):
		s.stacks = mini(int(s.get("add_stacks", 1)), int(s.max_stacks))
		_apply_stacks(s)
	statuses.append(s)
	if s.type == "stun" or s.type == "stasis":
		_interrupted()


func _apply_stacks(s: Dictionary) -> void:
	if s.type != "buff" or not s.has("per_add"):
		return
	var n := float(s.stacks)
	s.add = {}
	s.mult = {}
	for k in s.per_add:
		s.add[k] = s.per_add[k] * n
	for k in s.per_mult:
		s.mult[k] = 1.0 + (s.per_mult[k] - 1.0) * n


func _interrupted() -> void:
	pass


func cleanse() -> void:
	statuses = statuses.filter(func(s): return not s.type in HARD_CC)
	stats_dirty = true


func _update_statuses(delta: float) -> void:
	if statuses.is_empty():
		shield = 0.0
		return
	for s in statuses.duplicate():
		s.time -= delta
		if s.type == "dot" or s.type == "hot":
			s.tick -= delta
			if s.tick <= 0.0:
				s.tick += s.interval
				if s.type == "dot":
					take_damage(s.amount * s.interval, s.source, s.dtype, {"vfx": "dot", "col": s.get("col", Color(1, 0.5, 0.2)),
						"dot": true, "ability": s.get("src_slot", ""), "item": s.get("item", ""), "raw": s.get("raw", false)})
					if dead:
						return
				else:
					heal(s.amount * s.interval, s.source, false)
	var before := statuses.size()
	statuses = statuses.filter(func(s): return s.time > 0.0 and not (s.type == "shield" and s.amount <= 0.0))
	if statuses.size() != before:
		stats_dirty = true
	shield = 0.0
	for s in statuses:
		if s.type == "shield":
			shield += s.amount


## Optional hook for subclasses to add flat stats (into st) and multipliers (into mult).
func _extra_stats(_st: Dictionary, _mult: Dictionary) -> void:
	pass


func recompute_stats() -> void:
	var old_max: float = stats.get("max_hp", base_stats.max_hp)
	var old_mana: float = stats.get("max_mana", 0.0)
	var st := base_stats.duplicate()
	var mult := {}
	_extra_stats(st, mult)
	var slow := 0.0
	for s in statuses:
		if s.type == "buff":
			for k in s.add:
				st[k] = float(st.get(k, 0.0)) + s.add[k]
	for s in statuses:
		if s.type == "buff":
			for k in s.mult:
				mult[k] = float(mult.get(k, 1.0)) * s.mult[k]
		elif s.type == "slow":
			slow = maxf(slow, s.amount)
	if not mult.is_empty():
		pre_mult = st.duplicate()
	elif not pre_mult.is_empty():
		pre_mult = {}
	for k in mult:
		st[k] = float(st.get(k, 0.0)) * mult[k]
	st.attack_speed = minf(st.attack_speed * maxf(1.0 + st.bonus_attack_speed, 0.1), st.attack_speed_cap)
	slow *= 1.0 - clampf(st.slow_resist, 0.0, 1.0)
	var ms: float = st.move_speed * maxf(1.0 + st.move_speed_bonus, 0.0) * (1.0 - slow)
	if ms > 490.0:
		ms = 475.0 + (ms - 490.0) * 0.5
	elif ms > 415.0:
		ms = 415.0 + (ms - 415.0) * 0.8
	st.move_speed = maxf(ms, 0.0)
	st.max_hp = maxf(st.max_hp, 1.0)
	st.size = clampf(st.size, 0.2, 6.0)
	stats = st
	if st.max_hp > old_max and not dead:
		hp += st.max_hp - old_max
	hp = minf(hp, st.max_hp)
	if st.max_mana > old_mana and not dead:
		mana += st.max_mana - old_mana
	mana = clampf(mana, 0.0, st.max_mana)
	set_radius(base_radius * st.size)
	stats_dirty = false


func set_radius(r: float) -> void:
	radius = r
	if collider != null:
		(collider.shape as CircleShape2D).radius = r * (0.9 if is_structure else 0.6)


func _compute_flags() -> int:
	var f := 0
	for s in statuses:
		match s.type:
			"stun": f |= F_STUN
			"root": f |= F_ROOT
			"slow": f |= F_SLOW
			"silence": f |= F_SILENCE
			"invulnerable": f |= F_INVULN
			"buff": f |= F_BUFF
			"dot": f |= F_DOT
			"hot": f |= F_HOT
			"stasis": f |= F_STASIS | F_INVULN
			"stealth": f |= F_STEALTH
			"spellshield": f |= F_SPELLSHIELD
			"grievous": f |= F_GRIEVOUS
			"untargetable": f |= F_UNTARGETABLE
	if forced != null and not forced.dash:
		f |= F_AIR
	if dead:
		f |= F_DEAD
	if is_protected():
		f |= F_PROTECTED
	return f


# -------------------------------------------------------- forced movement ---

func knockback(vec: Vector2, dur: float) -> void:
	if dead or puppet or is_structure:
		return
	forced = {"vel": vec / dur, "time": dur, "dash": false}
	path = PackedVector2Array()
	_interrupted()


func start_dash(dir: Vector2, length: float, speed: float, e: Dictionary, ctx: Dictionary) -> void:
	if dead:
		return
	forced = {"vel": dir * speed, "time": length / speed, "dash": true, "e": e, "ctx": ctx, "hit": {}}
	path = PackedVector2Array()
	face(global_position + dir)
	if length <= 0.0:
		_end_forced()


func _forced_process(delta: float) -> void:
	var f: Dictionary = forced
	velocity = f.vel
	move_and_slide()
	f.time -= delta
	if f.dash and f.e.has("on_hit"):
		var e: Dictionary = f.e
		for u in world.query(global_position, radius + 10.0, team, str(e.get("affects", "enemies")), false):
			if u == self or f.hit.has(u.net_id):
				continue
			f.hit[u.net_id] = true
			Effects.run(e.on_hit, Effects.sub(f.ctx, {"target": u, "pos": u.global_position, "origin": global_position}))
			if not is_same(forced, f):
				return
			if bool(e.get("stop_on_hit", false)):
				f.time = 0.0
				break
	if is_same(forced, f) and (f.time <= 0.0 or get_slide_collision_count() > 0):
		_end_forced()


func _end_forced() -> void:
	var f = forced
	forced = null
	velocity = Vector2.ZERO
	if f != null and f.dash and not dead and f.e.has("on_end"):
		Effects.run(f.e.on_end, Effects.sub(f.ctx, {"pos": global_position, "origin": global_position}))


func teleport(p: Vector2) -> void:
	global_position = p
	path = PackedVector2Array()
	forced = null


func set_anim_lock(a: int, t: float) -> void:
	anim_lock = t
	anim_lock_kind = a


func _update_anim() -> void:
	if dead:
		anim = ANIM_DEAD
	elif anim_lock > 0.0:
		anim = anim_lock_kind
	elif velocity.length() > 10.0:
		anim = ANIM_WALK
	else:
		anim = ANIM_IDLE

# ---------------------------------------------------------------- network ---

func net_state() -> PackedFloat32Array:
	return PackedFloat32Array([global_position.x, global_position.y, hp, stats.max_hp, shield, flags, facing, anim, stats.size])


func apply_net_state(s: PackedFloat32Array) -> void:
	var p := Vector2(s[0], s[1])
	if p.distance_to(global_position) > 300.0:
		global_position = p
	net_from = global_position
	net_to = p
	net_t = 0.0
	if s[2] < hp - 0.5:
		flash = 0.12
	hp = s[2]
	stats.max_hp = s[3]
	shield = s[4]
	flags = int(s[5])
	facing = s[6]
	anim = int(s[7])
	if absf(stats.size - s[8]) > 0.001:
		stats.size = s[8]
		set_radius(base_radius * s[8])
	dead = flags & F_DEAD != 0


# ---------------------------------------------------------------- visuals ---

func _process(delta: float) -> void:
	if puppet:
		life += delta
		net_t = minf(net_t + delta / World.SNAP_DT, 1.0)
		global_position = net_from.lerp(net_to, net_t)
	flash = maxf(flash - delta, 0.0)
	squash = move_toward(squash, 0.0, delta * 5.0)
	kick = kick.lerp(Vector2.ZERO, minf(14.0 * delta, 1.0))
	_update_ghost_hp(delta)
	_afterimages(delta)
	_update_status_fx()
	if sprite != null:
		_update_sprite()
	queue_redraw()
	overlay.queue_redraw()


## Visual reaction to a hit (played on every client by the hit FX).
func hit_react(ang: float, amount: float) -> void:
	flash = 0.1
	squash = 1.0
	if not is_structure:
		kick = Vector2.from_angle(ang) * clampf(2.0 + amount / 25.0, 2.0, 9.0)


func _bob() -> Vector2:
	if is_structure or dead:
		return Vector2.ZERO
	if anim == ANIM_WALK:
		return Vector2(0, -absf(sin(life * 11.0)) * 3.5)
	return Vector2(0, sin(life * 2.4) * 1.2)


func _body_offset() -> Vector2:
	return kick + _bob()


func _squash_scale() -> Vector2:
	return Vector2(1.0 + 0.16 * squash, 1.0 - 0.12 * squash)


func _update_ghost_hp(delta: float) -> void:
	if hp_ghost < hp:
		hp_ghost = hp
	elif hp < _prev_hp:
		_ghost_hold = 0.45
	_prev_hp = hp
	_ghost_hold -= delta
	if _ghost_hold <= 0.0:
		hp_ghost = move_toward(hp_ghost, hp, stats.max_hp * 0.9 * delta)
	var shielded := shield > 0.0 and not dead
	if shielded and not _was_shielded and world != null:
		Vfx.flash(world.fx_layer, global_position, Color(0.75, 0.88, 1.0, 0.8), radius * 1.9, 0.35, Vfx.ring(), 1.3)
	elif _was_shielded and not shielded and not dead and world != null:
		Vfx.particles(world.fx_layer, global_position, Color(0.85, 0.93, 1.0), 14, 220.0, 0.4, 3.0)
	_was_shielded = shielded


func _afterimages(delta: float) -> void:
	var moved := 0.0 if _last_pos == Vector2.INF else global_position.distance_to(_last_pos)
	_last_pos = global_position
	if dead or is_structure or delta <= 0.0 or moved > 150.0 or moved / delta < 820.0 or not visible or modulate.a < 0.5:
		return
	_afterimage_t -= delta
	if _afterimage_t > 0.0:
		return
	_afterimage_t = 0.03
	var g: Node2D
	if sprite != null:
		var s := Sprite2D.new()
		s.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		s.flip_h = sprite.flip_h
		s.scale = sprite.scale
		s.position = global_position + sprite.position
		g = s
	else:
		var dn := DrawNode.new()
		var r := radius
		dn.draw_func = func(n): n.draw_circle(Vector2.ZERO, r, Color.WHITE)
		dn.position = global_position + _body_offset()
		g = dn
	g.modulate = Color(color.lightened(0.35), 0.5)
	world.under_layer.add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.28)
	tw.tween_callback(g.queue_free)


## Ambient particles that make ongoing statuses readable at a glance.
func _update_status_fx() -> void:
	var col := Color.TRANSPARENT
	var falling := false
	if not dead:
		if flags & F_DOT:
			col = Color(1.0, 0.45, 0.15)
		elif flags & F_HOT:
			col = Color(0.4, 1.0, 0.45)
		elif flags & F_BUFF:
			col = Color(0.8, 1.0, 0.35)
		elif flags & F_SLOW:
			col = Color(0.45, 0.7, 1.0)
			falling = true
	if col.a == 0.0:
		if status_fx != null:
			status_fx.emitting = false
		return
	if status_fx == null:
		status_fx = CPUParticles2D.new()
		status_fx.amount = 10
		status_fx.lifetime = 0.8
		status_fx.local_coords = false
		status_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		status_fx.spread = 20.0
		status_fx.initial_velocity_min = 15.0
		status_fx.initial_velocity_max = 45.0
		status_fx.scale_amount_min = 2.5
		status_fx.scale_amount_max = 4.0
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		status_fx.color_ramp = ramp
		status_fx.material = Vfx.add_material()
		add_child(status_fx)
	status_fx.emission_sphere_radius = radius * 0.8
	status_fx.direction = Vector2.DOWN if falling else Vector2.UP
	status_fx.gravity = Vector2(0, 60) if falling else Vector2(0, -60)
	status_fx.color = col
	status_fx.emitting = true


func _update_sprite() -> void:
	var anim_name: String = ANIM_NAMES[clampi(anim, 0, 4)]
	if not sprite.sprite_frames.has_animation(anim_name):
		anim_name = "idle"
	sprite.visible = not dead or sprite.sprite_frames.has_animation("death")
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	sprite.flip_h = (facing < 0.0) != bool(sprite_info.faces_left)
	sprite.position = sprite_info.offset + _body_offset()
	sprite.scale = Vector2.ONE * sprite_info.scale * stats.size * _squash_scale()
	sprite.modulate = Color(2.2, 2.2, 2.2) if flash > 0.0 else _tint()


func _tint() -> Color:
	if flags & F_STUN:
		return Color(1, 1, 0.6)
	if flags & F_SLOW:
		return Color(0.7, 0.85, 1.2)
	if flags & F_DOT:
		return Color(1.2, 0.8, 0.6)
	return Color.WHITE


func team_color() -> Color:
	return Game.TEAM_COLORS[clampi(team, 0, 2)]


## Ring color from the local player's point of view: you, allies, enemies.
func ring_color() -> Color:
	if world == null:
		return team_color()
	if world.local_champion == self:
		return Color(0.35, 1.0, 0.4)
	if team == 2:
		return Color(1.0, 0.85, 0.3)
	if team == world.local_team:
		return Color(0.35, 0.65, 1.0)
	return Color(1.0, 0.3, 0.25)


func body_color() -> Color:
	var c := color
	if flags & F_SLOW:
		c = c.lerp(Color(0.5, 0.7, 1.0), 0.3)
	return c.lerp(Color.WHITE, 0.7) if flash > 0.0 else c


func _draw() -> void:
	if dead and not is_structure:
		return
	_draw_ground()
	draw_set_transform(_body_offset(), 0.0, _squash_scale())
	if sprite == null:
		_draw_body()
	draw_set_transform(_body_offset())
	_draw_statuses()
	draw_set_transform(Vector2.ZERO)
	_draw_extra()


## Shadow, team ring and hover highlight (stays on the ground).
func _draw_ground() -> void:
	draw_set_transform(Vector2(0, radius * 0.75), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius * 1.05, Color(0, 0, 0, 0.32))
	if world != null and not dead:
		if not is_structure:
			draw_arc(Vector2.ZERO, radius * 1.22, 0, TAU, 40, Color(ring_color(), 0.85 if is_champion else 0.5), 5.0 if is_champion else 3.0, true)
		if world.hover_unit == self:
			var pulse := 0.5 + 0.5 * sin(life * 10.0)
			draw_arc(Vector2.ZERO, radius * 1.5, 0, TAU, 40, Color(1, 0.3, 0.25, 0.55 + 0.45 * pulse), 7.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_body() -> void:
	var c := body_color()
	draw_circle(Vector2.ZERO, radius, c.darkened(0.4))
	draw_circle(Vector2(0, -radius * 0.1), radius * 0.86, c)
	draw_circle(Vector2(-radius * 0.3, -radius * 0.38), radius * 0.28, c.lightened(0.35))


func _draw_extra() -> void:
	pass


func _draw_statuses() -> void:
	var t := life
	if shield > 0.0:
		draw_circle(Vector2.ZERO, radius + 8.0, Color(0.7, 0.85, 1.0, 0.13))
		draw_arc(Vector2.ZERO, radius + 8.0, 0, TAU, 40, Color(0.85, 0.93, 1.0, 0.85), 2.5, true)
		draw_arc(Vector2.ZERO, radius + 4.0, -2.4 + sin(t * 2.0) * 0.2, -1.6 + sin(t * 2.0) * 0.2, 10, Color(1, 1, 1, 0.8), 2.0)
	if flags & F_INVULN:
		draw_arc(Vector2.ZERO, radius + 12.0, t * 2.0, t * 2.0 + TAU, 40, Color(1, 0.85, 0.2, 0.9), 3.0, true)
	if flags & F_ROOT:
		for i in 3:
			var a := i * TAU / 3.0 + 0.4
			draw_arc(Vector2(cos(a), sin(a) * 0.4) * radius * 0.6 + Vector2(0, radius * 0.6), radius * 0.5, a, a + 2.4, 10, Color(0.4, 0.8, 0.25, 0.95), 4.0)
	if flags & F_STUN:
		for i in 3:
			var a := t * 5.0 + i * TAU / 3.0
			_star(Vector2(cos(a) * radius * 0.75, -radius - 10.0 + sin(a) * 4.0), 6.0, Color(1, 0.9, 0.25))
	if flags & F_RECALL:
		var pulse := 0.5 + 0.5 * sin(t * 6.0)
		draw_arc(Vector2.ZERO, radius + 14.0, 0, TAU, 40, Color(0.5, 0.75, 1.0, 0.5 + 0.4 * pulse), 3.0, true)
		draw_rect(Rect2(-radius * 0.55, -radius * 3.2, radius * 1.1, radius * 3.2), Color(0.55, 0.75, 1.0, 0.12 + 0.08 * pulse))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(c + Vector2.from_angle(i * TAU / 8.0 - PI / 2.0) * (r if i % 2 == 0 else r * 0.4))
	draw_colored_polygon(pts, col)


func bar_width() -> float:
	return 44.0


func bar_height() -> float:
	return 5.0


func bar_color() -> Color:
	if world != null and world.local_champion == self:
		return Color(0.35, 0.9, 0.35)
	if team == 2:
		return Color(0.95, 0.8, 0.3)
	if world != null and team == world.local_team:
		return Color(0.3, 0.6, 1.0)
	return Color(0.95, 0.3, 0.25)


func bar_top() -> float:
	if sprite != null:
		var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		if tex != null:
			return sprite_info.offset.y - tex.get_height() * sprite_info.scale * stats.size * 0.5 - 12.0
	return -radius - 16.0


func icon_y(top: float) -> float:
	return top - 10.0


func _draw_overlay(n: Node2D) -> void:
	if dead:
		return
	var w := bar_width()
	var h := bar_height()
	var top := bar_top()
	var total := maxf(stats.max_hp, hp + shield)
	var x := -w * 0.5
	var col := Color(0.6, 0.6, 0.6) if flags & F_PROTECTED else bar_color()
	var hw := w * clampf(hp / total, 0.0, 1.0)
	n.draw_rect(Rect2(x - 2, top - 2, w + 4, h + 4), Color(0.04, 0.04, 0.07, 0.9))
	n.draw_rect(Rect2(x, top, w, h), Color(0.2, 0.08, 0.08))
	if hp_ghost > hp:
		n.draw_rect(Rect2(x + hw, top, w * clampf((hp_ghost - hp) / total, 0.0, 1.0), h), Color(1.0, 0.88, 0.55, 0.9))
	n.draw_rect(Rect2(x, top, hw, h), col)
	n.draw_rect(Rect2(x, top, hw, maxf(h * 0.35, 1.0)), col.lightened(0.35))
	if shield > 0.0:
		n.draw_rect(Rect2(x + hw, top, w * shield / total, h), Color(0.92, 0.94, 1.0))
	if is_champion:
		var v := 100.0
		while v < total:
			var tx := x + w * v / total
			n.draw_line(Vector2(tx, top), Vector2(tx, top + (h if int(v) % 1000 == 0 else h * 0.55)), Color(0, 0, 0, 0.55), 1.0)
			v += 100.0
	if flags & F_PROTECTED:
		n.draw_string(ThemeDB.fallback_font, Vector2(x, top - 3), "protected", HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.8, 0.8, 0.8))
	_draw_status_icons(n, icon_y(top))


func _draw_status_icons(n: Node2D, y: float) -> void:
	var icons := []
	for pair in [[F_STUN, "stun"], [F_ROOT, "root"], [F_SILENCE, "silence"], [F_SLOW, "slow"], [F_DOT, "dot"],
			[F_HOT, "hot"], [F_BUFF, "buff"], [F_INVULN, "invuln"]]:
		if flags & pair[0]:
			icons.append(pair[1])
	if shield > 0.0:
		icons.append("shield")
	var x := -(icons.size() - 1) * 8.0
	for ic in icons:
		StatusIcons.draw(n, Vector2(x, y), ic)
		x += 16.0


