class_name RuneState
extends RefCounted

var c: Champion
var picks: Array
var state := {}
var timers := {}
var unique := {}
var hits := {}
var keystone: int
var rotation := [8005, 8008, 8021, 8010, 8112, 8128, 9923, 8214, 8229, 8230, 8992, 8437, 8439, 8465, 8351, 8369, 8124, 8231, 8359]
var rotation_index := 0
var last_pos := Vector2.INF


func _init(champion: Champion, page: Dictionary) -> void:
	c = champion
	picks = page.major + page.minor + page.shards
	keystone = page.major[0]
	if keystone == 8358:
		rotation_index = c.team % rotation.size()


func has(id: int) -> bool:
	return picks.has(id) or (keystone == 8358 and rotation[rotation_index] == id)


func ready(id: int) -> bool:
	return has(id) and c.world.time >= float(timers.get(id, 0.0))


func proc(id: int, cooldown: float) -> void:
	timers[id] = c.world.time + cooldown
	if keystone == 8358 and id == rotation[rotation_index]:
		state.rotate = c.world.time + 8.0


func count(key: String, delta := 1, limit := 99999) -> int:
	state[key] = mini(int(state.get(key, 0)) + delta, limit)
	c.stats_dirty = true
	return state[key]


func buff(id: int, duration: float, add: Dictionary, mult := {}) -> void:
	c.add_status({"type": "buff", "id": "Rune %d" % id, "time": duration, "add": add, "mult": mult}, c, "rune:%d" % id)


func hit(t: Unit, amount: float, dtype := "adaptive") -> void:
	if dtype == "adaptive":
		dtype = "magic" if c.stats.ability_power > bonus_ad() else "physical"
	t.take_damage(amount, c, dtype, {"proc": true})


func bonus_ad() -> float:
	return c.stats.attack_damage - c.base_stats.attack_damage


func river(pos: Vector2) -> bool:
	for poly in c.world.map.rivers:
		if Geometry2D.is_point_in_polygon(pos, poly):
			return true
	return false


func adaptive(stats: Dictionary, value: float) -> void:
	if stats.ability_power > stats.attack_damage - c.base_stats.attack_damage or (is_equal_approx(stats.ability_power, stats.attack_damage - c.base_stats.attack_damage) and Champion.role_of(c.def) == "mage"):
		stats.ability_power += value
	else:
		stats.attack_damage += value * 0.6


func stats(add: Dictionary, mult: Dictionary) -> void:
	if has(5005): add.bonus_attack_speed += 0.10
	if has(5007): add.ability_haste += 8
	if has(5010): add.move_speed_bonus += 0.02
	if has(5011): add.max_hp += 65
	if has(5013):
		add.tenacity += 0.10
		add.slow_resist += 0.10
	add.max_hp += picks.count(5001) * 10 * mini(c.level, 18)
	add.max_hp += int(state.get("grasp", 0)) + int(state.get("biscuit_hp", 0))
	add.max_mana += int(state.get("manaflow", 0)) * 25
	var force := 9.0 * picks.count(5008)
	if has(8010) and c.world.time < float(state.get("conqueror_end", 0.0)):
		force += int(state.get("conqueror", 0)) * lerpf(1.8, 4.0, progress())
	var legend := minf(int(state.get("legend", 0)) / 25.0, 10.0)
	if has(9104): add.bonus_attack_speed += 0.03 + legend * 0.015
	if has(9103):
		add.lifesteal += legend * 0.0045
		if legend >= 10: add.max_hp += 85
	if has(9107): add.tenacity += 0.05 + legend * 0.025
	if has(8140): add.summoner_haste += int(state.get("mementos", 0)) * 3
	if has(8105) and c.world.time - c.combat_t >= 5.0: add.move_speed += 5 * unique.size()
	if has(8210): add.ability_haste += (5 if c.level >= 5 else 0) + (5 if c.level >= 8 else 0)
	if has(8234):
		add.move_speed += maxf(add.move_speed - c.base_stats.move_speed, 0.0) * 0.07
		add.move_speed_bonus = add.move_speed_bonus * 1.07 + 0.01
	if has(8233) and c.hp >= c.stats.max_hp * 0.7: force += lerpf(3.0, 30.0, progress())
	if has(8232) and river(c.global_position):
		add.move_speed += 10
		force += lerpf(5.0, 18.0, progress())
	if has(8236):
		var periods := floorf(c.world.time / 600.0)
		force += 4.0 * periods * (periods + 1.0)
	if has(8429) and c.world.time >= 720.0:
		for key in ["armor", "magic_resist"]:
			add[key] += 8
			mult[key] = float(mult.get(key, 1.0)) * 1.03
	if has(8451):
		add.max_hp += int(int(state.get("growth", 0)) / 8.0) * 3
		if int(state.get("growth", 0)) >= 120: mult.max_hp = float(mult.get("max_hp", 1.0)) * 1.035
	if has(8453): add.heal_power += 0.05
	if has(8347):
		add.summoner_haste += 18
		add.item_haste += 10
	if has(8134): add.item_haste += 20 + 6 * unique.size()
	if state.get("shoes", false): add.move_speed += 10
	if has(8316):
		var types := {}
		for i in c.items.size():
			var item = c.item_def(i)
			if item != null:
				for key in item.stats.keys() + item.stats_mult.keys(): types[key] = true
		add.ability_haste += types.size()
		force += 20 if types.size() >= 10 else (8 if types.size() >= 5 else 0)
	adaptive(add, force)


