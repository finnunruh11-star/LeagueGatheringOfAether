class_name Hud
extends CanvasLayer
## In-match UI: ability bar, health/xp, score, kill feed, minimap, menus.

class DrawControl extends Control:
	var draw_func: Callable

	func _draw() -> void:
		if draw_func.is_valid():
			draw_func.call(self)


const SLOT_KEYS := ["p", "q", "w", "e", "r"]
const HELP := "RMB move/attack   QWER hold to aim, release to cast   A+LMB attack-move   S stop   B recall   Y camera lock   Space center   Tab scores   Esc menu"

var world: World
var font: Font
var top_label: Label
var feed_label: Label
var center_label: Label
var bar: DrawControl
var slot_boxes := {}
var minimap: DrawControl
var scores: DrawControl
var end_panel: PanelContainer
var end_label: Label
var menu_panel: PanelContainer
var feed: Array = []
var _tooltips_for := ""
var _last_hp := -1.0


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	top_label = _label(root, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_place(top_label, 0.5, 0.0, -300, 8, 600, 40)
	feed_label = _label(root, 16, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(feed_label, 1.0, 0.0, -620, 10, 600, 200)
	center_label = _label(root, 36, HORIZONTAL_ALIGNMENT_CENTER)
	_place(center_label, 0.5, 0.3, -400, 0, 800, 60)
	var help := _label(root, 13, HORIZONTAL_ALIGNMENT_LEFT)
	help.text = HELP
	help.modulate = Color(1, 1, 1, 0.55)
	_place(help, 0.0, 1.0, 12, -26, 1200, 20)

	bar = DrawControl.new()
	bar.draw_func = _draw_bar
	_place(bar, 0.5, 1.0, -300, -152, 600, 120)
	root.add_child(bar)
	for i in SLOT_KEYS.size():
		var s := DrawControl.new()
		var key: String = SLOT_KEYS[i]
		s.draw_func = func(c): _draw_slot(c, key)
		s.position = Vector2(112 + i * 72, 10)
		s.size = Vector2(64, 64)
		bar.add_child(s)
		slot_boxes[key] = s

	minimap = DrawControl.new()
	minimap.draw_func = _draw_minimap
	var mw := 300.0
	var mh := mw * world.map.size.y / world.map.size.x
	_place(minimap, 1.0, 1.0, -mw - 12, -mh - 36, mw, mh)
	minimap.gui_input.connect(_minimap_input)
	root.add_child(minimap)

	scores = DrawControl.new()
	scores.draw_func = _draw_scores
	scores.visible = false
	scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(scores, 0.5, 0.5, -360, -220, 720, 440)
	root.add_child(scores)

	end_panel = _panel(root)
	var ev := end_panel.get_child(0)
	end_label = _label(ev, 40, HORIZONTAL_ALIGNMENT_CENTER)
	if Game.is_host():
		_button(ev, "Back to lobby", Game.return_to_lobby)
	else:
		var wl := _label(ev, 18, HORIZONTAL_ALIGNMENT_CENTER)
		wl.text = "Waiting for the host to return to the lobby..."
	_button(ev, "Leave to main menu", _leave)

	menu_panel = _panel(root)
	var mv := menu_panel.get_child(0)
	var ml := _label(mv, 24, HORIZONTAL_ALIGNMENT_CENTER)
	ml.text = "Menu (the game keeps running)"
	_button(mv, "Resume", toggle_menu)
	if Game.is_host():
		_button(mv, "End match - back to lobby", Game.return_to_lobby)
	_button(mv, "Leave to main menu", _leave)


func _place(c: Control, ax: float, ay: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


func _label(parent: Node, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	_place(p, 0.5, 0.45, -230, -120, 460, 240)
	p.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	root.add_child(p)
	return p


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _leave() -> void:
	Game.leave()
	Game.left_game.emit("")


func toggle_menu() -> void:
	menu_panel.visible = not menu_panel.visible and not end_panel.visible


func show_scores(on: bool) -> void:
	scores.visible = on


func show_end(t: int) -> void:
	menu_panel.visible = false
	end_panel.visible = true
	var won := t == world.local_team
	end_label.text = ("VICTORY!" if won else "DEFEAT") + "\n%s team wins" % Game.TEAM_NAMES[t]
	end_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if won else Color(1, 0.4, 0.35))


func announce(text: String, col: Color) -> void:
	feed.append([text, col, Time.get_ticks_msec()])
	if feed.size() > 6:
		feed.pop_front()


func _process(_delta: float) -> void:
	var t := int(world.time)
	top_label.text = "%s %d  :  %d %s      %02d:%02d" % [Game.TEAM_NAMES[0], world.kills[0], world.kills[1], Game.TEAM_NAMES[1], t / 60, t % 60]
	var now := Time.get_ticks_msec()
	var lines := PackedStringArray()
	for f in feed:
		if now - f[2] < 10000:
			lines.append(f[0])
	feed_label.text = "\n".join(lines)
	var ch := world.local_champion
	if ch != null:
		if _last_hp >= 0.0 and ch.hp < _last_hp - ch.stats.max_hp * 0.01 and not ch.dead:
			world._sfx("hit", null, -14.0)
		_last_hp = ch.hp
	center_label.text = ""
	if not world.started:
		center_label.text = "Waiting for players..."
	elif ch != null and ch.dead and not world.ended:
		center_label.text = "Respawning in %d" % ceili(ch.respawn_timer)
	elif ch != null and ch.recall_timer > 0.0:
		center_label.text = "Recalling... %.1f" % ch.recall_timer
	if ch != null and _tooltips_for != ch.char_id:
		_tooltips_for = ch.char_id
		_build_tooltips(ch)
	bar.queue_redraw()
	for s in slot_boxes.values():
		s.queue_redraw()
	minimap.queue_redraw()
	if scores.visible:
		scores.queue_redraw()


func _build_tooltips(ch: Champion) -> void:
	var p: Dictionary = ch.def.passive
	slot_boxes.p.tooltip_text = "Passive - %s\n%s" % [p.name, p.description]
	for slot in ["q", "w", "e", "r"]:
		var ab = ch.def.abilities.get(slot)
		if ab == null:
			slot_boxes[slot].tooltip_text = "(no ability)"
			continue
		slot_boxes[slot].tooltip_text = "%s - %s\nCooldown: %s   Range: %s   Targeting: %s\n%s" % [
			slot.to_upper(), ab.name, str(ab.cooldown), str(ab.range), ab.targeting, ab.description]


# ---------------------------------------------------------------- drawing ---

func _draw_bar(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.05, 0.06, 0.08, 0.92))
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.3, 0.32, 0.38), false, 2.0)
	var ch := world.local_champion
	if ch == null:
		return
	var pr := Rect2(10, 10, 90, 90)
	if ch.def.get("portrait") != null:
		c.draw_texture_rect(ch.def.portrait, pr, false)
	else:
		c.draw_rect(pr, ch.color.darkened(0.2))
		c.draw_string(font, Vector2(pr.position.x, pr.position.y + 58), ch.display_name.substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 34)
	c.draw_rect(pr, ch.team_color(), false, 3.0)
	c.draw_circle(Vector2(98, 98), 14.0, Color(0.1, 0.1, 0.12))
	c.draw_arc(Vector2(98, 98), 14.0, 0, TAU, 24, Color(1, 0.85, 0.4), 2.0)
	c.draw_string(font, Vector2(84, 104), str(ch.level), HORIZONTAL_ALIGNMENT_CENTER, 28, 15, Color(1, 0.9, 0.5))
	var hb := Rect2(112, 80, 352, 18)
	var total := maxf(ch.stats.max_hp, ch.hp + ch.shield)
	c.draw_rect(hb, Color(0.18, 0.06, 0.06))
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * ch.hp / total, hb.size.y)), Color(0.25, 0.75, 0.3))
	if ch.shield > 0.0:
		c.draw_rect(Rect2(hb.position + Vector2(hb.size.x * ch.hp / total, 0), Vector2(hb.size.x * ch.shield / total, hb.size.y)), Color(0.9, 0.9, 0.95))
	c.draw_string(font, hb.position + Vector2(0, 14), "%d / %d" % [int(ch.hp), int(ch.stats.max_hp)], HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, 13)
	var xb := Rect2(112, 102, 352, 7)
	c.draw_rect(xb, Color(0.1, 0.1, 0.15))
	c.draw_rect(Rect2(xb.position, Vector2(xb.size.x * clampf(ch.xp_frac, 0.0, 1.0), xb.size.y)), Color(0.6, 0.4, 1.0))
	var lines := ["AD  %d" % int(ch.stats.attack_damage), "AP  %d" % int(ch.stats.ability_power),
		"MS  %d" % int(ch.stats.move_speed), "RNG %d" % int(ch.stats.attack_range)]
	for i in lines.size():
		c.draw_string(font, Vector2(476, 28 + i * 22), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.87, 0.92))


