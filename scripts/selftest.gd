extends Node
## Self-test: for every character, cast each ability at a training dummy and
## report damage dealt and what got spawned. Run with:
##   godot --path . -- --auto=practice --map=arena --selftest [--only=ember] [--speed=4]

const WAIT := 2.6

var world: World


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	world = Game.world
	if world == null:
		print("[selftest] no world")
		get_tree().quit(1)
		return
	if Game.cmdline.get("selftest") == "balance":
		_test_balance()
		return
	if Game.cmdline.get("selftest") == "windup":
		_test_windup()
		return
	if Game.cmdline.get("selftest") == "runes":
		_test_runes()
		return
	if Game.cmdline.get("selftest") == "abilitytips":
		await _test_ability_tips()
		return
	if Game.cmdline.get("selftest") == "matchfixes":
		await _test_match_fixes()
		return
	if Game.cmdline.get("selftest") == "league_units":
		await _test_league_units()
		return
	if Game.cmdline.get("selftest") == "zeri":
		await _test_zeri()
		return
	if Game.cmdline.get("selftest") == "rift":
		_test_rift()
		return
	if Game.cmdline.get("selftest") == "classic_items":
		await _test_classic_items()
		return
	if Game.cmdline.get("selftest") == "colorblind":
		await _test_colorblind()
		return
	for e in world.entities.values():
		if e is Dummy:
			world.despawn(e)
	var center := world.map.size * 0.5
	var dummy_pos := center + Vector2(100, 0)
	var cast_pos := center - Vector2(350, 0)
	var dummy: Dummy = world.spawn("dummy", {"pos": dummy_pos, "hp": 1000000.0})
	var ally: Dummy = world.spawn("dummy", {"pos": center - Vector2(400, 150), "hp": 1000000.0})
	ally.team = 0
	world.cam_locked = false
	world.edge_pan = false
	world.camera.global_position = center - Vector2(125, 50)
	var only := str(Game.cmdline.get("only", ""))
	var ids := Game.sorted_character_ids()
	print("[selftest] testing %d characters" % ids.size())
	for e in Game.content_errors:
		print("[selftest] CONTENT ERROR: ", e)
	var pid := 1000
	for id in ids:
		if only != "" and id != only:
			continue
		pid += 1
		var c: Champion = world.spawn("champion", {"peer": pid, "team": 0, "character": id, "name": "Test", "pos": cast_pos})
		c.max_ranks()
		var real_local := world.local_champion
		world.local_champion = c
		await get_tree().create_timer(0.3).timeout
		var before := dummy.total_taken
		c.attack_target = dummy
		await get_tree().create_timer(2.5).timeout
		c.attack_target = null
		print("[selftest] %-12s attack   dmg=%6.0f" % [id, dummy.total_taken - before])
		for slot in ["q", "w", "e", "r"]:
			var ab = c.def.abilities.get(slot)
			if ab == null:
				print("[selftest] %-12s %s        (none)" % [id, slot])
				continue
			var start := cast_pos
			if ab.targeting == "self":
				start = dummy.global_position - Vector2(150, 0)
			c.teleport(start)
			c.dead = false
			c.hp = c.stats.max_hp
			c.mana = c.stats.max_mana
			c.cooldowns[slot] = 0.0
			c.statuses.clear()
			before = dummy.total_taken
			var n_before := world.entities.size()
			var target := dummy
			if ab.targeting == "ally":
				target = ally
			world.aim_slot = slot
			world.test_aim = target.global_position
			await get_tree().create_timer(0.35).timeout
			world.aim_slot = ""
			world.test_aim = null
			var ok := c.cast(slot, target.global_position, target.net_id)
			await get_tree().create_timer(0.4).timeout
			var spawned := world.entities.size() - n_before
			await get_tree().create_timer(WAIT - 0.4).timeout
			var moved := c.global_position.distance_to(start)
			print("[selftest] %-12s %s %-18s cast=%s dmg=%6.0f spawned=%d moved=%4.0f shield=%3.0f hp=%4.0f/%4.0f dummy_flags=%d" % [
				id, slot, ab.name.substr(0, 18), str(ok), dummy.total_taken - before, spawned, moved, c.shield, c.hp, c.stats.max_hp, dummy.flags])
		world.local_champion = real_local
		world.despawn(c)
		world.champions.erase(pid)
		for e in world.entities.values():
			if e is Summon or e is Zone or e is Projectile:
				world.despawn(e)
		dummy.teleport(dummy_pos)
		dummy.statuses.clear()
	print("[selftest] done")
	get_tree().quit()


func _test_colorblind() -> void:
	world.hud.open_settings()
	var toggle: CheckButton = world.hud.settings_menu._controls.colorblind_mode
	var player := world.local_champion
	var ally := Unit.new()
	var enemy := Unit.new()
	var neutral := Unit.new()
	# Check the palette from the red side, not just the default blue spawn.
	var old_team := world.local_team
	world.local_team = 1
	ally.team = 1
	enemy.team = 0
	neutral.team = 2
	var units: Array[Unit] = [player, ally, enemy, neutral]
	toggle.button_pressed = false
	var baseline: Array[Color] = []
	for unit in units:
		unit.world = world
		baseline.append(unit.bar_color())
	toggle.button_pressed = true
	var track := Unit.COLORBLIND_HP_TRACK.srgb_to_linear().get_luminance()
	var colors := {}
	var ok := true
	for i in units.size():
		var fill := units[i].bar_color()
		colors[fill] = true
		var contrast := (fill.srgb_to_linear().get_luminance() + 0.05) / (track + 0.05)
		ok = ok and fill != baseline[i] and contrast >= 3.0 and fill == units[i].ring_color()
	ok = ok and colors.size() == units.size()
	ok = ok and ally.bar_color().b > ally.bar_color().r and enemy.bar_color().r > enemy.bar_color().b
	world.local_team = old_team
	await get_tree().process_frame
	toggle.button_pressed = false
	world.local_team = 1
	for i in units.size():
		ok = ok and units[i].bar_color() == baseline[i]
	world.local_team = old_team
	ally.free()
	enemy.free()
	neutral.free()
	if not ok:
		push_error("[colorblind] expected distinct, high-contrast HP colors from the red side and the original palette after disabling")
	print("[colorblind] ", "passed" if ok else "failed")
	get_tree().quit(0 if ok else 1)


