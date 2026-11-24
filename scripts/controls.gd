class_name Controls
extends RefCounted
## Rebindable game controls on top of Godot's InputMap. Each action has one key (or an extra mouse
## button). Bindings are saved in the [keys] section of user://settings.cfg as "key:<keycode>" or
## "mouse:<button>" ("" = unbound). Left/right click, the mouse wheel, Esc, Ctrl (level up), the arrow
## keys (camera) and F1-F4 (practice cheats) are fixed.

## [action, label, classic default, WASD default]
const ACTIONS := [
	["ability_q", "Ability Q", "Q", "Q"],
	["ability_w", "Ability W", "W", "E"],
	["ability_e", "Ability E", "E", "R"],
	["ability_r", "Ability R (ultimate)", "R", "F"],
	["summoner_1", "Summoner spell 1", "D", "Space"],
	["summoner_2", "Summoner spell 2", "F", "Shift"],
	["item_1", "Item 1", "1", "1"],
	["item_2", "Item 2", "2", "2"],
	["item_3", "Item 3", "3", "3"],
	["item_4", "Item 4", "4", "4"],
	["item_5", "Item 5", "5", "5"],
	["item_6", "Item 6", "6", "6"],
	["attack_move", "Attack move", "A", "X"],
	["stop", "Stop", "S", ""],
	["recall", "Recall", "B", "B"],
	["shop", "Shop", "P", "P"],
	["camera_lock", "Lock / unlock camera", "Y", "Y"],
	["camera_center", "Center camera (hold)", "Space", ""],
	["scoreboard", "Scoreboard (hold)", "Tab", "Tab"],
	["move_up", "Move up (WASD mode)", "W", "W"],
	["move_left", "Move left (WASD mode)", "A", "A"],
	["move_down", "Move down (WASD mode)", "S", "S"],
	["move_right", "Move right (WASD mode)", "D", "D"],
]
const MOVE_ACTIONS := ["move_up", "move_left", "move_down", "move_right"]
## Mouse buttons that can be bound (left/right click and the wheel are taken).
const MOUSE_OK := [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]


## Creates the actions with the defaults of `mode` ("click" or "wasd"), then applies `saved` bindings.
static func setup(saved: Dictionary, mode: String) -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0], 0.2)
	var d := defaults(mode)
	for k in d:
		bind(k, str(saved.get(k, d[k])) if saved.get(k) is String else d[k])


## action -> code for a layout ("click" = right-click to move, "wasd" = WASD movement).
static func defaults(mode: String) -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[a[0]] = to_code(a[3] if mode == "wasd" else a[2])
	return out


## Replaces an action's binding. `code` is "key:<keycode>", "mouse:<button>" or "" (unbound).
static func bind(action: String, code: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	InputMap.action_erase_events(action)
	var ev := event_from_code(code)
	if ev != null:
		InputMap.action_add_event(action, ev)


static func bindings() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[a[0]] = code_of(a[0])
	return out


static func code_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var c := code_from_event(ev)
		if c != "":
			return c
	return ""


## A short key name for the HUD and tooltips ("Q", "Space", "Mouse 4"; "-" when unbound).
static func label(action: String) -> String:
	var c := code_of(action)
	return code_label(c) if c != "" else "-"


static func code_label(code: String) -> String:
	if code.begins_with("key:"):
		var s := OS.get_keycode_string(int(code.substr(4)))
		return s if s != "" else "?"
	if code.begins_with("mouse:"):
		match int(code.substr(6)):
			MOUSE_BUTTON_MIDDLE:
				return "Mouse 3"
			MOUSE_BUTTON_XBUTTON1:
				return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2:
				return "Mouse 5"
		return "Mouse " + code.substr(6)
	return ""


## "Q" / "Space" / "Shift" / "Mouse 4" -> code. Used for the default tables.
static func to_code(name: String) -> String:
	if name == "":
		return ""
	if name.begins_with("Mouse "):
		return "mouse:%d" % {"Mouse 3": MOUSE_BUTTON_MIDDLE, "Mouse 4": MOUSE_BUTTON_XBUTTON1, "Mouse 5": MOUSE_BUTTON_XBUTTON2}.get(name, 0)
	return "key:%d" % OS.find_keycode_from_string(name)


static func event_from_code(code: String) -> InputEvent:
	if code.begins_with("key:") and int(code.substr(4)) != 0:
		var k := InputEventKey.new()
		k.keycode = int(code.substr(4)) as Key
		return k
	if code.begins_with("mouse:") and int(code.substr(6)) in MOUSE_OK:
		var m := InputEventMouseButton.new()
		m.button_index = int(code.substr(6)) as MouseButton
		return m
	return null


## The code for a key press / mouse button the player wants to bind ("" if it can't be bound).
static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var kc: int = ev.keycode if ev.keycode != KEY_NONE else ev.physical_keycode
		if kc == KEY_NONE or kc in [KEY_ESCAPE, KEY_CTRL, KEY_ALT, KEY_META, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_F1, KEY_F2, KEY_F3, KEY_F4]:
			return ""
		return "key:%d" % kc
	if ev is InputEventMouseButton and ev.button_index in MOUSE_OK:
		return "mouse:%d" % ev.button_index
	return ""


## The first action this key/mouse event belongs to ("" if none). In click mode the WASD movement
## actions are ignored (their keys belong to abilities there), in WASD mode they come first.
static func action_of(ev: InputEvent, mode: String) -> String:
	if not (ev is InputEventKey or ev is InputEventMouseButton):
		return ""
	for a in ACTIONS:
		if a[0] in MOVE_ACTIONS:
			continue
		if InputMap.has_action(a[0]) and ev.is_action(a[0]):
			return a[0]
	if mode == "wasd":
		for m in MOVE_ACTIONS:
			if InputMap.has_action(m) and ev.is_action(m):
				return m
	return ""


## The bottom-left controls reminder in a match.
static func help_text(mode: String) -> String:
	var abil := label("ability_q") + label("ability_w") + label("ability_e") + label("ability_r")
	if abil.length() != 4:
		abil = "%s %s %s %s" % [label("ability_q"), label("ability_w"), label("ability_e"), label("ability_r")]
	var parts := PackedStringArray()
	if mode == "wasd":
		parts.append("%s%s%s%s move   LMB attack   RMB move/attack" % [label("move_up"), label("move_left"), label("move_down"), label("move_right")])
	else:
		parts.append("RMB move/attack")
	parts.append("%s cast (hold to aim)" % abil)
	parts.append("Ctrl+%s level up" % abil.replace(" ", ""))
	parts.append("%s/%s summoners" % [label("summoner_1"), label("summoner_2")])
	parts.append("%s-%s items" % [label("item_1"), label("item_6")])
	if code_of("attack_move") != "":
		parts.append("%s attack-move" % label("attack_move"))
	if code_of("stop") != "":
		parts.append("%s stop" % label("stop"))
	parts.append("%s recall" % label("recall"))
	parts.append("%s shop" % label("shop"))
	parts.append("%s camera" % label("camera_lock"))
	parts.append("%s scores" % label("scoreboard"))
	parts.append("Esc menu")
	return "   ".join(parts)
