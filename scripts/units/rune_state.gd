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
		roll_keystone()


func has(id: int) -> bool:
	return picks.has(id) or (keystone == 8358 and rotation[rotation_index] == id)


func ready(id: int) -> bool:
	return has(id) and c.world.time >= float(timers.get(id, 0.0))


func proc(id: int, cooldown: float) -> void:
	timers[id] = c.world.time + cooldown
	if keystone == 8358 and id == rotation[rotation_index]:
		state.rotate = c.world.time + lerpf(9.0 if c.attack_def.ranged else 5.0, 7.0 if c.attack_def.ranged else 3.0, progress())


func roll_keystone() -> void:
	var pool := [8005, 8008, 8021, 8010, 8112, 8128, 9923, 8214, 8229, 8437, 8465, 8351, 8231]
	if owns_boots(): pool.append(8124)
	if ["q", "w", "e"].any(func(slot): return c.ranks[slot] > 0 and Runes.can_immobilize(c.def.abilities[slot].effects)): pool.append(8439)
	pool.erase(rotation[rotation_index])
	rotation_index = rotation.find(pool.pick_random())
	timers.erase(rotation[rotation_index])
	state.erase("rotate")
	state.rotation_started = c.world.time


func owns_boots() -> bool:
	for i in c.items.size():
		var item = c.item_def(i)
		if item != null and item.rarity == "boots": return true
	return false


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
	add.max_hp += int(state.get("grasp", 0))
	if c.base_stats.max_mana > 0.0:
		add.max_mana += int(state.get("biscuit_mana", 0)) * 50
	var force := 9.0 * picks.count(5008)
	if has(8010) and c.world.time < float(state.get("conqueror_end", 0.0)):
		force += int(state.get("conqueror", 0)) * lerpf(2.0, 10.0, progress())
	var legend := mini(floori(int(state.get("legend", 0)) / 25.0), 10)
	if has(9104): add.bonus_attack_speed += 0.03 + legend * 0.015
	if has(9103): add.lifesteal += mini(floori(int(state.get("legend", 0)) / 25.0), 20) * 0.006
	if has(9107): add.tenacity += 0.05 + legend * 0.025
	if has(8140): add.summoner_haste += int(state.get("mementos", 0)) * 3
	if has(8105) and c.world.time - c.combat_t >= 5.0: add.move_speed += 10 + 9 * unique.size()
	var vision_stacks := int(state.get("vision_stacks", 0))
	if has(8138): force += vision_stacks + (10 if vision_stacks >= 20 else 0)
	if has(8136) or has(8120): force += vision_stacks * 2 + (10 if vision_stacks >= 10 else 0)
	if has(8339): add.max_hp += 100
	if has(8472):
		if int(state.get("takedowns", 0)) < 4: add.max_hp += 60
		else: force += 15
	if has(8430): add.armor += 5
	if has(8435): add.magic_resist += 6
	if has(8401) and c.statuses.any(func(s): return s.type == "shield" and s.amount > 0.0):
		add.armor += lerpf(1.0, 10.0, progress())
		add.magic_resist += lerpf(1.0, 10.0, progress())
	if has(8242):
		var resist := 0.10 + 0.20 * clampf((1.0 - c.hp / c.stats.max_hp) / 0.70, 0.0, 1.0)
		add.tenacity += resist
		add.slow_resist += resist
	if c.world.time < float(state.get("coup_end", 0.0)): force += 15
	if has(8210): add.ability_haste += (5 if c.level >= 5 else 0) + (5 if c.level >= 8 else 0)
	if has(8234): add.move_speed_bonus += 0.015
	if has(8233) and c.hp > c.stats.max_hp * 0.7: force += lerpf(5.0, 40.0, progress())
	if has(8232) and river(c.global_position):
		add.move_speed += 25
		force += lerpf(5.0, 30.0, progress())
	if has(8236):
		var periods := floorf(c.world.time / 600.0)
		force += 4.0 * periods * (periods + 1.0)
	if has(8429) and c.world.time >= 720.0:
		for key in ["armor", "magic_resist"]:
			add[key] += 9
			mult[key] = float(mult.get(key, 1.0)) * 1.05
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
		force += 25 if types.size() >= 10 else (10 if types.size() >= 5 else 0)
	adaptive(add, force)


func progress() -> float:
	return clampf((c.level - 1) / 17.0, 0.0, 1.0)