func _test_runes() -> void:
	var ok := true
	var player := world.local_champion
	var page := Runes.preset()
	page.major = [8008, 9102, 9107, 8014]
	ok = _check(Runes.valid(page), "historical keystone and legacy minors can coexist") and ok
	var invalid := page.duplicate(true)
	invalid.minor = [8444, 8473]
	ok = _check(not Runes.valid(invalid), "secondary picks from the same row are rejected") and ok
	invalid = page.duplicate(true)
	invalid.shards[0] = 5011
	ok = _check(not Runes.valid(invalid), "out-of-row stat shards are rejected") and ok

	var center := world.map.size * 0.5
	var foe: Champion = world.spawn("champion", {"peer": -98, "team": 1, "character": player.char_id,
		"pos": center + Vector2(90, 0)})
	player.teleport(center)
	player.rune_state = RuneState.new(player, page)
	player.recompute_stats()
	ok = _check(is_equal_approx(player.stats.max_hp, player.base_stats.max_hp + 65.0), "flat health shard is applied") and ok
	var speed: float = player.stats.bonus_attack_speed
	var reach: float = player.stats.attack_range
	var previous_hp: float = foe.hp
	for i in 6:
		foe.take_damage(5.0, player, "true", {"attack": true})
	player.recompute_stats()
	var range_bonus := 75.0 if player.attack_def.ranged else 50.0
	ok = _check(float(player.stats.bonus_attack_speed) > speed and is_equal_approx(player.stats.attack_range, reach + range_bonus) and is_equal_approx(previous_hp - foe.hp, 30.0), "12.19 Lethal Tempo grants range instead of bonus damage at six stacks") and ok
	player.hp = player.stats.max_hp
	player.heal(100.0, player)
	ok = _check(not player.find_status("overheal").is_empty(), "excess healing creates the legacy Overheal shield") and ok

	page = Runes.preset()
	player.rune_state = RuneState.new(player, page)
	for i in 3:
		foe.take_damage(5.0, player, "true", {"attack": true})
	var ally: Champion = world.spawn("champion", {"peer": -97, "team": 0, "character": player.char_id,
		"pos": center - Vector2(90, 0)})
	var allied_hit := foe.take_damage(50.0, ally, "true")
	ok = _check(is_equal_approx(allied_hit, 56.0), "7.23 Press the Attack increases allied damage to the exposed target by 12%") and ok
	foe.remove_status_id("press_the_attack")

	page = {"primary": "Domination", "secondary": "Sorcery", "major": [8112, 8126, 8136, 8132],
		"minor": [8225, 8237], "shards": [5007, 5008, 5011]}
	ok = _check(Runes.valid(page), "restored ward, hunter, and orb runes can be picked together") and ok
	player.rune_state = RuneState.new(player, page)
	var enemy_ward: Summon = world.spawn("summon", {"pos": center, "team": 1, "ward": true, "name": "Test Ward", "stats": {"max_hp": 1}})
	enemy_ward.take_damage(1.0, player, "physical", {"attack": true})
	ok = _check(world.units.any(func(u): return u is Summon and u.team == player.team and u.display_name == "Zombie Ward" and is_equal_approx(u.lifetime, 120.0)), "9.7 Zombie Ward replaces a destroyed enemy ward for 120 seconds") and ok
	player.remove_status_id("overheal")
	player.hp = player.stats.max_hp * 0.31
	player.take_damage(20.0, foe, "true")
	ok = _check(not player.rune_state.timers.has(8225), "12.9 Nullifying Orb does not activate on true damage") and ok
	player.take_damage(20.0, foe, "magic")
	ok = _check(player.rune_state.timers.has(8225) and player.statuses.any(func(s): return s.key == "rune:orb" and s.dtype == "magic"), "12.9 Nullifying Orb grants a magic-only shield") and ok

	page = Runes.preset("mage")
	page.major[0] = 8231
	player.rune_state = RuneState.new(player, page)
	for slot in ["q", "w", "e"]:
		foe.take_damage(1.0, player, "true", {"ability": slot})
	ok = _check(player.rune_state.timers.has(8231), "Phase Rush procs on three distinct hits even without burst damage") and ok
	page.major[0] = 8230
	player.rune_state = RuneState.new(player, page)
	foe.hp = foe.stats.max_hp
	foe.take_damage(foe.stats.max_hp * 0.26, player, "true", {"ability": "q"})
	ok = _check(player.rune_state.timers.has(8230), "Stormraider's Surge procs on burst even with one hit") and ok

	page = {"primary": "Inspiration", "secondary": "Precision", "major": [8360, 8306, 8317, 8347],
		"minor": [9102, 9107], "shards": [5007, 5008, 5011]}
	player.rune_page = page
	player.rune_state = RuneState.new(player, page)
	var editor := RunePageEditor.new()
	add_child(editor)
	editor.open("Rune test", page, func(_chosen): pass)
	ok = _check(editor.fields.get_child_count() == 11, "rune editor offers both paths, six picks and three shards") and ok
	editor.queue_free()
	world.time = 361.0
	player.summoners = ["flash", "ignite"]
	player.sum_cd = [15.0, 60.0]
	player.rune_state.action("spellbook", [1, "heal"])
	ok = _check(player.summoners[1] == "heal" and player.sum_cd[1] == 0.0, "Spellbook equips a ready replacement") and ok
	ok = _check(player.use_summoner(1, player.global_position, player.net_id) and player.summoners[1] == "ignite" and is_equal_approx(player.sum_cd[1], 60.0), "casting the replacement restores the original spell and cooldown") and ok
	player._tick_summoners(0.0)
	ok = _check(player.use_summoner(0, center + Vector2(250, 0), 0) and player.casting != null and player.casting.ctx.hexflash and is_equal_approx(player.sum_cd[0], 15.0), "Hexflash channels without resetting the original Flash cooldown") and ok
	player.command("move", [center])
	ok = _check(player.casting == null, "moving cancels the Hexflash channel") and ok
	print("[runes] ", "passed" if ok else "failed")
	get_tree().quit(0 if ok else 1)


