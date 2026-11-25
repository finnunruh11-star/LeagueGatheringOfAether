class_name World
extends Node2D
## One match. On the host it simulates everything; clients mirror the host via
## spawn/despawn RPCs plus ~20 Hz snapshots, and send their inputs as commands.

const SNAP_EVERY := 3
const SNAP_DT := SNAP_EVERY / 60.0
const SNAP_CHUNK := 300  # floats per snapshot packet (~1.2 KB, under the usual 1392-byte MTU)
const XP_RANGE := 1400.0
const MINION_XP_MULTIPLIER := 0.92
const SHARED_MINION_XP_MULTIPLIER := 1.2
const KILL_GOLD := 300.0
const ASSIST_GOLD := 150.0
const TOWER_GOLD := 50.0
const BRUSH_REVEAL := 2.0       # seconds a champion stays revealed after damaging a champion from brush
const RELIC_FIRST := 75.0
const RELIC_RESPAWN := 90.0
const RELIC_COLOR := Color("78f5a8")
const PINGS := preload("res://scripts/ui/team_pings.gd")

var config := {}
var online := false
var is_server := true
var aram := false
var mayhem := false
var mayhem_tiers := [0, 1, 1, 2]
var relic_positions := PackedVector2Array()
var relic_ready := PackedFloat32Array()
var relic_art: DrawNode
var map: GameMap
var jungle: Jungle = null
var entities := {}
var units: Array = []
var structures: Array = []
var champions := {}
var dematerializer_armed := false
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
## Host: what bots can "see" being cast - recent ability/item casts and telegraphed areas/beams
## (read by BotBrain to dodge). Short-lived; old entries are dropped as new ones arrive.
var bot_casts: Array = []   # {id, c, slot, recast, item, pos, dir, from, target, t, ct}
var bot_warns: Array = []   # {id, kind ("circle"/"line"), pos, r | from, to, t (impact time), team}
var _bot_seq := 0

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
var _cam_focus := 0          # net id of the unit the camera is pointed at by a "camera" effect
var _cam_focus_t := 0.0
var _cam_return := 0.0
var edge_pan := true
var cam_zoom := 0.8
var aim_slot := ""
var amove_armed := false
var rmb_held := false
var rmb_timer := 0.0
var hover_unit: Unit = null
var test_aim = null  # Vector2 override for automated indicator screenshots
var _shake := 0.0
var _cursor_attack := false
var _cam_hold := false             # camera_center key held
var _amove_ring := 0.0             # attack-range ring flash after an instant attack-move
var _steer_sent := Vector2.ZERO    # last WASD direction sent to the host
var _sion_q_held := false
var _sion_steer_timer := 0.0
var pings := PINGS.new()


func start(cfg: Dictionary) -> void:
	config = cfg
	aram = Game.Mayhem.is_aram(cfg.map)
	mayhem = cfg.get("map") == Game.Mayhem.MAP_ID
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
	if not map.camps.is_empty():
		jungle = Jungle.new(self)
	zone_layer = _layer(-5, false)
	under_layer = _layer(-4, false)
	if aram:
		for x in [0.24, 0.41, 0.59, 0.76]:
			relic_positions.append(map.nearest_open(map.size * Vector2(x, 0.62 if x < 0.5 else 0.38)))
			relic_ready.append(RELIC_FIRST)
		relic_art = DrawNode.new()
		relic_art.draw_func = _draw_relics
		under_layer.add_child(relic_art)
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
	camera.zoom = Vector2.ONE * cam_zoom
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
	cam_locked = bool(Game.prefs.camera_locked)
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
	if mayhem:
		mayhem_tiers.shuffle()
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
		var role := map.role_lane(per_team[t])
		var sums: Array = p.get("summoners", Game.default_summoners(p.character)).duplicate()
		if role < 0 and bool(p.get("bot", false)) and jungle != null and Game.summoners.has("smite") and not "smite" in sums and sums.size() == 2:
			sums[1 if sums[0] == "flash" else 0] = "smite"  # bot junglers take Smite
		var c: Champion = spawn("champion", {"peer": pid, "team": t, "character": p.character, "name": p.name, "gold": start_gold,
			"bot": bool(p.get("bot", false)) or gone, "difficulty": str(p.get("difficulty", "normal")),
			"pos": map.spawn_point(t) + off, "lane": role, "summoners": sums, "runes": p.get("runes", {})})
		for k in int(map.data.get("start_level", 1)) - 1:
			c.cheat("level")
		if mayhem:
			_offer_augment(c)
		per_team[t] += 1
	for dpos in map.dummies:
		spawn("dummy", {"pos": dpos})
	wave_timer = map.first_wave
	if jungle != null:
		sync_jungle()


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
		"monster": e = Monster.new()
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
				send_build.call_deferred()
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
	if is_server and not data.get("cosmetic", false) and (kind == "telegraph" or kind == "beam_warn"):
		_note_warn(kind, data)
	_play_fx(kind, data)
	if online and is_server:
		_pending_fx.append([kind, data])