func progress() -> float:
	return clampf((c.level - 1) / 17.0, 0.0, 1.0)


func pre_damage(t: Unit, info: Dictionary, tags: Dictionary) -> void:
	if has(8224) and tags.get("ability") == "r": info.amount *= 1.08 if tags.get("aoe", false) else 1.12
	if t is Minion:
		var uses: int = state.get("demat_" + t.minion_type, 0)
		if uses > 0: info.amount *= 1.03 + 0.03 * uses
	if not t.is_champion:
		return
	if has(8014) and t.hp < t.stats.max_hp * 0.4: info.amount *= 1.08
	if has(8017) and t.hp > t.stats.max_hp * 0.6: info.amount *= 1.08
	if has(8299) and c.hp < c.stats.max_hp * 0.6: info.amount *= 1.05 + 0.06 * clampf((0.6 - c.hp / c.stats.max_hp) / 0.3, 0.0, 1.0)
	if has(8005) and c.world.time < float(state.get("pta_end", 0.0)): info.amount *= 1.08
	if has(8369) and c.world.time < float(state.get("first_end", 0.0)):
		c.add_gold(float(info.amount) * (0.035 if c.attack_def.ranged else 0.05))
		info.amount *= 1.07


func defend(src: Unit, info: Dictionary, tags: Dictionary) -> void:
	if not src.is_champion or src.team == c.team or tags.get("proc", false):
		return
	if ready(8369) and c.world.time >= float(state.get("first_end", 0.0)): proc(8369, 23.0)
	if ready(8473):
		proc(8473, 55.0)
		state.plate_end = c.world.time + 1.5
		state.plate_target = src.net_id
		state.plates = 3
	elif c.world.time < float(state.get("plate_end", 0.0)) and src.net_id == state.get("plate_target") and int(state.get("plates", 0)) > 0:
		count("plates", -1)
		info.amount -= lerpf(30.0, 60.0, progress())
	if c.world.time < float(state.get("glacial_%d" % src.net_id, 0.0)): info.amount *= 0.85
	for ally in c.world.champions.values():
		if ally != c and not ally.dead and ally.team == c.team and ally.rune_state != null and ally.rune_state.ready(8465) and c.global_position.distance_to(ally.global_position) <= 350:
			ally.rune_state.guard(c, float(info.amount), c.hp)
	if ready(8465):
		for ally in c.world.champions.values():
			if ally != c and not ally.dead and ally.team == c.team and c.global_position.distance_to(ally.global_position) <= 350:
				guard(ally, float(info.amount), c.hp)
				break


