extends Node
## Item test harness. Gives a champion items and runs a scripted scenario against an
## enemy champion, printing every damage/heal/shield/proc event. Example:
##   godot --headless --path . -- --auto=practice --map=arena --itemtest=kraken_slayer,trinity_force
##       [--char=gizmo] [--enemy=sir_bonk] [--level=11] [--enemy_items=thornmail]
##       [--steps=attack:4,cast:q,item:0,hurt:300,hurtm:200,enemy_attack:3,lowhp,kill,wait:2,stats]

var world: World
var a: Champion
var b: Champion


func _ready() -> void:
	Game.debug_log = true
	await get_tree().create_timer(0.3).timeout
	world = Game.world
	for e in world.entities.values():
		if e is Dummy or (e is Champion):
			e.visible = e is Champion
	for e in world.entities.values():
		if e is Dummy:
			world.despawn(e)
	for e in Game.content_errors:
		print("[itemtest] CONTENT ERROR: ", e)
	var lvl := int(Game.cmdline.get("level", "11"))
	a = world.local_champion
	a.teleport(Vector2(900, 750))
	b = world.spawn("champion", {"peer": 999, "team": 1, "character": str(Game.cmdline.get("enemy", "sir_bonk")),
		"name": "Enemy", "pos": Vector2(1050, 750), "gold": 0.0})
	for c in [a, b]:
		for k in lvl - 1:
			c.cheat("level")
		c.max_ranks()
	_give(a, str(Game.cmdline.get("itemtest", "")))
	_give(b, str(Game.cmdline.get("enemy_items", "")))
	await get_tree().create_timer(0.3).timeout
	a.hp = a.stats.max_hp
	a.mana = a.stats.max_mana
	b.hp = b.stats.max_hp
	_print_stats("A", a)
	_print_stats("B", b)
	var steps := str(Game.cmdline.get("steps", "attack:4,cast:q,cast:w,cast:e,cast:r,item:0,hurt:300,hurtm:300,wait:1,stats"))
	for step in steps.split(",", false):
		var kv := step.split(":")
		var what := kv[0]
		var v := float(kv[1]) if kv.size() > 1 else 0.0
		print("[itemtest] --- step %s (t=%.2f) A hp=%d/%d mana=%d  B hp=%d/%d" % [step, world.time, a.hp, a.stats.max_hp, a.mana, b.hp, b.stats.max_hp])
		match what:
			"attack":
				a.attack_target = b
				await _wait(v)
				a.attack_target = null
			"cast":
				a.cooldowns[kv[1]] = 0.0
				a.mana = a.stats.max_mana
				print("[itemtest] cast %s -> %s" % [kv[1], str(a.cast(kv[1], b.global_position, b.net_id))])
				await _wait(1.5)
			"item":
				var i := int(v)
				if a.items[i] != null:
					a.items[i].cd = 0.0
				print("[itemtest] use item %d (%s) -> %s" % [i, a.items[i].id if a.items[i] != null else "-", str(a.use_item(i, b.global_position, b.net_id))])
				await _wait(1.0)
			"hurt":
				a.take_damage(v, b, "physical", {"attack": true, "vfx": "slash"})
				await _wait(0.3)
			"hurtm":
				a.take_damage(v, b, "magic", {"ability": "q", "vfx": "ability"})
				await _wait(0.3)
			"enemy_attack":
				b.attack_target = a
				await _wait(v)
				b.attack_target = null
			"lowhp":
				a.hp = a.stats.max_hp * 0.25
			"kill":
				b.take_damage(99999.0, a, "true", {"ability": "q"})
				await _wait(0.5)
			"move":
				a.move_goal = a.global_position + Vector2(v, 0)
				await _wait(absf(v) / maxf(a.stats.move_speed, 1.0) + 0.2)
			"wait":
				await _wait(v)
			"stats":
				_print_stats("A", a)
				_print_stats("B", b)
			"buy":
				a.gold = 99999.0
				print("[itemtest] buy %s -> '%s'" % [kv[1], a.buy(kv[1])])
	print("[itemtest] done")
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(maxf(t, 0.05)).timeout


func _give(c: Champion, list: String) -> void:
	var slot := 0
	for id in list.split(",", false):
		if not Game.items.has(id):
			print("[itemtest] UNKNOWN ITEM ", id)
			continue
		c.items[slot] = {"id": id, "n": Game.items[id].stack, "cd": 0.0, "cd_total": 1.0}
		slot += 1
	c._items_changed()
	c.recompute_stats()


func _print_stats(label: String, c: Champion) -> void:
	var s: Dictionary = c.stats
	var ids := []
	for inst in c.items:
		if inst != null:
			ids.append(inst.id)
	print("[itemtest] %s %s lvl %d items=%s" % [label, c.char_id, c.level, str(ids)])
	print("[itemtest]   hp %d/%d mana %d/%d ad %.1f ap %.1f as %.2f armor %.1f mr %.1f ms %.0f crit %.2f ah %.0f leth %.0f arpen %.2f mpen %.0f/%.2f ls %.2f omni %.2f hsp %.2f ten %.2f" % [
		c.hp, s.max_hp, c.mana, s.max_mana, s.attack_damage, s.ability_power, s.attack_speed, s.armor, s.magic_resist, s.move_speed,
		s.crit_chance, s.ability_haste, s.lethality, s.armor_pen, s.magic_pen, s.magic_pen_percent, s.lifesteal, s.omnivamp, s.heal_power, s.tenacity])
	var sts := []
	for st in c.statuses:
		sts.append("%s%s(%.1fs%s)" % [st.type, (":" + st.id) if st.has("id") else "", st.time, (" x%d" % st.stacks) if st.has("stacks") else ""])
	print("[itemtest]   statuses=%s counters=%s shield=%.0f" % [str(sts), str(c.counters), c.shield])