## Host: remembers an ability cast for the bots (see bot_casts).
func note_cast(c: Champion, slot: String, recast: bool, item: String, ctx: Dictionary, cast_time: float) -> void:
	_bot_seq += 1
	while not bot_casts.is_empty() and (float(bot_casts[0].t) < time - 5.0 or bot_casts.size() > 64):
		bot_casts.pop_front()
	bot_casts.append({"id": _bot_seq, "c": c, "slot": slot, "recast": recast, "item": item, "pos": ctx.get("pos", c.global_position),
		"dir": ctx.get("dir", Vector2.RIGHT), "from": c.global_position, "target": ctx.get("target"), "t": time, "ct": cast_time})


func _note_warn(kind: String, data: Dictionary) -> void:
	_bot_seq += 1
	while not bot_warns.is_empty() and (float(bot_warns[0].t) < time or bot_warns.size() > 64):
		bot_warns.pop_front()
	var w := {"id": _bot_seq, "t": time + float(data.get("dur", 0.5)), "team": int(data.get("team", 0))}
	if kind == "telegraph":
		w.merge({"kind": "circle", "pos": data.get("pos", Vector2.ZERO), "r": float(data.get("radius", 100.0))})
	else:
		w.merge({"kind": "line", "from": data.get("from", Vector2.ZERO), "to": data.get("to", Vector2.ZERO), "r": float(data.get("width", 70.0)) * 0.5})
	bot_warns.append(w)


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
		"camera":
			if local_champion != null and int(data.get("v", 0)) == local_champion.net_id:
				_cam_focus = int(data.get("t", 0))
				_cam_focus_t = float(data.get("dur", 1.0))
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
	var c: Champion = champions.get(pid)
	if c != null and started and not ended:
		if cmd == "ping":
			_send_team_ping(pid, c.team, args)
		elif cmd in ["augment_pick", "augment_reroll"]:
			if not _augment_command(c, cmd, args):
				fx("notice", {"peer": pid, "text": "That augment choice is no longer available."})
		else:
			c.command(cmd, args)


func _send_team_ping(pid: int, team: int, args: Array) -> void:
	if not pings.accept(pid, args, map.size, Time.get_ticks_msec()):
		return
	var kind: String = args[0]
	var at: Vector2 = args[1]
	if team == local_team:
		_receive_team_ping(kind, at)
	if online:
		for peer in multiplayer.get_peers():
			var recipient: Champion = champions.get(peer)
			if recipient != null and recipient.team == team:
				_receive_team_ping.rpc_id(peer, kind, at)


@rpc("authority", "call_remote", "reliable")
func _receive_team_ping(kind: String, at: Vector2) -> void:
	if not ended and not closing:
		pings.show_ping(kind, at)


func _input(event: InputEvent) -> void:
	if _handle_ping_input(event, get_viewport().get_mouse_position()):
		get_viewport().set_input_as_handled()


func _handle_ping_input(event: InputEvent, mouse: Vector2) -> bool:
	if not started or ended or closing:
		return false
	if not keys_free() or hud.shop_open():
		pings.cancel()
		return false
	if event.is_echo():
		return false
	var action := Controls.action_of(event, Game.prefs.move_mode)
	if pings.open_action != "":
		if action == pings.open_action and not event.is_pressed():
			send_command("ping", [pings.selection(mouse), pings.anchor])
			pings.cancel()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			pings.cancel()
			rmb_held = false
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			pings.cancel()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			pass
		else:
			return false
	elif event.is_pressed() and action in ["ping", "ping_retreat", "ping_vision"]:
		var mm := hud.minimap.get_global_rect()
		var at := (mouse - mm.position) / mm.size * map.size if mm.has_point(mouse) else get_canvas_transform().affine_inverse() * mouse
		if not Rect2(Vector2.ZERO, map.size).has_point(at):
			return false
		if action == "ping_retreat":
			send_command("ping", ["retreat", at])
		else:
			pings.open_action = action
			pings.origin = mouse
			pings.anchor = at
	else:
		return false
	return true


func on_peer_left(id: int, pname: String) -> void:
	if not started:
		check_ready()
		return
	var c = champions.get(id)
	if c != null:
		c.is_bot = true
	fx("announce", {"text": "%s left the game - a bot takes over" % pname, "color": Color(1, 0.8, 0.4)})


