class_name World
extends Node2D
## One match. On the host it simulates everything; clients mirror the host via
## spawn/despawn RPCs plus ~20 Hz snapshots, and send their inputs as commands.

const SNAP_EVERY := 3
const SNAP_DT := SNAP_EVERY / 60.0
const XP_RANGE := 1300.0

var config := {}
var online := false
var is_server := true
var map: GameMap
var entities := {}
var units: Array = []
var structures: Array = []
var champions := {}
var next_id := 1
var time := 0.0
var started := false
var ended := false
var closing := false
var winner := -1
var kills := [0, 0]
var wave_timer := 0.0
var wave_count := 0
var _fountain_t := 0.0
var _trickle_t := 0.0
var _scheduled: Array = []
var _pending_fx: Array = []
var _frame := 0
var _wait_t := 0.0
var _sounds := {}

var local_peer := 1
var local_team := 0
var local_champion: Champion = null

var zone_layer: Node2D
var unit_layer: Node2D
var proj_layer: Node2D
var fx_layer: Node2D
var indicator: DrawNode
var camera: Camera2D
var hud: Hud

var cam_locked := true
var cam_zoom := 1.0
var aim_slot := ""
var amove_armed := false
var rmb_held := false
var rmb_timer := 0.0


func start(cfg: Dictionary) -> void:
	config = cfg
	Game.world = self
	online = bool(cfg.get("online", false))
	is_server = multiplayer.is_server()
	local_peer = multiplayer.get_unique_id()
	var me = cfg.players.get(local_peer)
	local_team = int(me.team) if me != null else 0
	map = GameMap.new()
	add_child(map)
	map.build(cfg.map_data)
	zone_layer = _layer(-1, false)
	unit_layer = _layer(0, true)
	proj_layer = _layer(5, false)
	fx_layer = _layer(20, false)
	indicator = DrawNode.new()
	indicator.z_index = 30
	indicator.draw_func = _draw_indicator
	add_child(indicator)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 10.0
	camera.limit_left = -300
	camera.limit_top = -300
	camera.limit_right = int(map.size.x) + 300
	camera.limit_bottom = int(map.size.y) + 300
	add_child(camera)
	camera.make_current()
	camera.global_position = map.spawn_point(local_team)
	camera.reset_smoothing()
	hud = Hud.new()
	hud.world = self
	add_child(hud)
	if is_server:
		check_ready()
	else:
		Game.notify_world_ready()


func _layer(z: int, ysort: bool) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.y_sort_enabled = ysort
	add_child(n)
	return n


func _exit_tree() -> void:
	if Game.world == self:
		Game.world = null


func shutdown() -> void:
	closing = true
	ended = true
	visible = false
	hud.visible = false
	camera.enabled = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if Game.world == self:
		Game.world = null


func check_ready() -> void:
	if is_server and not started and Game.all_peers_ready():
		begin()


func begin() -> void:
	if started:
		return
	started = true
	if online:
		_rpc_begin.rpc()
	for s in map.structures:
		spawn("tower", s)
	var per_team := [0, 0]
	for pid in config.players:
		var p: Dictionary = config.players[pid]
		var t := clampi(int(p.team), 0, 1)
		var off := Vector2(0, 70).rotated(per_team[t] * 2.1) if per_team[t] > 0 else Vector2.ZERO
		var gone: bool = online and pid != 1 and not bool(p.get("bot", false)) and not Game.players.has(pid)
		spawn("champion", {"peer": pid, "team": t, "character": p.character, "name": p.name,
			"bot": bool(p.get("bot", false)) or gone, "pos": map.spawn_point(t) + off, "lane": per_team[t]})
		per_team[t] += 1
	for dpos in map.dummies:
		spawn("dummy", {"pos": dpos})
	wave_timer = map.first_wave


@rpc("authority", "call_remote", "reliable")
func _rpc_begin() -> void:
	started = true


# ------------------------------------------------------------- entities ---

