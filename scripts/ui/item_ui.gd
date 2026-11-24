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


## The local player's champion: expression stats and cooldowns are shown as their current value for it.
static func viewer() -> Champion:
	var w = Game.world
	if not is_instance_valid(w):
		return null
	var ch = w.get("local_champion")
	return ch if is_instance_valid(ch) and ch is Champion else null


static func _eval(v, fallback: float) -> float:
	var ch := viewer()
	return Effects.num(v, {"caster": ch, "target": ch, "rank": ch.level}, fallback) if ch != null else fallback


static func stat_line(k: String, v) -> String:
	var info: Array = STAT_NAMES.get(k, [k.capitalize(), false])
	var note := ""
	if v is String:
		if viewer() == null:
			return "%s (scales)" % info[0]
		v = _eval(v, 0.0)
		if absf(v) < 0.0001:
			return ""  # a conditional stat that is currently off - the passive text explains it
		note = " (scales)"
	var f := float(v)
	if info[1]:
		return "%s%s%% %s%s" % ["+" if f >= 0.0 else "", _fmt(f * 100.0), info[0], note]
	return "%s%s %s%s" % ["+" if f >= 0.0 else "", _fmt(f), info[0], note]


static func _fmt(f: float) -> String:
	return str(int(round(f))) if absf(f - round(f)) < 0.05 else "%.1f" % f


## The pieces of an item's description, in display order:
## ["stat", text] / ["mythic", text] / ["passive", name, description] /
## ["active", name, description, cooldown text or ""] / ["text", text] / ["limit", text]
static func parts(it: Dictionary) -> Array:
	var out := []
	for k in it.stats:
		var line := stat_line(k, it.stats[k])
		if line != "":
			out.append(["stat", line])
	for k in it.get("stats_mult", {}):
		var v = it.stats_mult[k]
		if v is float:
			out.append(["stat", "x%s %s" % [_fmt(v), STAT_NAMES.get(k, [k])[0]]])
	if not it.get("mythic_stats", {}).is_empty():
		var bonus := PackedStringArray()
		for k in it.mythic_stats:
			var line := stat_line(k, it.mythic_stats[k])
			if line != "":
				bonus.append(line)
		out.append(["mythic", "Mythic: each other Legendary item grants " + ", ".join(bonus)])
	var shown := {}
	for p in it.get("passives", []):
		var n := str(p.get("name", ""))
		if n == "" or shown.has(n):
			continue
		shown[n] = true
		out.append(["passive", n, str(p.get("description", ""))])
	if it.get("active") != null:
		var a: Dictionary = it.active
		var cd = a.get("cooldown", 0)
		if cd is String and viewer() != null:
			cd = _eval(cd, 0.0)
		var cd_text := (_fmt(float(cd)) + "s cooldown") if cd is float or cd is int else "Cooldown scales"
		out.append(["active", str(a.name), str(a.description), cd_text if not ((cd is float or cd is int) and cd <= 0) else ""])
	if str(it.get("description", "")) != "":
		out.append(["text", str(it.description)])
	if not it.get("groups", []).is_empty():
		out.append(["limit", "Limit: one %s item" % ", ".join(it.groups).replace("_", " ")])
	return out


## Multi-line plain-text description: stats, passives, active, recipe notes.
static func describe(it: Dictionary, with_header := true) -> String:
	var lines := PackedStringArray()
	if with_header:
		lines.append("%s   (%s, %d gold)" % [it.name, str(it.rarity).capitalize(), int(it.cost)])
	for p in parts(it):
		match p[0]:
			"passive":
				lines.append(("[%s] %s" % [p[1], p[2]]) if p[2] != "" else "[%s]" % p[1])
			"active":
				lines.append("Active - %s: %s%s" % [p[1], p[2], ("  (%s)" % p[3]) if p[3] != "" else ""])
			_:
				lines.append(p[1])
	return "\n".join(lines)