func _offer_augment(c: Champion) -> void:
	var round_index := c.augments.size()
	if not is_server or not mayhem or not c.augment_offers.is_empty() \
			or round_index >= Game.Mayhem.LEVELS.size() or c.level < Game.Mayhem.LEVELS[round_index]:
		return
	c.augment_tier = mayhem_tiers[round_index]
	c.augment_offers = Game.Mayhem.draw_augments(c.augment_tier, 3, c.augments)
	c.augment_seen = c.augment_offers.duplicate()
	c.augment_rerolled = [false, false, false]
	if not c.is_bot:
		_sync_augments(c)


func _augment_command(c: Champion, cmd: String, args: Array) -> bool:
	if not mayhem or c.is_bot or args.size() != 3 or not args[0] is int \
			or not args[1] is int or not args[2] is String or args[0] != c.augments.size():
		return false
	var slot: int = args[1]
	if slot < 0 or slot >= c.augment_offers.size() or args[2] != c.augment_offers[slot]:
		return false
	if cmd == "augment_pick":
		_pick_augment(c, c.augment_offers[slot])
		return true
	if c.augment_rerolled[slot]:
		return false
	var draw: Array = Game.Mayhem.draw_augments(c.augment_tier, 1, c.augments + c.augment_seen)
	if draw.is_empty():
		return false
	c.augment_offers[slot] = draw[0]
	c.augment_seen.append(draw[0])
	c.augment_rerolled[slot] = true
	_sync_augments(c)
	return true


func _pick_augment(c: Champion, id: String) -> void:
	c.augments.append(id)
	c.augment_offers.clear()
	c.augment_rerolled.clear()
	c.augment_tier = -1
	c._rebuild_triggers()
	c.recompute_stats()
	_sync_augments(c)
	_offer_augment(c)


func _sync_augments(c: Champion) -> void:
	if online and c.peer > 1 and Game.players.has(c.peer):
		_rpc_augments.rpc_id(c.peer, c.augments, c.augment_offers, c.augment_rerolled, c.augment_tier)


@rpc("authority", "call_remote", "reliable")
func _rpc_augments(chosen: Array, offers: Array, rerolled: Array, tier: int) -> void:
	if mayhem and not closing and local_champion != null:
		local_champion.augments = chosen
		local_champion.augment_offers = offers
		local_champion.augment_rerolled = rerolled
		local_champion.augment_tier = tier


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
	if aram:
		_tick_aram()
	if jungle != null:
		jungle.tick(delta)
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
	wave_timer += map.wave_interval
	wave_count += 1
	for team in 2:
		for li in map.lane_count():
			var types := _wave_types(team, li)
			var start: Vector2 = map.lane(team, li)[0]
			for k in types.size():
				schedule(k * 0.792, _spawn_minion.bind(team, li, types[k], start, floori((wave_count - 1) / 3.0)))


func _wave_types(team: int, lane: int) -> Array[String]:
	var types: Array[String] = []
	for k in map.wave_melee:
		types.append("melee")
	if aram or map.rift_waves:
		var down := 0
		var total := 0
		var lane_down := false
		for s in structures:
			if s.team == 1 - team and s.is_inhibitor:
				total += 1
				if s.dead:
					down += 1
					lane_down = lane_down or s.lane == lane
		var siege_every := (3 if time < 480.0 else 2) if aram else (3 if time < 900.0 else (2 if time < 1500.0 else 1))
		if lane_down:
			types.append("super")
			if total > 1 and down == total:
				types.append("super")
		elif wave_count % siege_every == 0:
			types.append("siege")
	for k in map.wave_ranged:
		types.append("ranged")
	return types


func _spawn_minion(team: int, li: int, type: String, pos: Vector2, upgrades: int) -> void:
	if not ended:
		spawn("minion", {"team": team, "lane": li, "type": type, "pos": pos, "upgrades": upgrades})


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
				if not aram and (c.sion == null or c.sion.form != SionKit.ZOMBIE):
					c.heal(c.stats.max_hp * 0.07, null, false)
					c.restore_mana(c.stats.max_mana * 0.07)
			elif map.lane_count() > 0:
				c.take_damage(300.0, null, "true", {"vfx": "star", "col": Game.TEAM_COLORS[t]})
				fx("beam", {"from": map.spawn_point(t), "to": c.global_position, "color": Game.TEAM_COLORS[t], "width": 18.0})


func _trickle(delta: float) -> void:
	_trickle_t += delta
	if _trickle_t >= 1.0:
		_trickle_t -= 1.0
		var g := float(map.data.get("gold_per_second", 2.04 if time >= 110.0 else 0.0))
		for c in champions.values():
			c.gold += g
			if aram:
				c.gain_xp(24.0)