func pre_damage(t: Unit, info: Dictionary, tags: Dictionary) -> void:
	if t.team == c.team:
		return
	if has(8224) and tags.get("ability") == "r": info.amount *= 1.09 if tags.get("aoe", false) else 1.14
	if has(8339) and c.world.time < 600.0 and (t.is_champion or t is Monster): info.amount *= 0.90
	if t is Minion:
		var uses: int = state.get("demat_" + t.minion_type, 0)
		if uses > 0: info.amount *= 1.03 + 0.01 * uses
	if not t.is_champion:
		return
	if has(8014) and t.hp < t.stats.max_hp * 0.4: info.amount *= 1.10
	if has(8017) and t.hp > t.stats.max_hp * 0.6: info.amount *= 1.08
	if has(8299) and c.hp < c.stats.max_hp * 0.6: info.amount *= 1.05 + 0.07 * clampf((0.6 - c.hp / c.stats.max_hp) / 0.3, 0.0, 1.0)
	if ready(8369) and not tags.get("proc", false) and c.world.time <= float(state.get("first_response", INF)):
		proc(8369, lerpf(25.0, 15.0, progress()))
		state.first_end = c.world.time + 3.0
		c.add_gold(15)
	if has(8369) and c.world.time < float(state.get("first_end", 0.0)):
		c.add_gold(float(info.amount) * 0.08 * (0.35 if c.attack_def.ranged else 0.50))
		info.amount *= 1.08


func conqueror_active() -> bool:
	return has(8010) and int(state.get("conqueror", 0)) == 5 and c.world.time < float(state.get("conqueror_end", 0.0))


func check_orb(amount: float, dtype: String) -> void:
	if ready(8225) and dtype == "magic" and c.hp - maxf(amount - c.shield, 0.0) < c.stats.max_hp * 0.30:
		proc(8225, 60.0)
		c.add_status({"type": "shield", "time": 4.0, "dtype": "magic", "amount": lerpf(40.0, 120.0, progress()) + 0.10 * c.stats.ability_power + 0.15 * bonus_ad()}, c, "rune:orb")
		return


func defend(src: Unit, info: Dictionary, tags: Dictionary, dtype: String) -> void:
	check_orb(float(info.amount), dtype)
	if not src.is_champion or src.team == c.team or tags.get("proc", false):
		return
	if ready(8369):
		var deadline := float(state.get("first_response", INF))
		if deadline == INF: state.first_response = c.world.time + 0.25
	if ready(8473):
		proc(8473, 45.0)
		state.plate_end = c.world.time + 5.0
		state.plate_target = src.net_id
		state.plates = 3
	elif c.world.time < float(state.get("plate_end", 0.0)) and src.net_id == state.get("plate_target") and int(state.get("plates", 0)) > 0:
		count("plates", -1)
		info.amount -= lerpf(20.0, 50.0, progress())
	if c.world.time < float(state.get("glacial_%d" % src.net_id, 0.0)): info.amount *= 0.85
	for ally in c.world.champions.values():
		if ally != c and not ally.dead and ally.team == c.team and ally.rune_state != null and ally.rune_state.ready(8465) and ally.rune_state.is_guarding(c):
			ally.rune_state.guard(c, float(info.amount), c.hp)
	if ready(8465):
		for ally in c.world.champions.values():
			if ally != c and not ally.dead and ally.team == c.team and is_guarding(ally):
				guard(ally, float(info.amount), c.hp)
				break


func guard(ally: Champion, damage: float, victim_hp: float) -> void:
	var key := "guard_damage_%d" % ally.net_id
	var window: Dictionary = state.get(key, {"total": 0.0, "end": 0.0})
	if c.world.time >= window.end: window = {"total": 0.0, "end": c.world.time + 2.5}
	window.total += damage
	state[key] = window
	if window.total < lerpf(90.0, 250.0, progress()) and victim_hp > damage:
		return
	proc(8465, lerpf(70.0, 40.0, progress()))
	var amount: float = lerpf(80.0, 200.0, progress()) + c.stats.ability_power * 0.25 + 0.12 * (c.stats.max_hp - c.base_stats.max_hp)
	give_shield(c, amount, 1.5, 8465)
	give_shield(ally, amount, 1.5, 8465)


