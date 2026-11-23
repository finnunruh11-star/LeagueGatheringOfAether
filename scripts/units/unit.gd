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
const NET_BASE := 9
const HARD_CC := ["stun", "root", "slow", "silence", "dot"]

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

var base_stats := Content.DEFAULT_STATS.duplicate()
var stats := Content.DEFAULT_STATS.duplicate()
var hp := 100.0
var shield := 0.0
var flags := 0
var dead := false
var statuses: Array = []
var stats_dirty := true
var base_radius := 20.0
var radius := 20.0

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
	hp = minf(hp + stats.hp_regen * delta, stats.max_hp)
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
	return is_instance_valid(t) and not t.dead and t.team != team and t.targetable()


func targetable() -> bool:
	return not dead


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


func can_move() -> bool:
	return not dead and not is_structure and forced == null and stats.move_speed > 0.0 and not has_status("stun") and not has_status("root")


func can_attack() -> bool:
	return not dead and forced == null and stats.attack_damage > 0.0 and not has_status("stun")


func can_cast() -> bool:
	return not dead and forced == null and not has_status("stun") and not has_status("silence")


# ---------------------------------------------------------------- attacks ---

func perform_attack(t: Unit) -> void:
	attack_cd = 1.0 / maxf(stats.attack_speed, 0.05)
	set_anim_lock(ANIM_ATTACK, minf(0.3, attack_cd * 0.8))
	var dmg := attack_damage_against(t)
	if attack_def.ranged:
		var p = world.spawn("projectile", {
			"pos": global_position, "dir": (t.global_position - global_position).normalized(),
			"radius": attack_def.size, "color": attack_def.color, "sprite": attack_def.sprite, "char": attack_def.char,
		})
		p.init_attack(self, t, dmg, attack_def.speed)
	else:
		land_attack(t, dmg)
		if is_champion:
			world.fx("ring", {"pos": t.global_position, "radius": t.radius + 8.0, "color": Color(1, 1, 1, 0.8), "dur": 0.15})


func attack_damage_against(_t) -> float:
	return stats.attack_damage


func land_attack(t, dmg: float) -> void:
	if not is_instance_valid(t) or t.dead:
		return
	t.take_damage(dmg, self, "physical")
	if not attack_def.on_hit.is_empty():
		Effects.run(attack_def.on_hit, attack_ctx(t))
	on_attack_hit(t)


func attack_ctx(t) -> Dictionary:
	var tp: Vector2 = t.global_position if is_instance_valid(t) else global_position
	return {"caster": self, "team": team, "target": t, "pos": tp, "origin": global_position,
		"dir": (tp - global_position).normalized(), "ability": "attack", "char": char_id, "color": color, "range": stats.attack_range}


func on_attack_hit(_t) -> void:
	pass


func on_damaged(_amount: float, _src) -> void:
	pass


func on_kill(_victim) -> void:
	pass


# ------------------------------------------------------------ health/CC ---

func take_damage(amount: float, source = null, dtype := "physical") -> float:
	if dead or puppet or amount <= 0.0:
		return 0.0
	if has_status("invulnerable") or is_protected():
		return 0.0
	var src = source if is_instance_valid(source) else null
	if src != null:
		amount *= src.stats.get("damage_mult", 1.0)
	amount *= stats.get("damage_taken_mult", 1.0)
	if dtype != "true":
		var armor: float = stats.armor
		amount *= 100.0 / (100.0 + armor) if armor >= 0.0 else 2.0 - 100.0 / (100.0 - armor)
	if amount <= 0.0:
		return 0.0
	var dealt := amount
	for s in statuses:
		if s.type == "shield" and amount > 0.0:
			var a := minf(s.amount, amount)
			s.amount -= a
			amount -= a
	hp -= amount
	flash = 0.12
	if src != null:
		if src.stats.get("lifesteal", 0.0) > 0.0:
			src.heal(dealt * src.stats.lifesteal, src, false)
		var credit = src
		if src is Summon and is_instance_valid(src.owner_unit):
			credit = src.owner_unit
		if credit.is_champion:
			last_champion_hit = credit
			last_champion_hit_time = world.time
	world.on_damage(self, dealt, src, dtype)
	if hp <= 0.0 and not _cheat_death():
		die(src)
	elif not dead:
		on_damaged(dealt, src)
	return dealt