func _tick_aram() -> void:
	for c: Champion in champions.values():
		if not c.dead and not c.aram_shop_locked and not c.in_base_shop_range():
			c.aram_shop_locked = true
		if mayhem:
			_offer_augment(c)
			if c.is_bot and not c.augment_offers.is_empty():
				_pick_augment(c, Game.Mayhem.bot_pick(c.augment_offers, Champion.role_of(c.def)))
	for i in relic_positions.size():
		if time < relic_ready[i]:
			continue
		var pos := relic_positions[i]
		for c: Champion in champions.values():
			if c.dead or c.global_position.distance_to(pos) > 85.0:
				continue
			if c.hp >= c.stats.max_hp and c.mana >= c.stats.max_mana:
				continue
			c.heal(c.stats.max_hp * 0.08)
			c.restore_mana(c.stats.max_mana * 0.08)
			relic_ready[i] = time + RELIC_RESPAWN
			if online:
				_rpc_relic_ready.rpc(i, relic_ready[i])
			fx("telegraph", {"pos": pos, "radius": 460.0, "dur": 2.0, "color": RELIC_COLOR, "cosmetic": true})
			schedule(2.0, _heal_relic.bind(pos))
			break


func _heal_relic(pos: Vector2) -> void:
	for c: Champion in champions.values():
		if not c.dead and c.global_position.distance_to(pos) <= 460.0:
			c.heal((c.stats.max_hp - c.hp) * 0.25)
			c.restore_mana((c.stats.max_mana - c.mana) * 0.25)
	fx("ring", {"pos": pos, "radius": 460.0, "color": RELIC_COLOR})


func _draw_relics(canvas: CanvasItem) -> void:
	for i in relic_positions.size():
		var p := relic_positions[i]
		var active := started and time >= relic_ready[i]
		var c := RELIC_COLOR if active else Color(0.35, 0.45, 0.45, 0.65)
		canvas.draw_circle(p, 32.0, Color(c, 0.25))
		canvas.draw_arc(p, 32.0, 0.0, TAU, 24, c, 3.0, true)
		if active:
			canvas.draw_line(p - Vector2(16, 0), p + Vector2(16, 0), c, 5.0, true)
			canvas.draw_line(p - Vector2(0, 16), p + Vector2(0, 16), c, 5.0, true)


@rpc("authority", "call_remote", "reliable")
func _rpc_relic_ready(index: int, ready_at: float) -> void:
	if not closing and index >= 0 and index < relic_ready.size():
		relic_ready[index] = ready_at


## Practice matches normally allow F1-F4 cheats and shopping anywhere.
func cheats_allowed() -> bool:
	return not aram and (not online or bool(map.data.get("cheats", false)))


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
	var has_inhibitors := false
	var down := false
	var nexus_turret_alive := false
	for s in structures:
		if s.team != t.team:
			continue
		if s.is_inhibitor:
			has_inhibitors = true
			down = down or s.dead
		elif s.is_nexus_turret and not s.dead:
			nexus_turret_alive = true
	if t.is_nexus_turret:
		return has_inhibitors and not down
	if t.is_nexus and has_inhibitors:
		return not down or nexus_turret_alive
	if t.is_nexus:
		var lanes_total := {}
		var lanes_alive := {}
		for s in structures:
			if s.team == t.team and not s.is_nexus and not s.is_nexus_turret:
				lanes_total[s.lane] = true
				if not s.dead:
					lanes_alive[s.lane] = true
		for l in lanes_total:
			if not lanes_alive.has(l):
				return false
		return not lanes_total.is_empty()
	for s in structures:
		if s.team == t.team and not s.is_nexus and not s.is_inhibitor and not s.is_nexus_turret and s.lane == t.lane and s.order < t.order and not s.dead:
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
		# Damaging a champion from brush gives your position away for a moment.
		if victim.team != src.team and victim.team <= 1 and fog != null and fog.enabled and fog.in_brush(src):
			src.add_status({"type": "reveal", "team": victim.team, "time": float(map.data.get("brush_reveal", BRUSH_REVEAL))},
				src, "brush_reveal")


