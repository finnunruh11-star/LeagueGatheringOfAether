class_name ItemUI
extends RefCounted
## Shared item drawing/text helpers for the HUD and the shop.

const STAT_NAMES := {
	"max_hp": ["Health", false], "hp_regen": ["Health Regen /s", false], "hp_regen_percent": ["Base Health Regen", true],
	"max_mana": ["Mana", false], "mana_regen": ["Mana Regen /s", false], "mana_regen_percent": ["Base Mana Regen", true],
	"move_speed": ["Move Speed", false], "move_speed_bonus": ["Move Speed", true], "attack_damage": ["Attack Damage", false],
	"ability_power": ["Ability Power", false], "bonus_attack_speed": ["Attack Speed", true], "attack_range": ["Attack Range", false],
	"armor": ["Armor", false], "magic_resist": ["Magic Resist", false], "crit_chance": ["Critical Strike Chance", true],
	"crit_damage": ["Critical Strike Damage", true], "ability_haste": ["Ability Haste", false], "lethality": ["Lethality", false],
	"armor_pen": ["Armor Penetration", true], "magic_pen": ["Magic Penetration", false], "magic_pen_percent": ["Magic Penetration", true],
	"lifesteal": ["Life Steal", true], "omnivamp": ["Omnivamp", true], "heal_power": ["Heal and Shield Power", true],
	"heal_received": ["Healing Received", true], "tenacity": ["Tenacity", true], "slow_resist": ["Slow Resist", true],
	"vision": ["Vision Range", false], "size": ["Size", false], "damage_mult": ["Damage Dealt", true],
	"damage_taken_mult": ["Damage Taken", true], "cooldown_mult": ["Cooldowns", true], "attack_speed": ["Base Attack Speed", false],
}
const RARITY_COLORS := {
	"basic": Color(0.55, 0.57, 0.62), "epic": Color(0.35, 0.6, 1.0), "legendary": Color(1.0, 0.55, 0.2),
	"mythic": Color(0.85, 0.35, 1.0), "boots": Color(0.55, 0.85, 0.55), "starter": Color(0.6, 0.8, 0.7),
	"consumable": Color(0.95, 0.45, 0.5), "jungle": Color(0.45, 0.8, 0.35), "transform": Color(1.0, 0.85, 0.3),
}


static func rarity_color(it: Dictionary) -> Color:
	return RARITY_COLORS.get(it.get("rarity", "basic"), Color.GRAY)


## Draws an item icon (its texture, or a procedural badge) into `r`.
static func draw_icon(ci: CanvasItem, r: Rect2, it: Dictionary, dim := false) -> void:
	var font := ThemeDB.fallback_font
	var col: Color = it.get("color", Color.GRAY)
	if it.get("icon") != null:
		ci.draw_texture_rect(it.icon, r, false, Color(0.5, 0.5, 0.5) if dim else Color.WHITE)
	else:
		var top := col.darkened(0.15)
		var bottom := col.darkened(0.6)
		var steps := 6
		for i in steps:
			var y0 := r.position.y + r.size.y * i / steps
			ci.draw_rect(Rect2(r.position.x, y0, r.size.x, r.size.y / steps + 1.0), top.lerp(bottom, float(i) / (steps - 1)))
		ci.draw_circle(r.position + r.size * Vector2(0.3, 0.28), r.size.x * 0.22, Color(1, 1, 1, 0.12))
		var fs := int(r.size.y * (0.42 if str(it.get("short", "")).length() <= 2 else 0.34))
		var y := r.position.y + r.size.y * 0.5 + fs * 0.36
		ci.draw_string_outline(font, Vector2(r.position.x, y), str(it.get("short", "?")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 4, Color(0, 0, 0, 0.7))
		ci.draw_string(font, Vector2(r.position.x, y), str(it.get("short", "?")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(1, 1, 1, 0.95))
		if dim:
			ci.draw_rect(r, Color(0, 0, 0, 0.5))
	ci.draw_rect(r, rarity_color(it), false, 2.0)


static func stat_line(k: String, v) -> String:
	var info: Array = STAT_NAMES.get(k, [k.capitalize(), false])
	if v is String:
		return "%s (scales)" % info[0]
	var f := float(v)
	if info[1]:
		return "%s%s%% %s" % ["+" if f >= 0.0 else "", _fmt(f * 100.0), info[0]]
	return "%s%s %s" % ["+" if f >= 0.0 else "", _fmt(f), info[0]]


static func _fmt(f: float) -> String:
	return str(int(round(f))) if absf(f - round(f)) < 0.05 else "%.1f" % f


## Multi-line plain-text description: stats, passives, active, recipe notes.
static func describe(it: Dictionary, with_header := true) -> String:
	var lines := PackedStringArray()
	if with_header:
		lines.append("%s   (%s, %d gold)" % [it.name, str(it.rarity).capitalize(), int(it.cost)])
	for k in it.stats:
		lines.append(stat_line(k, it.stats[k]))
	for k in it.get("stats_mult", {}):
		var v = it.stats_mult[k]
		if v is float:
			lines.append("x%s %s" % [_fmt(v), STAT_NAMES.get(k, [k])[0]])
	if not it.get("mythic_stats", {}).is_empty():
		var parts := PackedStringArray()
		for k in it.mythic_stats:
			parts.append(stat_line(k, it.mythic_stats[k]))
		lines.append("Mythic: each other Legendary item grants " + ", ".join(parts))
	var shown := {}
	for p in it.get("passives", []):
		var n := str(p.get("name", ""))
		if n == "" or shown.has(n):
			continue
		shown[n] = true
		var d := str(p.get("description", ""))
		lines.append(("[%s] %s" % [n, d]) if d != "" else "[%s]" % n)
	if it.get("active") != null:
		var a: Dictionary = it.active
		var cd = a.get("cooldown", 0)
		lines.append("Active - %s: %s%s" % [a.name, a.description, ("  (%ss cooldown)" % str(cd)) if not (cd is float and cd <= 0.0) else ""])
	if str(it.get("description", "")) != "":
		lines.append(str(it.description))
	if not it.get("groups", []).is_empty():
		lines.append("Limit: one %s item" % ", ".join(it.groups).replace("_", " "))
	return "\n".join(lines)