func _test_zeri() -> void:
	var c := world.local_champion
	if c == null or c.char_id != "zeri" or world.map.data.get("name") != "Training Arena":
		push_error("[zeri] requires --char=zeri --map=arena")
		get_tree().quit(1)
		return
	for u in world.units.duplicate():
		if u is Dummy:
			world.despawn(u)
	var at := Vector2(700, 900)
	c.teleport(at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var primary: Dummy = world.spawn("dummy", {"pos": at + Vector2(300, 0), "hp": 1000})
	var secondary: Dummy = world.spawn("dummy", {"pos": at + Vector2(550, 0), "hp": 1000})
	var checks := {"starts with Q learned and a full battery": c.ranks.q == 1 and c.skill_points == 0 and c.zeri_charge == 100.0}
	c.perform_attack(primary, 0.0)
	checks["charged zap does 85 magic damage and consumes charge"] = is_equal_approx(primary.total_taken, 85.0) and c.zeri_charge == 0.0
	var before := primary.total_taken
	var cast_ok := c.cast("q", primary.global_position, 0)
	await get_tree().create_timer(0.7).timeout
	checks["normal burst deals 79.12 physical damage, charges battery, and stops at first target"] = (
		cast_ok and is_equal_approx(primary.total_taken - before, 79.12) and secondary.total_taken == 0.0
		and is_equal_approx(c.zeri_charge, 10.0))
	c.ranks.e = 1
	c.attack_cd = 1.0
	checks["Spark Surge resets zap and Q timers"] = c.cast("e", at + Vector2(900, 0), 0) and c.cooldowns.q == 0.0 and c.attack_cd == 0.0
	await get_tree().create_timer(0.55).timeout
	checks["ground dash travels exactly 300 units"] = is_equal_approx(c.global_position.distance_to(at), 300.0)
	c.teleport(at)
	before = primary.total_taken
	cast_ok = c.cast("q", primary.global_position, 0)
	await get_tree().create_timer(0.7).timeout
	checks["Spark Surge adds 22 magic damage up front and pierces for 80% behind"] = (
		cast_ok and is_equal_approx(primary.total_taken - before, 101.12) and is_equal_approx(secondary.total_taken, 63.296))
	c.teleport(Vector2(724, 380))
	c.cooldowns.e = 0.0
	c.mana = c.stats.max_mana
	cast_ok = c.cast("e", Vector2(1200, 380), 0)
	await get_tree().create_timer(0.55).timeout
	checks["wall dash clears the far edge and lands on open ground"] = (
		cast_ok and c.global_position.x >= 952.0 and not world.map.is_wall(c.global_position))
	c.teleport(Vector2(550, 380))
	primary.home = Vector2(1070, 380)
	primary.teleport(primary.home)
	c.mana = c.stats.max_mana
	c.ranks.w = 1
	before = primary.total_taken
	cast_ok = c.cast("w", primary.global_position, 0)
	await get_tree().create_timer(0.95).timeout
	var waited := primary.total_taken == before
	await get_tree().create_timer(0.95).timeout
	checks["W hitting terrain fires the delayed laser, not the ordinary pulse"] = (
		cast_ok and waited and is_equal_approx(primary.total_taken - before, 86.0))
	world.despawn(secondary)
	var foe: Champion = world.spawn("champion", {"peer": 1001, "team": 1, "character": "zeri", "name": "Target",
		"pos": Vector2(1350, 900)})
	c.teleport(Vector2(1000, 900))
	c.ranks.r = 1
	c.mana = c.stats.max_mana
	cast_ok = c.cast("r", c.global_position, 0)
	await get_tree().create_timer(0.4).timeout
	checks["R on a champion starts Overcharge and adds 30% bonus attack speed"] = (
		cast_ok and not c.find_status(ZeriKit.OVERCHARGE).is_empty() and is_equal_approx(c.stats.attack_speed, 0.8455))
	var chain_target: Dummy = world.spawn("dummy", {"pos": Vector2(1360, 1120), "hp": 1000})
	c.remove_status_id(ZeriKit.LIGHTNING_ROUNDS)
	c.cooldowns.q = 0.0
	var old_e_cd: float = c.cooldowns.e
	var old_r_time: float = c.find_status(ZeriKit.OVERCHARGE).get("time", 0.0)
	cast_ok = c.cast("q", foe.global_position, 0)
	await get_tree().create_timer(0.55).timeout
	checks["overcharged burst chains for 40% AD, adds a stack and refreshes the buff"] = (
		cast_ok and is_equal_approx(chain_target.total_taken, 22.4)
		and c.find_status(ZeriKit.HYPERCHARGE).get("stacks", 0) == 1
		and float(c.find_status(ZeriKit.OVERCHARGE).get("time", 0.0)) > old_r_time - 0.3
		and c.cooldowns.e < old_e_cd - 0.8)
	world.despawn(foe)
	c.remove_status_id(ZeriKit.OVERCHARGE)
	for i in 17:
		c._level_up()
	checks["level 18 uses League growth, with no free AP"] = (
		is_equal_approx(c.stats.max_hp, 2470.0) and is_equal_approx(c.stats.max_mana, 1015.0)
		and is_equal_approx(c.stats.attack_damage, 90.0) and is_equal_approx(c.stats.magic_resist, 51.7)
		and is_equal_approx(c.stats.attack_speed, 0.8705) and c.stats.ability_power == 0.0)
	c.base_stats.bonus_attack_speed = 2.0
	c.base_stats.ability_haste = 100.0
	c.recompute_stats()
	checks["excess attack speed becomes AD, and haste cannot shorten Q"] = (
		is_equal_approx(c.stats.attack_speed, 1.5) and is_equal_approx(c.stats.attack_damage, 129.168)
		and is_equal_approx(c.ability_cooldown(c.def.abilities.q), 2.0 / 3.0))
	var passed := true
	for label in checks:
		if checks[label]:
			print("[zeri] OK: ", label)
		else:
			push_error("[zeri] " + label)
			passed = false
	get_tree().quit(0 if passed else 1)


func _test_league_units() -> void:
	var c := world.local_champion
	if c == null or c.char_id != "prism_gauge" or world.map.size.x < 7000.0:
		push_error("[league_units] requires --char=prism_gauge --map=bridge")
		get_tree().quit(1)
		return
	var at := world.map.size * 0.5
	c.teleport(at)
	c.move_goal = at + Vector2(500, 0)
	await get_tree().physics_frame
	var start := c.global_position
	for i in Engine.physics_ticks_per_second:
		await get_tree().physics_frame
	c.move_goal = null
	var walked := c.global_position.distance_to(start)
	var checks := {
		"walked %.2f units in one second (expected 330)" % walked: absf(walked - 330.0) < 0.1,
		"combat radius 65 and terrain/separation radius 35": is_equal_approx(c.radius, 65.0)
			and is_equal_approx(c.pathing_radius(), 35.0) and is_equal_approx((c.collider.shape as CircleShape2D).radius, 35.0),
	}
	c.teleport(at)
	checks["selection picks at 100 units but not at 101"] = (
		world.pick_unit(at + Vector2(100, 0), c.team, false, 0.0) == c
		and world.pick_unit(at + Vector2(101, 0), c.team, false, 0.0) != c)
	var authored_speed: float = c.base_stats.move_speed
	for speeds in [[0.0, 0.0], [200.0, 210.0], [220.0, 220.0], [415.0, 415.0], [450.0, 443.0], [490.0, 475.0], [520.0, 490.0]]:
		c.base_stats.move_speed = speeds[0]
		c.recompute_stats()
		checks["raw speed %.0f becomes %.0f units/s" % speeds] = is_equal_approx(c.stats.move_speed, speeds[1])
	c.base_stats.move_speed = authored_speed
	c.recompute_stats()
	c.max_ranks()
	var dummy: Dummy = world.spawn("dummy", {"pos": at + Vector2(900, 0), "hp": 10000.0})
	checks["basic attack reach is 550 between gameplay edges"] = is_equal_approx(c.attack_reach(dummy) - c.radius - dummy.radius, 550.0)
	for probe in [["q", 1175.0, 70.0, 1200.0], ["w", 1150.0, 110.0, 2400.0]]:
		var projectile_matches := false
		if c.cast(probe[0], at + Vector2(4000, 0), 0):
			for entity in world.entities.values():
				if entity is Projectile and entity.ctx.get("src_slot") == probe[0]:
					projectile_matches = entity.max_dist == probe[1] and entity.radius == probe[2] and entity.speed == probe[3]
					world.despawn(entity)
					break
		checks["%s projectile geometry" % probe[0]] = projectile_matches and world.aim_ability(probe[0]).range == probe[1]
	var before := dummy.total_taken
	dummy.teleport(at + Vector2(1100, 310.0 + dummy.radius - 1.0))
	var outside: Dummy = world.spawn("dummy", {"pos": at + Vector2(1100, -310.0 - dummy.radius - 1.0), "hp": 10000.0})
	checks["E clamps its center to 1100 and hits at the 310-unit boundary"] = (
		c.cast("e", at + Vector2(4000, 0), 0) and dummy.total_taken > before and outside.total_taken == 0.0)
	before = dummy.total_taken
	dummy.teleport(at + Vector2(3340, 100.0 + dummy.radius - 1.0))
	outside.teleport(at + Vector2(3340.0 + 100.0 + outside.radius + 1.0, 0))
	checks["R reaches 3340 with a 200-unit-wide beam"] = (
		c.cast("r", at + Vector2(4000, 0), 0) and dummy.total_taken > before and outside.total_taken == 0.0)
	var passed := true
	for label in checks:
		if checks[label]:
			print("[league_units] OK: ", label)
		else:
			push_error("[league_units] " + label)
			passed = false
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if passed else 1)


