extends RefCounted

const MAP_ID := "aram_mayhem"
const STANDARD_MAP_ID := "aram"
const START_LEVEL := 3
const LEVELS := [3, 7, 11, 15]
const TIERS := ["Silver", "Gold", "Prismatic"]
const TIER_COLORS := [Color("c7d6e8"), Color("ffd16e"), Color("e1a3ff")]
const DISALLOWED_SPELLS := ["teleport", "smite"]

const AUGMENTS := {
	"battle_drill": {"tier": 0, "name": "Battle Drill", "desc": "+20 attack damage and +15% attack speed.",
		"stats": {"attack_damage": 20.0, "bonus_attack_speed": 0.15}},
	"quick_study": {"tier": 0, "name": "Quick Study", "desc": "+30 ability power and +20 ability haste.",
		"stats": {"ability_power": 30.0, "ability_haste": 20.0}},
	"second_skin": {"tier": 0, "name": "Second Skin", "desc": "+180 health and +15 armor and magic resist.",
		"stats": {"max_hp": 180.0, "armor": 15.0, "magic_resist": 15.0}},
	"light_steps": {"tier": 0, "name": "Light Steps", "desc": "+30 move speed and +20% slow resistance.",
		"stats": {"move_speed": 30.0, "slow_resist": 0.20}},
	"field_medic": {"tier": 0, "name": "Field Medic", "desc": "+20% heal and shield power and +3 health per second.",
		"stats": {"heal_power": 0.20, "hp_regen": 3.0}},
	"first_aid": {"tier": 0, "name": "First Aid", "desc": "When damaged below 35% health, shield yourself for 180 for 3s (30s cooldown).",
		"trigger": {"on": "low_health", "threshold": 0.35, "cooldown": 30.0,
			"effects": [{"type": "shield", "target": "self", "amount": 180.0, "duration": 3.0}]}},
	"loaded_dice": {"tier": 0, "name": "Loaded Dice", "desc": "+25% critical strike chance and +10% critical strike damage.",
		"stats": {"crit_chance": 0.25, "crit_damage": 0.10}},

	"longshot": {"tier": 1, "name": "Longshot", "desc": "+100 attack range and +20% attack speed.",
		"stats": {"attack_range": 100.0, "bonus_attack_speed": 0.20}},
	"arcane_reserve": {"tier": 1, "name": "Arcane Reserve", "desc": "+65 ability power, +25 ability haste, and +4 mana regen if you use mana.",
		"stats": {"ability_power": 65.0, "ability_haste": 25.0, "mana_regen": 4.0}},
	"resolve": {"tier": 1, "name": "Iron Resolve", "desc": "+350 health and +30% tenacity.",
		"stats": {"max_hp": 350.0, "tenacity": 0.30}},
	"spell_sprint": {"tier": 1, "name": "Spell Sprint", "desc": "+35 summoner spell haste and +40 move speed.",
		"stats": {"summoner_haste": 35.0, "move_speed": 40.0}},
	"vampire": {"tier": 1, "name": "Blood Bargain", "desc": "+12% omnivamp and +20 attack damage.",
		"stats": {"omnivamp": 0.12, "attack_damage": 20.0}},
	"static_strike": {"tier": 1, "name": "Static Strike", "desc": "Attacks deal 45 + 5 per level bonus magic damage (3s cooldown).",
		"trigger": {"on": "attack", "cooldown": 3.0,
			"effects": [{"type": "damage", "damage_type": "magic", "amount": "45 + 5 * level"}]}},
	"victory_lap": {"tier": 1, "name": "Victory Lap", "desc": "Champion takedowns heal you for 15% max health.",
		"trigger": {"on": "takedown", "effects": [{"type": "heal", "target": "self", "amount": "0.15 * max_hp"}]}},
	"breach": {"tier": 1, "name": "Breach", "desc": "+20% armor penetration and +20% magic penetration.",
		"stats": {"armor_pen": 0.20, "magic_pen_percent": 0.20}},

	"living_fortress": {"tier": 2, "name": "Living Fortress", "desc": "+22% max health and +30 armor and magic resist.",
		"stats": {"armor": 30.0, "magic_resist": 30.0}, "mult": {"max_hp": 1.22}},
	"spell_engine": {"tier": 2, "name": "Spell Engine", "desc": "+65 ability haste and +90 ability power.",
		"stats": {"ability_haste": 65.0, "ability_power": 90.0}},
	"redline": {"tier": 2, "name": "Redline", "desc": "+60% attack speed and +1.5 attacks/s to the cap.",
		"stats": {"bonus_attack_speed": 0.60, "attack_speed_cap": 1.5}},
	"headhunter": {"tier": 2, "name": "Headhunter", "desc": "+55 attack damage. Champion takedowns grant 175 bonus gold.",
		"stats": {"attack_damage": 55.0}, "trigger": {"on": "takedown",
			"effects": [{"type": "gold", "target": "self", "amount": 175.0}]}},
	"final_stand": {"tier": 2, "name": "Final Stand", "desc": "When damaged below 30% health, gain a shield for 30% of max health for 4s (40s cooldown).",
		"trigger": {"on": "low_health", "threshold": 0.30, "cooldown": 40.0,
			"effects": [{"type": "shield", "target": "self", "amount": "0.30 * max_hp", "duration": 4.0}]}},
	"overdrive": {"tier": 2, "name": "Overdrive", "desc": "+50 move speed. Champion takedowns shorten Q, W and E cooldowns by 3s.",
		"stats": {"move_speed": 50.0}, "trigger": {"on": "takedown", "effects": [
			{"type": "cooldown", "slot": "q", "amount": 3.0}, {"type": "cooldown", "slot": "w", "amount": 3.0},
			{"type": "cooldown", "slot": "e", "amount": 3.0}]}},
	"wild_magic": {"tier": 2, "name": "Wild Magic", "desc": "+110 ability power and +30% magic penetration.",
		"stats": {"ability_power": 110.0, "magic_pen_percent": 0.30}},
}


