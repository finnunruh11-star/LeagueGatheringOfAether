extends Node
## Run this scene in three processes with -- --auto=test --port=... --role=host|guest|late.
## Start the late peer after the host prints "[suggestions] approved".

const Lobby = preload("res://scripts/ui/lobby.gd")
const ID := "suggestion_test_champion"
const JSON_TEXT := """{"name":"Suggestion Test","description":"A test champion.","sprite":"sprite.png",
	"abilities":{"q":{"name":"Test Shot","effects":[{"type":"damage","amount":"max(25, [10, 30][rank - 1])"}]}}}"""

var _lobby: Lobby
var _path := ""
var _failed := false


func _ready() -> void:
	await get_tree().process_frame
	var port := int(Game.cmdline.get("port", 17777))
	var role: String = Game.cmdline.get("role", "")
	if role == "host":
		await _host(port)
	elif role in ["guest", "late"]:
		await _guest(port, role == "late")
	else:
		_check(false, "missing test role")
	if not _path.is_empty():
		for file in ["character.json", "sprite.png"]:
			DirAccess.remove_absolute(_path.path_join(file))
		DirAccess.remove_absolute(_path)
		DirAccess.remove_absolute(_path.get_base_dir())
	print("[suggestions] ", role, " ", "FAILED" if _failed else "PASS")
	get_tree().quit(int(_failed))


func _host(port: int) -> void:
	if not _check(Game.host(port).is_empty(), "host opened"):
		return
	_open_lobby()
	var loader = Game.CharacterSuggestions
	_check(loader.inspect(ID, {"character.json": "[]".to_utf8_buffer()}).has("error"), "reject invalid JSON")
	_check(loader.inspect(ID, {"character.json": "{}".to_utf8_buffer(), "../bad.png": PackedByteArray([1])}).has("error"), "reject unsafe paths")
	_check(loader.inspect(ID, {"character.json": "{}".to_utf8_buffer(), "code.gd": PackedByteArray([1])}).has("error"), "reject unsupported file")
	_check(Effects.num("max(25, [10, 30][rank - 1])", {"rank": 2}) == 30.0, "ability formulas still work")
	if not await _pending():
		return
	var peer: int = Game.pending_suggestions.keys()[0]
	_check(not Game.characters.has(ID), "pending character is not in the roster")
	_lobby._suggest_button.pressed.emit()
	_check(_lobby._suggest_preview.text.contains("Test Shot"), "host preview shows ability")
	_lobby._decline_button.pressed.emit()
	_check(Game.pending_suggestions.is_empty() and not Game.characters.has(ID), "decline does not change roster")
	if not await _pending():
		return
	_lobby._suggest_button.pressed.emit()
	_lobby._approve_button.pressed.emit()
	if not _check(Game.characters.has(ID) and Game.pending_suggestions.is_empty(), "approved roster and queue"):
		return
	print("[suggestions] approved")
	await _wait_for(func(): return Game.players.size() >= 3 and Game.players.get(peer, {}).get("character") == ID,
		"guest selected approved character and late peer joined")
	Game.start_match()
	await get_tree().create_timer(1.5).timeout
	Game.leave()
	_check(not Game.characters.has(ID) and not Game.character_packs.has(ID), "leaving clears session-only content")


func _guest(port: int, late: bool) -> void:
	if not _check(Game.join("127.0.0.1", port).is_empty(), "guest opened connection"):
		return
	if not await _wait_for(func(): return Game.players.has(multiplayer.get_unique_id()), "lobby joined"):
		return
	_open_lobby()
	if not late:
		_path = ProjectSettings.globalize_path("user://suggestions_%d/%s" % [OS.get_process_id(), ID])
		DirAccess.make_dir_recursive_absolute(_path)
		var file := FileAccess.open(_path.path_join("character.json"), FileAccess.WRITE)
		if not _check(file != null, "write test character"):
			return
		file.store_string(JSON_TEXT)
		file.close()
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color.BLUE)
		if not _check(image.save_png(_path.path_join("sprite.png")) == OK, "write test sprite"):
			return
		Game.suggest_character(_path)
		if not await _wait_for(func(): return Game.suggestion_status.contains("declined"), "guest notified of decline"):
			return
		_check(not Game.characters.has(ID), "guest roster unchanged after decline")
		await get_tree().create_timer(3.1).timeout
		Game.suggest_character(_path)
	if not await _wait_for(func(): return Game.characters.has(ID), "approved character synchronized"):
		return
	_check(Game.characters[ID].sprite != null, "approved character includes sprite")
	var roster_names := _lobby.grid.get_children().map(func(card): return card.text)
	_check("Suggestion Test" in roster_names, "approved character appears in lobby grid")
	if not late:
		await _wait_for(func(): return Game.suggestion_status.contains("available"), "guest notified of approval")
		_lobby._pick(ID)
	await _wait_for(func(): return Game.in_match, "match started with synchronized roster")


func _open_lobby() -> void:
	_lobby = Lobby.new()
	add_child(_lobby)


func _pending() -> bool:
	return await _wait_for(func(): return not Game.pending_suggestions.is_empty(), "suggestion reached host")


func _wait_for(condition: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _check(condition.call(), label)


func _check(ok: bool, label: String) -> bool:
	if not ok:
		_failed = true
		push_error("[suggestions] " + label)
	return ok
