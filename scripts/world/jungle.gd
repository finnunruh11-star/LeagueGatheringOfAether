class_name Jungle
extends RefCounted
## Jungle camps of maps with "camps" (see maps/rift.json). The host spawns and respawns them,
## shares aggro inside a camp and hands out the rewards:
## - Blue Sentinel / Red Brambleback: the killer gets Crest of Insight / Crest of Cinders (2 min,
##   taken over by whoever kills the holder).
## - Drakes: a permanent, stacking team bonus by element; the 4th drake of a team grants its
##   Dragon Soul, after which the Elder Dragon spawns instead (Aspect of the Elder: burn + execute).
## - Baron Nashor: Hand of Baron for the living team (AD/AP, 4s recall, empowered nearby minions).
## - Rift Scuttler: a speed shrine with vision for the killer's team.
## Clients only receive camp timers and the Dragon state (World._rpc_jungle) for the HUD.

const CAMPS := {
	"blue": {"monsters": [["blue_sentinel", Vector2.ZERO]], "first": 90.0, "respawn": 300.0, "leash": 900.0},
	"red": {"monsters": [["red_brambleback", Vector2.ZERO]], "first": 90.0, "respawn": 300.0, "leash": 900.0},
	"gromp": {"monsters": [["gromp", Vector2.ZERO]], "first": 90.0, "respawn": 135.0, "leash": 800.0},
	"wolves": {"monsters": [["greater_murk_wolf", Vector2(0, -30)], ["murk_wolf", Vector2(-120, 60)], ["murk_wolf", Vector2(120, 60)]],
		"first": 90.0, "respawn": 135.0, "leash": 800.0},
	"raptors": {"monsters": [["crimson_raptor", Vector2.ZERO], ["raptor", Vector2(-130, -70)], ["raptor", Vector2(130, -70)],
		["raptor", Vector2(-160, 60)], ["raptor", Vector2(160, 60)], ["raptor", Vector2(0, 140)]], "first": 90.0, "respawn": 135.0, "leash": 800.0},
	"krugs": {"monsters": [["ancient_krug", Vector2(-40, 0)], ["krug", Vector2(100, 60)]], "first": 90.0, "respawn": 135.0, "leash": 800.0},
	"scuttle": {"monsters": [["rift_scuttler", Vector2.ZERO]], "first": 210.0, "respawn": 150.0, "leash": 100000.0},
	"dragon": {"monsters": [["dragon", Vector2.ZERO]], "first": 300.0, "respawn": 300.0, "leash": 1100.0, "epic": true},
	"baron": {"monsters": [["baron", Vector2.ZERO]], "first": 1200.0, "respawn": 360.0, "leash": 1200.0, "epic": true},
}
const DRAKES := ["infernal", "mountain", "ocean", "cloud"]
const SOUL_AT := 4
const ELDER_RESPAWN := 360.0
const SHRINE_TIME := 90.0
const SHRINE_RADIUS := 500.0
const DRAKE_GOLD := 50.0
const ELDER_GOLD := 100.0
const BARON_GOLD := 300.0
const BUFFS := {
	"blue": {"type": "buff", "id": "crest_of_insight", "target": "self", "duration": 120.0,
		"add": {"ability_haste": 10.0, "mana_regen": "5 + 0.01 * max_mana"}},
	"red": {"type": "buff", "id": "crest_of_cinders", "target": "self", "duration": 120.0, "add": {"hp_regen": "2 + 0.004 * max_hp"},
		"triggers": [{"on": "attack", "if": "not t_structure", "effects": [
			{"type": "dot", "id": "cinders_burn", "amount": "(8 + 2 * level) / 3", "interval": 1.0, "duration": 3.0,
				"damage_type": "true", "color": "#ff7a3a"},
			{"type": "slow", "id": "cinders_slow", "amount": "0.1 + 0.005 * level", "duration": 1.5}]}]},
	"elder": {"type": "buff", "id": "aspect_of_the_elder", "target": "self", "duration": 150.0, "triggers": [
		{"on": "deal_damage", "if": "t_champion and t_hp > 0 and t_hp < 0.2 * t_max_hp", "effects": [
			{"type": "damage", "amount": "t_hp + 50", "damage_type": "true", "raw": true, "vfx": "burst", "color": "#d8ccff"},
			{"type": "text", "text": "Executed!", "color": "#d8ccff"}]},
		{"on": "deal_damage", "if": "t_champion", "cooldown": 1.0, "effects": [
			{"type": "dot", "id": "elder_burn", "amount": "(45 + 5 * level) / 3", "interval": 0.5, "duration": 3.0,
				"damage_type": "true", "color": "#c8b8ff"}]}]},
}
const BUFF_IDS := {"blue": "crest_of_insight", "red": "crest_of_cinders", "baron": "hand_of_baron", "elder": "aspect_of_the_elder"}

