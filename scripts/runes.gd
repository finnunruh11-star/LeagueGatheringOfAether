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
	"Domination": {0: [[8124, "Predator", "Use your boots out of combat to sprint toward enemy champions and empower your first hit."]], 3: [[8134, "Ingenious Hunter", "Unique takedowns increase item haste."]]},
	"Sorcery": {0: [[8231, "Phase Rush", "Land three distinct attacks or abilities to gain speed and slow resistance."]]},
	"Inspiration": {0: [[8359, "Kleptomancy", "Casting an ability prepares attacks that steal gold and can grant a potion."], [8358, "Omnistone", "Cycle through other keystones as you use them."]], 1: [[8323, "Future's Market", "Buy on credit after two minutes, paying a fee when you enter debt."]], 2: [[8317, "Minion Dematerializer", "Dematerialize three lane minions and permanently deal more damage to their type."]]}
}

const SHARDS := [
	[[5008, "Adaptive Force", "+9 adaptive force."], [5005, "Attack Speed", "+10% attack speed."], [5007, "Ability Haste", "+8 ability haste."]],
	[[5008, "Adaptive Force", "+9 adaptive force."], [5010, "Move Speed", "+2% movement speed."], [5001, "Health Scaling", "+10 health per level, up to 180."]],
	[[5011, "Health", "+65 health."], [5013, "Tenacity and Slow Resist", "+10% tenacity and slow resistance."], [5001, "Health Scaling", "+10 health per level, up to 180."]]
]


static func row(tree: String, index: int) -> Array:
	return TREES[tree][index] + LEGACY.get(tree, {}).get(index, [])


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


static func keystone_name(id: int) -> String:
	for tree in TREES:
		for choice in row(tree, 0):
			if choice[0] == id:
				return choice[1]
	return ""