func guard(ally: Champion, damage: float, victim_hp: float) -> void:
	if damage < lerpf(45.0, 100.0, progress()) and victim_hp > damage:
		return
	proc(8465, lerpf(90.0, 40.0, progress()))
	var amount: float = lerpf(45.0, 120.0, progress()) + c.stats.ability_power * 0.15
	give_shield(c, amount, 2.0, 8465)
	give_shield(ally, amount, 2.0, 8465)


func give_shield(target: Unit, amount: float, duration: float, id: int) -> void:
	target.add_status({"type": "shield", "time": duration, "amount": amount}, c, "rune:%d:%d" % [id, c.net_id])


func dealt(t: Unit, amount: float, tags: Dictionary) -> void:
	if t.team == c.team or tags.get("proc", false):
		return
	var attack := bool(tags.get("attack", false) or tags.get("onhit", false))
	var slot := str(tags.get("ability", ""))
	var spell: bool = slot in ["q", "w", "e", "r"] or tags.get("spell", false)
	var now: float = c.world.time
	var ranged: bool = c.attack_def.ranged
	grasp_combat()
	if t.hp <= 0.0:
		return
	if t is Tower and not t.is_inhibitor and not t.is_nexus and attack and ready(8446):
		var key := "tower_%d" % t.net_id
		if count(key) >= 3:
			state[key] = 0
			proc(8446, 30)
			hit(t, (50.0 if ranged else 85.0) + c.stats.max_hp * (0.2 if ranged else 0.28), "physical")
	if attack and ready(8021) and float(state.get("fleet", 0.0)) + 6.0 >= 100.0 and not t.is_structure:
		state.fleet = 0.0
		c.heal(lerpf(10.0, 75.0, progress()) * (1.0 if t.is_champion else 0.25), c)
		buff(8021, 1, {"move_speed_bonus": 0.2})
		proc(8021, 0)
	if not t.is_champion:
		return
	if ready(8369) and now >= float(state.get("first_end", 0.0)):
		proc(8369, lerpf(25.0, 15.0, progress()))
		state.first_end = now + 3.0
		c.add_gold(10.0 + amount * 0.04)
	if has(8009) and c.uses_mana() and ready(8009):
		proc(8009, 8)
		c.restore_mana(lerpf(6.0, 50.0, progress()))
	if spell and ready(8226) and c.uses_mana() and int(state.get("manaflow", 0)) < 10:
		proc(8226, 15)
		count("manaflow")
	if attack:
		attack_champion(t)
	if ready(8128) and t.hp < t.stats.max_hp * 0.5:
		proc(8128, 35)
		hit(t, 30 + 11 * count("souls") + 0.05 * c.stats.ability_power + 0.1 * bonus_ad())
	if ready(8139):
		proc(8139, 20)
		c.heal(lerpf(16.0, 40.0, progress()) + 0.05 * c.stats.ability_power + 0.1 * bonus_ad(), c)
	if ready(8126) and impaired(t):
		proc(8126, 4)
		hit(t, lerpf(10.0, 45.0, progress()), "true")
	if ready(8143) and now < float(state.get("dash_end", 0.0)):
		proc(8143, 10)
		hit(t, lerpf(20.0, 80.0, progress()), "true")
	if ready(8214):
		proc(8214, 2.5)
		hit(t, lerpf(10.0, 50.0, progress()) + 0.05 * c.stats.ability_power, "magic")
	if spell:
		if ready(8229):
			proc(8229, lerpf(20.0, 8.0, progress()))
			state.comet = {"at": t.global_position, "when": now + 0.65}
		if ready(8237):
			proc(8237, 10)
			state.scorch = {"id": t.net_id, "when": now + 1.0}
		if has(8992):
			var key := "df_%d" % t.net_id
			var burn: Dictionary = state.get(key, {"start": now, "end": now, "tick": now + 1.0})
			if burn.end < now: burn = {"start": now, "end": now, "tick": now + 1.0}
			burn.end = maxf(burn.end, now + (1.0 if tags.get("dot", false) else (2.0 if tags.get("aoe", false) else 4.0)))
			state[key] = burn
			if ready(8992): proc(8992, 0.5)
	if spell or attack:
		if has(8010):
			if now >= float(state.get("conqueror_end", 0.0)): state.conqueror = 0
			state.conqueror_end = now + 5.0
			if count("conqueror", 1 if ranged and attack else 2, 12) == 12:
				c.heal(amount * (0.05 if ranged else 0.08), c, false)
				if ready(8010): proc(8010, 0)
		if ready(8112) or ready(8231):
			multi_hit(t, amount, "attack" if attack else slot)
	if ready(8230):
		var key := "burst_%d" % t.net_id
		var burst: Array = state.get(key, [])
		burst = burst.filter(func(data): return now - data[0] <= 3.0)
		burst.append([now, amount])
		state[key] = burst
		if burst.reduce(func(sum, data): return sum + data[1], 0.0) >= t.stats.max_hp * 0.25:
			state.erase(key)
			proc(8230, lerpf(20.0, 10.0, progress()))
			buff(8230, 4.0, {"move_speed_bonus": 0.36 if ranged else 0.48, "slow_resist": 0.50})


