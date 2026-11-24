class_name World
extends Node2D
## One match. On the host it simulates everything; clients mirror the host via
## spawn/despawn RPCs plus ~20 Hz snapshots, and send their inputs as commands.

const SNAP_EVERY := 3
const SNAP_DT := SNAP_EVERY / 60.0
const SNAP_CHUNK := 300  # floats per snapshot packet (~1.2 KB, under the usual 1392-byte MTU)
const XP_RANGE := 1300.0
const KILL_GOLD := 300.0
const ASSIST_GOLD := 150.0
const TOWER_GOLD := 150.0

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
var under_layer: Node2D
var unit_layer: Node2D
var proj_layer: Node2D
var fx_layer: Node2D
var fog: FogOfWar
var indicator: DrawNode
var camera: Camera2D
var hud: Hud

var cam_locked := true
var edge_pan := true
var cam_zoom := 1.0
var aim_slot := ""
var amove_armed := false
var rmb_held := false
var rmb_timer := 0.0
var hover_unit: Unit = null
var test_aim = null  # Vector2 override for automated indicator screenshots
var _shake := 0.0
var _cursor_attack := false


func start(cfg: Dictionary) -> void:
	config = cfg
	Game.world = self
	online = bool(cfg.get("online", false))
	is_server = multiplayer.is_server()
	local_peer = multiplayer.get_unique_id()
	var me = cfg.players.get(local_peer)
	local_team = int(me.team) if me != null else 0
	map = GameMap.new()
	map.z_index = -10
	add_child(map)
	map.build(cfg.map_data)
	zone_layer = _layer(-5, false)
	under_layer = _layer(-4, false)
	unit_layer = _layer(0, true)
	proj_layer = _layer(5, false)
	fog = FogOfWar.new()
	add_child(fog)
	fog.setup(self)
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
	Input.set_custom_mouse_cursor(null)
	if Game.world == self:
		Game.world = null


func shutdown() -> void:
	closing = true
	ended = true
	Input.set_custom_mouse_cursor(null)
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
	var start_gold := float(map.data.get("start_gold", 500.0))
	for pid in config.players:
		var p: Dictionary = config.players[pid]
		var t := clampi(int(p.team), 0, 1)
		var off := Vector2(0, 70).rotated(per_team[t] * 2.1) if per_team[t] > 0 else Vector2.ZERO
		var gone: bool = online and pid != 1 and not bool(p.get("bot", false)) and not Game.players.has(pid)
		var c = spawn("champion", {"peer": pid, "team": t, "character": p.character, "name": p.name, "gold": start_gold,
			"bot": bool(p.get("bot", false)) or gone, "pos": map.spawn_point(t) + off, "lane": per_team[t]})
		for k in int(map.data.get("start_level", 1)) - 1:
			c.cheat("level")
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
	# Split into packets below the network MTU: each one is applied on its own, so a lost
	# packet only delays those entities until the next snapshot.
	var head := PackedFloat32Array([time, kills[0], kills[1]])
	var buf := head.duplicate()
	for id in entities:
		var st: PackedFloat32Array = entities[id].net_state()
		if buf.size() > 3 and buf.size() + st.size() + 2 > SNAP_CHUNK:
			_rpc_snapshot.rpc(buf)
			buf = head.duplicate()
		buf.append(id)
		buf.append(st.size())
		buf.append_array(st)
	_rpc_snapshot.rpc(buf)


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
	if not _fx_visible(kind, data):
		return
	if kind == "sound":
		_play_sound(data)
		return
	match kind:
		"notice":
			if int(data.get("peer", 0)) == local_peer:
				hud.notice(str(data.get("text", "")))
				_sfx("error", null, -12.0)
			return
		"gold":
			if int(data.get("peer", 0)) == local_peer:
				var g := Fx.new()
				g.setup("text", {"pos": Vector2(data.p) + Vector2(randf_range(-12, 12), -46), "text": "+%d" % int(data.a),
					"color": Color(1.0, 0.85, 0.25), "size": 18, "dur": 0.9})
				fx_layer.add_child(g)
				_sfx("coin", data.p, -16.0)
			return
		"buy", "rankup":
			if local_champion != null and int(data.get("v", 0)) == local_champion.net_id:
				_sfx("buy" if kind == "buy" else "pop", null, -10.0)
				if kind == "rankup":
					hud.flash_slot(str(data.get("s", "")))
			return
	if kind == "announce":
		hud.announce(str(data.text), data.get("color", Color.WHITE))
		var txt := str(data.text)
		if txt.contains("destroyed"):
			_sfx("boom", null, -2.0)
		elif txt.contains("slain") or txt.contains("died"):
			_sfx("death", null, -6.0)
		return
	if FxPlayer.play(self, kind, data):
		return
	var f := Fx.new()
	f.setup(kind, data)
	fx_layer.add_child(f)
	match kind:
		"ring":
			_sfx("pop", data.get("pos"), -16.0)
		"line", "beam":
			_sfx("zap", data.get("from"), -12.0)
	if kind == "beam":
		Vfx.particles(fx_layer, data.to, Color(data.get("color", Color.WHITE)).lightened(0.3), 10, 260.0, 0.4, 3.0)