func spawn(kind: String, data: Dictionary) -> Node:
	var id := next_id
	next_id += 1
	var e := _create(kind, id, data)
	if online:
		_rpc_spawn.rpc(kind, id, data)
	return e


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn(kind: String, id: int, data: Dictionary) -> void:
	if not closing:
		_create(kind, id, data)


func _create(kind: String, id: int, data: Dictionary) -> Node:
	var e: Node
	var layer := unit_layer
	match kind:
		"champion": e = Champion.new()
		"minion": e = Minion.new()
		"tower": e = Tower.new()
		"summon": e = Summon.new()
		"dummy": e = Dummy.new()
		"projectile":
			e = Projectile.new()
			layer = proj_layer
		"zone":
			e = Zone.new()
			layer = zone_layer
		_:
			push_error("Unknown entity kind: " + kind)
			return null
	e.world = self
	e.net_id = id
	e.puppet = not is_server
	e.name = "%s_%d" % [kind, id]
	e.setup(data)
	entities[id] = e
	layer.add_child(e)
	if e is Unit:
		units.append(e)
		if e is Tower:
			structures.append(e)
		if e is Champion:
			champions[e.peer] = e
			if e.peer == local_peer:
				local_champion = e
	return e


func despawn(e: Node) -> void:
	if e == null or not is_instance_valid(e) or not entities.has(e.net_id):
		return
	var id: int = e.net_id
	_remove(id)
	if online:
		_rpc_despawn.rpc(id)


func despawn_later(e: Node, delay: float) -> void:
	schedule(delay, _despawn_id.bind(e.net_id))


func _despawn_id(id: int) -> void:
	if entities.has(id):
		despawn(entities[id])


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn(id: int) -> void:
	_remove(id)


func _remove(id: int) -> void:
	var e = entities.get(id)
	if e == null:
		return
	entities.erase(id)
	if e is Unit:
		units.erase(e)
		structures.erase(e)
	e.queue_free()


func schedule(delay: float, f: Callable) -> void:
	_scheduled.append([time + delay, f])


func _run_scheduled() -> void:
	if _scheduled.is_empty():
		return
	var due := []
	var keep := []
	for s in _scheduled:
		if s[0] <= time:
			due.append(s)
		else:
			keep.append(s)
	_scheduled = keep
	for s in due:
		s[1].call()


# ----------------------------------------------------------- networking ---

func _build_snapshot() -> PackedFloat32Array:
	var buf := PackedFloat32Array([time, kills[0], kills[1]])
	for id in entities:
		var st: PackedFloat32Array = entities[id].net_state()
		buf.append(id)
		buf.append(st.size())
		buf.append_array(st)
	return buf


func _send_snapshot() -> void:
	_rpc_snapshot.rpc(_build_snapshot())


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(buf: PackedFloat32Array) -> void:
	if buf.size() < 3 or closing:
		return
	time = buf[0]
	kills = [int(buf[1]), int(buf[2])]
	var i := 3
	while i + 1 < buf.size():
		var id := int(buf[i])
		var n := int(buf[i + 1])
		var e = entities.get(id)
		if e != null and i + 2 + n <= buf.size():
			e.apply_net_state(buf.slice(i + 2, i + 2 + n))
		i += 2 + n


func fx(kind: String, data: Dictionary) -> void:
	_play_fx(kind, data)
	if online and is_server:
		_pending_fx.append([kind, data])


@rpc("authority", "call_remote", "reliable")
func _rpc_fx(list: Array) -> void:
	if closing:
		return
	for f in list:
		_play_fx(f[0], f[1])


func _play_fx(kind: String, data: Dictionary) -> void:
	if kind == "sound":
		_play_sound(data)
		return
	if kind == "announce":
		hud.announce(str(data.text), data.get("color", Color.WHITE))
		var txt := str(data.text)
		if txt.contains("destroyed"):
			_sfx("boom", null, -2.0)
		elif txt.contains("slain") or txt.contains("died"):
			_sfx("death", null, -6.0)
		return
	var f := Fx.new()
	f.setup(kind, data)
	fx_layer.add_child(f)
	match kind:
		"blast":
			_sfx("boom", data.get("pos"), -14.0 + clampf(float(data.get("radius", 100.0)) / 40.0, 0.0, 7.0))
		"ring":
			_sfx("pop", data.get("pos"), -16.0)
		"line", "beam":
			_sfx("zap", data.get("from"), -12.0)
		"text":
			if str(data.get("text", "")).begins_with("LEVEL"):
				_sfx("level", data.get("pos"), -8.0)