func multi_hit(t: Unit, amount: float, slot: String) -> void:
	var now: float = c.world.time
	var recent: Array = hits.get(t.net_id, [])
	recent = recent.filter(func(data): return now - data[0] <= 3.0)
	if slot == "attack" or not recent.any(func(data): return data[1] == slot):
		recent.append([now, slot, amount])
	hits[t.net_id] = recent
	var id := 0
	if ready(8112) and recent.size() >= 3:
		proc(8112, lerpf(25, 20, progress()))
		hit(t, lerpf(50.0, 190.0, progress()) + c.stats.ability_power * 0.1 + bonus_ad() * 0.1)
	if ready(8231) and recent.size() >= 3: id = 8231
	if id != 0:
		proc(id, lerpf(25.0, 10.0, progress()))
		buff(id, 3.0, {"move_speed_bonus": lerpf(0.30, 0.60, progress()) * (0.75 if c.attack_def.ranged else 1.0), "slow_resist": 0.75})


func attack_champion(t: Unit) -> void:
	var now: float = c.world.time
	var ranged: bool = c.attack_def.ranged
	if ready(8005):
		if t.net_id != state.get("pta_target") or now > float(state.get("pta_hit", 0.0)) + 4.0: state.pta = 0
		state.pta_target = t.net_id
		state.pta_hit = now
		if count("pta") >= 3:
			state.pta = 0
			state.pta_end = now + 6.0
			proc(8005, 6)
			hit(t, lerpf(40.0, 160.0, progress()))
	if has(8008):
		if now >= float(state.get("tempo_end", 0.0)): state.tempo = 0
		state.tempo_end = now + 6.0
		var stacks := count("tempo", 1, 6)
		buff(8008, 6, {"bonus_attack_speed": (0.04 if ranged else 0.06) * stacks})
		if stacks == 6:
			hit(t, lerpf(6 if ranged else 9, 24 if ranged else 30, progress()) * (1.0 + c.stats.bonus_attack_speed))
			if ready(8008): proc(8008, 0)
	if ready(9923):
		proc(9923, 12)
		state.blades = 2
		buff(9923, 3, {"bonus_attack_speed": 0.8 if ranged else 1.1, "attack_speed_cap": 3.5})
	elif int(state.get("blades", 0)) > 0 and count("blades", -1) == 0:
		c.statuses = c.statuses.filter(func(s): return s.key != "rune:9923")
	if ready(8437) and now - float(state.get("grasp_start", now)) >= 4.0:
		proc(8437, 4)
		var m := 0.6 if ranged else 1.0
		hit(t, c.stats.max_hp * 0.035 * m, "magic")
		c.heal(c.stats.max_hp * 0.013 * m, c)
		count("grasp", 4 if ranged else 7)
	if has(8401) and float(state.get("bash", 0.0)) > 0 and now < float(state.get("bash_end", 0.0)):
		hit(t, lerpf(15.0, 50.0, progress()) + c.stats.max_hp * 0.025 + float(state.bash) * 0.15)
		state.bash = 0.0
	if has(8359) and int(state.get("klepto", 0)) > 0 and now < float(state.get("klepto_end", 0.0)):
		count("klepto", -1)
		c.add_gold(5)
		if count("klepto_hits") % 3 == 0: count("klepto_potions")
		if ready(8359): proc(8359, 0)
	if has(8124) and not state.get("predator", {}).is_empty():
		var active: Dictionary = state.predator
		if now >= active.start and now < active.end:
			hit(t, lerpf(40.0, 170.0, progress()))
		state.predator = {}
		c.statuses = c.statuses.filter(func(s): return s.key != "rune:8124")