## Client-side delayed visual (not part of the simulation).
func schedule_visual(delay: float, f: Callable) -> void:
	get_tree().create_timer(delay, false).timeout.connect(func():
		if not closing:
			f.call()
	)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Shake scaled by how close the event is to what the camera is looking at.
func shake_at(pos: Vector2, amount: float) -> void:
	var d := pos.distance_to(camera.get_screen_center_position())
	if d < 1400.0:
		shake(amount * clampf(1.3 - d / 1000.0, 0.2, 1.0))


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
				c.restore_mana(c.stats.max_mana * 0.07)
			elif map.lane_count() > 0:
				c.take_damage(300.0, null, "true", {"vfx": "star", "col": Game.TEAM_COLORS[t]})
				fx("beam", {"from": map.spawn_point(t), "to": c.global_position, "color": Game.TEAM_COLORS[t], "width": 18.0})


func _trickle(delta: float) -> void:
	_trickle_t += delta
	if _trickle_t >= 1.0:
		_trickle_t -= 1.0
		var g := float(map.data.get("gold_per_second", 2.5))
		for c in champions.values():
			c.gain_xp(3.0)
			c.gold += g


## Practice matches (and maps with "cheats": true) allow F1-F4 cheats and shopping anywhere.
func cheats_allowed() -> bool:
	return not online or bool(map.data.get("cheats", false))


## Whether `u` can be seen by `viewer_team` (fog of war and stealth).
func can_see(u: Unit, viewer_team: int) -> bool:
	if u.team == viewer_team:
		return true
	if fog != null and fog.enabled:
		return fog.sees(u, viewer_team)
	if u.flags & Unit.F_STEALTH and not _revealed(u, viewer_team):
		return false
	return true


## Whether an effect at this spot should be shown to the local player (fog of war).
func _fx_visible(kind: String, data: Dictionary) -> bool:
	if fog == null or not fog.enabled or ended or kind in ["kill", "announce", "notice", "gold", "buy", "rankup", "click"]:
		return true
	if data.has("team") and int(data.team) == local_team:
		return true
	for k in ["s", "v"]:
		var id = data.get(k)
		if (id is int or id is float) and int(id) != 0:
			var e = entities.get(int(id))
			if e is Unit and e.team == local_team:
				return true
	var any := false
	for k in ["p", "pos", "from", "to"]:
		var v = data.get(k)
		if v is Vector2:
			any = true
			if fog.point_visible(v, local_team):
				return true
	return not any