func is_guarding(ally: Unit) -> bool:
	return c.global_position.distance_to(ally.global_position) <= 350.0 or c.world.time < float(state.get("guard_%d" % ally.net_id, 0.0))


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
	if attack and c.is_champion:
		for mark in t.statuses:
			if mark.get("id") != "font_of_life" or not is_instance_valid(mark.source) or mark.source == c or mark.source.team != c.team:
				continue
			c.add_status({"type": "hot", "time": 2.0, "tick": 0.5, "interval": 0.5,
				"amount": (5.0 + 0.01 * mark.source.stats.max_hp) / 2.0}, mark.source, "rune:font_heal:%d" % mark.source.net_id)
	if t.hp <= 0.0:
		return
	if t is Tower and attack and ready(8446):
		var key := "tower_%d" % t.net_id
		if now - float(state.get(key, now)) >= 4.0:
			state.erase(key)
			proc(8446, 45)
			hit(t, 175.0 + c.stats.max_hp * 0.30, "physical")
	if attack and ready(8021) and float(state.get("fleet", 0.0)) + 6.0 >= 100.0 and not t.is_structure:
		state.fleet = -6.0
		var heal_amount := lerpf(3.0, 60.0, progress()) + 0.30 * bonus_ad() + 0.40 * float(c.stats.ability_power)
		if t is Minion: heal_amount *= 0.30 if ranged else 0.60
		if tags.get("crit", false): heal_amount *= 1.0 + 0.4 * (c.stats.crit_damage - 1.0)
		c.heal(heal_amount, c)
		buff(8021, 1, {"move_speed_bonus": 0.30})
		proc(8021, 0)
	if not t.is_champion:
		return
	if attack:
		attack_champion(t)
	if (attack or spell) and state.has("predator"):
		var active: Dictionary = state.predator
		if now >= active.start and now < active.end:
			state.erase("predator")
			c.stats_dirty = true
			hit(t, lerpf(40.0, 120.0, progress()) + 0.20 * bonus_ad() + 0.10 * c.stats.ability_power)
	if ready(8128) and t.hp < t.stats.max_hp * 0.5:
		proc(8128, 45)
		var souls := int(state.get("souls", 0))
		count("souls")
		hit(t, lerpf(50.0, 80.0, progress()) + 8 * souls + 0.15 * c.stats.ability_power + 0.25 * bonus_ad())
	if ready(8139):
		proc(8139, 20)
		c.heal(lerpf(18.0, 35.0, progress()) + 0.10 * c.stats.ability_power + 0.20 * bonus_ad(), c)
	if ready(8126) and impaired(t):
		proc(8126, 4)
		hit(t, lerpf(15.0, 40.0, progress()), "true")
	if ready(8143) and now < float(state.get("dash_end", 0.0)):
		proc(8143, 4)
		buff(8143, 5, {"lethality": 10.0, "magic_pen": 8.0})
	if (attack or spell) and ready(8214):
		proc(8214, 2.5)
		hit(t, lerpf(20.0, 60.0, progress()) + 0.10 * c.stats.ability_power + 0.15 * bonus_ad())
	if spell:
		if ready(8229):
			proc(8229, lerpf(20.0, 8.0, progress()))
			state.comet = {"at": t.global_position, "when": now + 0.65}
		elif has(8229):
			var reduction := 0.05 if tags.get("dot", false) else (0.10 if tags.get("aoe", false) else 0.20)
			timers[8229] = now + (float(timers[8229]) - now) * (1.0 - reduction)
		if ready(8237):
			proc(8237, 20)
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
			state.conqueror_end = now + (2.0 if ranged else 8.0)
			if (attack or not tags.get("dot", false)) and count("conqueror", 1, 5) == 5 and ready(8010):
				proc(8010, 0)
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
	var window := 4.0 if has(8231) else 3.0
	recent = recent.filter(func(data): return now - data[0] <= window)
	if slot == "attack" or not recent.any(func(data): return data[1] == slot):
		recent.append([now, slot, amount])
	hits[t.net_id] = recent
	var id := 0
	if ready(8112) and recent.size() >= 3:
		proc(8112, lerpf(50.0, 25.0, progress()))
		hit(t, lerpf(50.0, 220.0, progress()) + c.stats.ability_power * 0.30 + bonus_ad() * 0.50)
	if ready(8231) and recent.size() >= 3: id = 8231
	if id != 0:
		proc(id, 15.0)
		var speed := lerpf(0.25, 0.40, progress()) if c.attack_def.ranged else lerpf(0.40, 0.60, progress())
		buff(id, 3.0, {"move_speed_bonus": speed, "slow_resist": 0.75})


