extends Node
## Bot AI test harness. Examples:
##   godot --headless --path . -- --auto=practice --map=arena --aitest=dodge --difficulty=scripting [--char=sir_bonk]
##       [--shooter=gizmo] [--slot=q] [--shots=12]
##     A shooter fires a skillshot at the bot whenever it is ready (perfectly led); prints how many hit.
##   godot --headless --path . -- --auto=practice --map=two_lanes --bots_blue=3 --bots_red=3 --aitest=watch [--every=30]
##     Prints each bot's mode, stats and the AI's time per frame every `every` seconds; flags
##     units with broken (non-finite) positions.

var world: World
var _t := 0.0
var _every := 30.0
var _usec := 0
var _frames := 0
var _bad := {}


func _ready() -> void:
	await get_tree().create_timer(0.4).timeout
	world = Game.world
	if world == null:
		print("[aitest] no world")
		get_tree().quit(1)
		return
	match str(Game.cmdline.get("aitest", "watch")):
		"dodge":
			_dodge_test()
		_:
			_every = float(Game.cmdline.get("every", "30"))


func _physics_process(_delta: float) -> void:
	if world == null or not world.started or str(Game.cmdline.get("aitest", "watch")) != "watch":
		return
	var t0 := Time.get_ticks_usec()
	_frames += 1
	for u in world.units:
		if not u.global_position.is_finite() and not _bad.has(u.net_id):
			_bad[u.net_id] = true
			print("[aitest] NON-FINITE position: %s (%s) vel=%s forced=%s" % [u.display_name, u.kind, str(u.velocity), str(u.forced)])
	_usec += Time.get_ticks_usec() - t0
	if world.time - _t >= _every:
		_t = world.time
		_report()


func _report() -> void:
	print("[aitest] t=%.0f kills=%s ai=%.2f ms/frame (all bots) checks=%.2f ms/frame" % [world.time, str(world.kills),
		BotBrain.cost_usec / 1000.0 / maxf(_frames, 1), _usec / 1000.0 / maxf(_frames, 1)])
	BotBrain.cost_usec = 0
	_usec = 0
	_frames = 0
	for c in world.champions.values():
		var b: BotBrain = c.brain
		print("[aitest]   %-8s %-10s %-9s lvl=%2d k/d/a=%d/%d/%d cs=%3d gold=%5d hp=%4d/%4d mode=%s items=%s" % [c.player_name, c.char_id,
			c.bot_difficulty if c.is_bot else "player", c.level, c.kills, c.deaths, c.assists, c.cs, c.gold, c.hp, c.stats.max_hp,
			b.mode if b != null else "-", str(c.items.filter(func(x): return x != null).map(func(x): return x.id))])


## The shooter fires `slot` at the bot each time it is ready, with a perfect lead. Counts hits.
func _dodge_test() -> void:
	for e in world.entities.values():
		if e is Dummy:
			world.despawn(e)
	var level := str(Game.cmdline.get("difficulty", "scripting"))
	var bot: Champion = world.spawn("champion", {"peer": 900, "team": 0, "character": str(Game.cmdline.get("char", "sir_bonk")),
		"name": "Bot", "pos": Vector2(700, 750), "bot": true, "difficulty": level})
	var shooter: Champion = world.spawn("champion", {"peer": 901, "team": 1, "character": str(Game.cmdline.get("shooter", "gizmo")),
		"name": "Shooter", "pos": Vector2(1500, 750)})
	for c in [bot, shooter]:
		for k in 8:
			c.cheat("level")
		c.max_ranks()
	world.local_champion.teleport(Vector2(200, 200))
	# The bot can't attack the shooter (it keeps moving around it instead), so it only has to dodge.
	shooter.add_status({"type": "untargetable", "time": 1.0e9}, shooter)
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func():
		print("[aitest] TIMEOUT")
		get_tree().quit(1))
	var slot := str(Game.cmdline.get("slot", "q"))
	var shots := int(Game.cmdline.get("shots", "12"))
	var hits := 0
	var fired := 0
	var pr: Dictionary = BotKit.char_kit(shooter.def).get(slot, {})
	var speed := maxf(float(pr.get("speed", 1500.0)), 50.0)
	while fired < shots:
		await get_tree().physics_frame
		bot.hp = bot.stats.max_hp
		shooter.hp = shooter.stats.max_hp
		shooter.mana = shooter.stats.max_mana
		shooter.cooldowns[slot] = 0.0
		var d := shooter.global_position.distance_to(bot.global_position)
		if d > 900.0 or d < 150.0:
			shooter.move_goal = bot.global_position + (shooter.global_position - bot.global_position).normalized() * 650.0
			continue
		shooter.move_goal = null
		var lead: Vector2 = bot.global_position + bot.velocity * d / speed
		var before := bot.hp
		if not shooter.cast(slot, lead, bot.net_id):
			continue
		fired += 1
		var hit := false
		for f in int(1.6 * 60):
			await get_tree().physics_frame
			shooter.hp = shooter.stats.max_hp
			if bot.hp < before - 1.0:
				hit = true
		if hit:
			hits += 1
		await get_tree().create_timer(0.5).timeout
	print("[aitest] dodge %s (%s vs %s %s): %d/%d hit" % [level, bot.char_id, shooter.char_id, slot.to_upper(), hits, fired])
	get_tree().quit()