## describe() as colored BBCode for a RichTextLabel (stats, then passives/active/notes).
static func describe_bbcode(it: Dictionary) -> String:
	var stats := PackedStringArray()
	var rest := PackedStringArray()
	for p in parts(it):
		match p[0]:
			"stat":
				stats.append("[color=#cfe8c8]%s[/color]" % _bb(p[1]))
			"mythic":
				rest.append("[color=#d39bff]%s[/color]" % _bb(p[1]))
			"passive":
				rest.append("[color=#ffd27a][b]%s[/b][/color]%s" % [_bb(p[1]), (": " + _bb(p[2])) if p[2] != "" else ""])
			"active":
				rest.append("[color=#8fd3ff][b]Active - %s[/b][/color]%s%s" % [_bb(p[1]), (": " + _bb(p[2])) if p[2] != "" else "",
					("  [color=#8a90a0](%s)[/color]" % _bb(p[3])) if p[3] != "" else ""])
			"text":
				rest.append("[color=#a9adb6][i]%s[/i][/color]" % _bb(p[1]))
			"limit":
				rest.append("[color=#ffa36b]%s[/color]" % _bb(p[1]))
	var blocks := PackedStringArray()
	if not stats.is_empty():
		blocks.append("\n".join(stats))
	if not rest.is_empty():
		blocks.append("\n\n".join(rest))
	return "\n\n".join(blocks) if not blocks.is_empty() else "[color=#8a90a0]No stats.[/color]"


static func _bb(s: String) -> String:
	return s.replace("[", "[lb]")


## A custom tooltip body (return it from Control._make_custom_tooltip): name, rarity and cost,
## then the description, colored like the shop. `notes` are extra [text, color] lines.
static func tooltip(it: Dictionary, notes: Array = []) -> Control:
	var t := Tip.new()
	t.add(str(it.name), rarity_color(it), 17)
	t.add("%s  -  %d gold" % [str(it.rarity).capitalize(), int(it.cost)], Color(1, 0.85, 0.4), 13, 2.0)
	var prev := ""
	for p in parts(it):
		var gap := 0.0 if p[0] == "stat" and prev == "stat" else 7.0
		prev = p[0]
		match p[0]:
			"stat":
				t.add(p[1], Color(0.82, 0.93, 0.8), 14, gap)
			"mythic":
				t.add(p[1], Color(0.83, 0.61, 1.0), 13, gap)
			"passive":
				t.add(p[1], Color(1, 0.82, 0.48), 14, gap)
				t.add(p[2], Color(0.82, 0.84, 0.88), 13, 1.0)
			"active":
				t.add("Active - " + p[1] + (("  (%s)" % p[3]) if p[3] != "" else ""), Color(0.56, 0.83, 1.0), 14, gap)
				t.add(p[2], Color(0.82, 0.84, 0.88), 13, 1.0)
			"text":
				t.add(p[1], Color(0.66, 0.68, 0.72), 13, gap)
			"limit":
				t.add(p[1], Color(1, 0.64, 0.42), 13, gap)
	for i in notes.size():
		t.add(str(notes[i][0]), notes[i][1], 13, 8.0 if i == 0 else 1.0)
	t.finish()
	return t


class Tip extends Control:
	const MAX_W := 340.0
	var rows: Array = []   # [text, color, font size, gap above]

	func add(text: String, color: Color, font_size: int, gap := 0.0) -> void:
		if text != "":
			rows.append([text, color, font_size, gap])

	func finish() -> void:
		var font := ThemeDB.fallback_font
		var w := 0.0
		for r in rows:
			w = maxf(w, font.get_multiline_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, r[2]).x)
		w = minf(ceilf(w) + 2.0, MAX_W)
		var h := 0.0
		for r in rows:
			h += r[3] + font.get_multiline_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, w, r[2]).y
		custom_minimum_size = Vector2(w, ceilf(h))
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := custom_minimum_size.x
		var y := 0.0
		for r in rows:
			y += r[3]
			draw_multiline_string(font, Vector2(0, y + font.get_ascent(r[2])), r[0], HORIZONTAL_ALIGNMENT_LEFT, w, r[2], -1, r[1])
			y += font.get_multiline_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, w, r[2]).y
