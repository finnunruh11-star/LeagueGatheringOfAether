class_name Runes
extends RefCounted

const TREES := {
	"Precision": [
		[[8005, "Press the Attack", "Three attacks on one champion deal bonus damage and start a combat damage boost."], [8008, "Lethal Tempo", "Champion attacks stack attack speed and add on-hit damage at full stacks."], [8021, "Fleet Footwork", "Moving and attacking charge a healing attack with a burst of speed."], [8010, "Conqueror", "Champion hits stack adaptive force; damage heals you at full stacks."]],
		[[9101, "Absorb Life", "Last hits restore health."], [9111, "Triumph", "Champion takedowns restore missing health and grant gold."], [8009, "Presence of Mind", "Champion hits and takedowns restore mana."]],
		[[9104, "Legend: Alacrity", "Farming and takedowns build permanent attack speed."], [9105, "Legend: Haste", "Farming and takedowns build basic ability haste."], [9103, "Legend: Bloodline", "Farming and takedowns build life steal and eventually grant health."]],
		[[8014, "Coup de Grace", "Deal more damage to low-health champions."], [8017, "Cut Down", "Deal more damage to healthy champions."], [8299, "Last Stand", "Deal more damage to champions when your health is low."]]],
	"Domination": [
		[[8112, "Electrocute", "Rapidly land three distinct attacks or abilities to deal bonus damage."], [8128, "Dark Harvest", "Damage low-health champions to collect souls that strengthen later procs."], [9923, "Hail of Blades", "Starting a fight with an attack grants fast follow-up attacks."]],
		[[8126, "Cheap Shot", "Deal bonus true damage to movement-impaired champions."], [8139, "Taste of Blood", "Damaging a champion periodically heals you."], [8143, "Sudden Impact", "Dash or blink, then damage a champion for bonus true damage."]],
		[[8137, "Sixth Sense", "Find nearby hidden enemy wards on a long cooldown."], [8140, "Grisly Mementos", "Takedowns stack summoner spell haste instead of trinket haste."], [8141, "Deep Ward", "Wards in enemy territory, and later the river, last longer and gain health."]],
		[[8135, "Treasure Hunter", "Your first takedown on each opponent grants increasing bonus gold."], [8105, "Relentless Hunter", "Unique takedowns increase out-of-combat movement speed."], [8106, "Ultimate Hunter", "Unique takedowns increase ultimate haste."]]],
	"Sorcery": [
		[[8214, "Summon Aery", "Your hits send Aery to damage an enemy, or your support spells send it to shield an ally."], [8229, "Arcane Comet", "Ability hits land a delayed comet around the target's position."], [8230, "Stormraider's Surge", "Burst a champion for a share of their health to gain speed and slow resistance."], [8992, "Deathfire Touch", "Abilities burn champions; sustained burns grow stronger."]],
		[[8224, "Axiom Arcanist", "Strengthen your ultimate's damage, healing and shielding. Takedowns reduce its cooldown."], [8226, "Manaflow Band", "Ability hits grow your mana pool and eventually restore missing mana."], [8275, "Nimbus Cloak", "Gain a burst of movement speed after using a summoner spell."]],
		[[8210, "Transcendence", "Gain haste at levels 5 and 8. From level 11, takedowns shorten basic cooldowns."], [8234, "Celerity", "Gain movement speed and amplify bonus movement speed."], [8233, "Absolute Focus", "Gain adaptive force while above 70% health."]],
		[[8237, "Scorch", "Periodically, your ability hit adds a delayed burst of magic damage."], [8232, "Waterwalking", "Gain movement speed and adaptive force in the river."], [8236, "Gathering Storm", "Gain increasing adaptive force every ten minutes."]]],
	"Resolve": [
		[[8437, "Grasp of the Undying", "Stay in combat, then attack a champion to deal damage, heal and gain permanent health."], [8439, "Aftershock", "Immobilizing a champion grants resistances and then damages nearby enemies."], [8465, "Guardian", "Protect yourself and a nearby ally with shields when they take damage."]],
		[[8446, "Demolish", "Your third attack against a turret deals bonus physical damage."], [8463, "Font of Life", "Impairing a champion heals you and a nearby ally."], [8401, "Shield Bash", "After gaining a shield, your next champion attack deals bonus damage."]],
		[[8429, "Conditioning", "Gain armor and magic resistance at twelve minutes."], [8444, "Second Wind", "Recover missing health over time after taking champion damage."], [8473, "Bone Plating", "An enemy champion's opening hit prepares you to reduce their next three hits."]],
		[[8451, "Overgrowth", "Nearby enemy minion and monster deaths grant permanent health."], [8453, "Revitalize", "Increase healing and shielding, especially on low-health targets."], [8242, "Unflinching", "Gain resistances during crowd control and briefly afterward."]]],
	"Inspiration": [
		[[8351, "Glacial Augment", "Immobilize an enemy champion to create a slowing field that protects allies from that enemy."], [8360, "Unsealed Spellbook", "Out of combat, choose a temporary summoner spell from the scoreboard."], [8369, "First Strike", "Strike a champion first to briefly deal extra damage and earn gold."]],
		[[8306, "Hextech Flashtraption", "While Flash cools down, hold still to channel a short-range Hexflash using the same key."], [8304, "Magical Footwear", "Receive speed-enhanced boots at 12 minutes, earlier with takedowns."], [8321, "Cash Back", "Receive a gold refund when buying Legendary items."]],
		[[8313, "Triple Tonic", "At levels 3, 6 and 9 gain gold, a temporary combat buff and a skill point."], [8352, "Time Warp Tonic", "Potions deliver part of their healing immediately."], [8345, "Biscuit Delivery", "At 2, 4 and 6 minutes, receive a healing biscuit. Use it or sell it for permanent health."]],
		[[8347, "Cosmic Insight", "Gain summoner spell and item haste."], [8410, "Approach Velocity", "Move faster toward impaired enemies, especially those you impaired."], [8316, "Jack Of All Trades", "Different stats on your items grant haste and unlock adaptive force."]]]
}

