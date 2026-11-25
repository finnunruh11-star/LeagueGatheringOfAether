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
	if Game.cmdline.get("selftest") == "abilitytips":
		await _test_ability_tips()
		return
	if Game.cmdline.get("selftest") == "matchfixes":
		await _test_match_fixes()
		return
	if Game.cmdline.get("selftest") == "league_units":
		await _test_league_units()
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
