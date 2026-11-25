extends RefCounted

const TACTICAL := ["retreat", "push", "on_my_way", "all_in", "assist", "hold", "missing", "bait"]
const VISION := ["vision_here", "need_vision", "vision_cleared"]
const LABELS := {
	"area": "Attention", "retreat": "Retreat", "push": "Push", "on_my_way": "On My Way",
	"all_in": "All In", "assist": "Assist Me", "hold": "Hold", "missing": "Enemy Missing", "bait": "Bait",
	"vision_here": "Enemy Vision", "need_vision": "Need Vision", "vision_cleared": "Vision Cleared",
}
const LIFETIME := 3.0

var open_action := ""
var origin := Vector2.ZERO
var anchor := Vector2.ZERO
var markers: Array[Dictionary] = []
var _recent := {}


func wheel() -> Array:
	return VISION if open_action == "ping_vision" else TACTICAL


func selection(mouse: Vector2) -> String:
	var offset := mouse - origin
	if offset.length_squared() < 24.0 * 24.0:
		return "vision_here" if open_action == "ping_vision" else "area"
	var choices := wheel()
	return choices[posmod(roundi((offset.angle() + PI * 0.5) * choices.size() / TAU), choices.size())]


func cancel() -> void:
	open_action = ""


func accept(peer: int, args: Array, map_size: Vector2, now: int) -> bool:
	if args.size() != 2 or not args[0] is String or not LABELS.has(args[0]) or not args[1] is Vector2:
		return false
	var at: Vector2 = args[1]
	if not at.is_finite() or not Rect2(Vector2.ZERO, map_size).has_point(at):
		return false
	var times: Array = _recent.get(peer, [])
	while not times.is_empty() and now - times[0] >= 5000:
		times.pop_front()
	if times.size() >= 3:
		return false
	times.append(now)
	_recent[peer] = times
	return true


func show_ping(kind: String, at: Vector2) -> void:
	markers.append({"kind": kind, "at": at, "left": LIFETIME})


func tick(delta: float) -> void:
	for i in range(markers.size() - 1, -1, -1):
		markers[i].left -= delta
		if markers[i].left <= 0.0:
			markers.remove_at(i)


static func color(kind: String) -> Color:
	match kind:
		"retreat", "all_in":
			return Color("ff826e")
		"missing", "bait":
			return Color("ffde83")
		"vision_here", "need_vision", "vision_cleared":
			return Color("cda4ff")
	return Color("83ddff")