const LEGACY := {
	"Precision": {1: [[9102, "Overheal", "Excess healing becomes a shield."]], 2: [[9107, "Legend: Tenacity", "Farming and takedowns build tenacity."]]},
	"Domination": {
		0: [[8124, "Predator", "Activate your boots to accelerate while chasing a champion and empower your first hit."]],
		2: [[8136, "Zombie Ward", "Killing enemy wards raises friendly wards and builds adaptive force."], [8120, "Ghost Poro", "Expired wards leave a scout that grants vision and builds adaptive force."], [8138, "Eyeball Collection", "Champion and ward takedowns build adaptive force."]],
		3: [[8134, "Ingenious Hunter", "Unique takedowns increase item haste."], [8132, "Ravenous Hunter", "Gain omnivamp for each unique champion takedown."]]},
	"Sorcery": {0: [[8231, "Phase Rush", "Land three distinct attacks or abilities in four seconds to gain speed and slow resistance."]],
		1: [[8225, "Nullifying Orb", "Magic damage that would put you below 30% health grants a magic shield."], [8243, "The Ultimate Hat", "Reduce your ultimate cooldown; casting it stacks further reduction."]]},
	"Resolve": {2: [[8430, "Iron Skin", "Gain armor. Healing and shielding can briefly increase it further."], [8435, "Mirror Shell", "Gain magic resistance. Healing and shielding can briefly increase it further."], [8472, "Chrysalis", "Start with extra health. After four takedowns, trade it for adaptive force."]]},
	"Inspiration": {
		0: [[8359, "Kleptomancy", "Your next champion attack after casting grants gold and can also grant a consumable."], [8358, "Prototype: Omnistone", "Randomly borrow other keystones and roll again after using one."]],
		1: [[8323, "Future's Market", "Buy on credit after two minutes, paying a fee when you enter debt."], [8324, "Perfect Timing", "Unlock a one-use Stopwatch after six minutes and shorten defensive item cooldowns."]],
		2: [[8317, "Minion Dematerializer", "After four minutes, erase up to six lane minions and increase damage to each type absorbed."]],
		3: [[8339, "Celestial Body", "Gain 100 health, but deal less damage to champions and monsters until ten minutes."]]}
}