func _cheat_death() -> bool:
	return false


func heal(amount: float, _source = null, show := true) -> void:
	if dead or puppet or amount <= 0.0:
		return
	var before := hp
	hp = minf(hp + amount, stats.max_hp)
	if show and hp - before >= 1.0 and is_champion:
		world.fx("text", {"pos": global_position + Vector2(randf_range(-12, 12), -radius - 40), "text": "+%d" % int(hp - before),
			"color": Color(0.45, 1, 0.45), "size": 16})


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
	world.on_unit_died(self, killer if is_instance_valid(killer) else null)
	_on_death()


func _on_death() -> void:
	pass


func add_status(s: Dictionary, source = null, key := "") -> void:
	if dead or puppet:
		return
	if is_structure and not s.type in ["shield", "buff", "hot"]:
		return
	s["source"] = source if is_instance_valid(source) else null
	s["key"] = key
	stats_dirty = true
	if key != "":
		for i in statuses.size():
			if statuses[i].key == key and statuses[i].type == s.type:
				statuses[i] = s
				return
	statuses.append(s)
	if s.type == "stun":
		_interrupted()


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
					take_damage(s.amount * s.interval, s.source, s.dtype)
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


func recompute_stats() -> void:
	var old_max: float = stats.get("max_hp", base_stats.max_hp)
	var st := base_stats.duplicate()
	var slow := 0.0
	for s in statuses:
		if s.type == "buff":
			for k in s.add:
				st[k] = float(st.get(k, 0.0)) + s.add[k]
	for s in statuses:
		if s.type == "buff":
			for k in s.mult:
				st[k] = float(st.get(k, 0.0)) * s.mult[k]
		elif s.type == "slow":
			slow = maxf(slow, s.amount)
	st.move_speed = maxf(st.move_speed * (1.0 - slow), 0.0)
	st.max_hp = maxf(st.max_hp, 1.0)
	st.size = clampf(st.size, 0.2, 6.0)
	stats = st
	if st.max_hp > old_max and not dead:
		hp += st.max_hp - old_max
	hp = minf(hp, st.max_hp)
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
	velocity = forced.vel
	move_and_slide()
	forced.time -= delta
	if forced.dash and forced.e.has("on_hit"):
		var e: Dictionary = forced.e
		for u in world.query(global_position, radius + 10.0, team, str(e.get("affects", "enemies")), false):
			if u == self or forced.hit.has(u.net_id):
				continue
			forced.hit[u.net_id] = true
			Effects.run(e.on_hit, Effects.sub(forced.ctx, {"target": u, "pos": u.global_position, "origin": global_position}))
			if forced == null:
				return
			if bool(e.get("stop_on_hit", false)):
				forced.time = 0.0
				break
	if forced != null and (forced.time <= 0.0 or get_slide_collision_count() > 0):
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
		net_t = minf(net_t + delta / World.SNAP_DT, 1.0)
		global_position = net_from.lerp(net_to, net_t)
	flash = maxf(flash - delta, 0.0)
	if sprite != null:
		_update_sprite()
	queue_redraw()
	overlay.queue_redraw()


func _update_sprite() -> void:
	var anim_name: String = ANIM_NAMES[clampi(anim, 0, 4)]
	if not sprite.sprite_frames.has_animation(anim_name):
		anim_name = "idle"
	sprite.visible = not dead or sprite.sprite_frames.has_animation("death")
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	sprite.flip_h = (facing < 0.0) != bool(sprite_info.faces_left)
	sprite.scale = Vector2.ONE * sprite_info.scale * stats.size
	sprite.modulate = Color(1.6, 1.6, 1.6) if flash > 0.0 else _tint()


