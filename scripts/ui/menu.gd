extends Control
## Main menu: player name, practice, host or join.

var main: Node
var name_edit: LineEdit
var ip_edit: LineEdit
var port_spin: SpinBox
var status: Label
var info: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)

	var title := Label.new()
	title.text = "CusOba"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "Custom MOBA Sandbox"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.6)
	v.add_child(sub)

	var row := UiKit.row(v)
	UiKit.label(row, "Your name", 140)
	name_edit = LineEdit.new()
	name_edit.text = Game.player_name
	name_edit.max_length = 20
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)

	UiKit.button(v, "Practice (offline, add bots in the lobby)", _practice)
	row = UiKit.row(v)
	UiKit.button(row, "Host game", _host).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.label(row, "Port", 50)
	port_spin = SpinBox.new()
	port_spin.min_value = 1024
	port_spin.max_value = 65535
	port_spin.value = Game.port
	row.add_child(port_spin)
	row = UiKit.row(v)
	UiKit.button(row, "Join game", _join).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.label(row, "Host IP", 70)
	ip_edit = LineEdit.new()
	ip_edit.text = Game.last_ip
	ip_edit.custom_minimum_size = Vector2(200, 0)
	row.add_child(ip_edit)
	row = UiKit.row(v)
	UiKit.button(row, "Open characters folder", func(): OS.shell_open(Content.characters_dir())).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.button(row, "Reload content", _reload).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.button(v, "Quit", func(): get_tree().quit())

	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	v.add_child(status)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.custom_minimum_size = Vector2(560, 0)
	v.add_child(info)
	Game.net_status.connect(set_status)
	Game.content_changed.connect(_show_info)
	_show_info()


func set_status(text: String) -> void:
	status.text = text


func _show_info() -> void:
	var t := "[center][color=#8a93a6]%d characters, %d maps loaded[/color][/center]" % [Game.characters.size(), Game.maps.size()]
	if not Game.content_errors.is_empty():
		t += "\n[color=#ff7a6a]Content problems:[/color]\n[color=#ffb0a0]" + "\n".join(Game.content_errors) + "[/color]"
	info.text = t


func _save_name() -> void:
	Game.player_name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Player"
	Game.save_settings()


func _practice() -> void:
	_save_name()
	Game.start_practice()
	main.show_lobby()


func _host() -> void:
	_save_name()
	var err := Game.host(int(port_spin.value))
	if err != "":
		set_status(err)
	else:
		main.show_lobby()


func _join() -> void:
	_save_name()
	var err := Game.join(ip_edit.text.strip_edges(), int(port_spin.value))
	if err != "":
		set_status(err)


func _reload() -> void:
	Game.reload_content()
	set_status("Reloaded.")