## --auto=practice --map=arena --char=clorinde --selftest=abilitytips
func _test_ability_tips() -> void:
	var ch := world.local_champion
	if ch == null or ch.char_id != "clorinde":
		push_error("[abilitytips] requires --char=clorinde")
		get_tree().quit(1)
		return
	var hud := world.hud
	var hover := InputEventMouseMotion.new()
	hover.position = hud.slot_boxes.q.get_global_rect().get_center()
	get_viewport().push_input(hover, true)
	await get_tree().create_timer(0.65).timeout
	var short := hud._ability_tip_text.text
	var short_size := hud._ability_tip.size
	var ok := _tip_check(hud._ability_tip.visible and short.contains("Stun enemies in a cone, then shoot them.") and not short.contains("70% AD"), "HUD shows summary")
	_tip_shift(true)
	await get_tree().create_timer(0.1).timeout
	var expanded := hud._ability_tip_text.text
	ok = _tip_check(expanded.contains("70% AD") and expanded.contains("Cooldown: 13 s") and expanded.contains("Range: 380"), "HUD expands without moving the mouse") and ok
	_tip_shift(false)
	await get_tree().create_timer(0.1).timeout
	ok = _tip_check(hud._ability_tip_text.text == short and hud._ability_tip.size.is_equal_approx(short_size), "HUD collapses on Shift release") and ok
	ch.recast_left.e = 1.0
	ok = _tip_check(hud._ability_tip_content(ch, "e", false).begins_with("E - Impale the Night"), "HUD shows the active recast") and ok
	ch.recast_left.e = 0.0

	var lobby := preload("res://scripts/ui/lobby.gd").new()
	add_child(lobby)
	lobby._show_details("clorinde")
	ok = _tip_check(lobby.details.text.contains("Recast - Impale the Night") and not lobby.details.text.contains("0/3/6/12/20"), "champion select shows summaries including recasts") and ok
	_tip_shift(true)
	await get_tree().create_timer(0.1).timeout
	ok = _tip_check(lobby.details.text.contains("0/3/6/12/20") and lobby.details.text.contains("13/12/11/10/9"), "champion select shows scaling and per-rank cooldown on Shift") and ok
	_tip_shift(false)
	await get_tree().create_timer(0.1).timeout
	ok = _tip_check(not lobby.details.text.contains("0/3/6/12/20"), "champion select collapses on Shift release") and ok
	get_tree().quit(0 if ok else 1)