var world: World
var camps: Array = []      # {id, kind, def, pos, side, route, next (spawn time, -1 = up), respawn, alive, hits}
var drakes := [[], []]     # team -> elements taken, in order
var soul := ["", ""]       # team -> Dragon Soul element
var next_drake := ""
var shrines: Array = []    # {team, pos, until}
var calls := [{}, {}]      # team -> {"m": Monster, "until": time}: bots gather to take this objective
var _t := 0.0


func _init(w: World) -> void:
	world = w
	for c in w.map.camps:
		var def: Dictionary = CAMPS.get(c.kind, {})
		if def.is_empty():
			push_warning("Unknown jungle camp kind: %s" % c.kind)
			continue
		camps.append({"id": camps.size(), "kind": c.kind, "def": def, "pos": c.pos, "side": c.side, "route": c.path,
			"next": float(c.first) if float(c.first) >= 0.0 else float(def.first),
			"respawn": float(c.respawn) if float(c.respawn) >= 0.0 else float(def.respawn), "alive": [], "hits": {}})
	next_drake = DRAKES[randi() % DRAKES.size()]


func average_level() -> float:
	var n := 0
	var s := 0.0
	for c in world.champions.values():
		n += 1
		s += c.level
	return s / n if n > 0 else 1.0


func elder_time() -> bool:
	return soul[0] != "" or soul[1] != ""


# ------------------------------------------------------------------- host ---

func tick(delta: float) -> void:
	var changed := false
	for c in camps:
		if float(c.next) >= 0.0 and world.time >= float(c.next):
			_spawn(c)
			changed = true
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_auras()
	if changed:
		world.sync_jungle()


func _spawn(c: Dictionary) -> void:
	c.next = -1.0
	c.alive = []
	c.hits = {}
	var lvl := average_level()
	var flip := world.map.mirror_mode != "" and int(c.side) == 1
	for m in c.def.monsters:
		var off: Vector2 = m[1]
		if flip:
			off = -off if world.map.mirror_mode == "rotate" else Vector2(-off.x, off.y)
		var at: Vector2 = c.pos + off
		var d := {"kind": m[0], "pos": at, "home": at, "camp": int(c.id), "level": lvl, "leash": float(c.def.leash)}
		if c.kind == "dragon":
			d.kind = "elder_dragon" if elder_time() else "dragon"
			d.element = "elder" if elder_time() else next_drake
		elif c.kind == "baron":
			d.bonus_hp = 180.0 * maxf(0.0, (world.time - 1200.0) / 60.0)
		if not c.route.is_empty():
			d.route = c.route
		c.alive.append(world.spawn("monster", d))
	if c.def.get("epic", false):
		var mon = c.alive[0]
		world.fx("announce", {"text": "%s has spawned!" % mon.display_name, "color": mon.color.lightened(0.3)})


## Something hit a monster of camp `id`: the whole camp turns on it.
func provoke(id: int, src: Unit) -> void:
	if id < 0 or id >= camps.size() or src.team > 1:
		return
	var c: Dictionary = camps[id]
	c.hits[src.net_id] = world.time
	for m in c.alive:
		if is_instance_valid(m) and not m.dead:
			m.provoke(src)


## The closest unit that hit the camp recently and is still inside `m`'s leash range.
func next_target(m: Monster) -> Unit:
	if m.camp_id < 0 or m.camp_id >= camps.size():
		return null
	var best: Unit = null
	var bd := INF
	var hits: Dictionary = camps[m.camp_id].hits
	for id in hits.keys():
		var u = world.entities.get(id)
		if world.time - float(hits[id]) > 8.0 or not (u is Unit) or u.dead or not u.targetable():
			hits.erase(id)
			continue
		if u.global_position.distance_to(m.home) > m.leash:
			continue
		var d: float = u.global_position.distance_to(m.global_position)
		if d < bd:
			bd = d
			best = u
	return best


func forget(id: int) -> void:
	if id >= 0 and id < camps.size():
		camps[id].hits.clear()