func grasp_combat() -> void:
	if not has(8437):
		return
	var now: float = c.world.time
	if now > float(state.get("grasp_last", -10.0)) + 4.0:
		state.grasp_start = now
	state.grasp_last = now


func impaired(t: Unit) -> bool:
	return t.statuses.any(func(s): return s.type in Unit.CC_TYPES) or (t.forced != null and not t.forced.dash)


func crowd_control(t: Unit, hard: bool) -> void:
	if t.team == c.team or not t.is_champion:
		return
	if ready(8463):
		proc(8463, 20)
		var amount := lerpf(10.0, 20.0, progress())
		c.heal(amount, c)
		for ally in c.world.query(c.global_position, 700.0, c.team, "allies"):
			if ally != c and ally.is_champion:
				ally.heal(amount, c)
				break
	if hard and ready(8439):
		proc(8439, 20)
		buff(8439, 2.5, {"armor": 35.0, "magic_resist": 35.0})
		state.aftershock = c.world.time + 2.5
	if hard and ready(8351):
		proc(8351, 25)
		state.glacial = {"pos": t.global_position, "end": c.world.time + 3.0, "id": t.net_id}


func support(t: Unit) -> void:
	if t != c and t.team == c.team and t.is_champion and ready(8214):
		proc(8214, 2.5)
		give_shield(t, lerpf(30.0, 80.0, progress()) + 0.05 * c.stats.ability_power, 2, 8214)


func on_kill(t: Unit) -> void:
	if has(9101): c.heal(lerpf(2.0, 20.0, progress()), c)
	if t is Minion or t is Monster: count("legend", 2 if t is Monster else 1, 250)


func takedown(t: Unit) -> void:
	count("legend", 25, 250)
	count("mementos", 1, 18)
	count("takedowns")
	if not unique.has(t.net_id):
		unique[t.net_id] = true
		if has(8135): c.add_gold(30.0 + 20.0 * (unique.size() - 1))
	if has(9111):
		c.heal(maxf(c.stats.max_hp - c.hp, 0.0) * 0.05 + c.stats.max_hp * 0.025, c)
		c.add_gold(20)
	if has(8009): c.restore_mana(c.stats.max_mana * 0.15)
	if has(8128) and timers.has(8128): timers[8128] = minf(timers[8128], c.world.time + 1.5)
	if has(8224): c.cooldowns.r *= 0.93
	if has(8210) and c.level >= 11:
		for slot in ["q", "w", "e"]: c.cooldowns[slot] *= 0.8


