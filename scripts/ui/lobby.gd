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
var sum_pick: Array = []   # the two summoner spell OptionButtons
var _preview_id := ""
var _expanded := false
var _suggest_button: Button
var _suggest_status: Label
var _suggest_dialog: AcceptDialog
var _suggest_list: OptionButton
var _suggest_preview: RichTextLabel
var _approve_button: Button
var _decline_button: Button


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
	var srow := UiKit.row(left)
	UiKit.label(srow, "Spells", 60)
	for i in 2:
		var o := OptionButton.new()
		o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		o.item_selected.connect(_pick_summoner.bind(i))
		srow.add_child(o)
		sum_pick.append(o)
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
	if Game.online:
		_setup_suggestions(left)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	start_btn = UiKit.button(left, "START MATCH", Game.start_match)
	start_btn.add_theme_font_size_override("font_size", 26)
	start_btn.custom_minimum_size = Vector2(0, 56)
	start_btn.visible = Game.is_host()
	UiKit.button(left, "Settings (keys, WASD, camera, autobuy)", func(): add_child(SettingsMenu.new()))
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


func _setup_suggestions(parent: VBoxContainer) -> void:
	if Game.is_host():
		_suggest_button = UiKit.button(parent, "", func(): _suggest_dialog.popup_centered(Vector2i(520, 360)))
		_suggest_dialog = AcceptDialog.new()
		_suggest_dialog.title = "Character suggestions"
		_suggest_dialog.ok_button_text = "Close"
		add_child(_suggest_dialog)
		var panel := VBoxContainer.new()
		_suggest_dialog.add_child(panel)
		var note := UiKit.label(panel, "Only approve characters you trust. Approval lasts until you end the hosted session.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_suggest_list = OptionButton.new()
		_suggest_list.clip_text = true
		panel.add_child(_suggest_list)
		_suggest_preview = RichTextLabel.new()
		_suggest_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(_suggest_preview)
		var row := UiKit.row(panel)
		_approve_button = UiKit.button(row, "Approve", _resolve_suggestion.bind(true))
		_decline_button = UiKit.button(row, "Decline", _resolve_suggestion.bind(false))
		_suggest_list.item_selected.connect(func(_index): _refresh_suggestion_preview())
		Game.suggestions_changed.connect(_refresh_suggestions)
		_refresh_suggestions()
	else:
		var picker := FileDialog.new()
		picker.title = "Choose a folder containing character.json (JSON, PNG, WebP only)"
		picker.access = FileDialog.ACCESS_FILESYSTEM
		picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		picker.current_dir = Content.characters_dir()
		picker.dir_selected.connect(Game.suggest_character)
		add_child(picker)
		UiKit.button(parent, "Suggest a character...", func(): picker.popup_centered_ratio(0.7))
	_suggest_status = UiKit.label(parent, Game.suggestion_status)
	_suggest_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Game.suggestion_status_changed.connect(func(text): _suggest_status.text = text)


func _refresh_suggestions() -> void:
	var selected := _suggest_list.get_selected_id()
	_suggest_list.clear()
	for peer in Game.pending_suggestions:
		var entry: Dictionary = Game.pending_suggestions[peer]
		_suggest_list.add_item("%s [%s]" % [entry.preview.name, entry.pack.id], peer)
	var index := _suggest_list.get_item_index(selected)
	if _suggest_list.item_count > 0:
		_suggest_list.select(maxi(index, 0))
	_suggest_button.text = "Character suggestions (%d)" % _suggest_list.item_count
	_refresh_suggestion_preview()


func _refresh_suggestion_preview() -> void:
	var peer := _suggest_list.get_selected_id()
	var entry: Dictionary = Game.pending_suggestions.get(peer, {})
	_approve_button.disabled = entry.is_empty()
	_decline_button.disabled = entry.is_empty()
	if entry.is_empty():
		_suggest_preview.text = "No pending suggestions."
		return
	var preview: Dictionary = entry.preview
	_suggest_preview.text = "%s\nSuggested by %s\n\n%s\n%s\n\n%s" % [
		preview.name, Game.players[peer].name, preview.title, preview.description, preview.abilities]


func _resolve_suggestion(approve: bool) -> void:
	# Close so the host sees the result before reviewing another suggestion.
	_suggest_dialog.hide()
	Game.resolve_character_suggestion(_suggest_list.get_selected_id(), approve)


func _rebuild_grid() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
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
		if bool(p.get("bot", false)):
			_difficulty_picker(row, pid, p)
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
	_refresh_summoners(mine, mine != null and (editing == 0 or (Game.is_host() and bool(mine.bot))))


## Bot difficulty (host can change it; the choice also becomes the default for new bots).
func _difficulty_picker(row: Control, pid: int, p: Dictionary) -> void:
	var cur := BotBrain.level_name(p.get("difficulty", "normal"))
	if not Game.is_host():
		UiKit.label(row, BotBrain.LABELS[cur])
		return
	var o := OptionButton.new()
	o.tooltip_text = "Bot difficulty\nBrick: barely plays\nNormal: a competent player\nScripting: frame-perfect - reads and dodges everything, kites, perfect last hits and builds"
	for i in BotBrain.LEVELS.size():
		o.add_item(BotBrain.LABELS[BotBrain.LEVELS[i]])
		if BotBrain.LEVELS[i] == cur:
			o.select(i)
	o.item_selected.connect(func(i: int):
		Game.prefs.bot_difficulty = BotBrain.LEVELS[i]
		Game.save_settings()
		Game.request_change("difficulty", BotBrain.LEVELS[i], pid))
	row.add_child(o)


## Fills the two summoner spell pickers for you (or the bot the host is editing).
func _refresh_summoners(p, can_edit: bool) -> void:
	var cur: Array = p.get("summoners", []) if p is Dictionary else []
	for i in 2:
		var o: OptionButton = sum_pick[i]
		o.clear()
		for k in Game.summoner_ids.size():
			var sp: Dictionary = Game.summoners[Game.summoner_ids[k]]
			o.add_item(sp.name)
			o.set_item_tooltip(k, sp.description)
			if i < cur.size() and cur[i] == Game.summoner_ids[k]:
				o.select(k)
		o.disabled = not can_edit or Game.summoner_ids.is_empty()
		o.tooltip_text = "Summoner spell %d (%s in a match)" % [i + 1, Controls.label("summoner_%d" % (i + 1))]


func _pick_summoner(idx: int, slot_i: int) -> void:
	var me := multiplayer.get_unique_id()
	var target := editing if editing != 0 and Game.players.has(editing) else me
	var cur: Array = Game.players.get(target, {}).get("summoners", []).duplicate()
	while cur.size() < 2:
		cur.append("")
	var id: String = Game.summoner_ids[idx]
	if cur[1 - slot_i] == id:
		cur[1 - slot_i] = cur[slot_i]  # picking the other slot's spell swaps them
	cur[slot_i] = id
	if target == me:
		Game.prefs.summoners = cur
		Game.save_settings()
	Game.request_change("summoners", cur, target if target != me else 0)


func _set_editing(pid: int) -> void:
	editing = pid
	_refresh()


func _show_details(id: String) -> void:
	_preview_id = id
	_expanded = Input.is_key_pressed(KEY_SHIFT)
	_render_details()
	details.get_v_scroll_bar().value = 0


func _process(_delta: float) -> void:
	var expanded := Input.is_key_pressed(KEY_SHIFT)
	if _expanded != expanded:
		_expanded = expanded
		_render_details()


func _render_details() -> void:
	var def = Game.characters.get(_preview_id)
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
	t += "[color=#9aa3b5]%s[/color]\n\n" % ("Release Shift for summaries" if _expanded else "Hold Shift for ability details")
	t += "[b][color=#ffd36b]Passive - %s[/color][/b]\n%s\n\n" % [def.passive.name, _ability_text(def.passive)]
	for slot in ["q", "w", "e", "r"]:
		var ab = def.abilities.get(slot)
		if ab == null:
			continue
		t += _ability_entry("%s - %s" % [slot.to_upper(), ab.name], "#7fc8ff", ab)
		if ab.get("recast") is Dictionary:
			t += _ability_entry("Recast - %s" % ab.recast.name, "#f080ff", ab.recast)
	details.text = t


func _ability_text(ab: Dictionary) -> String:
	var text: String = ab.description if _expanded else ab.short_description
	return (text if not text.is_empty() else ab.short_description).replace("[", "[lb]")


func _ability_entry(title: String, color: String, ab: Dictionary) -> String:
	var t := "[b][color=%s]%s[/color][/b]\n" % [color, title]
	if _expanded:
		var meta := "Base cooldown: %s s" % _per_rank(ab.cooldown)
		if ab.cost != 0.0:
			meta += "  |  Cost: %s %s" % [_per_rank(ab.cost), ab.cost_type]
		if ab.targeting != "self":
			meta += "  |  Range: %s" % _per_rank(ab.range)
		if ab.cast_time != 0.0:
			meta += "  |  Cast time: %s s" % _per_rank(ab.cast_time)
		t += "[color=#9aa3b5]%s[/color]\n" % meta.replace("[", "[lb]")
	return t + _ability_text(ab) + "\n\n"


static func _per_rank(v) -> String:
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(_per_rank(x))
		return "/".join(parts)
	return String.num(float(v), 2).trim_suffix(".0") if (v is float or v is int) else str(v)