func on_unit_died(u: Unit, killer) -> void:
	if u is Minion or u is Monster:
		for ch in champions.values():
			if ch.team != u.team and not ch.dead and ch.rune_state != null and ch.rune_state.has(8451) and ch.global_position.distance_to(u.global_position) <= 1400:
				ch.rune_state.count("growth")
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
			if jungle != null:
				jungle.transfer_buffs(u, ck)
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
		if u is Monster:
			# Monster experience goes to the killer's team nearby.
			if is_instance_valid(credit) and credit is Champion and u.xp_value > 0.0:
				_give_xp(u.global_position, 1 - credit.team, u.xp_value, credit)
			if jungle != null:
				jungle.on_monster_died(u, credit)
		elif u.xp_value > 0.0:
			_give_xp(u.global_position, u.team, u.xp_value, null, u is Minion)
	if u is Tower:
		fx("announce", {"text": "%s %s destroyed!" % [Game.TEAM_NAMES[u.team], u.display_name], "color": Game.TEAM_COLORS[1 - u.team]})
		if u.is_inhibitor:
			return
		for c in champions.values():
			if c.team != u.team:
				c.add_gold(TOWER_GOLD, u.global_position if c.global_position.distance_to(u.global_position) < 1200.0 else null)
		if not u.is_nexus:
			fx("kill", {"k": 0, "v": u.net_id, "tower": true, "t": u.team})
		if u.is_nexus:
			end_match(1 - u.team)


func _give_xp(pos: Vector2, victim_team: int, amount: float, killer, lane_minion := false) -> void:
	var near := []
	for c in champions.values():
		if c.team != victim_team and not c.dead and c.global_position.distance_to(pos) <= XP_RANGE:
			near.append(c)
	if killer != null and not near.has(killer):
		near.append(killer)
	if near.is_empty():
		return
	var total_multiplier := 1.0 + 0.2 * (near.size() - 1)
	if lane_minion:
		total_multiplier = MINION_XP_MULTIPLIER * (SHARED_MINION_XP_MULTIPLIER if near.size() > 1 else 1.0)
	var share := amount * total_multiplier / near.size()
	for c in near:
		c.gain_xp(share)


func end_match(win_team: int) -> void:
	if ended:
		return
	_finish(win_team)
	if online:
		_rpc_end.rpc(win_team, _build_snapshot())


## Host: sends camp timers and the Dragon state to the clients (HUD/minimap).
func sync_jungle() -> void:
	if online and is_server and jungle != null:
		_rpc_jungle.rpc(jungle.state())


@rpc("authority", "call_remote", "reliable")
func _rpc_jungle(s: Dictionary) -> void:
	if jungle != null and not closing:
		jungle.apply_state(s)


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


## Closest visible enemy. `neutral` = false skips jungle monsters (pets don't start camps).
func nearest_enemy(pos: Vector2, team: int, max_d: float, champs_only := false, structs := false, neutral := true) -> Unit:
	var best: Unit = null
	var bd := max_d
	for u in units:
		if u.team == team or u.dead or not u.targetable() or (u.is_structure and not structs) or (champs_only and not u.is_champion):
			continue
		if not neutral and u is Monster:
			continue
		if not can_see(u, team):
			continue
		var d: float = u.global_position.distance_to(pos) - u.radius
		if d <= bd:
			bd = d
			best = u
	return best


## Unit under/near a point. enemy=true picks enemies of `team`, otherwise allies.
func pick_unit(pos: Vector2, team: int, enemy: bool, tolerance: float, structs := true, champs_only := false) -> Unit:
	var best: Unit = null
	var bd := INF
	for u in units:
		if u.dead or not u.targetable() or (u.is_structure and not structs) or (u.team != team) != enemy or (champs_only and not u.is_champion):
			continue
		if enemy and not can_see(u, team):
			continue
		var d: float = u.global_position.distance_to(pos) - u.selection_radius()
		if d <= tolerance and d < bd:
			bd = d
			best = u
	return best


# ------------------------------------------------------- input & camera ---

