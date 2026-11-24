extends Node
## Item test harness. Gives a champion items and runs a scripted scenario against an
## enemy champion, printing every damage/heal/status/proc event. Example:
##   godot --headless --path . -- --auto=practice --map=arena --itemtest=kraken_slayer,trinity_force
##       [--char=gizmo] [--enemy=sir_bonk] [--ally=mender] [--level=11] [--enemy_items=thornmail]
##       [--steps=attack:4,cast:q,item:0,hurt:300,wait:2,stats]
## Steps (comma separated, "name:value"):
##   attack:S       A basic-attacks the enemy for S seconds      enemy_attack:S  the enemy attacks A
##   cast:q         A casts q at the enemy (cooldown/mana reset)  enemy_cast:q    the enemy casts q at A
##   cast_now:q     like cast, without waiting afterwards         heal:X          A is healed for X (no source)
##   try:q          A casts q without resetting its cooldown (prints whether it worked)   pos   print A's and B's positions
##   side:D         A jumps D units sideways (perpendicular to the line to the enemy)
##   behind         spawn a training dummy behind the enemy (seen from A)
##   net            print what clients would see of A (its network snapshot applied to a copy)
##   aim:q          show A's aiming indicator for q toward the enemy (aim: hides it) - for screenshots
##   item:N         A uses item slot N on the enemy              item_ally:N / item_self:N
##   hurt:X / hurtm:X / hurtt:X   A takes X physical (attack) / magic (ability) / true damage from the enemy
##   ally           spawn an allied champion at 50% HP next to A   heal_ally:X  A heals the ally for X
##   shield_ally:X  A shields the ally                            ally_attack:S   the ally attacks the enemy
##   minion         spawn an enemy minion next to the enemy        kill_minion     A last-hits a fresh minion
##   cc:stun        A stuns (or slows/roots/silences) the enemy    kill            A kills the enemy
##   self_cc:stun   the enemy stuns (slows/roots/silences) A
##   assist         A damages the enemy, then the enemy dies to something else
##   level:N        A gains N levels       hp:F / ehp:F / mana:F   set A's / enemy's HP or A's mana fraction
##   far:D          put the enemy D units away    move:D   A walks D units right    wait:S    stats
##   buy:id         A buys id with infinite gold  sell:N   A sells slot N  combat_reset   A leaves combat
##   home           teleport A to its fountain     back     teleport A back to the test spot
##   sum:N          A uses summoner spell N (0/1) on the enemy (cooldown reset first); sum_self:N, sum_ally:N,
##                  sum_tower:N (A's farthest allied tower), sum_try:N (no cooldown reset)   [--summoners=flash,ignite]
##   steer:DEG      A steers (WASD) toward DEG degrees (0 = right, 90 = down); steer:off stops
##   amove:D        A attack-moves to a point D units past the enemy (closest to that point)
##   cmd:NAME       A runs a champion command without arguments (e.g. cmd:stop)

var world: World
var a: Champion
var b: Champion
var ally: Champion = null
var spot := Vector2(900, 750)