## Stealthed units are revealed when an enemy champion is very close.
func _revealed(u: Unit, viewer_team: int) -> bool:
	for c in champions.values():
		if c.team == viewer_team and not c.dead and c.global_position.distance_to(u.global_position) < 250.0:
			return true
	return false


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


func on_damage(victim: Unit, amount: float, src, dtype: String, hit := {}) -> void:
	if Game.debug_log:
		var fl := PackedStringArray()
		for k in ["attack", "crit", "onhit", "dot", "aoe", "proc", "raw"]:
			if hit.get(k, false):
				fl.append(k)
		if str(hit.get("ability", "")) != "":
			fl.append("ab:" + str(hit.ability))
		if str(hit.get("item", "")) != "":
			fl.append("item:" + str(hit.item))
		print("[dmg] t=%.2f %s -> %s %.1f %s %s" % [time, src.display_name if src != null else "-", victim.display_name, amount, dtype, " ".join(fl)])
	if amount >= 1.0:
		fx("hit", {"p": victim.global_position, "v": victim.net_id, "a": amount, "t": dtype, "x": str(hit.get("vfx", "spark")),
			"c": hit.get("col", Color.WHITE), "r": float(hit.get("dir", randf() * TAU)), "s": src.net_id if src != null else 0})
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
		var helpers := []
		for id in u.damagers:
			var h = entities.get(id)
			if h is Champion and h != ck and h.team != u.team and time - float(u.damagers[id]) < 10.0:
				helpers.append(h)
		if ck != null:
			ck.kills += 1
			ck.add_gold(KILL_GOLD, u.global_position)
			ck.on_kill(u)
			ck.on_takedown(u, false)
		for h in helpers:
			h.add_gold(ASSIST_GOLD / helpers.size(), u.global_position)
			h.on_takedown(u, true)
		fx("kill", {"k": ck.net_id if ck != null else 0, "v": u.net_id})
		_give_xp(u.global_position, u.team, 90.0 + 30.0 * u.level, ck)
	else:
		if is_instance_valid(credit) and credit is Champion:
			if u.gold_value > 0.0:
				credit.add_gold(u.gold_value, u.global_position)
			credit.on_kill(u)
		if u.xp_value > 0.0:
			_give_xp(u.global_position, u.team, u.xp_value, null)
	if u is Tower:
		fx("announce", {"text": "%s %s destroyed!" % [Game.TEAM_NAMES[u.team], u.display_name], "color": Game.TEAM_COLORS[1 - u.team]})
		for c in champions.values():
			if c.team != u.team:
				c.add_gold(TOWER_GOLD, u.global_position if c.global_position.distance_to(u.global_position) < 1200.0 else null)
		if not u.is_nexus:
			fx("kill", {"k": 0, "v": u.net_id, "tower": true, "t": u.team})
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


## Units in a circle (abilities). Wards are skipped unless `wards` is true.
func query(center: Vector2, r: float, team: int, affects := "enemies", structs := false, wards := false) -> Array:
	var out := []
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or (u.is_ward and not wards) or not team_matches(team, u.team, affects):
			continue
		if u.global_position.distance_to(center) <= r + u.radius:
			out.append(u)
	return out


func query_line(a: Vector2, b: Vector2, half_w: float, team: int, affects := "enemies", structs := false, wards := false) -> Array:
	var out := []
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or (u.is_ward and not wards) or not team_matches(team, u.team, affects):
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
		if not can_see(u, team):
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
		if enemy and not can_see(u, team):
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
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6: slot = "i%d" % (k.keycode - KEY_1)
		if slot != "":
			if k.pressed and (k.ctrl_pressed or k.alt_pressed) and not slot.begins_with("i"):
				send_command("rank_up", [slot])
				return
			if k.pressed:
				var ab = aim_ability(slot)
				if slot.begins_with("i") and (ab == null or ab.targeting == "self"):
					_cast(slot)
					return
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
			KEY_P:
				hud.toggle_shop()
			KEY_Y, KEY_Z:
				cam_locked = not cam_locked
			KEY_SPACE:
				if local_champion != null:
					camera.global_position = local_champion.global_position
			KEY_F1, KEY_F2, KEY_F3, KEY_F4:
				if cheats_allowed():
					send_command("cheat", [["level", "gold", "cd", "ranks"][k.keycode - KEY_F1]])
			KEY_ESCAPE:
				if aim_slot != "" or amove_armed:
					aim_slot = ""
					amove_armed = false
				elif hud.shop_open():
					hud.toggle_shop()
				else:
					hud.toggle_menu()


