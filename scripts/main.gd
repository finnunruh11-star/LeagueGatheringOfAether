extends Node
## Screen manager (menu -> lobby -> match) plus command-line automation used
## for testing, e.g.:  -- --auto=practice --char=ember --bots_red=1 --shots=5 --quit_at=6

const MenuScreen = preload("res://scripts/ui/menu.gd")
const LobbyScreen = preload("res://scripts/ui/lobby.gd")

var screen: Node = null
var ui_layer: CanvasLayer
var _shots: Array = []
var _quit_at := -1.0
var _auto_started := false
var _clock := 0.0


func _ready() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	Game.match_started.connect(_on_match_started)
	Game.lobby_joined.connect(show_lobby)
	Game.back_to_lobby.connect(show_lobby)
	Game.left_game.connect(show_menu)
	if not _auto():
		show_menu("")


func show_menu(msg := "") -> void:
	var m := MenuScreen.new()
	m.main = self
	_set_screen(m)
	m.set_status(msg)


func show_lobby() -> void:
	var l := LobbyScreen.new()
	l.main = self
	_set_screen(l)


func _on_match_started(cfg: Dictionary) -> void:
	var w := World.new()
	w.name = "World%d" % int(cfg.id)
	_set_screen(w)
	w.start(cfg)
	if Game.cmdline.has("selftest"):
		add_child(preload("res://scripts/selftest.gd").new())
	if Game.cmdline.has("itemtest"):
		add_child(preload("res://scripts/itemtest.gd").new())
	if Game.cmdline.has("inputtest"):
		add_child(preload("res://scripts/inputtest.gd").new())
	if Game.cmdline.has("aitest"):
		add_child(preload("res://scripts/aitest.gd").new())


func _set_screen(n: Node) -> void:
	if screen != null and is_instance_valid(screen):
		if screen is World:
			# Keep the old match around (disabled) for a moment so network
			# messages still in flight find their node instead of erroring.
			screen.shutdown()
			get_tree().create_timer(3.0).timeout.connect(screen.queue_free)
		else:
			screen.get_parent().remove_child(screen)
			screen.queue_free()
	screen = n
	if n is Control:
		ui_layer.add_child(n)
	else:
		add_child(n)


# -------------------------------------------------------- test automation ---

func _auto() -> bool:
	var a := Game.cmdline
	if a.has("name"):
		Game.player_name = a.name
	for s in str(a.get("shots", "")).split(",", false):
		_shots.append(float(s))
	_quit_at = float(a.get("quit_at", "-1"))
	if a.has("speed"):
		Engine.time_scale = float(a.speed)
		Engine.max_physics_steps_per_frame = 16
	match str(a.get("auto", "")):
		"practice":
			Game.start_practice()
			_setup_lobby(a)
			Game.start_match()
		"host":
			Game.host(int(a.get("port", "7777")))
			_setup_lobby(a)
			show_lobby()
		"join":
			Game.join(str(a.get("ip", "127.0.0.1")), int(a.get("port", "7777")))
			show_menu("Joining...")
		_:
			return false
	return true


func _setup_lobby(a: Dictionary) -> void:
	if a.has("map"):
		Game.settings.map = a.map
	if a.has("fog"):
		Game.settings.fog = str(a.fog) != "0"
	if a.has("char"):
		Game.players[1].character = a.char
	if a.has("team"):
		Game.players[1].team = int(a.team)
	for i in int(a.get("bots_blue", "0")):
		Game.add_bot(0, str(a.get("blue_difficulty", a.get("bot_difficulty", ""))))
	for i in int(a.get("bots_red", "0")):
		Game.add_bot(1, str(a.get("red_difficulty", a.get("bot_difficulty", ""))))
	if a.has("bot_char"):
		for pid in Game.players:
			if Game.players[pid].bot:
				Game.players[pid].character = a.bot_char
	for key in ["blue_char", "red_char"]:
		if a.has(key):
			# One id for every bot of the team, or a comma list assigned in order.
			var ids := str(a[key]).split(",", false)
			var k := 0
			var pids := Game.players.keys()
			pids.sort()
			pids.reverse()
			for pid in pids:
				if Game.players[pid].bot and int(Game.players[pid].team) == (0 if key == "blue_char" else 1) and not ids.is_empty():
					var cid: String = ids[mini(k, ids.size() - 1)]
					Game.players[pid].character = cid
					Game.players[pid].summoners = Game.default_summoners(cid)
					k += 1