func _ready() -> void:
	Game.debug_log = true
	# Never hang: quit after 90 real seconds no matter what.
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func():
		print("[itemtest] TIMEOUT - a step crashed or took too long")
		get_tree().quit(1))
	await get_tree().create_timer(0.3).timeout
	world = Game.world
	for e in world.entities.values():
		if e is Dummy:
			world.despawn(e)
	for e in Game.content_errors:
		print("[itemtest] CONTENT ERROR: ", e)
	var lvl := int(Game.cmdline.get("level", "11"))
	a = world.local_champion
	a.teleport(spot)
	b = world.spawn("champion", {"peer": 999, "team": 1, "character": str(Game.cmdline.get("enemy", "sir_bonk")),
		"name": "Enemy", "pos": spot + Vector2(150, 0), "gold": 0.0})
	for c in [a, b]:
		for k in lvl - 1:
			c.cheat("level")
		c.max_ranks()
	_give(a, str(Game.cmdline.get("itemtest", "")))
	if Game.cmdline.has("summoners"):
		a.summoners = Array(str(Game.cmdline.summoners).split(",", false)).filter(func(s): return Game.summoners.has(s))
		print("[itemtest] A summoners: ", a.summoners)
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
		var arg := kv[1] if kv.size() > 1 else ""
		var v := float(arg) if arg.is_valid_float() else 0.0
		print("[itemtest] --- step %s (t=%.2f) A hp=%d/%d mana=%d shield=%d bond=%d  B hp=%d/%d" % [step, world.time, a.hp, a.stats.max_hp, a.mana, a.shield, a.bond, b.hp, b.stats.max_hp])
		if b.dead:
			b.respawn()
			b.teleport(a.global_position + Vector2(150, 0))
		match what:
			"attack":
				a.attack_target = b
				await _wait(v)
				a.attack_target = null
			"cast", "cast_now":
				a.cooldowns[arg] = 0.0
				a.mana = a.stats.max_mana
				print("[itemtest] cast %s -> %s" % [arg, str(a.cast(arg, b.global_position, b.net_id))])
				await _wait(1.5 if what == "cast" else 0.05)
			"try":
				print("[itemtest] try %s (cooldown %.2f) -> %s" % [arg, a.cooldowns.get(arg, 0.0), str(a.cast(arg, b.global_position, b.net_id))])
				await _wait(0.05)
			"pos":
				print("[itemtest] pos A=%s B=%s dist=%.0f" % [str(a.global_position.round()), str(b.global_position.round()), a.global_position.distance_to(b.global_position)])
			"side":
				a.teleport(a.global_position + (b.global_position - a.global_position).normalized().orthogonal() * v)
			"heal":
				print("[itemtest] A is healed for %d -> healed %.1f" % [int(v), a.heal(v, null, true)])
				await _wait(0.1)
			"net":
				# What a client would see: apply A's snapshot to a fresh puppet copy.
				var p := Champion.new()
				p.puppet = true
				p.def = a.def
				p.apply_net_state(a.net_state())
				print("[itemtest] net: hp %d/%d bond %.0f (host %.0f) level %d cds %s recast %s charges %s (host %s %s)" % [p.hp, p.stats.max_hp,
					p.bond, a.bond, p.level, str(p.cooldowns.values().map(func(x): return snappedf(x, 0.1))),
					str(p.recast_left.values().map(func(x): return snappedf(x, 0.1))), str(p.recast_charges.values()),
					str(a.recast_left.values().map(func(x): return snappedf(x, 0.1))), str(a.recast_charges.values())])
				p.free()
			"behind":
				var d = world.spawn("dummy", {"pos": b.global_position + (b.global_position - a.global_position).normalized() * 120.0, "hp": 100000.0})
				print("[itemtest] dummy %d spawned behind the enemy" % d.net_id)
				await _wait(0.1)
			"aim":
				world.aim_slot = arg
				world.test_aim = b.global_position if arg != "" else null
			"enemy_cast":
				b.cooldowns[arg] = 0.0
				b.mana = b.stats.max_mana
				print("[itemtest] enemy cast %s -> %s" % [arg, str(b.cast(arg, a.global_position, a.net_id))])
				await _wait(1.5)
			"item", "item_ally", "item_self":
				var i := int(v)
				if a.items[i] != null:
					a.items[i].cd = 0.0
				var t: Unit = b
				if what == "item_ally" and ally != null:
					t = ally
				elif what == "item_self":
					t = a
				print("[itemtest] use item %d (%s) on %s -> %s" % [i, a.items[i].id if a.items[i] != null else "-", t.display_name,
					str(a.use_item(i, t.global_position, t.net_id))])
				await _wait(1.0)
			"hurt":
				a.take_damage(v, b, "physical", {"attack": true, "vfx": "slash"})
				await _wait(0.3)
			"hurtm":
				a.take_damage(v, b, "magic", {"ability": "q", "vfx": "ability"})
				await _wait(0.3)
			"hurtt":
				a.take_damage(v, b, "true", {"ability": "q", "vfx": "ability"})
				await _wait(0.3)
			"enemy_attack":
				b.attack_target = a
				await _wait(v)
				b.attack_target = null
			"ally":
				if ally == null:
					ally = world.spawn("champion", {"peer": 998, "team": 0, "character": str(Game.cmdline.get("ally", "mender")),
						"name": "Ally", "pos": a.global_position + Vector2(0, 120), "gold": 0.0})
					for k in a.level - 1:
						ally.cheat("level")
					ally.max_ranks()
					await _wait(0.2)
				ally.hp = ally.stats.max_hp * 0.5
				print("[itemtest] ally %s hp=%d/%d" % [ally.char_id, ally.hp, ally.stats.max_hp])
			"heal_ally":
				if ally != null:
					Effects.run([{"type": "heal", "amount": v}], {"caster": a, "team": a.team, "target": ally, "src_slot": "q", "ability": "test"})
					await _wait(0.3)
			"shield_ally":
				if ally != null:
					Effects.run([{"type": "shield", "amount": v, "duration": 3}], {"caster": a, "team": a.team, "target": ally, "src_slot": "q", "ability": "test"})
					await _wait(0.3)
			"ally_attack":
				if ally != null:
					ally.attack_target = b
					await _wait(v)
					ally.attack_target = null
			"minion":
				world.spawn("minion", {"team": 1, "lane": 0, "type": "melee", "pos": b.global_position + Vector2(60, 40), "scale": 1.0})
				await _wait(0.2)
			"kill_minion":
				var m = world.spawn("minion", {"team": 1, "lane": 0, "type": "melee", "pos": a.global_position + Vector2(80, -60), "scale": 1.0})
				await _wait(0.1)
				m.take_damage(m.hp - 1.0, null, "true", {"raw": true})
				a.attack_target = m
				await _wait(1.6)
				a.attack_target = null
				print("[itemtest] minion dead=%s gold=%.0f" % [str(not is_instance_valid(m) or m.dead), a.gold])
			"cc":
				var kind := arg if arg != "" else "stun"
				Effects.run([{"type": kind, "duration": 1.0, "amount": 0.4}], {"caster": a, "team": a.team, "target": b, "src_slot": "q", "ability": "test"})
				await _wait(0.2)
			"self_cc":
				var kind2 := arg if arg != "" else "stun"
				Effects.run([{"type": kind2, "duration": 1.5, "amount": 0.4}], {"caster": b, "team": b.team, "target": a, "src_slot": "q", "ability": "test"})
				await _wait(0.2)
			"kill":
				b.take_damage(99999.0, a, "true", {"ability": "q"})
				await _wait(0.5)
			"assist":
				b.take_damage(50.0, a, "true", {"ability": "q"})
				b.last_champion_hit = null
				b.take_damage(99999.0, null, "true", {})
				await _wait(0.5)
			"level":
				for k in maxi(int(v), 1):
					a.cheat("level")
				await _wait(0.1)
			"hp":
				a.hp = a.stats.max_hp * v
			"ehp":
				b.hp = b.stats.max_hp * v
			"mana":
				a.mana = a.stats.max_mana * v
			"far":
				b.teleport(a.global_position + Vector2(v, 0))
			"sum", "sum_self", "sum_ally", "sum_tower", "sum_try":
				var si := int(v)
				if what != "sum_try":
					a.sum_cd[si] = 0.0
				var st: Unit = b
				if what == "sum_self":
					st = a
				elif what == "sum_ally" and ally != null:
					st = ally
				elif what == "sum_tower":
					for s in world.structures:
						if s.team == a.team and not s.dead and not s.is_nexus and (st == b or s.global_position.distance_to(a.global_position) > st.global_position.distance_to(a.global_position)):
							st = s
				var sab = a.summoner_ability(si)
				print("[itemtest] summoner %d (%s) on %s -> %s  cd=%.1f" % [si, sab.name if sab != null else "-", st.display_name,
					str(a.use_summoner(si, st.global_position, st.net_id)), a.sum_cd[si]])
				await _wait(1.0)
			"steer":
				var dir := Vector2.ZERO if arg == "off" else Vector2.from_angle(deg_to_rad(v))
				a.command("steer", [dir])
				print("[itemtest] steer %s from %s" % [str(dir.snapped(Vector2(0.01, 0.01))), str(a.global_position.round())])
			"amove":
				var to := b.global_position + (b.global_position - a.global_position).normalized() * v
				a.command("amove", [to, "cursor"])
				await _wait(0.1)
				print("[itemtest] amove -> target %s amove %s" % [a.attack_target.display_name if is_instance_valid(a.attack_target) else "none", str(a.amove)])
			"cmd":
				a.command(arg, [])
			"move":
				a.move_goal = a.global_position + Vector2(v, 0)
				await _wait(absf(v) / maxf(a.stats.move_speed, 1.0) + 0.2)
			"wait":
				await _wait(v)
			"stats":
				_print_stats("A", a)
				_print_stats("B", b)
				if ally != null:
					_print_stats("Ally", ally)
			"buy":
				a.gold = 99999.0
				print("[itemtest] buy %s -> '%s'" % [arg, a.buy(arg)])
			"sell":
				print("[itemtest] sell %d -> '%s'" % [int(v), a.sell(int(v))])
			"combat_reset":
				a.combat_t = -100.0
				a.hurt_t = -100.0
			"home":
				a.teleport(world.map.spawn_point(a.team))
				await _wait(0.3)
			"back":
				a.teleport(spot)
				b.teleport(spot + Vector2(150, 0))
			_:
				print("[itemtest] UNKNOWN STEP ", what)
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
		c.items[slot] = c.new_instance(id)
		if Game.items[id].stack > 1:
			c.items[slot].n = Game.items[id].stack
		slot += 1
	c._items_changed()
	c.recompute_stats()