func _unhandled_input(event: InputEvent) -> void:
	if hud != null and hud.modal_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					cam_zoom = clampf(cam_zoom * 1.1, 0.45, 1.8)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					cam_zoom = clampf(cam_zoom / 1.1, 0.45, 1.8)
				return
			MOUSE_BUTTON_RIGHT:
				if dematerializer_armed and mb.pressed:
					dematerializer_armed = false
					return
				rmb_held = mb.pressed
				if mb.pressed:
					if aim_slot != "":
						aim_slot = ""
						return
					amove_armed = false
					_right_click(true)
				return
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var click_world := get_canvas_transform().affine_inverse() * mb.position
					if dematerializer_armed:
						dematerializer_armed = false
						var target := pick_unit(click_world, local_team, true, 12.0, false)
						if target is Minion:
							send_command("rune", ["dematerialize", target.net_id])
						return
					if aim_slot != "":
						_cast(aim_slot, click_world)
						aim_slot = ""
					elif amove_armed or Game.prefs.move_mode == "wasd":
						if amove_armed:
							amove_armed = false
							attack_move(click_world)
						else:
							var target := pick_unit(click_world, local_team, true, 14.0, true, Input.is_action_pressed("target_champions"))
							if target != null:
								send_command("attack", [target.net_id])
							else:
								inspect_at(click_world)
					else:
						inspect_at(click_world)
				return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if k.pressed and not k.echo:
				if dematerializer_armed:
					dematerializer_armed = false
				elif aim_slot != "" or amove_armed:
					aim_slot = ""
					amove_armed = false
				elif hud.shop_open():
					hud.toggle_shop()
				else:
					hud.toggle_menu()
			return
		if k.pressed and not k.echo and k.keycode in [KEY_F1, KEY_F2, KEY_F3, KEY_F4]:
			if cheats_allowed():
				send_command("cheat", [["level", "gold", "cd", "ranks"][k.keycode - KEY_F1]])
			return
		if k.echo:
			return
	var act := Controls.action_of(event, Game.prefs.move_mode)
	if act == "" or act in Controls.MOVE_ACTIONS:
		return
	var pressed := event.is_pressed()
	var slot := ""
	if act.begins_with("ability_"):
		slot = act.substr(8)
	elif act.begins_with("item_"):
		slot = "i%d" % (int(act.substr(5)) - 1)
	elif act.begins_with("summoner_"):
		slot = "s%d" % (int(act.substr(9)) - 1)
	if slot != "":
		var wm := event as InputEventWithModifiers
		var mods: bool = wm != null and (wm.ctrl_pressed or wm.alt_pressed)
		if pressed and mods and slot in Champion.SLOTS:
			send_command("rank_up", [slot])
			return
		if slot == "q" and local_champion != null and local_champion.sion != null:
			if pressed:
				_cast(slot)
				_sion_q_held = true
				aim_slot = ""
				amove_armed = false
			elif _sion_q_held:
				_release_sion_q()
			return
		if pressed:
			var ab = aim_ability(slot)
			amove_armed = false
			if Game.prefs.cast_mode == "quick" or (ab != null and ab.targeting == "self") or channeling(slot):
				aim_slot = ""
				_cast(slot)
				return
			aim_slot = slot
		elif aim_slot == slot and Game.prefs.cast_mode == "indicator":
			_cast(slot)
			aim_slot = ""
		return
	match act:
		"scoreboard":
			hud.show_scores(pressed)
		"camera_center":
			_cam_hold = pressed
	if not pressed:
		return
	match act:
		"attack_move":
			aim_slot = ""
			if Game.prefs.amove_click:
				amove_armed = true
				rmb_held = false
			else:
				attack_move()
		"attack_move_click":
			aim_slot = ""
			amove_armed = false
			attack_move()
		"stop":
			send_command("stop")
		"recall":
			send_command("recall")
		"shop":
			hud.toggle_shop()
		"camera_lock":
			cam_locked = not cam_locked


## Attack-move at the cursor: the host attacks the enemy in range closest to the cursor (or to
## you - see Settings), otherwise walks there attacking whatever comes into range.
func attack_move(at := Vector2.INF) -> void:
	if local_champion == null or local_champion.dead or ended:
		return
	var m := at if at.is_finite() else get_global_mouse_position()
	send_command("amove", [m, str(Game.prefs.amove_target)])
	_play_fx("click", {"pos": m, "color": Color(1, 0.3, 0.3)})
	_amove_ring = 0.35


## Sends this player's autobuy setting and build (for the current character) to the host.
func send_build() -> void:
	if local_champion == null or ended:
		return
	var b = Game.prefs.builds.get(local_champion.char_id, [])
	send_command("build", [b if b is Array else []])
	send_command("autobuy", [bool(Game.prefs.autobuy)])


## True while keyboard keys should control the game (not typing in a text box or in a menu).
func keys_free() -> bool:
	var focus := get_window().has_focus() or DisplayServer.get_name() == "headless"
	return focus and not (get_viewport().gui_get_focus_owner() is LineEdit) and not hud.modal_open()


## WASD mode: sends the movement direction to the host whenever it changes.
func _steer() -> void:
	var dir := Vector2.ZERO
	if Game.prefs.move_mode == "wasd" and local_champion != null and not ended and keys_free():
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not dir.is_equal_approx(_steer_sent):
		_steer_sent = dir
		send_command("steer", [dir])