func _draw_slot(c: Control, slot: String) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.07, 0.08, 0.11))
	var ch := world.local_champion
	if ch == null:
		return
	var icon: Texture2D = null
	var nm := ""
	if slot == "p":
		icon = ch.def.passive.get("icon")
		nm = ch.def.passive.name
	else:
		var ab = ch.def.abilities.get(slot)
		if ab != null:
			icon = ab.icon
			nm = ab.name
	var cd: float = ch.cooldowns.get(slot, 0.0) if slot != "p" else 0.0
	if icon != null:
		c.draw_texture_rect(icon, r.grow(-3), false)
	elif nm != "":
		c.draw_rect(r.grow(-3), ch.color.darkened(0.5))
		var abbr := ""
		for w in nm.split(" ", false):
			abbr += w.substr(0, 1).to_upper()
		if cd <= 0.0:
			c.draw_string(font, Vector2(0, 40), abbr.substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 20)
	if cd > 0.0:
		var frac := clampf(cd / maxf(ch.cd_total.get(slot, 1.0), 0.01), 0.0, 1.0)
		c.draw_rect(Rect2(0, c.size.y * (1.0 - frac), c.size.x, c.size.y * frac), Color(0, 0, 0, 0.7))
		var txt := ("%.1f" % cd) if cd < 1.0 else str(ceili(cd))
		c.draw_string_outline(font, Vector2(0, 42), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, 4, Color.BLACK)
		c.draw_string(font, Vector2(0, 42), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22)
	elif slot != "p" and (ch.dead or ch.flags & (Unit.F_STUN | Unit.F_SILENCE)):
		c.draw_rect(r, Color(0, 0, 0, 0.5))
	c.draw_rect(r, Color(0.45, 0.8, 1.0) if world.aim_slot == slot else Color(0.35, 0.37, 0.42), false, 2.0)
	c.draw_string_outline(font, Vector2(4, 15), slot.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color.BLACK)
	c.draw_string(font, Vector2(4, 15), slot.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13)