func on_monster_died(m: Monster, credit) -> void:
	if m.camp_id < 0 or m.camp_id >= camps.size():
		return
	var c: Dictionary = camps[m.camp_id]
	c.alive.erase(m)
	var champ: Champion = credit if is_instance_valid(credit) and credit is Champion else null
	if champ != null:
		match m.kind_id:
			"blue_sentinel":
				give_buff(champ, "blue")
			"red_brambleback":
				give_buff(champ, "red")
			"rift_scuttler":
				_shrine(champ.team, m.global_position)
			"dragon", "elder_dragon", "baron":
				_epic(m, champ.team)
	var left: Array = c.alive.filter(func(x): return is_instance_valid(x) and not x.dead)
	if left.is_empty():
		c.next = world.time + (ELDER_RESPAWN if c.kind == "dragon" and elder_time() else float(c.respawn))
		world.sync_jungle()


func give_buff(ch: Champion, which: String, time := -1.0) -> void:
	var e: Dictionary
	if which == "baron":
		var mins := world.time / 60.0
		var ad := clampf(24.0 + 1.2 * (mins - 20.0), 24.0, 48.0)
		e = {"type": "buff", "id": "hand_of_baron", "target": "self", "duration": 180.0,
			"add": {"attack_damage": ad, "ability_power": ad * 1.6}}
	else:
		e = BUFFS[which].duplicate(true)
	if time > 0.0:
		e.duration = time
		e.keep_longer = true  # taking over a buff never shortens the one you already have
	Effects.run([e], {"caster": ch, "team": ch.team, "target": ch, "rank": ch.level, "ability": "Jungle", "color": ch.color})


## Killing a buff holder takes over the rest of their Blue/Red buff.
func transfer_buffs(victim: Champion, killer: Champion) -> void:
	for which in ["blue", "red"]:
		var s := victim.find_status(BUFF_IDS[which])
		if not s.is_empty() and float(s.time) > 1.0:
			give_buff(killer, which, float(s.time))


func _epic(m: Monster, team: int) -> void:
	var tname: String = Game.TEAM_NAMES[team]
	var col: Color = Game.TEAM_COLORS[team]
	match m.kind_id:
		"dragon":
			var elem := m.element if m.element in DRAKES else next_drake
			drakes[team].append(elem)
			if drakes[team].size() >= SOUL_AT and not elder_time():
				soul[team] = elem
			for ch in world.champions.values():
				if ch.team == team:
					sync_team_buffs(ch)
					ch.add_gold(DRAKE_GOLD, ch.global_position if not ch.dead else null)
			world.fx("announce", {"text": "%s team slew the %s!" % [tname, m.display_name], "color": col})
			if soul[team] == elem and drakes[team].size() == SOUL_AT:
				world.fx("announce", {"text": "%s team claimed the %s Dragon Soul!" % [tname, elem.capitalize()], "color": col})
			var others := DRAKES.filter(func(x): return x != elem)
			next_drake = others[randi() % others.size()]
		"elder_dragon":
			for ch in world.champions.values():
				if ch.team == team and not ch.dead:
					give_buff(ch, "elder")
					ch.add_gold(ELDER_GOLD, ch.global_position)
			world.fx("announce", {"text": "%s team slew the Elder Dragon!" % tname, "color": col})
		"baron":
			for ch in world.champions.values():
				if ch.team == team and not ch.dead:
					give_buff(ch, "baron")
					ch.add_gold(BARON_GOLD, ch.global_position)
			world.fx("announce", {"text": "%s team slew Baron Nashor!" % tname, "color": col})
	world.sync_jungle()


## Gives `ch` any drake stacks and Dragon Soul its team has but it lacks (it was dead when they
## were taken - dead units can't receive statuses). Called on kills and on respawn.
func sync_team_buffs(ch: Champion) -> void:
	if ch.dead or ch.team > 1:
		return
	for elem in DRAKES:
		var have := int(ch.find_status("drake_" + elem).get("stacks", 0))
		for k in drakes[ch.team].count(elem) - have:
			_drake_buff(ch, elem)
	if soul[ch.team] != "" and ch.find_status("dragon_soul").is_empty():
		_soul_buff(ch, soul[ch.team])