func attack_champion(t: Unit) -> void:
	var now: float = c.world.time
	var ranged: bool = c.attack_def.ranged
	if ready(8005):
		if t.net_id != state.get("pta_target") or now > float(state.get("pta_hit", 0.0)) + 4.0: state.pta = 0
		state.pta_target = t.net_id
		state.pta_hit = now
		if count("pta") >= 3:
			state.pta = 0
			proc(8005, 6)
			hit(t, lerpf(30.0, 120.0, progress()))
			t.add_status({"type": "mark", "id": "press_the_attack", "time": 6.0}, c, "rune:pta")
	if has(8008):
		if now >= float(state.get("tempo_end", 0.0)): state.tempo = 0
		state.tempo_end = now + 6.0
		var stacks := count("tempo", 1, 6)
		var attack_speed := lerpf(0.05, 0.09, progress()) if ranged else lerpf(0.10, 0.15, progress())
		var bonuses := {"bonus_attack_speed": attack_speed * stacks}
		if stacks == 6:
			bonuses.attack_range = 75.0 if ranged else 50.0
			bonuses.attack_speed_cap = 100.0
			if ready(8008): proc(8008, 0)
		buff(8008, 6, bonuses)
	if ready(8437) and now - float(state.get("grasp_start", now)) >= 4.0:
		proc(8437, 4)
		var m := 0.6 if ranged else 1.0
		hit(t, c.stats.max_hp * 0.035 * m, "magic")
		c.heal(c.stats.max_hp * 0.013 * m, c)
		count("grasp", 3 if ranged else 5)
	if has(8401) and float(state.get("bash", 0.0)) > 0 and now < float(state.get("bash_end", 0.0)):
		hit(t, lerpf(5.0, 30.0, progress()) + (c.stats.max_hp - c.base_stats.max_hp) * 0.015 + float(state.bash) * 0.085)
		state.bash = 0.0
	if has(8359) and int(state.get("klepto", 0)) > 0 and now < float(state.get("klepto_end", 0.0)):
		count("klepto", -1)
		c.add_gold(5)
		if randf() < 0.30: count("klepto_potions")
		if ready(8359): proc(8359, 0)


func launch_attack(t: Unit) -> void:
	if t.is_champion and t.team != c.team and ready(9923):
		proc(9923, 10.0)
		state.blades = 3
		state.blades_end = c.world.time + 3.0
	if int(state.get("blades", 0)) <= 0 or c.world.time >= float(state.get("blades_end", INF)):
		state.blades = 0
		return
	var speed := 0.80 if c.attack_def.ranged else 1.60
	buff(9923, 3.0, {"bonus_attack_speed": speed, "attack_speed_cap": 100.0})
	state.blades_end = c.world.time + 3.0
	count("blades", -1)
	var effective_speed := float(c.stats.attack_speed)
	if c.stats.attack_speed_cap < 100.0:
		effective_speed *= (1.0 + c.stats.bonus_attack_speed + speed) / maxf(1.0 + c.stats.bonus_attack_speed, 0.1)
	c.attack_cd = minf(c.attack_cd, 1.0 / maxf(effective_speed, 0.05))
	if int(state.blades) == 0:
		state.blades_end = INF
		for status in c.statuses:
			if status.key == "rune:9923": status.time = 0.001


func grasp_combat() -> void:
	if not has(8437):
		return
	var now: float = c.world.time
	if now > float(state.get("grasp_last", -10.0)) + 4.0:
		state.grasp_start = now
	state.grasp_last = now


func impaired(t: Unit) -> bool:
	return t.statuses.any(func(s): return s.type in Unit.CC_TYPES) or (t.forced != null and not t.forced.dash)