const PATCHES := {
	8005: "7.23", 8008: "12.19", 8021: "8.10", 8010: "9.4", 9101: "14.14", 9102: "9.5", 9111: "7.23", 8009: "9.22",
	9104: "10.3", 9105: "14.10", 9107: "12.23", 9103: "10.22", 8014: "7.23", 8017: "14.10", 8299: "8.1",
	8112: "8.15", 8124: "11.23", 8128: "8.23", 9923: "26.8", 8126: "8.15", 8139: "12.9", 8143: "8.15",
	8136: "9.7", 8120: "11.13", 8138: "7.23", 8137: "25.5", 8140: "25.S1.2", 8141: "25.S1.2",
	8132: "11.1", 8134: "11.21", 8105: "10.19", 8106: "11.1", 8135: "13.3",
	8214: "7.22", 8229: "26.8", 8231: "11.9", 8230: "26.10", 8992: "26.9", 8225: "12.9", 8224: "25.S1.3",
	8226: "7.23", 8275: "11.12", 8243: "8.10", 8210: "10.23", 8234: "8.15", 8233: "9.1", 8237: "7.23",
	8232: "13.19", 8236: "7.22",
	8437: "25.11", 8439: "8.1", 8465: "10.12", 8446: "8.22", 8463: "12.9", 8401: "9.1", 8430: "8.5",
	8435: "8.5", 8472: "8.9", 8429: "12.9", 8444: "12.13", 8473: "8.5", 8451: "9.7", 8453: "7.24", 8242: "12.13",
	8351: "13.14", 8359: "7.23", 8360: "25.13", 8358: "10.3", 8369: "14.11", 8306: "7.22", 8304: "8.2",
	8324: "8.3", 8321: "26.2", 8323: "13.16", 8317: "9.5", 8313: "26.2", 8352: "8.21", 8345: "11.10",
	8347: "11.1", 8410: "10.12", 8339: "8.3", 8316: "26.14"
}

const HISTORICAL_TOOLTIPS := {
	8005: "Three consecutive champion attacks deal bonus damage and expose that target to damage from all sources.",
	8008: "Champion attacks stack attack speed. At six stacks, gain attack range and break the attack speed cap.",
	8010: "Stack adaptive force on champion hits. At five stacks, convert part of your damage into true damage and heal.",
	8009: "Champion takedowns restore 20% maximum mana and refund 10% of your ultimate cooldown.",
	9103: "Farming and takedowns build up to 20 stacks of life steal.",
	8014: "Deal more damage to low-health champions. Takedowns briefly grant adaptive force.",
	8143: "After using mobility or breaking stealth, champion damage grants lethality and magic penetration.",
	8226: "Periodically refund the resource cost of your next ability and restore missing mana.",
	8234: "Gain movement speed and convert bonus movement speed to adaptive force.",
	8446: "Charge up while near a turret, then strike it for bonus physical damage.",
	8463: "Impair enemies to mark them. Allied champions heal when attacking a marked target.",
	8242: "Gain tenacity and slow resistance, increasing as your health falls.",
	8304: "Get boots at ten minutes, 30 seconds earlier per takedown, with bonus speed and a cheaper upgrade.",
	8313: "Receive usable elixirs at levels 3, 6, and 9.",
	8352: "Potions, biscuits and elixirs last longer and give movement speed during their effects.",
	8345: "Receive three biscuits that restore missing health and mana, and permanently increase mana when used or sold."
}
const SHARDS := [
	[[5008, "Adaptive Force", "+9 adaptive force."], [5005, "Attack Speed", "+10% attack speed."], [5007, "Ability Haste", "+8 ability haste."]],
	[[5008, "Adaptive Force", "+9 adaptive force."], [5010, "Move Speed", "+2% movement speed."], [5001, "Health Scaling", "+10 health per level, up to 180."]],
	[[5011, "Health", "+65 health."], [5013, "Tenacity and Slow Resist", "+10% tenacity and slow resistance."], [5001, "Health Scaling", "+10 health per level, up to 180."]]
]