func _tint() -> Color:
	if flags & F_STUN:
		return Color(1, 1, 0.6)
	if flags & F_SLOW:
		return Color(0.7, 0.85, 1.2)
	if flags & F_DOT:
		return Color(1.2, 0.8, 0.6)
	return Color.WHITE


func _draw() -> void:
	if dead and not is_structure:
		return
	draw_set_transform(Vector2(0, radius * 0.75), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius * 1.05, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	if sprite == null:
		_draw_body()
	_draw_statuses()


func _draw_body() -> void:
	var c := color.lerp(Color.WHITE, 0.6) if flash > 0.0 else color
	draw_circle(Vector2.ZERO, radius, c)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, team_color(), 3.0, true)


func team_color() -> Color:
	return Game.TEAM_COLORS[clampi(team, 0, 2)]


func _draw_statuses() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if shield > 0.0:
		draw_arc(Vector2.ZERO, radius + 6.0, 0, TAU, 40, Color(0.95, 0.95, 1.0, 0.85), 3.0, true)
	if flags & F_INVULN:
		draw_arc(Vector2.ZERO, radius + 10.0, 0, TAU, 40, Color(1, 0.85, 0.2, 0.9), 3.0, true)
	if flags & F_SLOW:
		draw_arc(Vector2(0, radius * 0.6), radius * 0.9, 0.2, PI - 0.2, 16, Color(0.4, 0.7, 1.0, 0.9), 3.0)
	if flags & F_ROOT:
		draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 24, Color(0.45, 0.8, 0.3, 0.9), 4.0)
	if flags & F_DOT:
		draw_arc(Vector2.ZERO, radius + 2.0, t * 4.0, t * 4.0 + 2.0, 12, Color(1, 0.5, 0.1, 0.9), 3.0)
	if flags & F_HOT:
		draw_arc(Vector2.ZERO, radius + 2.0, -t * 4.0, -t * 4.0 + 2.0, 12, Color(0.4, 1, 0.4, 0.9), 3.0)
	if flags & F_BUFF:
		draw_arc(Vector2.ZERO, radius + 4.0, -t * 2.0, -t * 2.0 + 1.0, 10, Color(0.6, 1, 0.5, 0.8), 2.0)
	if flags & F_STUN:
		for i in 3:
			var a := t * 5.0 + i * TAU / 3.0
			draw_circle(Vector2(cos(a) * radius * 0.7, -radius - 8.0 + sin(a) * 4.0), 4.0, Color(1, 0.9, 0.2))
	if flags & F_SILENCE:
		draw_string(ThemeDB.fallback_font, Vector2(-radius, -radius - 4.0), "...", HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, Color(0.8, 0.6, 1))
	if flags & F_RECALL:
		draw_arc(Vector2.ZERO, radius + 14.0, 0, TAU, 40, Color(0.5, 0.7, 1.0, 0.7), 2.0, true)
		draw_rect(Rect2(-radius * 0.5, -radius * 3.0, radius, radius * 3.0), Color(0.5, 0.7, 1.0, 0.18))


func bar_width() -> float:
	return 44.0


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
			return sprite.position.y - tex.get_height() * sprite.scale.y * 0.5 - 12.0
	return -radius - 16.0


func _draw_overlay(n: Node2D) -> void:
	if dead:
		return
	var w := bar_width()
	var top := bar_top()
	var total := maxf(stats.max_hp, hp + shield)
	var x := -w * 0.5
	var col := Color(0.6, 0.6, 0.6) if flags & F_PROTECTED else bar_color()
	n.draw_rect(Rect2(x - 1, top - 1, w + 2, 8), Color(0, 0, 0, 0.85))
	n.draw_rect(Rect2(x, top, w * clampf(hp / total, 0.0, 1.0), 6), col)
	if shield > 0.0:
		n.draw_rect(Rect2(x + w * hp / total, top, w * shield / total, 6), Color(0.92, 0.92, 0.95))
	if flags & F_PROTECTED:
		n.draw_string(ThemeDB.fallback_font, Vector2(x, top - 3), "protected", HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(0.8, 0.8, 0.8))
