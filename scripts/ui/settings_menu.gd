class_name SettingsMenu
extends Control
## Player settings: movement mode, attack-move, autobuy, camera and key bindings. Changes apply and
## are saved right away. Opened from the main menu, the lobby and the in-game menu (Esc).

signal closed

var _capture := ""          # action waiting for its new key
var _key_buttons := {}      # action -> Button
var _key_labels := {}       # action -> Label
var _keys_grid: GridContainer
var _note: Label
var _speed_label: Label
var _controls := {}         # pref -> Control (refreshed after presets)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.98)
	sb.border_color = Color(0.35, 0.37, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := UiKit.label(v, "Settings")
	title.add_theme_font_size_override("font_size", 30)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, mini(560, int(get_viewport_rect().size.y) - 190))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)

	_section(body, "Gameplay")
	_option(body, "Movement", "move_mode", [["click", "Right-click to move (classic)"], ["wasd", "WASD keys (left click attacks)"]], _on_move_mode)
	_option(body, "Attack-move attacks", "amove_target", [["cursor", "the enemy closest to the cursor"], ["champion", "the enemy closest to you"]])
	_check(body, "The attack-move key waits for a left click (otherwise it attacks at the cursor right away)", "amove_click")
	_check(body, "Autobuy - buy your build in your base or while dead (edit the build in the shop)", "autobuy", _on_autobuy)

	_section(body, "Camera")
	_check(body, "Camera follows your champion when a match starts (%s toggles it)" % Controls.label("camera_lock"), "camera_locked")
	_check(body, "Edge panning - an unlocked camera moves when the mouse touches the screen edge", "edge_pan")
	var row := UiKit.row(body)
	UiKit.label(row, "Camera speed", 190)
	var slider := HSlider.new()
	slider.min_value = 0.25
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = float(Game.prefs.camera_speed)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(300, 0)
	row.add_child(slider)
	_speed_label = UiKit.label(row, "", 70)
	slider.value_changed.connect(func(x):
		Game.prefs.camera_speed = x
		_speed_label.text = "%.2fx" % x
		Game.save_settings())
	_speed_label.text = "%.2fx" % slider.value

	_section(body, "Keys")
	var hint := UiKit.label(body, "Click a key, then press the new key or mouse button (Esc cancels, Backspace clears it). Ctrl + an ability key levels it up.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.6)
	_keys_grid = GridContainer.new()
	_keys_grid.columns = 4
	_keys_grid.add_theme_constant_override("h_separation", 10)
	_keys_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(_keys_grid)
	for a in Controls.ACTIONS:
		var l := UiKit.label(_keys_grid, a[1], 210)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 0)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_start_capture.bind(a[0]))
		_keys_grid.add_child(b)
		_key_buttons[a[0]] = b
		_key_labels[a[0]] = l
	var krow := UiKit.row(body)
	UiKit.button(krow, "Reset keys to defaults", _reset_keys).focus_mode = Control.FOCUS_NONE

	_note = UiKit.label(v, "")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(800, 0)
	_note.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	var close := UiKit.button(v, "Close", _close)
	close.focus_mode = Control.FOCUS_NONE
	_refresh_keys()


func _section(parent: Node, text: String) -> void:
	var l := UiKit.label(parent, text)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1, 0.82, 0.45))


func _check(parent: Node, text: String, pref: String, cb := Callable()) -> void:
	var c := CheckBox.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Game.prefs[pref])
	c.toggled.connect(func(on):
		Game.prefs[pref] = on
		Game.save_settings()
		if cb.is_valid():
			cb.call(on))
	parent.add_child(c)
	_controls[pref] = c


## options: [[value, label], ...]
func _option(parent: Node, text: String, pref: String, options: Array, cb := Callable()) -> void:
	var row := UiKit.row(parent)
	UiKit.label(row, text, 190)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in options.size():
		o.add_item(options[i][1])
		if str(Game.prefs[pref]) == options[i][0]:
			o.select(i)
	o.item_selected.connect(func(i):
		Game.prefs[pref] = options[i][0]
		Game.save_settings()
		if cb.is_valid():
			cb.call(options[i][0]))
	row.add_child(o)
	_controls[pref] = o