func _draw_minimap(c: Control) -> void:
	var m := world.map
	var sc := c.size.x / m.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), m.ground.darkened(0.2))
	for l in m.lanes:
		var pts := PackedVector2Array()
		for p in l:
			pts.append(p * sc)
		c.draw_polyline(pts, m.lane_color, 5.0)
	for r in m.walls:
		c.draw_rect(Rect2(r.position * sc, r.size * sc), m.wall_color)
	for t in 2:
		c.draw_circle(m.spawns[t] * sc, 7.0, Color(Game.TEAM_COLORS[t], 0.6))
	for u in world.units:
		if u.dead and not u.is_structure:
			continue
		var p: Vector2 = u.global_position * sc
		var col: Color = u.team_color()
		if u.is_structure:
			c.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 0.4, 0.4) if u.dead else col)
		elif u.is_champion:
			c.draw_circle(p, 5.5, col)
			c.draw_arc(p, 5.5, 0, TAU, 12, Color.WHITE if u == world.local_champion else Color.BLACK, 1.5)
		else:
			c.draw_circle(p, 2.0, col)
	var vs := get_viewport().get_visible_rect().size / world.camera.zoom
	c.draw_rect(Rect2((world.camera.get_screen_center_position() - vs * 0.5) * sc, vs * sc), Color(1, 1, 1, 0.7), false, 1.0)
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.3, 0.32, 0.38), false, 2.0)


func _minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var wp: Vector2 = event.position / minimap.size * world.map.size
		if event.button_index == MOUSE_BUTTON_RIGHT:
			world.send_command("move", [wp])
		elif event.button_index == MOUSE_BUTTON_LEFT:
			world.cam_locked = false
			world.camera.global_position = wp


func _draw_scores(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.05, 0.06, 0.08, 0.92))
	var y := 44.0
	for t in 2:
		c.draw_string(font, Vector2(24, y), "%s team  -  %d kills" % [Game.TEAM_NAMES[t], world.kills[t]], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Game.TEAM_COLORS[t])
		y += 34.0
		for ch in world.champions.values():
			if ch.team != t:
				continue
			var line := "%s  -  %s     Lv %d     %d / %d" % [ch.player_name, ch.display_name, ch.level, ch.kills, ch.deaths]
			c.draw_string(font, Vector2(40, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			y += 28.0
		y += 24.0