func crowd_control(t: Unit, hard: bool, duration := 0.0) -> void:
	if t.team == c.team or not t.is_champion:
		return
	if has(8463) and not t.dead:
		t.add_status({"type": "mark", "id": "font_of_life", "time": 4.0}, c, "rune:font:%d" % c.net_id)
	if hard and ready(8439):
		proc(8439, 20)
		buff(8439, 2.5, {"armor": 20.0, "magic_resist": 20.0}, {"armor": 1.30, "magic_resist": 1.30})
		state.aftershock = c.world.time + 2.5
	if hard and ready(8351):
		proc(8351, 25)
		var origin := t.global_position
		var direction := origin.direction_to(c.global_position)
		if direction == Vector2.ZERO: direction = Vector2.RIGHT
		var rays := [origin + direction * 550.0]
		for ally in c.world.champions.values():
			if ally != c and ally != t and not ally.dead and ally.global_position.distance_to(origin) <= 650.0:
				rays.append(origin + origin.direction_to(ally.global_position) * 550.0)
				if rays.size() == 3: break
		while rays.size() < 3:
			rays.append(origin + direction.rotated(1.05 if rays.size() == 1 else -1.05) * 550.0)
		state.glacial = {"pos": origin, "rays": rays, "end": c.world.time + 3.0 + duration, "id": t.net_id}


func support(t: Unit) -> void:
	if t != c and t.team == c.team and t.is_champion and has(8465):
		state["guard_%d" % t.net_id] = c.world.time + 2.5
	if t != c and t.team == c.team and t.is_champion and ready(8214):
		proc(8214, 2.5)
		give_shield(t, lerpf(30.0, 80.0, progress()) + 0.25 * c.stats.ability_power + 0.40 * bonus_ad(), 2, 8214)


func sustain(healed: float, consumable := false) -> void:
	if healed < 20.0 and not consumable: return
	if has(8430): buff(8430, 3.0, {}, {"armor": 1.05})
	if has(8435): buff(8435, 3.0, {}, {"magic_resist": 1.05})


func ward_spawn(pos: Vector2, ghost: bool) -> void:
	var ward: Summon = c.world.spawn("summon", {"pos": pos, "team": c.team, "ward": true, "name": "Ghost Poro" if ghost else "Zombie Ward",
		"stats": {"max_hp": 1.0, "vision": 450.0 if ghost else 600.0}, "color": c.color})
	ward.init_server(c, 90.0 if ghost else 120.0, {}, {})
	ward.gold_value = 0.0
	if ghost: ward.ghost_poro = true
	count("vision_stacks", 1, 10)


func on_kill(t: Unit) -> void:
	if has(9101): c.heal(lerpf(1.0, 18.0, progress()), c)
	if t is Minion or t is Monster: count("legend", 5 if t is Monster else 1, 500)
	if t is Minion and c.world.time < float(state.get("avarice", 0.0)): c.add_gold(2)
	if t.is_ward and t.team != c.team:
		if has(8138): count("vision_stacks", 1, 20)
		if has(8136): ward_spawn(t.global_position, false)


func takedown(t: Unit) -> void:
	count("legend", 20, 500)
	count("mementos", 1, 18)
	count("takedowns")
	if not unique.has(t.net_id):
		unique[t.net_id] = true
		if has(8135): c.add_gold(70.0 + 20.0 * (unique.size() - 1))
	if has(9111):
		state.triumph = c.world.time + 1.0
		count("triumph_pending")
	if has(8009):
		c.restore_mana(c.stats.max_mana * 0.20)
		c.cooldowns.r = maxf(c.cooldowns.r - c.cd_total.r * 0.10, 0.0)
	if has(8014): state.coup_end = c.world.time + 10.0
	if has(8138): count("vision_stacks", 2, 20)
	if has(8128) and timers.has(8128): timers[8128] = minf(timers[8128], c.world.time + 1.5)
	if has(8224): c.cooldowns.r *= 0.93
	if has(8210) and c.level >= 11:
		for slot in ["q", "w", "e"]: c.cooldowns[slot] *= 0.8


