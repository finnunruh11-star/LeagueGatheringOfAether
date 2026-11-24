class_name Hud
extends CanvasLayer
## In-match UI: ability bar, health/xp, score, kill feed, minimap, menus.

class DrawControl extends Control:
	var draw_func: Callable

	func _draw() -> void:
		if draw_func.is_valid():
			draw_func.call(self)


const SLOT_KEYS := ["p", "q", "w", "e", "r"]
const HELP := "RMB move/attack   QWER cast (hold to aim)   Ctrl+QWER level up   1-6 items   P shop   A+LMB attack-move   S stop   B recall   Y camera   Tab scores   Esc menu"
const BAR_W := 860.0
const SLOT_X := 262.0
const ITEM_X := 618.0

var world: World
var font: Font
var top_label: Label
var feed_label: RichTextLabel
var _feed_dirty := false
var center_label: Label
var bar: DrawControl
var slot_boxes := {}
var item_boxes: Array = []
var plus_buttons := {}
var shop: Shop
var notice_label: Label
var _notice_t := 9.0
var minimap: DrawControl
var minimap_units: DrawControl
var scores: DrawControl
var end_panel: PanelContainer
var end_label: Label
var menu_panel: PanelContainer
var feed: Array = []
var _tooltips_for := ""
var _tooltip_key := ""
var _items_key := ""
var _last_hp := -1.0
var vignette: TextureRect
var hurt_rect: TextureRect
var _hurt := 0.0
var desat: ColorRect
var _desat := 0.0
var banner: Label
var _banner_t := 9.0
var _prev_cd := {}
var _ready_flash := {}