func tick(delta: float) -> void:
	var now: float = c.world.time
	if keystone == 8358:
		if now >= float(state.get("rotate", 25.0 + float(state.get("rotation_started", 0.0)))):
			rotation_index = (rotation_index + 1) % rotation.size()
			state.erase("rotate")
			state.rotation_started = now
	if has(8021) and last_pos != Vector2.INF:
		state.fleet = minf(float(state.get("fleet", 0.0)) + last_pos.distance_to(c.global_position) / 24.0, 100.0)
	last_pos = c.global_position
	if c.forced != null and c.forced.dash: state.dash_end = now + 4.0
	if int(state.get("manaflow", 0)) == 10:
		c.restore_mana(maxf(c.stats.max_mana - c.mana, 0.0) * delta * 0.002)
	if state.has("comet") and now >= state.comet.when:
		for t in c.world.query(state.comet.at, 140, c.team):
			hit(t, lerpf(30.0, 130.0, progress()) + 0.05 * c.stats.ability_power + 0.1 * bonus_ad())
		state.erase("comet")
	if state.has("scorch") and now >= state.scorch.when:
		var target = c.world.entities.get(state.scorch.id)
		if is_instance_valid(target): hit(target, lerpf(20, 40, progress()), "magic")
		state.erase("scorch")
	if state.has("aftershock") and now >= state.aftershock:
		for t in c.world.query(c.global_position, 350, c.team):
			hit(t, lerpf(35.0, 80.0, progress()) + 0.08 * (c.stats.max_hp - c.base_stats.max_hp), "magic")
		state.erase("aftershock")
	if state.has("glacial"):
		if now >= state.glacial.end:
			state.erase("glacial")
		else:
			for t in c.world.query(state.glacial.pos, 315, c.team):
				t.add_status({"type": "slow", "time": 0.25, "amount": 0.30}, c, "rune:glacial")
			for ally in c.world.champions.values():
				if ally != c and ally.team == c.team and ally.rune_state != null and ally.global_position.distance_to(state.glacial.pos) < 450:
					ally.rune_state.state["glacial_%d" % state.glacial.id] = now + 0.25
	for key in state.keys():
		if not key.begins_with("df_"): continue
		var burn: Dictionary = state[key]
		if now >= burn.tick and burn.tick <= burn.end:
			var target = c.world.entities.get(int(key.substr(3)))
			if is_instance_valid(target) and not target.dead:
				hit(target, (lerpf(3.0, 12.0, progress()) + 0.025 * c.stats.ability_power + 0.07 * bonus_ad()) * (1.75 if now - burn.start >= 3.0 else 1.0), "magic")
			burn.tick += 1.0
		if now >= burn.end: state.erase(key)
	if now >= float(state.get("periodic", 0.0)):
		state.periodic = now + 0.25
		periodic(now)


func periodic(now: float) -> void:
	c.stats_dirty = true
	if has(8242) and impaired(c): buff(8242, 2.25, {"armor": 10.0, "magic_resist": 10.0})
	if has(8410) and c.move_goal is Vector2:
		for enemy in c.world.query(c.global_position, 1000, c.team):
			if enemy.is_champion and enemy.visible_to(c.team) and impaired(enemy) and c.global_position.direction_to(c.move_goal).dot(c.global_position.direction_to(enemy.global_position)) > 0.65:
				var from_self: bool = enemy.statuses.any(func(s): return s.type in Unit.CC_TYPES and s.source == c)
				buff(8410, 0.3, {"move_speed_bonus": 0.15 if from_self else 0.075})
				break
	if ready(8137):
		for ward in c.world.query(c.global_position, 550, c.team, "enemies", false, true):
			if ward.is_ward and not ward.visible_to(c.team):
				proc(8137, 250)
				c.world.fx("notice", {"peer": c.peer, "text": "Sixth Sense: enemy ward nearby"})
				if c.level >= 11: ward.add_status({"type": "reveal", "time": 10.0, "team": c.team}, c, "rune:sixth")
				break
	if has(8304) and not state.get("shoes", false) and now >= 720.0 - 45.0 * int(state.get("takedowns", 0)):
		if c.has_item("boots") or _grant_item("boots"):
			state.shoes = true
	if has(8345):
		var due := mini(floori(now / 120.0), 3)
		if int(state.get("delivered", 0)) < due:
			count("delivered")
			count("biscuits")
	if int(state.get("klepto_potions", 0)) > 0 and _grant_item("health_potion"): count("klepto_potions", -1)
	if c.is_bot:
		if c.hp < c.stats.max_hp * 0.55 and int(state.get("biscuits", 0)) > 0: action("biscuit", [])
		if ready(8124) and c.attack_target != null: action("predator", [])
		if ready(8360) and c.summoners.size() == 2 and c.sum_cd[1] > 45 and can_swap(): action("spellbook", [1, "heal" if not c.summoners.has("heal") else "ghost"])
		if has(8317) and c.attack_target is Minion: action("dematerialize", [c.attack_target.net_id])