func tick(delta: float) -> void:
	var now: float = c.world.time
	if keystone == 8358:
		if (state.has("rotate") and now >= float(state.rotate)) or (not state.has("rotate") and now >= 40.0 + float(state.get("rotation_started", 0.0)) and now - c.combat_t >= 5.0):
			roll_keystone()
	if has(8021) and last_pos != Vector2.INF:
		state.fleet = minf(float(state.get("fleet", 0.0)) + last_pos.distance_to(c.global_position) / 24.0, 100.0)
	last_pos = c.global_position
	if c.forced != null and c.forced.dash: state.dash_end = now + 4.0
	if state.get("was_stealthed", false) and not c.has_status("stealth"): state.dash_end = now + 4.0
	state.was_stealthed = c.has_status("stealth")
	if state.has("biscuit_mana_tick"):
		if now >= float(state.biscuit_mana_tick.end):
			state.erase("biscuit_mana_tick")
		else:
			c.restore_mana(float(state.biscuit_mana_tick.rate) * delta)
	if state.has("triumph") and now >= float(state.triumph):
		for i in int(state.get("triumph_pending", 0)):
			c.heal(maxf(c.stats.max_hp - c.hp, 0.0) * 0.15, c)
			c.add_gold(25)
		state.erase("triumph_pending")
		state.erase("triumph")
	if state.has("comet") and now >= state.comet.when:
		for t in c.world.query(state.comet.at, 140, c.team):
			hit(t, lerpf(30.0, 130.0, progress()) + 0.05 * c.stats.ability_power + 0.1 * bonus_ad())
		state.erase("comet")
	if state.has("scorch") and now >= state.scorch.when:
		var target = c.world.entities.get(state.scorch.id)
		if is_instance_valid(target): hit(target, lerpf(30, 60, progress()), "magic")
		state.erase("scorch")
	if state.has("aftershock") and now >= state.aftershock:
		for t in c.world.query(c.global_position, 350, c.team):
			hit(t, lerpf(40.0, 140.0, progress()) + 0.035 * c.stats.max_hp, "magic")
		state.erase("aftershock")
	if state.has("glacial"):
		if now >= state.glacial.end:
			state.erase("glacial")
		else:
			var slow := clampf(0.30 + 0.9 * float(c.stats.heal_power) + 0.0003 * float(c.stats.ability_power) + 0.0004 * bonus_ad(), 0.0, 0.95)
			for ray in state.glacial.rays:
				for t in c.world.query_line(state.glacial.pos, ray, 85.0, c.team):
					t.add_status({"type": "slow", "time": 0.25, "amount": slow}, c, "rune:glacial")
			for ally in c.world.champions.values():
				if ally != c and ally.team == c.team and ally.rune_state != null and ally.global_position.distance_to(state.glacial.pos) < 450:
					ally.rune_state.state["glacial_%d" % state.glacial.id] = now + 0.25
	for key in state.keys():
		if not key.begins_with("df_"): continue
		var burn: Dictionary = state[key]
		if now >= burn.tick and burn.tick <= burn.end:
			var target = c.world.entities.get(int(key.substr(3)))
			if is_instance_valid(target) and not target.dead:
				hit(target, (lerpf(4.0, 12.0, progress()) + 0.03 * c.stats.ability_power + 0.07 * bonus_ad()) * (1.75 if now - burn.start >= 3.0 else 1.0))
			burn.tick += 1.0
		if now >= burn.end: state.erase(key)
	if now >= float(state.get("periodic", 0.0)):
		state.periodic = now + 0.25
		periodic(now)