static func is_aram(map_id: String) -> bool:
	return map_id == STANDARD_MAP_ID or map_id == MAP_ID


static func map_variant(bridge: Dictionary, augments: bool) -> Dictionary:
	var data := bridge.duplicate(true)
	data.merge({
		"name": "ARAM Mayhem" if augments else "ARAM (Standard)",
		"description": "Random champion cards and permanent augments on a single lane." if augments
			else "All Random All Mid: a single-lane match without augments.",
		"fog": false, "start_level": START_LEVEL, "start_gold": 1400.0, "gold_per_second": 5.5,
		"waves": {"interval": 25, "first": 15, "melee": 3, "ranged": 3},
		"brush": [
			[[2830, 620], [3090, 605], [3170, 720], [3100, 860], [2860, 850], [2760, 730]],
			[[3510, 1440], [3700, 1400], [3900, 1420], [4040, 1510], [3900, 1630], [3540, 1610]],
		],
	}, true)
	data.towers.append_array([
		{"lane": 0, "order": 2, "kind": "inhibitor", "pos": [1250, 1170]},
		{"lane": -1, "kind": "nexus_turret", "pos": [950, 910]},
		{"lane": -1, "kind": "nexus_turret", "pos": [950, 1430]},
	])
	# The centre brush spans both halves; only the outer brush is mirrored.
	data.brush[1] = {"poly": data.brush[1], "mirror": false}
	return data


static func draw_augments(tier: int, count: int, excluded: Array) -> Array:
	var pool := []
	for id in AUGMENTS:
		if AUGMENTS[id].tier == tier and not excluded.has(id):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, count)


static func bot_pick(offers: Array, role: String) -> String:
	var preferred: Dictionary = {
		"tank": ["max_hp", "armor", "magic_resist", "tenacity"],
		"support": ["heal_power", "ability_haste", "mana_regen", "max_hp"],
		"mage": ["ability_power", "ability_haste", "magic_pen_percent", "mana_regen"],
		"marksman": ["bonus_attack_speed", "attack_range", "crit_chance", "attack_damage"],
		"assassin": ["attack_damage", "magic_pen_percent", "ability_haste", "move_speed"],
	}
	var stats: Array = preferred.get(role, ["max_hp", "attack_damage", "omnivamp", "ability_haste"])
	var best: String = offers[0]
	var high := -1
	for id in offers:
		var score := 0
		var augment: Dictionary = AUGMENTS[id]
		for stat in stats:
			if augment.get("stats", {}).has(stat) or augment.get("mult", {}).has(stat):
				score += 1
		if score > high:
			high = score
			best = id
	return best
