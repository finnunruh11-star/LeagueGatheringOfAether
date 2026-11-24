extends Node
## Global singleton "Game": settings, content registry, lobby and networking.
## The host is authoritative: it owns the lobby, runs the match simulation and
## sends its characters to clients, so only the host needs the character files.

signal lobby_changed
signal lobby_joined
signal content_changed
signal net_status(text: String)
signal match_started(config: Dictionary)
signal back_to_lobby
signal left_game(reason: String)

const PROTOCOL := 2
const DEFAULT_PORT := 7777
const TEAM_NAMES := ["Blue", "Red", "Neutral"]
const TEAM_COLORS := [Color("4d8dff"), Color("ff5a4d"), Color("bbbbbb")]
const SETTINGS_PATH := "user://settings.cfg"

var player_name := "Player"
var last_ip := "127.0.0.1"
var port := DEFAULT_PORT

var characters := {}       # id -> built character definition
var character_packs := {}  # id -> {id, files} raw files, sent to clients
var maps := {}             # id -> map dictionary
var items := {}            # id -> item definition
var item_pack := {}        # raw items/ folder, sent to clients
var item_ids: Array = []   # sorted ids; snapshots send items as index + 1
var item_index := {}       # id -> index + 1
var content_errors := PackedStringArray()
var using_host_content := false

var online := false
var in_match := false
var players := {}          # peer id -> {name, team, character, bot}
var settings := {"map": "two_lanes", "fog": true}
var world: Node = null
var match_count := 0
var cmdline := {}
var debug_log := false  # --itemtest prints every damage/heal/proc
var _ready_peers := {}
var _next_bot := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := str(a).trim_prefix("--").split("=", true, 1)
		cmdline[kv[0]] = kv[1] if kv.size() > 1 else "true"
	load_settings()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	reload_content()


func is_host() -> bool:
	return multiplayer.is_server()


# ---------------------------------------------------------------- content ---

func reload_content() -> void:
	content_errors = PackedStringArray()
	character_packs = Content.read_character_packs(content_errors)
	characters.clear()
	for id in character_packs:
		var def = Content.build_character(character_packs[id], content_errors)
		if def != null:
			characters[id] = def
	maps = Content.read_maps(content_errors)
	item_pack = Content.read_item_pack(content_errors)
	_build_items()
	using_host_content = false
	if not maps.has(settings.map) and not maps.is_empty():
		settings.map = "two_lanes" if maps.has("two_lanes") else maps.keys()[0]
	for e in content_errors:
		push_warning("[content] " + e)
	content_changed.emit()


func _build_items() -> void:
	items = Content.build_items(item_pack, content_errors)
	item_ids = items.keys()
	item_ids.sort()
	item_index.clear()
	for i in item_ids.size():
		item_index[item_ids[i]] = i + 1


func sorted_character_ids() -> Array:
	var ids := characters.keys()
	ids.sort_custom(func(a, b): return str(characters[a].name).naturalnocasecmp_to(str(characters[b].name)) < 0)
	return ids


func default_character() -> String:
	var ids := sorted_character_ids()
	return ids[0] if not ids.is_empty() else ""


# ---------------------------------------------------------------- session ---

func start_practice() -> void:
	leave(false)
	_init_lobby()


func host(p: int) -> String:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, 8)
	if err != OK:
		return "Could not host on port %d (error %d). Is another game already using it?" % [p, err]
	multiplayer.multiplayer_peer = peer
	online = true
	port = p
	save_settings()
	_init_lobby()
	return ""


func join(ip: String, p: int) -> String:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, p)
	if err != OK:
		return "Could not start connection (error %d)" % err
	multiplayer.multiplayer_peer = peer
	online = true
	last_ip = ip
	port = p
	save_settings()
	net_status.emit("Connecting to %s:%d ..." % [ip, p])
	return ""


func leave(reload := true) -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	in_match = false
	players.clear()
	_ready_peers.clear()
	if reload and using_host_content:
		reload_content()


func _init_lobby() -> void:
	players.clear()
	players[1] = {"name": player_name, "team": 0, "character": default_character(), "bot": false}
	lobby_changed.emit()


func _smaller_team() -> int:
	var counts := [0, 0]
	for p in players.values():
		counts[clampi(int(p.team), 0, 1)] += 1
	return 0 if counts[0] <= counts[1] else 1


# ------------------------------------------------------------ connections ---

func _on_peer_connected(_id: int) -> void:
	pass  # Clients register themselves once connected.


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var pname: String = players.get(id, {}).get("name", "Someone")
	players.erase(id)
	_ready_peers.erase(id)
	if in_match and world != null:
		world.on_peer_left(id, pname)
	_broadcast_lobby()


func _on_connected_to_server() -> void:
	net_status.emit("Connected! Downloading characters...")
	_rpc_register.rpc_id(1, player_name, PROTOCOL)


func _on_connection_failed() -> void:
	leave()
	left_game.emit("Could not connect. Check the IP/port and that the host forwarded the port.")