func periodic(now: float) -> void:
	c.stats_dirty = true
	if now > float(state.get("first_response", INF)):
		state.erase("first_response")
		if ready(8369): proc(8369, lerpf(25.0, 15.0, progress()))
	if ready(8446):
		var nearby := {}
		for t in c.world.query(c.global_position, 600.0, c.team, "enemies", true):
			if t is Tower and not t.is_inhibitor and not t.is_nexus and not t.is_protected():
				var key := "tower_%d" % t.net_id
				nearby[key] = true
				if not state.has(key): state[key] = now
		for key in state.keys():
			if key.begins_with("tower_") and not nearby.has(key): state.erase(key)
	if state.has("predator"):
		if now >= float(state.predator.end):
			state.erase("predator")
		elif c.move_goal is Vector2 or c.move_dir != Vector2.ZERO or (is_instance_valid(c.attack_target) and c.attack_target.is_champion):
			var heading: Vector2 = c.move_dir
			if is_instance_valid(c.attack_target) and c.attack_target.is_champion: heading = c.global_position.direction_to(c.attack_target.global_position)
			elif c.move_goal is Vector2: heading = c.global_position.direction_to(c.move_goal)
			for enemy in c.world.query(c.global_position, 2500.0, c.team):
				if enemy.is_champion and enemy.visible_to(c.team) and heading.dot(c.global_position.direction_to(enemy.global_position)) > 0.65:
					buff(8124, 0.26, {"move_speed_bonus": 0.60 * clampf(now - float(state.predator.start) + 1.0, 0.0, 1.0)})
					break
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
	if has(8304) and not state.get("shoes", false) and now >= 600.0 - 30.0 * int(state.get("takedowns", 0)):
		if c.has_item("boots") or _grant_item("boots"):
			state.shoes = true
	if has(8345):
		var due := mini(floori(now / 120.0), 3)
		if int(state.get("delivered", 0)) < due:
			count("delivered")
			count("biscuits")
	if int(state.get("klepto_potions", 0)) > 0 and _grant_item("health_potion"): count("klepto_potions", -1)
	if c.is_bot:
		for milestone in [3, 6, 9]:
			if has(8313) and c.level >= milestone and not state.get("tonic_%d" % milestone, false): action("tonic", [milestone])
		if has(8324) and c.hp < c.stats.max_hp * 0.20 and now - c.combat_t <= 2.0: action("stopwatch", [])
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
				var uses_mana := c.uses_mana()
				var duration := 6.0 if has(8352) else 5.0
				var healing: float = maxf(c.stats.max_hp - c.hp, 0.0) * (0.10 if uses_mana else 0.12) * duration / 5.0
				c.add_status({"type": "hot", "time": duration, "tick": 0.5, "interval": 0.5, "amount": healing / duration}, c, "rune:biscuit")
				if uses_mana:
					state.biscuit_mana_tick = {"end": c.world.time + duration, "rate": maxf(c.stats.max_mana - c.mana, 0.0) * 0.02}
				if has(8352): buff(8352, duration, {"move_speed_bonus": 0.05})
				sustain(0.0, true)
			count("biscuits", -1)
			if c.uses_mana(): count("biscuit_mana")
		"dematerialize":
			if not ready(8317) or c.world.time < 240.0 or int(state.get("demat", 0)) >= 6 or args.size() != 1 or not args[0] is int: return false
			var target = c.world.entities.get(args[0])
			if not target is Minion or target.dead or target.team == c.team or not target.visible_to(c.team) or c.global_position.distance_to(target.global_position) > 550.0: return false
			count("demat")
			count("demat_" + target.minion_type)
			proc(8317, 10.0)
			target.die(c)
		"predator":
			if not ready(8124) or not owns_boots(): return false
			state.predator = {"start": c.world.time + 1.0, "end": c.world.time + 10.0}
			proc(8124, lerpf(90.0, 60.0, progress()) * 100.0 / (100.0 + c.stats.item_haste))
		"stopwatch":
			if not has(8324) or c.world.time < 360.0 or state.get("stopwatch_used", false) or not c.can_use_summoner({}): return false
			state.stopwatch_used = true
			c.command("stop", [])
			c.add_status({"type": "stasis", "time": 2.5}, c, "rune:stopwatch")
		"tonic":
			if not has(8313) or args.size() != 1 or not args[0] is int or not args[0] in [3, 6, 9] or c.level < args[0]: return false
			var key := "tonic_%d" % args[0]
			if state.get(key, false): return false
			state[key] = true
			var duration := 72.0 if has(8352) else 60.0
			match args[0]:
				3:
					state.avarice = c.world.time + duration
					c.add_gold(40)
				6:
					var bonuses := {"attack_damage": 12.0, "ability_power": 0.0}
					if c.stats.ability_power > bonus_ad(): bonuses = {"ability_power": 20.0}
					buff(8313, duration, bonuses)
				9: c.skill_points += 1
			if has(8352) and args[0] != 9: buff(8352, duration, {"move_speed_bonus": 0.05})
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
			count("swaps")
			proc(8360, maxf(0.0, 240.0 - 25.0 * seen.size()))
		_: return false
	return true


func used_summoner(slot: int) -> void:
	if has(8275):
		var cooldown := Effects.num(c.summoner_def(slot).active.cooldown, {"caster": c}, 180.0)
		var speed := 0.05 if cooldown < 100.0 else (0.20 if cooldown < 250.0 else 0.35)
		buff(8275, 2, {"move_speed_bonus": speed, "ghost": 1.0})
	var swap: Dictionary = state.get("swap", {})
	if not swap.is_empty() and slot == swap.slot:
		c.summoners[slot] = swap.id
		c.sum_cd[slot] = maxf(0.0, swap.until - c.world.time)
		c.sum_cd_total[slot] = swap.total
		c.sum_recast[slot] = false
		state.erase("swap")
