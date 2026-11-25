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
	if Game.cmdline.get("selftest") == "rift":
		_test_rift()
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