## Permanent, stacking drake bonus (kept through deaths).
func _drake_buff(ch: Champion, elem: String) -> void:
	var e := {"type": "buff", "id": "drake_" + elem, "target": "self", "duration": 1.0e9, "persist": true, "hidden": true,
		"max_stacks": 9, "stacks": 1}
	match elem:
		"infernal":
			e.multiply = {"attack_damage": 1.06, "ability_power": 1.06}
		"mountain":
			e.multiply = {"armor": 1.06, "magic_resist": 1.06}
		"cloud":
			e.add = {"move_speed_bonus": 0.035, "slow_resist": 0.05}
		"ocean":
			e.add = {"hp_regen": 0.0}  # healing over time: see _auras
	Effects.run([e], {"caster": ch, "team": ch.team, "target": ch, "rank": ch.level, "ability": "Drake"})


func _soul_buff(ch: Champion, elem: String) -> void:
	var e := {"type": "buff", "id": "dragon_soul", "target": "self", "duration": 1.0e9, "persist": true, "hidden": true}
	match elem:
		"infernal":
			e.multiply = {"attack_damage": 1.12, "ability_power": 1.12}
		"mountain":
			e.multiply = {"armor": 1.15, "magic_resist": 1.15}
			e.add = {"max_hp": 200.0}
		"cloud":
			e.add = {"move_speed_bonus": 0.1, "slow_resist": 0.2}
		"ocean":
			e.add = {"hp_regen": 10.0, "mana_regen": 5.0}
	Effects.run([e], {"caster": ch, "team": ch.team, "target": ch, "rank": ch.level, "ability": "Dragon Soul"})


## Rift Scuttler reward: a shrine that reveals the area and speeds up allies passing through.
func _shrine(team: int, at: Vector2) -> void:
	var s = world.spawn("summon", {"team": team, "pos": at, "name": "Speed Shrine", "ward": true, "stationary": true,
		"color": Color(0.45, 0.9, 1.0), "size": 0.7, "stats": {"vision": 900.0, "max_hp": 999.0}})
	s.init_server(null, SHRINE_TIME, {}, {})
	s.add_status({"type": "untargetable", "time": SHRINE_TIME}, null, "shrine")
	shrines.append({"team": team, "pos": at, "until": world.time + SHRINE_TIME})


## Every 0.25s: ocean drake healing, shrine speed, Baron-empowered minions.
func _auras() -> void:
	shrines = shrines.filter(func(s): return world.time < float(s.until))
	var barons := [[], []]
	for ch in world.champions.values():
		if ch.dead or ch.team > 1:
			continue
		var oceans := float(drakes[ch.team].count("ocean"))
		if soul[ch.team] == "ocean":
			oceans += 2.0
		if oceans > 0.0 and ch.hp < ch.stats.max_hp:
			ch.heal((ch.stats.max_hp - ch.hp) * 0.005 * oceans * 0.25, ch, false)
		for s in shrines:
			if int(s.team) == ch.team and ch.global_position.distance_to(s.pos) < SHRINE_RADIUS:
				ch.add_status({"type": "buff", "add": {"move_speed_bonus": 0.3}, "mult": {}, "time": 1.5, "hidden": true}, null, "speed_shrine")
		if not ch.find_status("hand_of_baron").is_empty():
			barons[ch.team].append(ch.global_position)
	for u in world.units:
		if not (u is Minion) or u.dead or u.team > 1 or barons[u.team].is_empty():
			continue
		for p in barons[u.team]:
			if u.global_position.distance_to(p) < 1100.0:
				u.add_status({"type": "buff", "add": {"armor": 40.0, "magic_resist": 40.0}, "mult": {"damage_mult": 1.6, "move_speed": 1.1},
					"time": 1.0}, null, "baron_aura")
				break


# ------------------------------------------------------------ replication ---

func state() -> Dictionary:
	var nexts := PackedFloat32Array()
	for c in camps:
		nexts.append(float(c.next))
	return {"next": nexts, "drakes": drakes, "soul": soul, "drake": next_drake}


func apply_state(s: Dictionary) -> void:
	var nexts: PackedFloat32Array = s.get("next", PackedFloat32Array())
	for i in mini(nexts.size(), camps.size()):
		camps[i].next = nexts[i]
	drakes = s.get("drakes", drakes)
	soul = s.get("soul", soul)
	next_drake = str(s.get("drake", next_drake))


## Seconds until camp `i` spawns (0 while it's up).
func respawn_in(i: int) -> float:
	var n := float(camps[i].next)
	return maxf(n - world.time, 0.0) if n >= 0.0 else 0.0