func _sfx(sound: String, pos, volume: float) -> void:
	if not Sfx.allow(sound):
		return
	var p: Node
	if pos is Vector2:
		var p2 := AudioStreamPlayer2D.new()
		p2.stream = Sfx.stream(sound)
		p2.volume_db = volume
		p2.max_distance = 2200.0
		p2.position = pos
		p = p2
	else:
		var p1 := AudioStreamPlayer.new()
		p1.stream = Sfx.stream(sound)
		p1.volume_db = volume
		p = p1
	fx_layer.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _play_sound(d: Dictionary) -> void:
	var key := "%s/%s" % [d.get("char", ""), d.get("file", "")]
	if not _sounds.has(key):
		_sounds[key] = _load_sound(str(d.get("char", "")), str(d.get("file", "")))
	var stream = _sounds[key]
	if stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = float(d.get("volume", 0.0))
	p.max_distance = 2500.0
	fx_layer.add_child(p)
	p.global_position = d.get("pos", Vector2.ZERO)
	p.finished.connect(p.queue_free)
	p.play()


func _load_sound(cid: String, file: String):
	var def = Game.characters.get(cid)
	if def == null or not def.pack.files.has(file):
		return null
	var bytes: PackedByteArray = def.pack.files[file]
	match file.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null


func send_command(cmd: String, args: Array = []) -> void:
	if is_server:
		apply_command(local_peer, cmd, args)
	else:
		_rpc_command.rpc_id(1, cmd, args)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: String, args: Array) -> void:
	if is_server:
		apply_command(multiplayer.get_remote_sender_id(), cmd, args)


func apply_command(pid: int, cmd: String, args: Array) -> void:
	var c = champions.get(pid)
	if c != null and started and not ended:
		c.command(cmd, args)


func on_peer_left(id: int, pname: String) -> void:
	if not started:
		check_ready()
		return
	var c = champions.get(id)
	if c != null:
		c.is_bot = true
	fx("announce", {"text": "%s left the game - a bot takes over" % pname, "color": Color(1, 0.8, 0.4)})

# ------------------------------------------------------------ game rules ---

func _physics_process(delta: float) -> void:
	if not is_server:
		return
	if not started:
		_wait_t += delta
		if _wait_t > 15.0:
			begin()
		return
	if ended:
		return
	time += delta
	_run_scheduled()
	_waves(delta)
	_fountain(delta)
	_trickle(delta)
	_frame += 1
	if online and _frame % SNAP_EVERY == 0:
		_send_snapshot()
		if not _pending_fx.is_empty():
			_rpc_fx.rpc(_pending_fx)
			_pending_fx = []


func _waves(delta: float) -> void:
	if map.lane_count() == 0:
		return
	wave_timer -= delta
	if wave_timer > 0.0:
		return
	wave_timer = map.wave_interval
	wave_count += 1
	var types := []
	for k in map.wave_melee:
		types.append("melee")
	for k in map.wave_ranged:
		types.append("ranged")
	var sc := 1.0 + 0.05 * time / 60.0
	for team in 2:
		for li in map.lane_count():
			var start: Vector2 = map.lane(team, li)[0]
			for k in types.size():
				schedule(k * 0.7, _spawn_minion.bind(team, li, types[k], start, sc))


func _spawn_minion(team: int, li: int, type: String, pos: Vector2, sc: float) -> void:
	if not ended:
		spawn("minion", {"team": team, "lane": li, "type": type, "pos": pos, "scale": sc})