func _print_stats(label: String, c: Champion) -> void:
	var s: Dictionary = c.stats
	var ids := []
	for i in Champion.ITEM_SLOTS:
		if c.items[i] != null:
			var view := c.item_view(i)
			ids.append("%s(n=%s cd=%.1f)" % [c.items[i].id, str(view[0]), view[1]])
	print("[itemtest] %s %s lvl %d gold %d items=%s" % [label, c.char_id, c.level, c.gold, str(ids)])
	print("[itemtest]   hp %d/%d mana %d/%d ad %.1f ap %.1f as %.2f armor %.1f mr %.1f ms %.0f crit %.2f critdmg %.2f ah %.0f leth %.0f arpen %.2f mpen %.0f/%.2f ls %.2f omni %.2f hsp %.2f ten %.2f range %.0f" % [
		c.hp, s.max_hp, c.mana, s.max_mana, s.attack_damage, s.ability_power, s.attack_speed, s.armor, s.magic_resist, s.move_speed,
		s.crit_chance, s.crit_damage, s.ability_haste, s.lethality, s.armor_pen, s.magic_pen, s.magic_pen_percent, s.lifesteal, s.omnivamp,
		s.heal_power, s.tenacity, s.attack_range])
	var sts := []
	for st in c.statuses:
		sts.append("%s%s(%.1fs%s%s)" % [st.type, (":" + st.id) if st.has("id") else "", st.time, (" x%d" % st.stacks) if st.has("stacks") else "",
			(" amt=%.0f" % st.amount) if st.has("amount") and st.amount is float else ""])
	print("[itemtest]   statuses=%s counters=%s shield=%.0f bond=%.0f energy=%.0f cds=%s" % [str(sts), str(c.counters), c.shield, c.bond, c.energy,
		str(c.cooldowns.values().map(func(x): return snappedf(x, 0.1)))])
