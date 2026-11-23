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
	for e in world.entities.values():
		if e is Dummy:
			world.despawn(e)
	var dummy: Dummy = world.spawn("dummy", {"pos": Vector2(1300, 750), "hp": 1000000.0})
	var ally: Dummy = world.spawn("dummy", {"pos": Vector2(800, 600), "hp": 1000000.0})
	ally.team = 0
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
		var c: Champion = world.spawn("champion", {"peer": pid, "team": 0, "character": id, "name": "Test", "pos": Vector2(850, 750)})
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
			var start := Vector2(850, 750)
			if ab.targeting == "self":
				start = dummy.global_position - Vector2(150, 0)
			c.teleport(start)
			c.dead = false
			c.hp = c.stats.max_hp
			c.cooldowns[slot] = 0.0
			c.statuses.clear()
			before = dummy.total_taken
			var n_before := world.entities.size()
			var target := dummy
			if ab.targeting == "ally":
				target = ally
			var ok := c.cast(slot, target.global_position, target.net_id)
			await get_tree().create_timer(0.4).timeout
			var spawned := world.entities.size() - n_before
			await get_tree().create_timer(WAIT - 0.4).timeout
			var moved := c.global_position.distance_to(start)
			print("[selftest] %-12s %s %-18s cast=%s dmg=%6.0f spawned=%d moved=%4.0f shield=%3.0f hp=%4.0f/%4.0f dummy_flags=%d" % [
				id, slot, ab.name.substr(0, 18), str(ok), dummy.total_taken - before, spawned, moved, c.shield, c.hp, c.stats.max_hp, dummy.flags])
		world.despawn(c)
		world.champions.erase(pid)
		for e in world.entities.values():
			if e is Summon or e is Zone or e is Projectile:
				world.despawn(e)
		dummy.teleport(Vector2(1300, 750))
		dummy.statuses.clear()
	print("[selftest] done")
	get_tree().quit()