func _fountain(delta: float) -> void:
	_fountain_t -= delta
	if _fountain_t > 0.0:
		return
	_fountain_t = 0.25
	for c in champions.values():
		if c.dead:
			continue
		for t in 2:
			if c.global_position.distance_to(map.spawn_point(t)) > map.fountain_radius:
				continue
			if c.team == t:
				c.heal(c.stats.max_hp * 0.07, null, false)
			elif map.lane_count() > 0:
				c.take_damage(300.0, null, "true")
				fx("line", {"from": map.spawn_point(t), "to": c.global_position, "color": Game.TEAM_COLORS[t], "dur": 0.2})


func _trickle(delta: float) -> void:
	_trickle_t += delta
	if _trickle_t >= 1.0:
		_trickle_t -= 1.0
		for c in champions.values():
			c.gain_xp(3.0)


func respawn_time(level: int) -> float:
	return 3.0 if map.lane_count() == 0 else 4.0 + 1.25 * level


func is_protected(t: Tower) -> bool:
	if t.is_nexus:
		var lanes_total := {}
		var lanes_alive := {}
		for s in structures:
			if s.team == t.team and not s.is_nexus:
				lanes_total[s.lane] = true
				if not s.dead:
					lanes_alive[s.lane] = true
		for l in lanes_total:
			if not lanes_alive.has(l):
				return false
		return not lanes_total.is_empty()
	for s in structures:
		if s != t and s.team == t.team and not s.is_nexus and s.lane == t.lane and s.order < t.order and not s.dead:
			return true
	return false


func on_damage(victim: Unit, amount: float, src, dtype: String) -> void:
	var show: bool = victim.is_champion or victim is Dummy or (src != null and src.is_champion)
	if show and amount >= 1.0:
		var col := Color(1, 0.75, 0.35)
		if dtype == "true":
			col = Color.WHITE
		elif dtype != "physical":
			col = Color(0.8, 0.55, 1.0)
		fx("text", {"pos": victim.global_position + Vector2(randf_range(-18, 18), -victim.radius - 30), "text": str(int(round(amount))),
			"color": col, "size": 18 if victim.is_champion else 15})
	if src != null and src.is_champion and victim.is_champion:
		for t in structures:
			if t.team == victim.team and t.global_position.distance_to(victim.global_position) < t.stats.attack_range + 300.0:
				t.aggro(src)


func on_unit_died(u: Unit, killer) -> void:
	var credit = killer
	if is_instance_valid(credit) and credit is Summon and is_instance_valid(credit.owner_unit):
		credit = credit.owner_unit
	if u is Champion:
		var ck = credit if is_instance_valid(credit) and credit is Champion and credit.team != u.team else null
		if ck == null and is_instance_valid(u.last_champion_hit) and time - u.last_champion_hit_time < 10.0 and u.last_champion_hit.team != u.team:
			ck = u.last_champion_hit
		if u.team <= 1:
			kills[1 - u.team] += 1
		if ck != null:
			ck.kills += 1
			ck.on_kill(u)
			fx("announce", {"text": "%s slain by %s" % [u.label(), ck.label()], "color": Game.TEAM_COLORS[ck.team]})
		else:
			fx("announce", {"text": "%s died" % u.label(), "color": Color(0.8, 0.8, 0.8)})
		_give_xp(u.global_position, u.team, 90.0 + 30.0 * u.level, ck)
	else:
		if is_instance_valid(credit) and credit is Champion:
			credit.on_kill(u)
		if u.xp_value > 0.0:
			_give_xp(u.global_position, u.team, u.xp_value, null)
	if u is Tower:
		fx("announce", {"text": "%s %s destroyed!" % [Game.TEAM_NAMES[u.team], u.display_name], "color": Game.TEAM_COLORS[1 - u.team]})
		if u.is_nexus:
			end_match(1 - u.team)


func _give_xp(pos: Vector2, victim_team: int, amount: float, killer) -> void:
	var near := []
	for c in champions.values():
		if c.team != victim_team and not c.dead and c.global_position.distance_to(pos) <= XP_RANGE:
			near.append(c)
	if killer != null and not near.has(killer):
		near.append(killer)
	if near.is_empty():
		return
	var share := amount * (1.0 + 0.2 * (near.size() - 1)) / near.size()
	for c in near:
		c.gain_xp(share)