## True while your champion channels the summoner spell in `slot` ("s0"/"s1"): pressing it again
## cancels the channel. Clients only know that you are casting something; the host checks which.
func channeling(slot: String) -> bool:
	var c := local_champion
	if c == null or not slot.begins_with("s"):
		return false
	var i := int(slot.substr(1))
	if is_server:
		return c.casting != null and int(c.casting.get("summoner", -1)) == i
	var ab = c.summoner_ability(i)
	return c.flags & Unit.F_CAST != 0 and ab != null and Effects.num(ab.cast_time, {"caster": c}, 0.0) > 0.0


## The ability (or item active / summoner spell) bound to an aim slot: q/w/e/r, i0..i5 or s0/s1.
func aim_ability(slot: String):
	if local_champion == null:
		return null
	if slot.begins_with("i"):
		var it = local_champion.item_def(int(slot.substr(1)))
		return it.active if it != null else null
	if slot.begins_with("s"):
		return local_champion.summoner_ability(int(slot.substr(1)))
	return local_champion.active_ability(slot)


func _right_click(with_fx: bool) -> void:
	if local_champion == null or local_champion.dead:
		return
	var m := get_global_mouse_position()
	var t := pick_unit(m, local_team, true, 14.0, true, Input.is_action_pressed("target_champions"))
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


func _cast(slot: String, at := Vector2.INF) -> void:
	var c := local_champion
	if c == null or ended:
		return
	var ab = aim_ability(slot)
	if ab == null or (c.dead and not (not slot in Champion.SLOTS and ab.get("while_dead", false))):
		return
	var m := at if at.is_finite() else get_global_mouse_position()
	if c.sion != null and slot in Champion.SLOTS:
		if c.sion.form == SionKit.ZOMBIE or (slot == "r" and c.sion.action == SionKit.CHARGE):
			send_command("cast", [slot, m, 0])
			return
	var tid := 0
	if ab.targeting == "unit" or ab.targeting == "ally":
		var t := pick_unit(m, local_team, ab.targeting == "unit", 14.0, bool(ab.get("structures", false)), Input.is_action_pressed("target_champions"))
		if t != null:
			tid = t.net_id
	if slot.begins_with("i"):
		var i := int(slot.substr(1))
		if c.items[i] != null and c.items[i].cd <= 0.0:
			send_command("item", [i, m, tid])
			_sfx("cast", c.global_position, -14.0)
		return
	if slot.begins_with("s"):
		var si := int(slot.substr(1))
		var sp = c.summoner_def(si)
		if sp != null and (c.sum_cd[si] <= 0.0 or ab != sp.active or channeling(slot)):
			send_command("summoner", [si, m, tid])
			_sfx("cast", c.global_position, -14.0)
		elif sp != null:
			hud.notice("%s is on cooldown (%ds)" % [sp.name, ceili(c.sum_cd[si])])
		return
	if int(c.ranks.get(slot, 0)) <= 0:
		hud.notice("%s isn't learned yet - Ctrl+%s (or the + button) to level it up" % [ab.name, Controls.label("ability_" + slot)])
		return
	if c.cooldowns.get(slot, 0.0) <= 0.0 and not c.can_pay(ab):
		hud.notice("Not enough health" if ab.cost_type == "health" else "Not enough mana")
		return
	send_command("cast", [slot, m, tid])
	if c.cooldowns.get(slot, 0.0) <= 0.0:
		_sfx("cast", c.global_position, -14.0)


func _release_sion_q() -> void:
	_sion_q_held = false
	send_command("sion_release")