const DESAT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g) * 0.7, amount), 1.0);
}
"""


func _ready() -> void:
	layer = 10
	font = ThemeDB.fallback_font
	var desat_layer := CanvasLayer.new()
	desat_layer.layer = 5
	add_child(desat_layer)
	desat = ColorRect.new()
	desat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DESAT_SHADER
	mat.shader = sh
	desat.material = mat
	desat.visible = false
	desat_layer.add_child(desat)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	vignette = _vignette(root, Color(0, 0, 0, 0.55), 0.6)
	hurt_rect = _vignette(root, Color(0.85, 0.05, 0.02, 0.85), 0.45)
	hurt_rect.modulate.a = 0.0

	banner = _label(root, 46, HORIZONTAL_ALIGNMENT_CENTER)
	_place(banner, 0.5, 0.2, -500, 0, 1000, 70)
	banner.pivot_offset = Vector2(500, 35)
	banner.modulate.a = 0.0

	top_label = _label(root, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_place(top_label, 0.5, 0.0, -300, 8, 600, 40)
	feed_label = RichTextLabel.new()
	feed_label.bbcode_enabled = true
	feed_label.scroll_active = false
	feed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_label.add_theme_font_size_override("normal_font_size", 16)
	feed_label.add_theme_constant_override("outline_size", 6)
	feed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(feed_label)
	_place(feed_label, 1.0, 0.0, -620, 10, 600, 200)
	center_label = _label(root, 36, HORIZONTAL_ALIGNMENT_CENTER)
	_place(center_label, 0.5, 0.3, -400, 0, 800, 110)
	var help := _label(root, 13, HORIZONTAL_ALIGNMENT_LEFT)
	help.text = HELP
	help.modulate = Color(1, 1, 1, 0.55)
	_place(help, 0.0, 1.0, 12, -26, 1200, 20)

	bar = DrawControl.new()
	bar.draw_func = _draw_bar
	_place(bar, 0.5, 1.0, -BAR_W * 0.5, -168, BAR_W, 136)
	root.add_child(bar)
	for i in SLOT_KEYS.size():
		var s := DrawControl.new()
		var key: String = SLOT_KEYS[i]
		s.draw_func = func(c): _draw_slot(c, key)
		s.position = Vector2(SLOT_X + i * 70, 12)
		s.size = Vector2(64, 64)
		s.clip_contents = true
		bar.add_child(s)
		slot_boxes[key] = s
		if key != "p":
			var b := Button.new()
			b.text = "+"
			b.add_theme_font_size_override("font_size", 18)
			b.position = Vector2(SLOT_X + i * 70 + 16, -30)
			b.size = Vector2(32, 26)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = "Level up (Ctrl+%s)" % key.to_upper()
			b.pressed.connect(func(): world.send_command("rank_up", [key]))
			b.visible = false
			bar.add_child(b)
			plus_buttons[key] = b
	for i in 6:
		var s := DrawControl.new()
		var idx := i
		s.draw_func = func(c): _draw_item_slot(c, idx)
		s.position = Vector2(ITEM_X + (i % 3) * 50, 12 + (i / 3) * 50)
		s.size = Vector2(44, 44)
		s.gui_input.connect(func(ev): _item_slot_input(ev, idx))
		bar.add_child(s)
		item_boxes.append(s)
	var shop_btn := Button.new()
	shop_btn.text = "Shop (P)"
	shop_btn.focus_mode = Control.FOCUS_NONE
	shop_btn.position = Vector2(ITEM_X + 152, 70)
	shop_btn.size = Vector2(84, 36)
	shop_btn.pressed.connect(toggle_shop)
	bar.add_child(shop_btn)

	notice_label = _label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_place(notice_label, 0.5, 1.0, -400, -232, 800, 30)
	notice_label.add_theme_color_override("font_color", Color(1, 0.7, 0.55))

	shop = Shop.new()
	shop.world = world
	root.add_child(shop)
	shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	minimap = DrawControl.new()
	minimap.draw_func = _draw_minimap
	var mw := 300.0
	var mh := mw * world.map.size.y / world.map.size.x
	_place(minimap, 1.0, 1.0, -mw - 12, -mh - 36, mw, mh)
	minimap.gui_input.connect(_minimap_input)
	minimap.clip_contents = true
	root.add_child(minimap)
	if world.fog != null and world.fog.enabled:
		var mf := TextureRect.new()
		mf.texture = world.fog.mask_texture()
		mf.material = world.fog.minimap_mat
		mf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mf.stretch_mode = TextureRect.STRETCH_SCALE
		mf.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The fog texture covers whole texels, slightly more than the map.
		var cover: Vector2 = Vector2(world.fog.vp.size) * FogOfWar.SCALE / world.map.size
		mf.anchor_right = cover.x
		mf.anchor_bottom = cover.y
		minimap.add_child(mf)
	minimap_units = DrawControl.new()
	minimap_units.draw_func = _draw_minimap_units
	minimap_units.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_units.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	minimap.add_child(minimap_units)

	scores = DrawControl.new()
	scores.draw_func = _draw_scores
	scores.visible = false
	scores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(scores, 0.5, 0.5, -380, -260, 760, 520)
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


## Full-screen radial gradient: transparent center, `col` at the edges.
func _vignette(parent: Control, col: Color, inner: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, inner, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.0), col])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 256
	t.height = 256
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## Red screen-edge flash when the local champion takes damage.
func hurt(frac: float) -> void:
	_hurt = clampf(maxf(_hurt, 0.25 + frac * 3.0), 0.0, 1.0)


## Big center-screen announcement.
func show_banner(text: String, col: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	_banner_t = 0.0


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


func toggle_shop() -> void:
	shop.toggle()


func shop_open() -> bool:
	return shop.is_open()


## Short message above the ability bar (e.g. "Not enough mana").
func notice(text: String) -> void:
	notice_label.text = text
	_notice_t = 0.0


func flash_slot(slot: String) -> void:
	_ready_flash[slot] = 1.0


func show_scores(on: bool) -> void:
	scores.visible = on


func show_end(t: int) -> void:
	menu_panel.visible = false
	end_panel.visible = true
	var won := t == world.local_team
	end_label.text = ("VICTORY!" if won else "DEFEAT") + "\n%s team wins" % Game.TEAM_NAMES[t]
	end_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if won else Color(1, 0.4, 0.35))


func announce(text: String, col: Color) -> void:
	announce_rich("[color=#%s]%s[/color]" % [col.to_html(false), text])


## Adds a BBCode line to the kill feed (top right).
func announce_rich(bbcode: String) -> void:
	feed.append([bbcode, Time.get_ticks_msec()])
	if feed.size() > 6:
		feed.pop_front()
	_feed_dirty = true


func _process(_delta: float) -> void:
	var t := int(world.time)
	top_label.text = "%s %d  :  %d %s      %02d:%02d" % [Game.TEAM_NAMES[0], world.kills[0], world.kills[1], Game.TEAM_NAMES[1], t / 60, t % 60]
	var now := Time.get_ticks_msec()
	var before := feed.size()
	feed = feed.filter(func(f): return now - f[1] < 10000)
	if _feed_dirty or feed.size() != before:
		_feed_dirty = false
		var lines := PackedStringArray()
		for f in feed:
			lines.append(f[0])
		feed_label.text = "[right]%s[/right]" % "\n".join(lines)
	var ch := world.local_champion
	center_label.text = ""
	if not world.started:
		center_label.text = "Waiting for players..."
	elif ch != null and ch.dead and not world.ended:
		center_label.text = "YOU DIED\nRespawning in %d" % ceili(ch.respawn_timer)
	elif ch != null and ch.recall_timer > 0.0:
		center_label.text = "Recalling... %.1f" % ch.recall_timer
	if ch != null and _tooltips_for != ch.char_id:
		_tooltips_for = ch.char_id
		_build_tooltips(ch)
	if ch != null:
		_update_rank_ui(ch)
	_update_effects(_delta, ch)
	_notice_t += _delta
	notice_label.modulate.a = clampf(2.5 - _notice_t, 0.0, 1.0)
	bar.queue_redraw()
	for s in slot_boxes.values():
		s.queue_redraw()
	for s in item_boxes:
		s.queue_redraw()
	minimap.queue_redraw()
	minimap_units.queue_redraw()
	if scores.visible:
		scores.queue_redraw()


func _update_rank_ui(ch: Champion) -> void:
	for slot in plus_buttons:
		plus_buttons[slot].visible = ch.can_rank_up(slot)
	var key := "%s|%s|%d" % [str(ch.ranks), str(ch.level), int(ch.stats.ability_haste)]
	if key != _tooltip_key:
		_tooltip_key = key
		_build_tooltips(ch)
	var ik := ""
	for inst in ch.items:
		ik += (inst.id if inst != null else "-") + ","
	if ik != _items_key:
		_items_key = ik
		for i in 6:
			var it = ch.item_def(i)
			item_boxes[i].tooltip_text = ItemUI.describe(it) if it != null else "Empty item slot %d" % (i + 1)


func _update_effects(delta: float, ch: Champion) -> void:
	_hurt = maxf(_hurt - delta * 1.8, 0.0)
	var low := 0.0
	if ch != null and not ch.dead and ch.hp < ch.stats.max_hp * 0.3:
		low = 0.25 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	hurt_rect.modulate.a = maxf(_hurt, low)
	var dead_amt := 1.0 if ch != null and ch.dead and not world.ended else 0.0
	_desat = move_toward(_desat, dead_amt, delta * 2.5)
	desat.material.set_shader_parameter("amount", _desat)
	desat.visible = _desat > 0.01
	_banner_t += delta
	var bt := _banner_t
	banner.modulate.a = clampf(bt * 6.0, 0.0, 1.0) * clampf((2.2 - bt) * 2.0, 0.0, 1.0)
	banner.scale = Vector2.ONE * (1.0 + 0.5 * maxf(0.0, 0.15 - bt) / 0.15)
	if ch != null:
		for s in ["q", "w", "e", "r"]:
			var cd: float = ch.cooldowns.get(s, 0.0)
			if _prev_cd.get(s, 0.0) > 0.0 and cd <= 0.0:
				_ready_flash[s] = 1.0
			_prev_cd[s] = cd
			_ready_flash[s] = maxf(float(_ready_flash.get(s, 0.0)) - delta * 2.5, 0.0)


func _build_tooltips(ch: Champion) -> void:
	var p: Dictionary = ch.def.passive
	slot_boxes.p.tooltip_text = "Passive - %s\n%s" % [p.name, p.description]
	for slot in ["q", "w", "e", "r"]:
		var ab = ch.def.abilities.get(slot)
		if ab == null:
			slot_boxes[slot].tooltip_text = "(no ability)"
			continue
		var r := int(ch.ranks.get(slot, 0))
		var cost := ch.ability_cost(ab)
		var lines := PackedStringArray()
		lines.append("%s - %s   (rank %d/%d)" % [slot.to_upper(), ab.name, r, int(ab.max_rank)])
		var meta := "Cooldown: %.1fs" % ch.ability_cooldown(ab)
		if cost > 0.0:
			meta += "   Cost: %d %s" % [int(cost), "health" if ab.cost_type == "health" else "mana"]
		meta += "   Range: %d" % int(Effects.num(ab.range, {"caster": ch, "rank": maxi(r, 1)}, 700.0))
		lines.append(meta)
		lines.append(str(ab.description))
		if r == 0:
			lines.append("Not learned yet: press Ctrl+%s or the + button when you have a skill point." % slot.to_upper())
		elif ab.get("auto_rank", false) and r < int(ab.max_rank):
			lines.append("Next rank: +%d%% damage/healing, shorter cooldown." % (50 if slot == "r" else 25))
		slot_boxes[slot].tooltip_text = "\n".join(lines)


func _item_slot_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var ab = world.aim_ability("i%d" % i)
		if ab == null:
			return
		if ab.targeting == "self":
			world._cast("i%d" % i)
		else:
			world.aim_slot = "i%d" % i


# ---------------------------------------------------------------- drawing ---

func _draw_bar(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.05, 0.06, 0.08, 0.92))
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.3, 0.32, 0.38), false, 2.0)
	var ch := world.local_champion
	if ch == null:
		return
	# Stats panel
	var st: Dictionary = ch.stats
	var rows := [
		["AD", "%d" % int(st.attack_damage), "AP", "%d" % int(st.ability_power)],
		["ARM", "%d" % int(st.armor), "MR", "%d" % int(st.get("magic_resist", 0.0))],
		["AS", "%.2f" % st.get("attack_speed", 0.0), "CRIT", "%d%%" % int(round(st.get("crit_chance", 0.0) * 100.0))],
		["AH", "%d" % int(st.get("ability_haste", 0.0)), "MS", "%d" % int(st.move_speed)],
		["RNG", "%d" % int(st.attack_range), "VAMP", "%d%%" % int(round((st.get("lifesteal", 0.0) + st.get("omnivamp", 0.0)) * 100.0))],
	]
	for i in rows.size():
		var y := 26.0 + i * 22.0
		for j in 2:
			var x := 8.0 + j * 74.0
			c.draw_string(font, Vector2(x, y), rows[i][j * 2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.63, 0.7))
			c.draw_string(font, Vector2(x + 37, y), rows[i][j * 2 + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.93, 0.96))
	var pen := PackedStringArray()
	if st.get("lethality", 0.0) > 0.0:
		pen.append("Leth %d" % int(st.lethality))
	if st.get("armor_pen", 0.0) > 0.0:
		pen.append("ArPen %d%%" % int(st.armor_pen * 100.0))
	if st.get("magic_pen", 0.0) > 0.0 or st.get("magic_pen_percent", 0.0) > 0.0:
		pen.append("MPen %d|%d%%" % [int(st.get("magic_pen", 0.0)), int(st.get("magic_pen_percent", 0.0) * 100.0)])
	if not pen.is_empty():
		c.draw_string(font, Vector2(10, 128), "  ".join(pen), HORIZONTAL_ALIGNMENT_LEFT, 145, 11, Color(1, 0.75, 0.55))
	# Portrait
	var pr := Rect2(160, 10, 92, 92)
	if ch.def.get("portrait") != null:
		c.draw_texture_rect(ch.def.portrait, pr, false)
	else:
		c.draw_rect(pr, ch.color.darkened(0.2))
		c.draw_string(font, Vector2(pr.position.x, pr.position.y + 58), ch.display_name.substr(0, 2), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 34)
	c.draw_rect(pr, ch.team_color(), false, 3.0)
	c.draw_circle(Vector2(250, 100), 14.0, Color(0.1, 0.1, 0.12))
	c.draw_arc(Vector2(250, 100), 14.0, 0, TAU, 24, Color(1, 0.85, 0.4), 2.0)
	c.draw_string(font, Vector2(236, 106), str(ch.level), HORIZONTAL_ALIGNMENT_CENTER, 28, 15, Color(1, 0.9, 0.5))
	var xb := Rect2(160, 110, 92, 6)
	c.draw_rect(xb, Color(0.1, 0.1, 0.15))
	c.draw_rect(Rect2(xb.position, Vector2(xb.size.x * clampf(ch.xp_frac, 0.0, 1.0), xb.size.y)), Color(0.6, 0.4, 1.0))
	if ch.skill_points > 0:
		c.draw_string_outline(font, Vector2(160, 130), "%d skill point%s" % [ch.skill_points, "s" if ch.skill_points > 1 else ""], HORIZONTAL_ALIGNMENT_CENTER, 92, 12, 3, Color.BLACK)
		c.draw_string(font, Vector2(160, 130), "%d skill point%s" % [ch.skill_points, "s" if ch.skill_points > 1 else ""], HORIZONTAL_ALIGNMENT_CENTER, 92, 12, Color(1, 0.9, 0.4))
	# Health and mana
	var bw := 4 * 70.0 + 64.0
	for i in 4:
		var s: String = ["q", "w", "e", "r"][i]
		var ab = ch.def.abilities.get(s)
		if ab == null:
			continue
		var n := int(ab.max_rank)
		var x0 := SLOT_X + (i + 1) * 70.0
		var pw := (64.0 - (n - 1) * 3.0) / n
		for k in n:
			var on := k < int(ch.ranks.get(s, 0))
			c.draw_rect(Rect2(x0 + k * (pw + 3.0), 80, pw, 6), Color(1, 0.82, 0.35) if on else Color(0.22, 0.23, 0.27))
	var hb := Rect2(SLOT_X, 92, bw, 17)
	var total := maxf(ch.stats.max_hp, ch.hp + ch.shield)
	c.draw_rect(hb, Color(0.18, 0.06, 0.06))
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * ch.hp / total, hb.size.y)), Color(0.25, 0.75, 0.3))
	if ch.shield > 0.0:
		c.draw_rect(Rect2(hb.position + Vector2(hb.size.x * ch.hp / total, 0), Vector2(hb.size.x * ch.shield / total, hb.size.y)), Color(0.9, 0.9, 0.95))
	c.draw_string(font, hb.position + Vector2(0, 13), "%d / %d" % [int(ch.hp), int(ch.stats.max_hp)], HORIZONTAL_ALIGNMENT_CENTER, hb.size.x, 13)
	c.draw_string(font, hb.position + Vector2(0, 13), "+%.1f " % ch.stats.get("hp_regen", 0.0), HORIZONTAL_ALIGNMENT_RIGHT, hb.size.x, 11, Color(0.8, 1, 0.8, 0.8))
	var mb := Rect2(SLOT_X, 112, bw, 13)
	if ch.stats.max_mana > 0.0:
		c.draw_rect(mb, Color(0.06, 0.08, 0.2))
		c.draw_rect(Rect2(mb.position, Vector2(mb.size.x * clampf(ch.mana / ch.stats.max_mana, 0.0, 1.0), mb.size.y)), Color(0.3, 0.55, 1.0))
		c.draw_string(font, mb.position + Vector2(0, 11), "%d / %d" % [int(ch.mana), int(ch.stats.max_mana)], HORIZONTAL_ALIGNMENT_CENTER, mb.size.x, 11)
	else:
		c.draw_rect(mb, Color(0.12, 0.12, 0.14))
		c.draw_string(font, mb.position + Vector2(0, 11), "no mana", HORIZONTAL_ALIGNMENT_CENTER, mb.size.x, 11, Color(0.6, 0.6, 0.65))
	# Gold
	var gx := ITEM_X + 152
	c.draw_circle(Vector2(gx + 10, 32), 8.0, Color(1, 0.8, 0.2))
	c.draw_circle(Vector2(gx + 10, 32), 5.0, Color(0.85, 0.6, 0.1))
	c.draw_string(font, Vector2(gx + 22, 38), str(int(ch.gold)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.88, 0.4))
	if ch.can_shop():
		c.draw_string(font, Vector2(gx, 60), "can shop", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1, 0.6, 0.8))


func _draw_item_slot(c: Control, i: int) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.08, 0.09, 0.12))
	var ch := world.local_champion
	if ch == null:
		return
	var it = ch.item_def(i)
	if it == null:
		c.draw_rect(r, Color(0.25, 0.27, 0.32), false, 1.0)
	else:
		var view := ch.item_view(i)
		var n := int(view[0])
		var cd: float = view[1]
		ItemUI.draw_icon(c, r.grow(-2), it, it.charges > 0 and n <= 0)
		if cd > 0.0:
			var frac := clampf(cd / maxf(view[2], 0.01), 0.0, 1.0)
			c.draw_rect(Rect2(0, c.size.y * (1.0 - frac), c.size.x, c.size.y * frac), Color(0, 0, 0, 0.65))
			var txt := ("%.1f" % cd) if cd < 1.0 else str(ceili(cd))
			c.draw_string_outline(font, Vector2(0, 29), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 16, 4, Color.BLACK)
			c.draw_string(font, Vector2(0, 29), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 16)
		if n > 1 or it.display != null or it.charges > 0:
			c.draw_string_outline(font, Vector2(0, c.size.y - 3), str(n), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 3, 13, 3, Color.BLACK)
			c.draw_string(font, Vector2(0, c.size.y - 3), str(n), HORIZONTAL_ALIGNMENT_RIGHT, c.size.x - 3, 13)
		if world.aim_slot == "i%d" % i:
			c.draw_rect(r, Color(0.45, 0.8, 1.0), false, 3.0)
		elif it.active != null and cd <= 0.0:
			c.draw_rect(r, Color(0.9, 0.8, 0.45, 0.8), false, 1.5)
	c.draw_string_outline(font, Vector2(3, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
	c.draw_string(font, Vector2(3, 12), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.95, 0.8))


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
	var learned: bool = slot == "p" or int(ch.ranks.get(slot, 0)) > 0
	if icon != null:
		c.draw_texture_rect(icon, r.grow(-3), false)
	elif nm != "":
		var base := ch.color.darkened(0.5)
		c.draw_rect(r.grow(-3), base)
		c.draw_rect(Rect2(3, 3, c.size.x - 6, (c.size.y - 6) * 0.45), base.lightened(0.12))
		var abbr := ""
		for w in nm.split(" ", false):
			abbr += w.substr(0, 1).to_upper()
		if cd <= 0.0:
			c.draw_string_outline(font, Vector2(0, 41), abbr.substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 21, 4, Color(0, 0, 0, 0.6))
			c.draw_string(font, Vector2(0, 41), abbr.substr(0, 3), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 21)
	if cd > 0.0:
		var frac := clampf(cd / maxf(ch.cd_total.get(slot, 1.0), 0.01), 0.0, 1.0)
		var center := c.size * 0.5
		var pts := PackedVector2Array([center])
		for i in 33:
			pts.append(center + Vector2.from_angle(-PI / 2.0 - TAU * frac * i / 32.0) * c.size.x)
		c.draw_colored_polygon(pts, Color(0, 0, 0, 0.68))
		c.draw_line(center, center + Vector2.from_angle(-PI / 2.0 - TAU * frac) * c.size.x, Color(1, 1, 1, 0.5), 2.0)
		var txt := ("%.1f" % cd) if cd < 1.0 else str(ceili(cd))
		c.draw_string_outline(font, Vector2(0, 42), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22, 5, Color.BLACK)
		c.draw_string(font, Vector2(0, 42), txt, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 22)
	elif slot != "p" and (ch.dead or ch.flags & (Unit.F_STUN | Unit.F_SILENCE | Unit.F_STASIS)):
		c.draw_rect(r, Color(0, 0, 0, 0.55))
	if not learned:
		c.draw_rect(r, Color(0.02, 0.02, 0.04, 0.72))
		if ch.can_rank_up(slot):
			c.draw_string(font, Vector2(0, 42), "+", HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 26, Color(1, 0.85, 0.4))
	elif slot != "p":
		var ab = ch.def.abilities.get(slot)
		var cost := ch.ability_cost(ab) if ab != null else 0.0
		if cost > 0.0:
			if not ch.can_pay(ab) and cd <= 0.0:
				c.draw_rect(r, Color(0.05, 0.1, 0.45, 0.55) if ab.cost_type != "health" else Color(0.45, 0.05, 0.08, 0.55))
			c.draw_string_outline(font, Vector2(0, c.size.y - 4), str(int(cost)), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 12, 3, Color.BLACK)
			c.draw_string(font, Vector2(0, c.size.y - 4), str(int(cost)), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 12, Color(0.55, 0.75, 1.0))
	var fl: float = _ready_flash.get(slot, 0.0)
	if fl > 0.0:
		c.draw_rect(r, Color(1, 1, 1, 0.45 * fl))
	var border := Color(0.35, 0.37, 0.42)
	if world.aim_slot == slot:
		border = Color(0.45, 0.8, 1.0)
	elif slot != "p" and cd <= 0.0 and learned and ch.def.abilities.has(slot):
		border = Color(0.85, 0.75, 0.45).lerp(Color.WHITE, fl)
	c.draw_rect(r, border, false, 2.0 + 2.0 * fl)
	c.draw_rect(Rect2(2, 2, 18, 17), Color(0, 0, 0, 0.6))
	c.draw_string(font, Vector2(2, 15), slot.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 18, 13, Color(1, 0.95, 0.8))


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


## Unit dots, camera frame and border - drawn above the minimap's fog layer.
func _draw_minimap_units(c: Control) -> void:
	var sc := c.size.x / world.map.size.x
	var lt := world.local_team
	for u in world.units:
		if u.dead and not u.is_structure:
			continue
		if u.team != lt and not u.is_structure and not world.ended and not world.can_see(u, lt):
			continue
		var p: Vector2 = u.global_position * sc
		var col: Color = u.team_color()
		if u.is_structure:
			c.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 0.4, 0.4) if u.dead else col)
		elif u.is_champion:
			c.draw_circle(p, 5.5, col)
			c.draw_arc(p, 5.5, 0, TAU, 12, Color.WHITE if u == world.local_champion else Color.BLACK, 1.5)
		elif u.is_ward:
			c.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), col.lightened(0.3))
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
			var line := "%s  -  %s     Lv %d     %d / %d / %d" % [ch.player_name, ch.display_name, ch.level, ch.kills, ch.deaths, ch.assists]
			c.draw_string(font, Vector2(40, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
			for i in 6:
				var it = ch.item_def(i)
				var r := Rect2(470 + i * 36, y - 22, 32, 32)
				if it != null:
					ItemUI.draw_icon(c, r, it)
				else:
					c.draw_rect(r, Color(0.2, 0.21, 0.25), false, 1.0)
			y += 40.0
		y += 20.0
