extends Control
## Lobby (used for practice and online): teams, bots, character select, map.

var main: Node
var players_box: VBoxContainer
var grid: GridContainer
var details: RichTextLabel
var map_select: OptionButton
var fog_check: CheckBox
var start_btn: Button
var status: Label
var problems: RichTextLabel
var editing := 0
var _map_ids: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	var title := UiKit.label(left, "Lobby")
	title.add_theme_font_size_override("font_size", 32)
	status = UiKit.label(left, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color(1, 1, 1, 0.7)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 6)
	left.add_child(players_box)
	var bots := UiKit.row(left)
	UiKit.button(bots, "+ Blue bot", func(): Game.add_bot(0)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.button(bots, "+ Red bot", func(): Game.add_bot(1)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots.visible = Game.is_host()
	var mrow := UiKit.row(left)
	UiKit.label(mrow, "Map", 50)
	map_select = OptionButton.new()
	map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_select.item_selected.connect(func(i): Game.set_map(_map_ids[i]))
	mrow.add_child(map_select)
	fog_check = CheckBox.new()
	fog_check.text = "Fog of war"
	fog_check.toggled.connect(func(on): Game.set_setting("fog", on))
	left.add_child(fog_check)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	start_btn = UiKit.button(left, "START MATCH", Game.start_match)
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.custom_minimum_size = Vector2(0, 56)
	start_btn.visible = Game.is_host()
	UiKit.button(left, "Leave", _leave)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mid)
	UiKit.label(mid, "Choose your champion (host can click a bot's name first to pick for it)")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	problems = RichTextLabel.new()
	problems.bbcode_enabled = true
	problems.fit_content = true
	mid.add_child(problems)

	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.custom_minimum_size = Vector2(440, 0)
	cols.add_child(details)

	Game.lobby_changed.connect(_refresh)
	Game.content_changed.connect(_rebuild_grid)
	_rebuild_grid()
	_refresh()


func _leave() -> void:
	Game.leave()
	main.show_menu("")


func _rebuild_grid() -> void:
	for c in grid.get_children():
		c.queue_free()
	for id in Game.sorted_character_ids():
		var def: Dictionary = Game.characters[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 160)
		b.text = def.name
		b.icon = UiKit.placeholder(def)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.clip_text = true
		b.pressed.connect(_pick.bind(id))
		b.mouse_entered.connect(_show_details.bind(id))
		grid.add_child(b)
	if Game.content_errors.is_empty():
		problems.text = ""
	else:
		problems.text = "[color=#ff7a6a]Content problems:[/color]\n[color=#ffb0a0]" + "\n".join(Game.content_errors) + "[/color]"
	_refresh()


func _pick(id: String) -> void:
	if editing != 0 and Game.players.has(editing):
		Game.request_change("character", id, editing)
	else:
		Game.request_change("character", id)
	_show_details(id)


func _refresh() -> void:
	if not is_inside_tree():
		return
	for c in players_box.get_children():
		c.queue_free()
	var me := multiplayer.get_unique_id()
	var ids := Game.players.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = Game.players[pid]
		var row := UiKit.row(players_box)
		var sw := ColorRect.new()
		sw.color = Game.TEAM_COLORS[clampi(int(p.team), 0, 1)]
		sw.custom_minimum_size = Vector2(10, 30)
		row.add_child(sw)
		var cname: String = Game.characters[p.character].name if Game.characters.has(p.character) else "?"
		var can_edit: bool = pid == me or (Game.is_host() and p.bot)
		var name_btn := Button.new()
		name_btn.text = "%s  -  %s%s" % [p.name, cname, "  (you)" if pid == me else ""]
		name_btn.flat = not (editing == pid)
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.disabled = not can_edit
		name_btn.pressed.connect(_set_editing.bind(pid if pid != me else 0))
		row.add_child(name_btn)
		if can_edit:
			UiKit.button(row, "Team", func(): Game.request_change("team", 1 - int(p.team), pid if pid != me else 0))
		if Game.is_host() and p.bot:
			UiKit.button(row, "X", func(): Game.remove_bot(pid))
	map_select.clear()
	_map_ids = Game.maps.keys()
	_map_ids.sort()
	for i in _map_ids.size():
		map_select.add_item(str(Game.maps[_map_ids[i]].get("name", _map_ids[i])))
		if _map_ids[i] == Game.settings.map:
			map_select.select(i)
	map_select.disabled = not Game.is_host()
	fog_check.set_pressed_no_signal(bool(Game.settings.get("fog", true)))
	fog_check.disabled = not Game.is_host()
	var md = Game.maps.get(Game.settings.map, {})
	fog_check.tooltip_text = "This map has fog of war turned off." if md is Dictionary and not bool(md.get("fog", true)) else ""
	if not Game.online:
		status.text = "Practice mode. Add bots to fight, or play alone with the training dummies."
	elif Game.is_host():
		var ips := []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
				ips.append(a)
		status.text = "Hosting on port %d. Friends join with your IP: %s\n(Over the internet: forward UDP port %d or use a VPN like Tailscale / ZeroTier.)" % [Game.port, ", ".join(ips), Game.port]
	else:
		status.text = "Connected. Waiting for the host to start..."
	var mine = Game.players.get(editing if editing != 0 else me)
	if mine != null:
		_show_details(mine.character)


func _set_editing(pid: int) -> void:
	editing = pid
	_refresh()


func _show_details(id: String) -> void:
	var def = Game.characters.get(id)
	if def == null:
		details.text = ""
		return
	var s: Dictionary = def.stats
	var t := "[font_size=30][b]%s[/b][/font_size]\n" % def.name
	if def.title != "":
		t += "[i]%s[/i]\n" % def.title
	if def.description != "":
		t += "%s\n" % def.description
	var mana := "Mana %d  |  " % s.get("max_mana", 0.0) if s.get("max_mana", 0.0) > 0.0 else "No mana  |  "
	t += "\n[color=#9aa3b5]HP %d  |  %sAD %d  |  AS %.2f  |  Range %d  |  MS %d  |  Armor %d  |  MR %d[/color]\n" % [
		s.max_hp, mana, s.attack_damage, s.attack_speed, s.attack_range, s.move_speed, s.armor, s.get("magic_resist", 0.0)]
	t += "[color=#9aa3b5]%s basic attack[/color]\n\n" % ("Ranged" if def.attack.ranged else "Melee")
	t += "[b][color=#ffd36b]Passive - %s[/color][/b]\n%s\n\n" % [def.passive.name, def.passive.description]
	for slot in ["q", "w", "e", "r"]:
		var ab = def.abilities.get(slot)
		if ab == null:
			continue
		t += "[b][color=#7fc8ff]%s - %s[/color][/b]  [color=#9aa3b5](%ss)[/color]\n%s\n\n" % [slot.to_upper(), ab.name, _per_rank(ab.cooldown), ab.description]
	details.text = t


static func _per_rank(v) -> String:
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(String.num(float(x), 2) if (x is float or x is int) else str(x))
		return "/".join(parts)
	return String.num(float(v), 2) if (v is float or v is int) else str(v)