func _grant_item(id: String) -> bool:
	if not Game.items.has(id): return false
	var slot := c._stack_slot(id)
	if slot >= 0:
		c.items[slot].n += 1
	else:
		slot = c._free_slot()
		if slot < 0: return false
		c.items[slot] = c.new_instance(id)
	c._items_changed()
	return true


func can_swap() -> bool:
	return c.world.time >= 360.0 and c.world.time - c.combat_t >= 5.0 and not state.has("swap")


func action(name: String, args: Array) -> bool:
	if c.dead or c.puppet: return false
	match name:
		"biscuit", "sell_biscuit":
			if not has(8345) or int(state.get("biscuits", 0)) <= 0: return false
			if name == "sell_biscuit":
				if not c.can_shop(): return false
				c.add_gold(5)
			else:
				var missing: float = 1.0 - c.hp / c.stats.max_hp
				c.heal((20 + 0.02 * c.stats.max_hp) * (1 + missing), c)
			count("biscuits", -1)
			count("biscuit_hp", 30)
		"dematerialize":
			if not has(8317) or c.world.time < 180.0 or int(state.get("demat", 0)) >= 3 or args.size() != 1 or not args[0] is int: return false
			var target = c.world.entities.get(args[0])
			if not target is Minion or target.dead or target.team == c.team or not target.visible_to(c.team) or c.global_position.distance_to(target.global_position) > 550.0: return false
			count("demat")
			count("demat_" + target.minion_type)
			target.die(c)
		"predator":
			if not ready(8124) or c.world.time - c.combat_t < 4.0: return false
			var boots := false
			for i in c.items.size():
				var item = c.item_def(i)
				if item != null and item.rarity == "boots": boots = true
			if not boots: return false
			state.predator = {"start": c.world.time + 1.0, "end": c.world.time + 10.0}
			buff(8124, 10.0, {"move_speed_bonus": 0.35})
			proc(8124, lerpf(120.0, 60.0, progress()))
		"spellbook":
			if not ready(8360) or not can_swap() or args.size() != 2 or not args[0] is int or not args[1] is String: return false
			var i: int = args[0]
			var id: String = args[1]
			var recent: Array = state.get("spells", [])
			if i < 0 or i >= c.summoners.size() or not Game.summoners.has(id) or c.summoners.has(id) or recent.has(id): return false
			state.swap = {"slot": i, "id": c.summoners[i], "until": c.world.time + c.sum_cd[i], "total": c.sum_cd_total[i]}
			recent.append(id)
			if recent.size() > 3: recent.pop_front()
			state.spells = recent
			var seen: Dictionary = state.get("unique_spells", {})
			seen[id] = true
			state.unique_spells = seen
			c.summoners[i] = id
			c.sum_cd[i] = 0.0
			c.sum_recast[i] = false
			proc(8360, maxf(120.0, 300.0 - 25.0 * (seen.size() - 1)))
		_: return false
	return true


func used_summoner(slot: int) -> void:
	if has(8275): buff(8275, 2, {"move_speed_bonus": 0.20})
	var swap: Dictionary = state.get("swap", {})
	if not swap.is_empty() and slot == swap.slot:
		c.summoners[slot] = swap.id
		c.sum_cd[slot] = maxf(0.0, swap.until - c.world.time)
		c.sum_cd_total[slot] = swap.total
		c.sum_recast[slot] = false
		state.erase("swap")