func _process(delta: float) -> void:
	pings.tick(delta)
	if pings.open_action != "" and (not keys_free() or hud.shop_open() or not Input.is_action_pressed(pings.open_action)):
		pings.cancel()
	if relic_art != null:
		relic_art.queue_redraw()
	camera.zoom = camera.zoom.lerp(Vector2.ONE * cam_zoom, minf(10.0 * delta, 1.0))
	_steer()
	if _sion_q_held and not Input.is_action_pressed("ability_q"):
		_release_sion_q()
	if local_champion != null and local_champion.sion != null and local_champion.sion.action == SionKit.CHARGE and not ended:
		_sion_steer_timer -= delta
		if _sion_steer_timer <= 0.0:
			_sion_steer_timer = 0.1
			send_command("sion_steer", [test_aim if test_aim != null else get_global_mouse_position()])
	else:
		_sion_steer_timer = 0.0
	_amove_ring = maxf(_amove_ring - delta, 0.0)
	var focus = entities.get(_cam_focus) if _cam_focus_t > 0.0 else null
	hud.minimap_dragging = hud.minimap_dragging and not ended and keys_free() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if hud.minimap_dragging:
		pass # The minimap owns the camera until the button is released.
	elif focus is Unit:
		# an ability (e.g. Clorinde's R) points the caster's camera at its target for a moment
		_cam_focus_t -= delta
		camera.global_position = camera.global_position.lerp(focus.global_position, minf(16.0 * delta, 1.0))
		_cam_return = 0.3
	elif (cam_locked or _cam_hold) and local_champion != null:
		_cam_return = maxf(_cam_return - delta, 0.0)
		if _cam_return > 0.0:
			camera.global_position = camera.global_position.lerp(local_champion.global_position, minf(16.0 * delta, 1.0))
		else:
			camera.global_position = local_champion.global_position
	elif not cam_locked:
		var vp := get_viewport().get_visible_rect().size
		var mp := get_viewport().get_mouse_position()
		var edge := edge_pan and bool(Game.prefs.edge_pan) and get_window().has_focus() and Rect2(Vector2.ZERO, vp).has_point(mp)
		var keys := keys_free()
		var pan := Vector2.ZERO
		if (edge and mp.x < 10) or (keys and Input.is_key_pressed(KEY_LEFT)):
			pan.x -= 1
		if (edge and mp.x > vp.x - 10) or (keys and Input.is_key_pressed(KEY_RIGHT)):
			pan.x += 1
		if (edge and mp.y < 10) or (keys and Input.is_key_pressed(KEY_UP)):
			pan.y -= 1
		if (edge and mp.y > vp.y - 10) or (keys and Input.is_key_pressed(KEY_DOWN)):
			pan.y += 1
		camera.global_position += pan * 1000.0 * clampf(float(Game.prefs.camera_speed), 0.1, 5.0) * delta / cam_zoom
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
		hover_unit = pick_unit(get_global_mouse_position(), local_team, true, 10.0, true, Input.is_action_pressed("target_champions"))
	var want_attack := hover_unit != null or amove_armed
	if want_attack != _cursor_attack:
		_cursor_attack = want_attack
		Input.set_custom_mouse_cursor(Cursors.attack() if want_attack else null, Input.CURSOR_ARROW, Vector2(15, 15) if want_attack else Vector2.ZERO)
	indicator.queue_redraw()


func inspect_at(pos: Vector2) -> Unit:
	var enemy := pick_unit(pos, local_team, true, 6.0)
	var ally := pick_unit(pos, local_team, false, 6.0)
	var u := enemy
	if ally != null and (enemy == null or ally.global_position.distance_squared_to(pos) < enemy.global_position.distance_squared_to(pos)):
		u = ally
	hud.inspected_unit = u
	return u


func _draw_indicator(n: Node2D) -> void:
	var c := local_champion
	if c == null or c.dead or ended:
		return
	var p := c.global_position
	if amove_armed or _amove_ring > 0.0:
		var a := 0.7 if amove_armed else 0.7 * _amove_ring / 0.35
		n.draw_arc(p, c.stats.attack_range + c.radius, 0, TAU, 64, Color(1, 0.35, 0.3, a), 2.0, true)
	if aim_slot == "":
		return
	var ab = aim_ability(aim_slot)
	if ab == null:
		return
	var ind: Dictionary = ab.get("indicator", {})
	var rng := Effects.num(ab.range, {"caster": c, "rank": maxi(int(c.ranks.get(aim_slot, 1)), 1)}, 700.0)
	var on_cd: bool = c.cooldowns.get(aim_slot, 0.0) > 0.0
	if aim_slot.begins_with("i"):
		on_cd = c.items[int(aim_slot.substr(1))] != null and c.items[int(aim_slot.substr(1))].cd > 0.0
	elif aim_slot.begins_with("s"):
		var spd = c.summoner_def(int(aim_slot.substr(1)))
		on_cd = spd != null and c.sum_cd[int(aim_slot.substr(1))] > 0.0 and ab == spd.active
	var col := Color(0.6, 0.6, 0.6) if on_cd else Color(0.45, 0.82, 1.0)
	var m: Vector2 = test_aim if test_aim != null else get_global_mouse_position()
	var to := m - p
	var dir := to.normalized() if to.length() > 1.0 else Vector2(c.facing, 0)
	var end := p + dir * minf(to.length(), rng)
	if ab.targeting != "self":
		n.draw_arc(p, rng, 0, TAU, 96, Color(col, 0.35), 2.0, true)
	if ab.targeting == "unit" or ab.targeting == "ally":
		var t := pick_unit(m, local_team, ab.targeting == "unit", 70.0, bool(ab.get("structures", false)))
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
			var full_len := Effects.num(ind.get("length", 350.0), {"caster": c, "target": c, "rank": maxi(int(c.ranks.get(aim_slot, 1)), 1)}, 350.0)
			var length := full_len if ind.get("full", false) else minf(to.length(), full_len)
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