func end_match(win_team: int) -> void:
	if ended:
		return
	_finish(win_team)
	if online:
		_rpc_end.rpc(win_team, _build_snapshot())


@rpc("authority", "call_remote", "reliable")
func _rpc_end(t: int, final_state: PackedFloat32Array) -> void:
	if closing:
		return
	_rpc_snapshot(final_state)
	_finish(t)


func _finish(t: int) -> void:
	ended = true
	winner = t
	aim_slot = ""
	hud.show_end(t)


# ---------------------------------------------------------------- queries ---

static func team_matches(team: int, other: int, affects: String) -> bool:
	match affects:
		"allies":
			return other == team
		"all":
			return true
	return other != team


func query(center: Vector2, r: float, team: int, affects := "enemies", structs := false) -> Array:
	var out := []
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or not team_matches(team, u.team, affects):
			continue
		if u.global_position.distance_to(center) <= r + u.radius:
			out.append(u)
	return out


func query_line(a: Vector2, b: Vector2, half_w: float, team: int, affects := "enemies", structs := false) -> Array:
	var out := []
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or not team_matches(team, u.team, affects):
			continue
		if Geometry2D.get_closest_point_to_segment(u.global_position, a, b).distance_to(u.global_position) <= half_w + u.radius:
			out.append(u)
	return out


func nearest_enemy(pos: Vector2, team: int, max_d: float, champs_only := false, structs := false) -> Unit:
	var best: Unit = null
	var bd := max_d
	for u in units:
		if u.team == team or u.dead or not u.targetable() or (u.is_structure and not structs) or (champs_only and not u.is_champion):
			continue
		var d: float = u.global_position.distance_to(pos) - u.radius
		if d <= bd:
			bd = d
			best = u
	return best


## Unit under/near a point. enemy=true picks enemies of `team`, otherwise allies.
func pick_unit(pos: Vector2, team: int, enemy: bool, tolerance: float, structs := true) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or (u.team != team) != enemy:
			continue
		var d: float = u.global_position.distance_to(pos) - u.radius
		if d <= tolerance and d < bd:
			bd = d
			best = u
	return best


# ------------------------------------------------------- input & camera ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom * 1.1, 0.45, 1.8)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom / 1.1, 0.45, 1.8)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			rmb_held = mb.pressed
			if mb.pressed:
				if aim_slot != "":
					aim_slot = ""
					return
				amove_armed = false
				_right_click(true)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if aim_slot != "":
				_cast(aim_slot)
				aim_slot = ""
			elif amove_armed:
				amove_armed = false
				send_command("amove", [get_global_mouse_position()])
				_play_fx("click", {"pos": get_global_mouse_position(), "color": Color(1, 0.3, 0.3)})
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		var slot := ""
		match k.keycode:
			KEY_Q: slot = "q"
			KEY_W: slot = "w"
			KEY_E: slot = "e"
			KEY_R: slot = "r"
		if slot != "":
			if k.pressed:
				aim_slot = slot
				amove_armed = false
			elif aim_slot == slot:
				_cast(slot)
				aim_slot = ""
			return
		if k.keycode == KEY_TAB:
			hud.show_scores(k.pressed)
			return
		if not k.pressed:
			return
		match k.keycode:
			KEY_A:
				amove_armed = true
			KEY_S:
				send_command("stop")
			KEY_B:
				send_command("recall")
			KEY_Y, KEY_Z:
				cam_locked = not cam_locked
			KEY_SPACE:
				if local_champion != null:
					camera.global_position = local_champion.global_position
			KEY_ESCAPE:
				if aim_slot != "" or amove_armed:
					aim_slot = ""
					amove_armed = false
				else:
					hud.toggle_menu()


func _right_click(with_fx: bool) -> void:
	if local_champion == null or local_champion.dead:
		return
	var m := get_global_mouse_position()
	var t := pick_unit(m, local_team, true, 14.0)
	if t != null:
		send_command("attack", [t.net_id])
		if with_fx:
			_play_fx("click", {"pos": t.global_position, "color": Color(1, 0.3, 0.3)})
		rmb_held = false
	else:
		send_command("move", [m])
		if with_fx:
			_play_fx("click", {"pos": m, "color": Color(0.4, 1, 0.4)})
	rmb_timer = 0.15