## The ability (or item active) bound to an aim slot: q/w/e/r or i0..i5.
func aim_ability(slot: String):
	if local_champion == null:
		return null
	if slot.begins_with("i"):
		var it = local_champion.item_def(int(slot.substr(1)))
		return it.active if it != null else null
	return local_champion.def.abilities.get(slot)


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
	var c := local_champion
	if c == null or ended:
		return
	var ab = aim_ability(slot)
	if ab == null or (c.dead and not (slot.begins_with("i") and ab.get("while_dead", false))):
		return
	var m := get_global_mouse_position()
	var tid := 0
	if ab.targeting == "unit" or ab.targeting == "ally":
		var t := pick_unit(m, local_team, ab.targeting == "unit", 70.0, false)
		if t != null:
			tid = t.net_id
	if slot.begins_with("i"):
		var i := int(slot.substr(1))
		if c.items[i] != null and c.items[i].cd <= 0.0:
			send_command("item", [i, m, tid])
			_sfx("cast", c.global_position, -14.0)
		return
	if int(c.ranks.get(slot, 0)) <= 0:
		hud.notice("%s isn't learned yet - Ctrl+%s (or the + button) to level it up" % [ab.name, slot.to_upper()])
		return
	if c.cooldowns.get(slot, 0.0) <= 0.0 and not c.can_pay(ab):
		hud.notice("Not enough health" if ab.cost_type == "health" else "Not enough mana")
		return
	send_command("cast", [slot, m, tid])
	if c.cooldowns.get(slot, 0.0) <= 0.0:
		_sfx("cast", c.global_position, -14.0)