static func row(tree: String, index: int) -> Array:
	return TREES[tree][index] + LEGACY.get(tree, {}).get(index, [])


static func tooltip(choice: Array) -> String:
	var id: int = choice[0]
	return "%s\nPatch %s" % [HISTORICAL_TOOLTIPS.get(id, choice[2]), PATCHES[id]] if PATCHES.has(id) else choice[2]


static func can_immobilize(effects: Array) -> bool:
	for effect in effects:
		if not effect is Dictionary:
			continue
		if effect.get("type") in ["root", "stun", "knockback", "pull"]:
			return true
		for key in ["effects", "on_hit", "on_end", "then", "else"]:
			var nested = effect.get(key)
			if nested is Array and can_immobilize(nested):
				return true
	return false


static func _has(row: Array, id) -> bool:
	if not id is int and not id is float:
		return false
	for choice in row:
		if choice[0] == id:
			return true
	return false


static func valid(page) -> bool:
	if not page is Dictionary or not page.get("primary") is String or not page.get("secondary") is String:
		return false
	if not TREES.has(page.primary) or not TREES.has(page.secondary) or page.primary == page.secondary:
		return false
	var major = page.get("major")
	var minor = page.get("minor")
	var shards = page.get("shards")
	if not major is Array or major.size() != 4 or not minor is Array or minor.size() != 2 or not shards is Array or shards.size() != 3:
		return false
	for i in 4:
		if not _has(row(page.primary, i), major[i]):
			return false
	var rows := secondary_rows(page.secondary, minor)
	if rows.size() != 2 or minor[0] == minor[1]:
		return false
	for i in 3:
		if not _has(SHARDS[i], shards[i]):
			return false
	return true


static func secondary_rows(tree: String, ids: Array) -> Array:
	var rows := []
	for i in range(1, 4):
		for id in ids:
			if _has(row(tree, i), id):
				rows.append(i)
				break
	return rows


static func canonical(page: Dictionary) -> Dictionary:
	return {"primary": page.primary, "secondary": page.secondary,
		"major": page.major.map(func(id): return int(id)), "minor": page.minor.map(func(id): return int(id)),
		"shards": page.shards.map(func(id): return int(id))}


static func preset(role := "") -> Dictionary:
	match role:
		"mage":
			return {"primary": "Sorcery", "secondary": "Precision", "major": [8229, 8226, 8210, 8237], "minor": [8009, 8014], "shards": [5008, 5008, 5011]}
		"tank", "support":
			return {"primary": "Resolve", "secondary": "Inspiration", "major": [8437, 8446, 8429, 8451], "minor": [8345, 8347], "shards": [5007, 5001, 5011]}
		"assassin":
			return {"primary": "Domination", "secondary": "Sorcery", "major": [8112, 8143, 8140, 8135], "minor": [8275, 8237], "shards": [5008, 5008, 5011]}
	return {"primary": "Precision", "secondary": "Resolve", "major": [8005, 9111, 9104, 8014], "minor": [8473, 8451], "shards": [5005, 5008, 5011]}


static func keystone(page: Dictionary) -> String:
	return keystone_name(page.major[0])


const TREE_COLORS := {"Precision": Color("c8aa6e"), "Domination": Color("e05050"), "Sorcery": Color("9faafc"),
	"Resolve": Color("a1d586"), "Inspiration": Color("49c6d8")}


## The path a rune belongs to ("" if unknown).
static func tree_of(id: int) -> String:
	for tree in TREES:
		for i in 4:
			if _has(row(tree, i), id):
				return tree
	return ""


static func tree_color(id: int) -> Color:
	return TREE_COLORS.get(tree_of(id), Color(0.9, 0.9, 0.9))


static func keystone_name(id: int) -> String:
	for tree in TREES:
		for choice in row(tree, 0):
			if choice[0] == id:
				return choice[1]
	return ""