func _cast(slot: String) -> void:
	if local_champion == null or local_champion.dead or ended:
		return
	var ab = local_champion.def.abilities.get(slot)
	if ab == null:
		return
	var m := get_global_mouse_position()
	var tid := 0
	if ab.targeting == "unit" or ab.targeting == "ally":
		var t := pick_unit(m, local_team, ab.targeting == "unit", 70.0, false)
		if t != null:
			tid = t.net_id
	send_command("cast", [slot, m, tid])
	if local_champion.cooldowns.get(slot, 0.0) <= 0.0:
		_sfx("cast", local_champion.global_position, -14.0)


func _process(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2.ONE * cam_zoom, minf(10.0 * delta, 1.0))
	if cam_locked and local_champion != null:
		camera.global_position = local_champion.global_position
	elif not cam_locked:
		var vp := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		var pan := Vector2.ZERO
		if mp.x < 10 or Input.is_key_pressed(KEY_LEFT):
			pan.x -= 1
		if mp.x > vp.x - 10 or Input.is_key_pressed(KEY_RIGHT):
			pan.x += 1
		if mp.y < 10 or Input.is_key_pressed(KEY_UP):
			pan.y -= 1
		if mp.y > vp.y - 10 or Input.is_key_pressed(KEY_DOWN):
			pan.y += 1
		camera.global_position += pan * 1400.0 * delta / cam_zoom
		var half := get_viewport_rect().size * 0.5 / camera.zoom
		var lo := Vector2(camera.limit_left, camera.limit_top) + half
		var hi := Vector2(camera.limit_right, camera.limit_bottom) - half
		var cp := camera.global_position
		camera.global_position = Vector2(clampf(cp.x, lo.x, maxf(lo.x, hi.x)), clampf(cp.y, lo.y, maxf(lo.y, hi.y)))
	if rmb_held:
		rmb_timer -= delta
		if rmb_timer <= 0.0:
			_right_click(false)
	indicator.queue_redraw()


func _draw_indicator(n: Node2D) -> void:
	var c := local_champion
	if c == null or c.dead or ended:
		return
	var p := c.global_position
	if amove_armed:
		n.draw_arc(p, c.stats.attack_range + c.radius, 0, TAU, 64, Color(1, 0.35, 0.3, 0.7), 2.0, true)
	if aim_slot == "":
		return
	var ab = c.def.abilities.get(aim_slot)
	if ab == null:
		return
	var rng := Effects.num(ab.range, {"caster": c}, 700.0)
	var col := Color(0.45, 0.8, 1.0, 0.7)
	var m := get_global_mouse_position()
	var to := m - p
	var dir := to.normalized() if to.length() > 1.0 else Vector2(c.facing, 0)
	var end := p + dir * minf(to.length(), rng)
	var rad: float = ab.indicator_radius
	match ab.targeting:
		"self":
			n.draw_arc(p, rad if rad > 0.0 else c.radius + 20.0, 0, TAU, 64, col, 3.0, true)
		"direction":
			n.draw_arc(p, rng, 0, TAU, 96, Color(col, 0.25), 2.0, true)
			n.draw_line(p, p + dir * rng, Color(col, 0.25), 40.0)
			n.draw_line(p, p + dir * rng, col, 2.0)
		"point":
			n.draw_arc(p, rng, 0, TAU, 96, Color(col, 0.3), 2.0, true)
			n.draw_arc(end, rad if rad > 0.0 else 40.0, 0, TAU, 48, col, 3.0, true)
		_:
			n.draw_arc(p, rng, 0, TAU, 96, Color(col, 0.3), 2.0, true)
			var t := pick_unit(m, local_team, ab.targeting == "unit", 70.0, false)
			if t != null:
				n.draw_arc(t.global_position, t.radius + 8.0, 0, TAU, 32, col, 4.0, true)