func _process(delta: float) -> void:
	_clock += delta
	var a := Game.cmdline
	if str(a.get("auto", "")) == "host" and not _auto_started and Game.players.size() >= int(a.get("wait", "2")):
		_auto_started = true
		get_tree().create_timer(1.0).timeout.connect(Game.start_match)
	if a.has("char") and str(a.get("auto", "")) == "join" and Game.players.has(multiplayer.get_unique_id()) \
			and Game.characters.has(a.char) and Game.players[multiplayer.get_unique_id()].character != a.char:
		Game.request_change("character", a.char)
	if a.has("autopilot") and Game.world != null and Game.world.local_champion != null and not Game.world.local_champion.get_meta("auto", false):
		Game.world.local_champion.set_meta("auto", true)
		Game.world.send_command("autopilot", [true] if str(a.autopilot) == "true" else [true, str(a.autopilot)])
	if a.has("cam") and Game.world != null and Game.world.camera != null:
		var xy := str(a.cam).split(",")
		if xy.size() == 2:
			Game.world.cam_locked = false
			Game.world.edge_pan = false
			Game.world.camera.global_position = Vector2(float(xy[0]), float(xy[1]))
		if a.has("zoom"):
			Game.world.cam_zoom = float(a.zoom)
	if not _shots.is_empty() and _clock >= _shots[0]:
		var t: float = _shots.pop_front()
		_screenshot("%s_%s.png" % [str(a.get("shot", "user://shot")), String.num(t, 1)])
	_at("end_at", func(): if Game.world != null: Game.world.end_match(0))
	_at("relobby_at", Game.return_to_lobby)
	_at("restart_at", Game.start_match)
	_at("leave_at", func(): Game.leave(); Game.left_game.emit("left (test)"))
	_at("settings_at", func():
		if Game.world != null:
			Game.world.hud.open_settings()
		elif screen != null:
			screen.add_child(SettingsMenu.new()))
	if a.has("fpslog") and Game.world != null and int(_clock) % 10 == 0 and int(_clock) != _last_fps_log:
		_last_fps_log = int(_clock)
		print("[fps] t=%d fps=%d entities=%d fx_nodes=%d" % [_last_fps_log, Engine.get_frames_per_second(), Game.world.entities.size(), Game.world.fx_layer.get_child_count()])
	if _quit_at > 0.0 and _clock >= _quit_at:
		_quit_at = -1.0
		_report()
		get_tree().quit()


var _done := {}
var _last_fps_log := -1


func _at(key: String, f: Callable) -> void:
	if Game.cmdline.has(key) and not _done.has(key) and _clock >= float(Game.cmdline[key]):
		_done[key] = true
		print("[auto] ", key)
		f.call()


func _screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[auto] screenshot saved: ", path)


func _report() -> void:
	var w = Game.world
	if w == null:
		print("[auto] no match running. players=", Game.players.size(), " chars=", Game.characters.size())
		return
	print("[auto] time=%.1f fps=%d entities=%d units=%d kills=%s ended=%s server=%s" % [w.time, Engine.get_frames_per_second(), w.entities.size(), w.units.size(), str(w.kills), str(w.ended), str(w.is_server)])
	var standing := [0, 0]
	for s in w.structures:
		if not s.dead and s.team <= 1:
			standing[s.team] += 1
	print("[auto]   winner=%d structures standing blue/red=%d/%d" % [w.winner, standing[0], standing[1]])
	if w.jungle != null:
		var up := 0
		for i in w.jungle.camps.size():
			if w.jungle.respawn_in(i) <= 0.0 and float(w.jungle.camps[i].next) < 0.0:
				up += 1
		print("[auto]   jungle: camps up=%d/%d drakes blue=%s red=%s soul=%s next=%s" % [up, w.jungle.camps.size(),
			str(w.jungle.drakes[0]), str(w.jungle.drakes[1]), str(w.jungle.soul), w.jungle.next_drake])
	for c in w.champions.values():
		var who: String = ("bot:" + c.bot_difficulty) if c.is_bot else "player"
		print("[auto]   %s %s %s team=%d lvl=%d hp=%d/%d pos=%s k/d/a=%d/%d/%d cs=%d dead=%s" % [c.player_name, c.char_id, who, c.team, c.level,
			c.hp, c.stats.max_hp, str(c.global_position.round()), c.kills, c.deaths, c.assists, c.cs, str(c.dead)])
		var inv := []
		for inst in c.items:
			if inst != null:
				inv.append(inst.id)
		print("[auto]     gold=%d ranks=%s items=%s" % [c.gold, str(c.ranks), str(inv)])
		print("[auto]     summoners=%s cds=%s build=%s autobuy=%s" % [str(c.summoners), str(c.sum_cd.map(func(x): return snappedf(x, 0.1))), str(c.build), str(c.autobuy)])
	var counts := {}
	for e in w.entities.values():
		counts[e.get_class() + ":" + str(e.get("kind"))] = counts.get(e.get_class() + ":" + str(e.get("kind")), 0) + 1
	print("[auto]   entity kinds: ", counts)