func _tip_shift(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.shift_pressed = pressed
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tip_check(condition: bool, label: String) -> bool:
	if condition:
		print("[abilitytips] OK: ", label)
	else:
		push_error("[abilitytips] " + label)
	return condition


func _test_balance() -> void:
	if not world.map.rift_waves:
		_check(false, "balance test requires --map=two_lanes")
		get_tree().quit(1)
		return
	var ok := true
	var base: Tower
	var inhibitor: Tower
	var guards: Array[Tower] = []
	var lane_turrets: Array[Tower] = []
	for s in world.structures:
		if s.team != 1:
			continue
		if s.is_nexus:
			base = s
		elif s.is_nexus_turret:
			guards.append(s)
		elif s.lane == 0:
			if s.is_inhibitor:
				inhibitor = s
			else:
				lane_turrets.append(s)
	if base == null or inhibitor == null or guards.size() != 2 or lane_turrets.size() != 3:
		_check(false, "missing base structures")
		get_tree().quit(1)
		return
	var lethal := 50000.0
	ok = _check(is_zero_approx(inhibitor.take_damage(lethal, null, "true")), "lane turrets protect inhibitor") and ok
	ok = _check(guards[0].is_protected() and base.is_protected(), "intact inhibitors protect base") and ok
	world.wave_count = 2
	world._waves(world.wave_timer)
	world.time += 6.0
	world._run_scheduled()
	var cannons := 0
	var wave_units := 0
	for u in world.units:
		if u is Minion:
			wave_units += 1
			if u.minion_type == "siege":
				cannons += 1
	ok = _check(cannons == 4 and wave_units == 28, "third wave spawns three melee, three casters and one cannon per team per lane") and ok
	var minion_radii := {"melee": 22.5, "ranged": 19.5, "siege": 33.0, "super": 36.0}
	for type in minion_radii:
		var minion: Minion = world.spawn("minion", {"team": 0, "type": type, "pos": world.map.lane(0, 0)[0]})
		var shape := minion.collider.shape as CircleShape2D
		ok = _check(is_equal_approx(minion.radius, minion_radii[type])
			and is_equal_approx(shape.radius, float(minion_radii[type]) * 0.6), "%s minion has 50%% larger hitbox and collider" % type) and ok
		world.despawn(minion)
	lane_turrets.sort_custom(func(a, b): return a.order < b.order)
	for s in lane_turrets:
		s.take_damage(lethal, null, "true")
	inhibitor.take_damage(lethal, null, "true")
	ok = _check(inhibitor.dead and not guards[0].is_protected() and base.is_protected(), "inhibitor destruction opens only Nexus turrets") and ok
	ok = _check("super" in world._wave_types(0, 0) and "siege" not in world._wave_types(0, 0)
		and "super" not in world._wave_types(0, 1) and "super" not in world._wave_types(1, 0), "supers replace cannons only on the attacking lane") and ok
	guards[0].take_damage(lethal, null, "true")
	ok = _check(base.is_protected(), "one surviving Nexus turret still protects Nexus") and ok
	guards[1].take_damage(lethal, null, "true")
	ok = _check(not base.is_protected(), "Nexus opens with both Nexus turrets and one inhibitor down") and ok
	world.time += 299.0
	world._run_scheduled()
	ok = _check(inhibitor.dead, "inhibitor remains down before five minutes") and ok
	world.time += 1.0
	world._run_scheduled()
	ok = _check(not inhibitor.dead and is_equal_approx(inhibitor.hp, inhibitor.stats.max_hp)
		and base.is_protected() and "super" not in world._wave_types(0, 0), "inhibitor respawn restores protection and stops supers") and ok
	inhibitor.take_damage(lethal, null, "true")
	base.take_damage(lethal, null, "true")
	ok = _check(world.ended and world.winner == 0, "destroying the exposed Nexus wins the match") and ok
	print("[balance] ", "passed" if ok else "failed")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit(0 if ok else 1)


func _check(condition: bool, label: String) -> bool:
	if not condition:
		push_error("[balance] " + label)
	return condition


func _test_classic_items() -> void:
	var player := world.local_champion
	var start := Vector2(900, 750)
	player.teleport(start)
	var enemy: Champion = world.spawn("champion", {"team": 1, "peer": 999, "character": "sir_bonk",
		"name": "Enemy", "pos": start + Vector2(150, 0)})
	var cannon: Minion = world.spawn("minion", {"team": 0, "lane": 0, "type": "siege", "pos": start + Vector2(0, 250)})
	var melee: Minion = world.spawn("minion", {"team": 0, "lane": 0, "type": "melee", "pos": start + Vector2(0, -250)})
	var enemy_minion: Minion = world.spawn("minion", {"team": 1, "lane": 0, "type": "melee", "pos": start + Vector2(0, 350)})
	var tower: Tower = world.spawn("tower", {"team": 1, "pos": start + Vector2(1000, 0)})
	var structure_hit := tower.take_damage(10.0, player, "true", {"ability": "q"})
	var cannon_hit := cannon.attack_damage_against(tower)
	player.items[0] = player.new_instance("prowlers_claw")
	player.items[1] = player.new_instance("hullbreaker")
	player._items_changed()
	await get_tree().create_timer(0.55).timeout
	var ok := _check(is_equal_approx(tower.take_damage(10.0, player, "true", {"ability": "q"}), structure_hit * 1.2),
		"Hullbreaker amplifies non-attack structure damage")
	ok = _check(is_equal_approx(cannon.attack_damage_against(tower), cannon_hit * 3.0)
		and cannon.stats.armor > cannon.base_stats.armor and is_equal_approx(melee.stats.armor, melee.base_stats.armor),
		"Hullbreaker empowers siege minions but not melee minions") and ok
	ok = _check(not player.use_item(0, enemy_minion.global_position, enemy_minion.net_id), "Sandswipe rejects enemy minions") and ok
	var base_hit := enemy.take_damage(10.0, player, "true")
	ok = _check(player.use_item(0, enemy.global_position, enemy.net_id), "Sandswipe accepts an enemy champion") and ok
	await get_tree().create_timer(0.35).timeout
	ok = _check(player.global_position.x > enemy.global_position.x
		and is_equal_approx(enemy.take_damage(10.0, player, "true"), base_hit * 1.15),
		"Sandswipe lands past its target and amplifies follow-up damage") and ok
	world.spawn("champion", {"team": 0, "peer": 998, "character": "mender",
		"name": "Ally", "pos": player.global_position + Vector2(0, 150)})
	await get_tree().create_timer(0.6).timeout
	ok = _check(is_equal_approx(tower.take_damage(10.0, player, "true", {"ability": "q"}), structure_hit)
		and is_equal_approx(cannon.attack_damage_against(tower), cannon_hit),
		"A nearby ally disables both Hullbreaker bonuses") and ok
	print("[classic_items] ", "passed" if ok else "failed")
	get_tree().quit(0 if ok else 1)


func _test_match_fixes() -> void:
	var player := world.local_champion
	var center := world.map.size * 0.5
	var shop := world.hud.shop
	player.gold = 500.0
	shop.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	shop._build.set_ids(["boots"])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = shop._build.get_global_transform_with_canvas() * shop._build.cells[0].r.get_center()
	click.global_position = click.position
	get_viewport().push_input(click, true)
	var purchased = player.item_def(0)
	var ok := _check(purchased != null and purchased.id == "boots" and is_equal_approx(player.gold, 200.0),
		"right-clicking the build row buys boots exactly once")
	click.pressed = false
	get_viewport().push_input(click, true)
	shop.toggle()
	world.hud.show_scores(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var scores := world.hud.scores
	var motion := InputEventMouseMotion.new()
	motion.position = scores.get_global_transform_with_canvas() * Vector2(486, 72)
	motion.global_position = motion.position
	get_viewport().push_input(motion, true)
	var item_id := scores._get_tooltip(Vector2(486, 72))
	ok = _check(get_viewport().gui_get_hovered_control() == scores and item_id == "boots"
		and scores._get_tooltip(Vector2(522, 72)) == "", "scoreboard receives hover and only occupied slots show items") and ok
	world.hud.show_scores(false)

	for u in world.units.duplicate():
		if u is Dummy:
			world.despawn(u)
	player.teleport(center + Vector2(300, 0))
	var minion: Minion = world.spawn("minion", {"team": 1 - player.team, "pos": center})
	minion._think(1.0)
	ok = _check(minion.attack_target == player, "nearby enemy draws minion aggro") and ok
	minion.teleport(center + Vector2(460, 0))
	player.teleport(center + Vector2(560, 0))
	minion._think(1.0)
	minion._think(1.0)
	ok = _check(minion.attack_target == null and minion.move_goal == center,
		"minion returns to its chase origin even if the champion remains in reach") and ok

	var xp_before := player.xp
	minion.die(player)
	ok = _check(is_equal_approx(player.xp - xp_before, 57.04), "solo melee minion awards 57.04 XP") and ok
	var ally: Champion = world.spawn("champion", {"peer": 999, "team": player.team, "character": player.char_id,
		"name": "Ally", "pos": player.global_position})
	xp_before = player.xp
	var shared: Minion = world.spawn("minion", {"team": 1 - player.team, "pos": center})
	shared.die(player)
	ok = _check(is_equal_approx(player.xp - xp_before, 34.224) and is_equal_approx(ally.xp, 34.224),
		"nearby allies split the reduced minion XP pool") and ok
	world.despawn(ally)
	world.champions.erase(999)
	player.xp = 0.0
	for i in 7:
		var lane_minion: Minion = world.spawn("minion", {"team": 1 - player.team, "pos": center,
			"type": "ranged" if i in [3, 4, 5] else "melee"})
		lane_minion.die(player)
		if i == 5:
			ok = _check(player.level == 1, "one solo wave does not grant level 2") and ok
	ok = _check(player.level == 2, "one solo wave plus one melee minion grants level 2") and ok
	world.camera.global_position = player.global_position
	world.camera.reset_smoothing()
	world.camera.force_update_scroll()
	var inspect_motion := InputEventMouseMotion.new()
	inspect_motion.position = world.get_canvas_transform() * player.global_position
	get_viewport().push_input(inspect_motion, true)
	var inspect_click := InputEventMouseButton.new()
	inspect_click.button_index = MOUSE_BUTTON_LEFT
	inspect_click.pressed = true
	inspect_click.position = inspect_motion.position
	get_viewport().push_input(inspect_click, true)
	ok = _check(world.hud.inspected_unit == player, "left-click selects a champion for inspection") and ok
	world.hud._update_inspection()
	ok = _check(world.hud.inspect_label.text.contains("Radius %.0f" % player.radius), "inspection shows the champion gameplay radius") and ok
	var tower: Tower = world.spawn("tower", {"team": player.team, "pos": center - Vector2(300, 0)})
	var lane_unit: Minion = world.spawn("minion", {"team": player.team, "pos": center - Vector2(150, 0)})
	ok = _check(world.inspect_at(tower.global_position) == tower and world.inspect_at(lane_unit.global_position) == lane_unit,
		"inspection can select structures and lane minions") and ok
	ok = _check(world.inspect_at(center - Vector2(600, 0)) == null and world.hud.inspected_unit == null,
		"clicking empty ground clears inspection") and ok
	print("[matchfixes] ", "passed" if ok else "failed")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit(0 if ok else 1)


func _test_windup() -> void:
	var at := world.map.size * 0.5
	var target: Dummy = world.spawn("dummy", {"pos": at + Vector2(70.0, 0.0)})
	var minion: Minion = world.spawn("minion", {"team": 0, "pos": at})
	var ok := true
	var tick := 1.0 / 60.0
	minion.attack_target = target
	minion._act(tick)
	ok = _check(minion.windup_left >= 0.3 and target.total_taken == 0.0, "melee minion winds up instead of dealing instant damage") and ok
	target.global_position = at + Vector2(minion.attack_reach(target) + 10.0, 0.0)
	minion._act(tick)
	ok = _check(minion.windup_left == 0.0 and target.total_taken == 0.0, "leaving attack reach cancels windup without damage") and ok
	target.global_position = at + Vector2(70.0, 0.0)
	for i in 12:
		minion._act(tick)
	ok = _check(target.total_taken == 0.0, "minion cannot hit during its startup") and ok
	for i in 12:
		minion._act(tick)
	ok = _check(is_equal_approx(target.total_taken, minion.stats.attack_damage), "staying in reach lets exactly one attack release") and ok
	ok = _check(minion.recovery_lock > 0.0 and minion.velocity == Vector2.ZERO, "attack release starts locked recovery") and ok
	minion.recovery_lock = 0.0
	minion.attack_cd = 0.0
	for i in 13:
		minion._act(tick)
	ok = _check(minion.attack_committed(), "the second part of startup commits the attack") and ok
	minion.cancel_attack_windup()
	target.global_position = at + Vector2(minion.attack_reach(target) + 100.0, 0.0)
	for i in 12:
		minion._act(tick)
	ok = _check(minion.recovery_lock > 0.0 and is_equal_approx(target.total_taken, minion.stats.attack_damage),
		"committed attack plays through recovery but misses an out-of-range target") and ok
	var ember := world.local_champion
	if not _check(ember != null and ember.char_id == "ember", "windup test requires --char=ember"):
		get_tree().quit(1)
		return
	ember.max_ranks()
	var before := world.entities.size()
	ok = _check(ember.cast("q", ember.global_position + Vector2.RIGHT * 400.0, 0)
		and ember.windup_left > 0.2 and world.entities.size() == before, "fireball cues before spawning its projectile") and ok
	for i in 12:
		ember._think(tick)
	ok = _check(world.entities.size() == before, "fireball is not released early") and ok
	for i in 13:
		ember._think(tick)
	var fireball: Projectile
	for e in world.entities.values():
		if e is Projectile:
			fireball = e
	ok = _check(ember.windup_left == 0.0 and fireball != null and world.entities.size() == before + 1,
		"fireball launches at the end of startup") and ok
	if fireball != null:
		var origin := fireball.global_position
		fireball._physics_process((fireball.max_dist + 10.0) / fireball.speed)
		ok = _check(fireball.done and is_equal_approx(origin.distance_to(fireball.global_position), 900.0),
			"fireball ends at its authored range instead of overshooting") and ok
	var walk_start := at - Vector2(800, 0)
	ember.teleport(walk_start)
	ember.move_goal = walk_start + Vector2(500, 0)
	await get_tree().physics_frame
	walk_start = ember.global_position
	for i in Engine.physics_ticks_per_second:
		await get_tree().physics_frame
	var distance := ember.global_position.distance_to(walk_start)
	ok = _check(absf(distance - 330.0) <= 0.1, "Ember walks 330 world units in one second (got %.1f)" % distance) and ok
	print("[windup] ", "passed" if ok else "failed")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit(0 if ok else 1)


## Aether Rift: layout invariants, brush vision and the jungle (aggro, leash, rewards, objectives).
##   godot --headless --path . -- --auto=practice --map=rift --char=ember --selftest=rift
func _test_rift() -> void:
	var m := world.map
	var jg := world.jungle
	var blue := world.local_champion
	if not _check(jg != null and m.mirror_mode == "rotate" and blue != null, "rift test requires --map=rift"):
		get_tree().quit(1)
		return
	var ok := true
	var per_team := [0, 0]
	var on_lane := true
	for s in world.structures:
		per_team[s.team] += 1
		if s.lane >= 0:
			on_lane = on_lane and m.nearest_lane(s.global_position) == s.lane
	ok = _check(per_team == [15, 15], "each team has a Nexus, two Nexus turrets, three inhibitors and nine lane turrets") and ok
	ok = _check(m.lane_count() == 3 and on_lane, "three lanes, and every mirrored turret/inhibitor guards the lane it stands on") and ok
	ok = _check(m.spawn_point(1).is_equal_approx(m.size - m.spawn_point(0)), "the red base is the blue base rotated 180 degrees") and ok
	for i in m.lane_count():
		var l: PackedVector2Array = m.lanes[i]
		ok = _check(_reachable(l[0], l[l.size() - 1]), "%s lane connects both bases" % m.lane_name(i)) and ok
	for c in m.camps:
		ok = _check(not m.is_wall(c.pos) and _reachable(m.spawn_point(0), c.pos), "%s camp (side %d) is reachable" % [c.kind, c.side]) and ok

	# ---- brush
	var red: Champion = world.spawn("champion", {"peer": 4242, "team": 1, "character": blue.char_id, "name": "Red", "pos": m.size * 0.5})
	var b: PackedVector2Array = m.brushes[0]
	var spot := Vector2.ZERO
	for p in b:
		spot += p
	spot /= b.size()
	var outside := Vector2.INF
	for k in 16:
		var q := spot + Vector2.from_angle(TAU * k / 16.0) * 450.0
		if m.brush_at(q) == 0 and not m.is_wall(q) and m.sight_clear(q, spot):
			outside = q
			break
	ok = _check(m.brush_at(spot) > 0 and outside != Vector2.INF, "brush has an inside and a clear outside") and ok
	red.teleport(spot)
	blue.teleport(outside)
	_vision()
	ok = _check(not world.can_see(red, 0) and world.can_see(blue, 1), "a champion in brush is hidden from enemies outside, and still sees out") and ok
	var ward: Summon = world.spawn("summon", {"team": 0, "pos": spot + Vector2(0, 20), "ward": true, "stationary": true, "stats": {"vision": 900.0}})
	_vision()
	ok = _check(world.can_see(red, 0), "a ward inside the brush reveals it") and ok
	world.despawn(ward)
	blue.teleport(spot + Vector2(0, -20))
	_vision()
	ok = _check(world.can_see(red, 0), "standing in the same brush reveals who is inside") and ok
	blue.teleport(outside)
	blue.take_damage(20.0, red, "physical", {"attack": true})
	red.flags = red._compute_flags()
	_vision()
	ok = _check(world.can_see(red, 0), "damaging a champion from brush reveals the attacker") and ok
	red._update_statuses(World.BRUSH_REVEAL + 0.1)
	red.flags = red._compute_flags()
	_vision()
	ok = _check(not world.can_see(red, 0), "the brush reveal wears off") and ok
	world.fog.dark = false
	red.teleport(m.spawn_point(1))
	red.add_status({"type": "stealth", "time": 5.0}, red, "test_stealth")
	red.flags = red._compute_flags()
	_vision()
	ok = _check(not world.can_see(red, 0), "with fog of war off, stealth still hides champions outside brush") and ok
	red.statuses.clear()
	red.flags = red._compute_flags()
	_vision()
	ok = _check(world.can_see(red, 0), "with fog of war off, champions outside brush are visible") and ok
	world.fog.dark = true
	red.teleport(m.spawn_point(1))

	# ---- jungle camps
	world.time = 90.0
	jg.tick(0.01)
	var bc := _camp("blue", 0)
	var sentinel: Monster = bc.alive[0] if not bc.alive.is_empty() else null
	ok = _check(sentinel != null and sentinel.kind_id == "blue_sentinel", "Blue Sentinel spawns at 1:30") and ok
	if sentinel == null:
		get_tree().quit(1)
		return
	blue.teleport(sentinel.home + Vector2(0, 250))
	sentinel.take_damage(50.0, blue, "physical", {"attack": true})
	ok = _check(sentinel.attack_target == blue, "a monster fights back when hit") and ok
	blue.teleport(m.nearest_open(sentinel.home + Vector2(0, 2600)))
	sentinel._think(0.3)
	ok = _check(sentinel.resetting, "leaving the leash range makes the monster reset") and ok
	sentinel.global_position = sentinel.home
	sentinel._think(0.1)
	ok = _check(not sentinel.resetting and is_equal_approx(sentinel.hp, sentinel.stats.max_hp), "a reset monster is back at full health") and ok
	var wc := _camp("wolves", 0)
	blue.teleport(wc.pos + Vector2(0, 250))
	wc.alive[0].take_damage(10.0, blue, "physical", {"attack": true})
	ok = _check(wc.alive.size() == 3 and wc.alive.all(func(w): return w.attack_target == blue), "hitting one wolf aggroes the whole camp") and ok
	blue.teleport(sentinel.home + Vector2(0, 250))
	var gold := blue.gold
	var xp := blue.xp + blue.level * 10000.0
	sentinel.take_damage(1.0e6, blue, "true")
	ok = _check(not blue.find_status("crest_of_insight").is_empty(), "killing Blue Sentinel grants Crest of Insight") and ok
	ok = _check(blue.gold - gold >= 89.9 and blue.xp + blue.level * 10000.0 > xp, "monsters give gold and experience to their killer") and ok
	ok = _check(is_equal_approx(float(bc.next), world.time + 300.0), "Blue Sentinel respawns after five minutes") and ok
	var bram: Monster = _camp("red", 0).alive[0]
	blue.summoners = ["flash", "smite"]
	blue.sum_cd = [0.0, 0.0]
	blue.teleport(bram.global_position + Vector2(0, 300))
	_vision()
	var before := bram.hp
	ok = _check(blue.use_summoner(1, bram.global_position, bram.net_id) and before - bram.hp >= 599.0, "Smite deals 600 true damage to a monster") and ok
	bram.take_damage(1.0e6, blue, "true")
	ok = _check(not blue.find_status("crest_of_cinders").is_empty(), "killing Red Brambleback grants Crest of Cinders") and ok
	var wolf: Monster = wc.alive[1]
	blue.teleport(m.spawn_point(0))
	var minion: Minion = world.spawn("minion", {"team": 1, "lane": 0, "type": "melee", "pos": wolf.global_position + Vector2(60, 0)})
	ok = _check(minion._find_target() == null, "minions ignore jungle monsters") and ok
	world.despawn(minion)
	red.teleport(blue.global_position + Vector2(120, 0))
	jg.give_buff(red, "blue")
	blue.find_status("crest_of_insight").time = 5.0
	blue.take_damage(1.0e6, red, "true")
	ok = _check(blue.dead and not red.find_status("crest_of_insight").is_empty() and not red.find_status("crest_of_cinders").is_empty(),
		"killing a buff holder takes over their buffs") and ok
	ok = _check(float(red.find_status("crest_of_insight").time) > 100.0, "taking over a shorter buff keeps your own longer one") and ok
	blue.respawn()
	red.teleport(m.spawn_point(1))

	# ---- Rift Scuttler, Drakes, Elder, Baron
	world.time = 210.0
	jg.tick(0.01)
	var crab: Monster = _camp("scuttle", 0).alive[0]
	blue.teleport(crab.global_position + Vector2(0, 150))
	crab.take_damage(1.0e6, blue, "true")
	var shrine: Summon = null
	for e in world.entities.values():
		if e is Summon and e.display_name == "Speed Shrine" and e.team == 0:
			shrine = e
	shrine.flags = shrine._compute_flags() if shrine != null else 0
	ok = _check(shrine != null and not shrine.targetable(), "killing the Rift Scuttler leaves an untargetable vision shrine") and ok
	world.time = 300.0
	jg.tick(0.01)
	var ally: Champion = world.spawn("champion", {"peer": 4243, "team": 0, "character": blue.char_id, "name": "Ally", "pos": m.spawn_point(0)})
	ally.take_damage(1.0e6, red, "true")
	var dc := _camp("dragon", -1)
	var taken := []
	for k in 4:
		var d: Monster = dc.alive[0]
		taken.append(d.element)
		blue.teleport(m.nearest_open(d.global_position + Vector2(0, 300)))
		d.take_damage(1.0e6, blue, "true")
		world.time = float(dc.next)
		jg.tick(0.01)
	ok = _check(jg.drakes[0] == taken and jg.soul[0] == taken[3], "four drakes grant the team their Dragon Soul (%s)" % str(taken)) and ok
	ok = _check(int(blue.find_status("drake_" + str(taken[0])).get("stacks", 0)) == taken.count(taken[0]), "drake bonuses stack per element") and ok
	ally.respawn()
	ok = _check(ally.find_status("drake_" + str(taken[0])).get("stacks", 0) == taken.count(taken[0]) and not ally.find_status("dragon_soul").is_empty(),
		"a teammate who was dead during the drakes gets the stacks and Soul on respawn") and ok
	var elder: Monster = dc.alive[0]
	ok = _check(elder.kind_id == "elder_dragon", "the Elder Dragon replaces drakes once a soul is claimed") and ok
	blue.teleport(m.nearest_open(elder.global_position + Vector2(0, 300)))
	elder.take_damage(1.0e6, blue, "true")
	red.teleport(blue.global_position + Vector2(150, 0))
	red.hp = red.stats.max_hp * 0.15
	red.take_damage(5.0, blue, "physical", {"attack": true})
	ok = _check(red.dead, "Aspect of the Elder executes champions below 20% health") and ok
	red.respawn()
	world.time = 1200.0
	jg.tick(0.01)
	var baron: Monster = _camp("baron", -1).alive[0]
	ok = _check(baron.kind_id == "baron", "Baron Nashor spawns at 20:00") and ok
	blue.teleport(m.nearest_open(baron.global_position + Vector2(0, 400)))
	baron.take_damage(1.0e6, blue, "true")
	ok = _check(not blue.find_status("hand_of_baron").is_empty(), "killing Baron grants Hand of Baron") and ok
	blue.start_recall()
	ok = _check(is_equal_approx(blue.recall_timer, 4.0), "Hand of Baron empowers recall (4s)") and ok
	blue._cancel_recall()
	var mn: Minion = world.spawn("minion", {"team": 0, "lane": 1, "type": "melee", "pos": blue.global_position + Vector2(80, 0)})
	jg._auras()
	ok = _check(mn.statuses.any(func(s): return s.key == "baron_aura"), "Hand of Baron empowers nearby minions") and ok
	print("[rift] ", "passed" if ok else "failed")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit(0 if ok else 1)


func _camp(kind: String, side: int) -> Dictionary:
	for c in world.jungle.camps:
		if c.kind == kind and (side < 0 or int(c.side) == side):
			return c
	return {}


func _reachable(a: Vector2, b: Vector2) -> bool:
	var m := world.map
	return not m.astar.get_id_path(m._nearest_open_cell(m.cell_of(a)), m._nearest_open_cell(m.cell_of(b))).is_empty()


func _vision() -> void:
	for t in 2:
		world.fog._collect(t)
		world.fog._compute(t)