func _process(delta: float) -> void:
	camera.zoom = camera.zoom.lerp(Vector2.ONE * cam_zoom, minf(10.0 * delta, 1.0))
	if cam_locked and local_champion != null:
		camera.global_position = local_champion.global_position
	elif not cam_locked:
		var vp := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		var edge := edge_pan and get_window().has_focus() and Rect2(Vector2.ZERO, vp).has_point(mp)
		var keys := not (get_viewport().gui_get_focus_owner() is LineEdit)  # not while typing in the shop search
		var pan := Vector2.ZERO
		if (edge and mp.x < 10) or (keys and Input.is_key_pressed(KEY_LEFT)):
			pan.x -= 1
		if (edge and mp.x > vp.x - 10) or (keys and Input.is_key_pressed(KEY_RIGHT)):
			pan.x += 1
		if (edge and mp.y < 10) or (keys and Input.is_key_pressed(KEY_UP)):
			pan.y -= 1
		if (edge and mp.y > vp.y - 10) or (keys and Input.is_key_pressed(KEY_DOWN)):
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
	if _shake > 0.2:
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
		_shake = lerpf(_shake, 0.0, minf(12.0 * delta, 1.0))
	else:
		_shake = 0.0
		camera.offset = Vector2.ZERO
	hover_unit = null
	if local_champion != null and not ended and not closing and get_viewport().gui_get_hovered_control() == null:
		hover_unit = pick_unit(get_global_mouse_position(), local_team, true, 10.0)
	var want_attack := hover_unit != null or amove_armed
	if want_attack != _cursor_attack:
		_cursor_attack = want_attack
		Input.set_custom_mouse_cursor(Cursors.attack() if want_attack else null, Input.CURSOR_ARROW, Vector2(15, 15) if want_attack else Vector2.ZERO)
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
	var ab = aim_ability(aim_slot)
	if ab == null:
		return
	var ind: Dictionary = ab.get("indicator", {})
	var rng := Effects.num(ab.range, {"caster": c, "rank": maxi(int(c.ranks.get(aim_slot, 1)), 1)}, 700.0)
	var on_cd: bool = c.cooldowns.get(aim_slot, 0.0) > 0.0 if not aim_slot.begins_with("i") else c.items[int(aim_slot.substr(1))] != null and c.items[int(aim_slot.substr(1))].cd > 0.0
	var col := Color(0.6, 0.6, 0.6) if on_cd else Color(0.45, 0.82, 1.0)
	var m: Vector2 = test_aim if test_aim != null else get_global_mouse_position()
	var to := m - p
	var dir := to.normalized() if to.length() > 1.0 else Vector2(c.facing, 0)
	var end := p + dir * minf(to.length(), rng)
	if ab.targeting != "self":
		n.draw_arc(p, rng, 0, TAU, 96, Color(col, 0.35), 2.0, true)
	if ab.targeting == "unit" or ab.targeting == "ally":
		var t := pick_unit(m, local_team, ab.targeting == "unit", 70.0, false)
		if t != null:
			n.draw_arc(t.global_position, t.radius + 8.0, 0, TAU, 32, col, 4.0, true)
		return
	var r: float = ind.get("radius", ab.indicator_radius)
	match str(ind.get("shape", "")):
		"line":
			var count := int(ind.get("count", 1))
			var spread := deg_to_rad(float(ind.get("spread", 0.0)))
			for k in count:
				var a := 0.0
				if count > 1:
					a = TAU * k / count if spread >= TAU - 0.01 else -spread * 0.5 + spread * k / (count - 1)
				_draw_lane(n, p, dir.rotated(a), rng, maxf(float(ind.get("width", 24.0)), 8.0), col)
		"dash":
			var length := minf(to.length(), float(ind.get("length", 350.0)))
			var tip := p + dir * length
			_draw_lane(n, p, dir, length, c.radius * 2.0, col)
			if r > 0.0:
				_draw_disc(n, tip, r, col)
		"cone":
			var half := deg_to_rad(float(ind.get("angle", 90.0))) * 0.5
			var pts := PackedVector2Array([p])
			for i in 21:
				pts.append(p + dir.rotated(-half + 2.0 * half * i / 20.0) * r)
			n.draw_colored_polygon(pts, Color(col, 0.18))
			pts.append(p)
			n.draw_polyline(pts, Color(col, 0.85), 2.0, true)
		"self":
			_draw_disc(n, p, r, col)
		_:
			if ab.targeting == "self":
				_draw_disc(n, p, r if r > 0.0 else c.radius + 20.0, col)
			else:
				_draw_disc(n, end, r if r > 0.0 else 40.0, col)


func _draw_disc(n: Node2D, at: Vector2, r: float, col: Color) -> void:
	n.draw_circle(at, r, Color(col, 0.15))
	n.draw_arc(at, r, 0, TAU, 64, Color(col, 0.9), 2.5, true)


## Skillshot lane with an arrow head.
func _draw_lane(n: Node2D, from: Vector2, d: Vector2, length: float, w: float, col: Color) -> void:
	var side := d.orthogonal() * w * 0.5
	var tip := from + d * length
	var body := tip - d * minf(w, length * 0.3)
	n.draw_colored_polygon(PackedVector2Array([from + side, body + side, body - side, from - side]), Color(col, 0.16))
	n.draw_colored_polygon(PackedVector2Array([body + side * 1.6, tip, body - side * 1.6]), Color(col, 0.35))
	n.draw_polyline(PackedVector2Array([from + side, body + side, body + side * 1.6, tip, body - side * 1.6, body - side, from - side]), Color(col, 0.85), 2.0, true)
