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
	var ember := world.local_champion
	if not _check(ember != null and ember.char_id == "ember", "windup test requires --char=ember"):
		get_tree().quit(1)
		return
	ember.max_ranks()
	var before := world.entities.size()
	ok = _check(ember.cast("q", ember.global_position + Vector2.RIGHT * 400.0, 0)
		and ember.windup_left > 0.2 and world.entities.size() == before, "fireball cues before spawning its projectile") and ok
	for i in 8:
		ember._think(tick)
	ok = _check(world.entities.size() == before, "fireball is not released early") and ok
	for i in 8:
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
	for i in 61:
		await get_tree().physics_frame
	var distance := ember.global_position.distance_to(walk_start)
	ok = _check(absf(distance - 247.5) <= 2.0, "Ember walks about 248 world units in one second (got %.1f)" % distance) and ok
	print("[windup] ", "passed" if ok else "failed")
	await get_tree().create_timer(1.0, true, false, true).timeout
	get_tree().quit(0 if ok else 1)
