extends Node
## Input test: feeds fake key/mouse events through Godot's input pipeline and checks that the
## rebindable controls reach the game (rebinding in Settings, WASD steering, attack-move, summoner
## keys). Run with:
##   godot --headless --path . -- --auto=practice --map=arena --inputtest

var world: World
var fails := 0


func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func():
		print("[inputtest] TIMEOUT")
		get_tree().quit(1))
	await get_tree().create_timer(0.5).timeout
	world = Game.world
	var c := world.local_champion
	_check("default Q label", Controls.label("ability_q") == "Q")
	_check("default summoner keys", Controls.label("summoner_1") == "D" and Controls.label("summoner_2") == "F")

	# Rebind Q to Z in the settings menu, like a player would.
	world.hud.open_settings()
	await _frames(2)
	var menu: SettingsMenu = world.hud.settings_menu
	_check("settings blocks game input", world.hud.modal_open())
	menu._start_capture("ability_q")
	_key(KEY_Z, true)
	_key(KEY_Z, false)
	await _frames(2)
	_check("Q rebound to Z", Controls.label("ability_q") == "Z")
	menu._start_capture("ability_w")
	_key(KEY_Z, true)
	_key(KEY_Z, false)
	await _frames(2)
	_check("Z moved to W, Q unbound", Controls.label("ability_w") == "Z" and Controls.code_of("ability_q") == "")
	menu._reset_keys()
	_check("reset keys", Controls.label("ability_q") == "Q" and Controls.label("ability_w") == "W")

	# Switch to WASD in the menu: the preset moves abilities and summoners.
	menu._on_move_mode("wasd")
	Game.prefs.move_mode = "wasd"
	_check("WASD preset", Controls.label("ability_w") == "E" and Controls.label("summoner_1") == "Space" and Controls.label("move_up") == "W")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check("Esc closes settings", not world.hud.modal_open())

	# Hold D: the champion walks right.
	var start := c.global_position
	_key(KEY_D, true)
	await get_tree().create_timer(0.6).timeout
	_key(KEY_D, false)
	await get_tree().create_timer(0.2).timeout
	var moved := c.global_position - start
	print("[inputtest] WASD: held D for 0.6s, moved %s (move speed %d)" % [str(moved.round()), c.stats.move_speed])
	_check("D walks right", moved.x > c.stats.move_speed * 0.4 and absf(moved.y) < 20.0)
	var still := c.global_position
	await get_tree().create_timer(0.3).timeout
	_check("releasing stops", c.global_position.distance_to(still) < 2.0)

	# Summoner key (Space in the WASD layout) casts Flash toward the mouse.
	if c.summoners.has("flash"):
		var i := c.summoners.find("flash")
		var code := Controls.code_of("summoner_%d" % (i + 1))
		var key := int(code.substr(4)) as Key
		_key(key, true)
		_key(key, false)
		await get_tree().create_timer(0.2).timeout
		_check("summoner key used Flash", c.sum_cd[i] > 0.0)

	# Back to classic: A attack-moves at the cursor right away.
	Game.prefs.move_mode = "click"
	var d := Controls.defaults("click")
	for k in d:
		Controls.bind(k, d[k])
	var foe: Unit = world.spawn("dummy", {"pos": c.global_position + Vector2(120, 0), "hp": 100000.0})
	foe.team = 1
	await _frames(2)
	_key(KEY_A, true)
	_key(KEY_A, false)
	await get_tree().create_timer(0.2).timeout
	_check("A attack-moves (target picked)", c.attack_target == foe)
	print("[inputtest] done, %d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(what: String, ok: bool) -> void:
	print("[inputtest] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1