func _on_move_mode(mode: String) -> void:
	var d := Controls.defaults(mode)
	for k in d:
		Controls.bind(k, d[k])
	Game.save_settings()
	_refresh_keys()
	if mode == "wasd":
		_note.text = "WASD layout: move with %s%s%s%s, left click attacks the enemy nearest the cursor, abilities on %s %s %s %s, summoner spells on %s / %s. Change any key below." % [
			Controls.label("move_up"), Controls.label("move_left"), Controls.label("move_down"), Controls.label("move_right"),
			Controls.label("ability_q"), Controls.label("ability_w"), Controls.label("ability_e"), Controls.label("ability_r"),
			Controls.label("summoner_1"), Controls.label("summoner_2")]
	else:
		_note.text = "Classic layout: right-click to move, abilities on Q W E R, summoner spells on D / F."


func _on_autobuy(on: bool) -> void:
	if Game.world != null and is_instance_valid(Game.world):
		Game.world.send_build()
	_note.text = "Autobuy on: your build (or the recommended one) is bought whenever you can shop." if on else "Autobuy off."


func _reset_keys() -> void:
	var d := Controls.defaults(str(Game.prefs.move_mode))
	for k in d:
		Controls.bind(k, d[k])
	Game.save_settings()
	_capture = ""
	_refresh_keys()
	_note.text = "Keys reset to the %s layout." % ("WASD" if Game.prefs.move_mode == "wasd" else "classic")


func _start_capture(action: String) -> void:
	_capture = action
	_refresh_keys()
	_note.text = "Press the new key for \"%s\" (Esc cancels, Backspace clears it)." % _action_name(action)


func _action_name(action: String) -> String:
	for a in Controls.ACTIONS:
		if a[0] == action:
			return a[1]
	return action


func _refresh_keys() -> void:
	var wasd: bool = Game.prefs.move_mode == "wasd"
	for a in Controls.ACTIONS:
		var id: String = a[0]
		var b: Button = _key_buttons[id]
		b.text = "press a key..." if _capture == id else Controls.label(id)
		var off: bool = id in Controls.MOVE_ACTIONS and not wasd
		_key_labels[id].modulate = Color(1, 1, 1, 0.45 if off else 1.0)
		b.modulate = Color(1, 1, 1, 0.45 if off else 1.0)
		b.tooltip_text = "Only used in WASD mode." if off else ""


## Binds `code` to the action being captured. Another action using the same key loses it (in classic
## mode the WASD movement keys may share keys with abilities - they are not used there).
func _assign(code: String) -> void:
	var action := _capture
	_capture = ""
	var cleared := PackedStringArray()
	if code != "":
		var wasd: bool = Game.prefs.move_mode == "wasd"
		for a in Controls.ACTIONS:
			var other: String = a[0]
			if other == action or Controls.code_of(other) != code:
				continue
			if not wasd and ((other in Controls.MOVE_ACTIONS) != (action in Controls.MOVE_ACTIONS)):
				continue
			Controls.bind(other, "")
			cleared.append(a[1])
	Controls.bind(action, code)
	Game.save_settings()
	_refresh_keys()
	_note.text = "%s: %s" % [_action_name(action), Controls.label(action)]
	if not cleared.is_empty():
		_note.text += "   (removed from: %s)" % ", ".join(cleared)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture != "":
		if event is InputEventKey and event.pressed and not event.echo:
			var k := event as InputEventKey
			if k.keycode == KEY_ESCAPE:
				_capture = ""
				_refresh_keys()
				_note.text = ""
			elif k.keycode == KEY_BACKSPACE:
				_assign("")
			else:
				var code := Controls.code_from_event(k)
				if code != "":
					_assign(code)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			var code := Controls.code_from_event(event)
			if code != "":
				_assign(code)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	Game.save_settings()
	closed.emit()
	queue_free()