func _on_server_disconnected() -> void:
	leave()
	left_game.emit("Disconnected from host.")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(pname: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_rpc_kicked.rpc_id(id, "Version mismatch: host has protocol %d, you have %d." % [PROTOCOL, protocol])
		return
	if in_match:
		_rpc_kicked.rpc_id(id, "A match is in progress. Try again when it ends.")
		return
	players[id] = {"name": pname.substr(0, 20), "team": _smaller_team(), "character": default_character(), "bot": false}
	_rpc_content_begin.rpc_id(id)
	for cid in character_packs:
		_rpc_character_pack.rpc_id(id, cid, character_packs[cid])
	_rpc_item_pack.rpc_id(id, item_pack)
	_rpc_content_end.rpc_id(id)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
	leave()
	left_game.emit(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_content_begin() -> void:
	characters.clear()
	character_packs.clear()
	content_errors = PackedStringArray()
	using_host_content = true


@rpc("authority", "call_remote", "reliable")
func _rpc_character_pack(cid: String, pack: Dictionary) -> void:
	character_packs[cid] = pack
	var def = Content.build_character(pack, content_errors)
	if def != null:
		characters[cid] = def


@rpc("authority", "call_remote", "reliable")
func _rpc_item_pack(pack: Dictionary) -> void:
	item_pack = pack
	_build_items()


@rpc("authority", "call_remote", "reliable")
func _rpc_content_end() -> void:
	content_changed.emit()
	net_status.emit("")


# ------------------------------------------------------------------ lobby ---

func _broadcast_lobby() -> void:
	if online and is_host():
		_rpc_lobby.rpc(players, settings)
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(p: Dictionary, s: Dictionary) -> void:
	var first := players.is_empty()
	players = p
	settings = s
	if first:
		lobby_joined.emit()
	lobby_changed.emit()


## Change your own team/character (or a bot's, if you are the host).
func request_change(key: String, value, who := 0) -> void:
	if is_host():
		_apply_change(who if who != 0 else 1, key, value)
	else:
		_rpc_request_change.rpc_id(1, key, value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_change(key: String, value) -> void:
	_apply_change(multiplayer.get_remote_sender_id(), key, value)


func _apply_change(pid: int, key: String, value) -> void:
	if not players.has(pid) or in_match:
		return
	match key:
		"team":
			players[pid].team = clampi(int(value), 0, 1)
		"character":
			if characters.has(str(value)):
				players[pid].character = str(value)
	_broadcast_lobby()


func set_map(id: String) -> void:
	if is_host() and maps.has(id):
		settings.map = id
		_broadcast_lobby()


## Host-only match options (e.g. "fog").
func set_setting(key: String, value) -> void:
	if is_host() and not in_match:
		settings[key] = value
		_broadcast_lobby()


func add_bot(team: int) -> void:
	if not is_host() or characters.is_empty():
		return
	var ids := characters.keys()
	var cid: String = ids[randi() % ids.size()]
	players[_next_bot] = {"name": "Bot %d" % -_next_bot, "team": team, "character": cid, "bot": true}
	_next_bot -= 1
	_broadcast_lobby()


func remove_bot(pid: int) -> void:
	if is_host() and players.has(pid) and players[pid].bot:
		players.erase(pid)
		_broadcast_lobby()


# ------------------------------------------------------------------ match ---

func start_match() -> void:
	if not is_host() or in_match or maps.is_empty():
		return
	var map_id: String = settings.map if maps.has(settings.map) else maps.keys()[0]
	for pid in players:
		if not characters.has(players[pid].character):
			players[pid].character = default_character()
	match_count += 1
	var config := {
		"id": match_count,
		"map": map_id,
		"map_data": maps[map_id],
		"players": players.duplicate(true),
		"online": online,
		"fog": bool(settings.get("fog", true)),
	}
	in_match = true
	_ready_peers.clear()
	if online:
		_rpc_start.rpc(config)
	match_started.emit(config)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(config: Dictionary) -> void:
	in_match = true
	match_started.emit(config)


func notify_world_ready() -> void:
	_rpc_world_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_world_ready() -> void:
	_ready_peers[multiplayer.get_remote_sender_id()] = true
	if world != null:
		world.check_ready()


func all_peers_ready() -> bool:
	for pid in players:
		if pid > 1 and not players[pid].bot and not _ready_peers.has(pid):
			return false
	return true


func return_to_lobby() -> void:
	if not is_host():
		return
	if online:
		_rpc_return_to_lobby.rpc()
	_rpc_return_to_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_return_to_lobby() -> void:
	in_match = false
	world = null
	back_to_lobby.emit()
	lobby_changed.emit()


# --------------------------------------------------------------- settings ---

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		player_name = str(cfg.get_value("player", "name", player_name))
		last_ip = str(cfg.get_value("net", "ip", last_ip))
		port = int(cfg.get_value("net", "port", port))
		settings.map = str(cfg.get_value("lobby", "map", settings.map))


func save_settings() -> void:
	if cmdline.has("auto"):
		return
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "ip", last_ip)
	cfg.set_value("net", "port", port)
	cfg.set_value("lobby", "map", settings.map)
	cfg.save(SETTINGS_PATH)
