class_name Monster
extends Unit
## Neutral jungle monster (team 2). It waits at its camp until something damages it; then the
## whole camp fights back (see Jungle.provoke). If its target leaves the leash range around the
## camp, or nobody that hit the camp is left, it walks home and resets to full health.
## Stats grow with the average champion level when the camp spawns. The Rift Scuttler never
## fights - it wanders along the river.

const KINDS := {
	"blue_sentinel": {"name": "Blue Sentinel", "hp": 1800.0, "ad": 42.0, "as": 0.49, "range": 150.0, "armor": 10.0,
		"mr": 0.0, "ms": 330.0, "radius": 52.0, "gold": 90.0, "xp": 95.0, "shape": "golem", "color": "4a7fe0", "large": true},
	"red_brambleback": {"name": "Red Brambleback", "hp": 1800.0, "ad": 42.0, "as": 0.49, "range": 150.0, "armor": 10.0,
		"mr": 0.0, "ms": 330.0, "radius": 52.0, "gold": 90.0, "xp": 95.0, "shape": "golem", "color": "d8503a", "large": true},
	"gromp": {"name": "Gromp", "hp": 1500.0, "ad": 45.0, "as": 0.42, "range": 250.0, "ranged": true, "armor": 0.0, "mr": 0.0,
		"ms": 330.0, "radius": 46.0, "gold": 80.0, "xp": 120.0, "shape": "frog", "color": "7ea84c", "large": true},
	"greater_murk_wolf": {"name": "Greater Murk Wolf", "hp": 1100.0, "ad": 28.0, "as": 0.63, "range": 175.0, "armor": 10.0,
		"mr": 0.0, "ms": 380.0, "radius": 38.0, "gold": 55.0, "xp": 80.0, "shape": "wolf", "color": "6c7088", "large": true},
	"murk_wolf": {"name": "Murk Wolf", "hp": 320.0, "ad": 12.0, "as": 0.63, "range": 150.0, "armor": 0.0, "mr": 0.0,
		"ms": 380.0, "radius": 24.0, "gold": 15.0, "xp": 20.0, "shape": "wolf", "color": "7a7e94"},
	"crimson_raptor": {"name": "Crimson Raptor", "hp": 800.0, "ad": 16.0, "as": 0.67, "range": 300.0, "ranged": true,
		"armor": 15.0, "mr": 0.0, "ms": 350.0, "radius": 34.0, "gold": 35.0, "xp": 30.0, "shape": "bird", "color": "d0583a", "large": true},
	"raptor": {"name": "Raptor", "hp": 250.0, "ad": 7.0, "as": 0.67, "range": 300.0, "ranged": true, "armor": 0.0, "mr": 0.0,
		"ms": 350.0, "radius": 20.0, "gold": 10.0, "xp": 13.0, "shape": "bird", "color": "c87a4a"},
	"ancient_krug": {"name": "Ancient Krug", "hp": 1000.0, "ad": 40.0, "as": 0.61, "range": 150.0, "armor": 15.0, "mr": 0.0,
		"ms": 300.0, "radius": 48.0, "gold": 50.0, "xp": 80.0, "shape": "rock", "color": "8c7c62", "large": true},
	"krug": {"name": "Krug", "hp": 450.0, "ad": 20.0, "as": 0.61, "range": 150.0, "armor": 10.0, "mr": 0.0,
		"ms": 300.0, "radius": 30.0, "gold": 20.0, "xp": 40.0, "shape": "rock", "color": "9a8a70"},
	"rift_scuttler": {"name": "Rift Scuttler", "hp": 900.0, "ad": 0.0, "as": 0.0, "range": 0.0, "armor": 40.0, "mr": 40.0,
		"ms": 200.0, "radius": 36.0, "gold": 70.0, "xp": 115.0, "shape": "crab", "color": "62c0c8", "passive": true},
	"dragon": {"name": "Drake", "hp": 3500.0, "ad": 100.0, "as": 0.5, "range": 500.0, "ranged": true, "dtype": "magic",
		"armor": 21.0, "mr": 30.0, "ms": 330.0, "radius": 80.0, "gold": 0.0, "xp": 300.0, "shape": "drake", "color": "e86a2a",
		"epic": true, "special": "breath", "special_cd": 7.0},
	"elder_dragon": {"name": "Elder Dragon", "hp": 6400.0, "ad": 150.0, "as": 0.5, "range": 500.0, "ranged": true, "dtype": "magic",
		"armor": 120.0, "mr": 70.0, "ms": 330.0, "radius": 90.0, "gold": 0.0, "xp": 450.0, "shape": "drake", "color": "b8a8ff",
		"epic": true, "special": "breath", "special_cd": 6.0},
	"baron": {"name": "Baron Nashor", "hp": 9000.0, "ad": 150.0, "as": 0.75, "range": 650.0, "ranged": true, "dtype": "magic",
		"armor": 120.0, "mr": 70.0, "ms": 0.0, "radius": 110.0, "gold": 0.0, "xp": 800.0, "shape": "baron", "color": "9a4ad8",
		"epic": true, "special": "acid", "special_cd": 6.0},
}
const ELEMENT_COLORS := {"infernal": "e8602a", "mountain": "b48c5a", "ocean": "3aa0d8", "cloud": "c8dcef", "elder": "b8a8ff"}

var kind_id := ""
var info := {}
var camp_id := -1
var home := Vector2.ZERO
var leash := 900.0
var element := ""
var resetting := false
var passive := false
var epic := false
var large := false
var think_t := 0.0
var special_t := 3.0
var route := PackedVector2Array()
var route_i := 0
var route_dir := 1


func setup(d: Dictionary) -> void:
	kind = "monster"
	team = 2
	kind_id = str(d.get("kind", "murk_wolf"))
	info = KINDS.get(kind_id, KINDS.murk_wolf)
	camp_id = int(d.get("camp", -1))
	element = str(d.get("element", ""))
	display_name = str(info.name)
	if element != "" and kind_id == "dragon":
		display_name = "%s Drake" % element.capitalize()
	passive = bool(info.get("passive", false))
	epic = bool(info.get("epic", false))
	large = bool(info.get("large", false)) or epic
	var lvl := maxf(float(d.get("level", 1.0)), 1.0)
	var hp_mult := 1.0 + 0.06 * (lvl - 1.0)
	base_stats.max_hp = float(info.hp) * hp_mult + float(d.get("bonus_hp", 0.0))
	base_stats.attack_damage = float(info.ad) * (1.0 + 0.07 * (lvl - 1.0))
	base_stats.attack_speed = float(info["as"])
	base_stats.attack_range = float(info.range)
	base_stats.armor = float(info.armor)
	base_stats.magic_resist = float(info.mr)
	base_stats.move_speed = float(info.ms)
	base_stats.hp_regen = 0.0
	base_stats.vision = 0.0
	base_radius = float(info.radius)
	gold_value = float(info.gold)
	xp_value = float(info.xp) * 1.25 * (1.0 + 0.08 * (lvl - 1.0))
	color = Color(ELEMENT_COLORS.get(element, info.color))
	attack_def = {"ranged": bool(info.get("ranged", false)), "speed": 1100.0, "color": color.lightened(0.35), "size": 9.0 if epic else 6.0,
		"sprite": "", "char": "", "on_hit": [], "damage_type": str(info.get("dtype", "physical"))}
	home = d.get("home", d.pos)
	leash = float(d.get("leash", 900.0))
	route = d.get("route", PackedVector2Array())
	global_position = d.pos


func _think(delta: float) -> void:
	if passive:
		_wander()
		return
	if resetting:
		attack_target = null
		hp = minf(hp + stats.max_hp * 0.3 * delta, stats.max_hp)
		move_goal = home
		if global_position.distance_to(home) < 30.0:
			_finish_reset()
		return
	if attack_target != null and (not valid_target(attack_target) or global_position.distance_to(home) > leash
			or attack_target.global_position.distance_to(home) > leash + 150.0):
		attack_target = null
		think_t = 0.0
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.25
		if attack_target == null:
			attack_target = world.jungle.next_target(self)
			if attack_target == null and (hp < stats.max_hp or global_position.distance_to(home) > 60.0):
				start_reset()
				return
	if attack_target == null:
		move_goal = home if global_position.distance_to(home) > 40.0 else null
	elif info.has("special"):
		special_t -= delta
		if special_t <= 0.0 and global_position.distance_to(attack_target.global_position) < 900.0:
			special_t = float(info.special_cd)
			_special(attack_target)


func start_reset() -> void:
	resetting = true
	attack_target = null
	cancel_attack_windup()
	statuses = statuses.filter(func(s): return not s.type in HARD_CC)
	stats_dirty = true
	if world.jungle != null:
		world.jungle.forget(camp_id)


func _finish_reset() -> void:
	resetting = false
	hp = stats.max_hp
	move_goal = null
	special_t = 3.0


## Something damaged the camp: fight it unless it's out of the leash range.
func provoke(src: Unit) -> void:
	if passive or dead or not is_instance_valid(src) or src.team == team:
		return
	if src.global_position.distance_to(home) > leash + 150.0:
		return
	if resetting:
		resetting = false
	if attack_target == null or not valid_target(attack_target):
		attack_target = src


func on_damaged(_amount: float, src) -> void:
	if world.jungle != null and is_instance_valid(src):
		world.jungle.provoke(camp_id, src)


## Rift Scuttler: walks back and forth along its river route.
func _wander() -> void:
	if route.size() < 2:
		move_goal = null
		return
	if move_goal == null or global_position.distance_to(route[route_i]) < 40.0:
		var nxt := route_i + route_dir
		if nxt < 0 or nxt >= route.size():
			route_dir = -route_dir
			nxt = route_i + route_dir
		route_i = clampi(nxt, 0, route.size() - 1)
	move_goal = route[route_i]


## Dragon breath (a line) or Baron's acid pool (a circle under the target) - telegraphed first.
func _special(t: Unit) -> void:
	var lvl := float(world.jungle.average_level()) if world.jungle != null else 1.0
	if info.special == "breath":
		var dir := global_position.direction_to(t.global_position)
		var from := global_position + dir * radius * 0.5
		var to := from + dir * 800.0
		world.fx("beam_warn", {"from": from, "to": to, "width": 180.0, "color": color, "dur": 0.8, "team": team})
		world.schedule(0.8, _breath.bind(from, to, 90.0 + 12.0 * lvl))
	else:
		var at := t.global_position
		world.fx("telegraph", {"pos": at, "radius": 320.0, "color": color, "dur": 0.9, "team": team})
		world.schedule(0.9, _acid.bind(at, 150.0 + 14.0 * lvl))


func _breath(from: Vector2, to: Vector2, dmg: float) -> void:
	if dead:
		return
	world.fx("beam", {"from": from, "to": to, "color": color, "width": 60.0})
	for u in world.query_line(from, to, 90.0, team):
		u.take_damage(dmg, self, "magic", {"vfx": "burst", "col": color, "aoe": true})


func _acid(at: Vector2, dmg: float) -> void:
	if dead:
		return
	world.fx("blast", {"pos": at, "radius": 320.0, "color": color})
	for u in world.query(at, 320.0, team):
		u.take_damage(dmg, self, "magic", {"vfx": "burst", "col": color, "aoe": true})
		u.add_status({"type": "slow", "amount": 0.35, "time": 1.5}, self, "baron_acid")


func _on_death() -> void:
	world.despawn_later(self, 1.0)


func bar_width() -> float:
	return 150.0 if epic else (70.0 if large else 40.0)


func bar_height() -> float:
	return 9.0 if epic else 5.0


func bar_top() -> float:
	return -radius * 1.3 - 14.0


# ---------------------------------------------------------------- drawing ---

func _draw_body() -> void:
	var c := body_color()
	var dark := c.darkened(0.45)
	var r := radius
	var f := facing
	match str(info.shape):
		"golem":
			draw_circle(Vector2(0, r * 0.1), r, dark)
			draw_circle(Vector2(0, -r * 0.05), r * 0.88, Color(0.42, 0.4, 0.38))
			draw_circle(Vector2(-r * 0.62, r * 0.05), r * 0.36, Color(0.36, 0.34, 0.32))
			draw_circle(Vector2(r * 0.62, r * 0.05), r * 0.36, Color(0.36, 0.34, 0.32))
			draw_circle(Vector2(0, -r * 0.15), r * 0.38, c)
			draw_circle(Vector2(0, -r * 0.15), r * 0.2, c.lightened(0.6))
			draw_circle(Vector2(f * r * 0.25, -r * 0.62), r * 0.09, c.lightened(0.7))
		"frog":
			draw_set_transform(Vector2(0, r * 0.1), 0.0, Vector2(1.2, 0.8))
			draw_circle(Vector2.ZERO, r, dark)
			draw_circle(Vector2(0, -r * 0.08), r * 0.9, c)
			draw_set_transform(Vector2.ZERO)
			for s in [-1.0, 1.0]:
				draw_circle(Vector2(s * r * 0.45, -r * 0.62), r * 0.24, Color(0.95, 0.9, 0.5))
				draw_circle(Vector2(s * r * 0.45 + f * 3.0, -r * 0.62), r * 0.11, Color(0.05, 0.05, 0.05))
			draw_arc(Vector2(f * r * 0.2, r * 0.05), r * 0.5, 0.3, 2.8, 12, dark, 3.0)
		"wolf":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.25, 0.85))
			draw_circle(Vector2.ZERO, r, dark)
			draw_circle(Vector2(0, -r * 0.08), r * 0.86, c)
			draw_set_transform(Vector2.ZERO)
			var head := Vector2(f * r * 0.85, -r * 0.4)
			draw_circle(head, r * 0.5, c.lightened(0.1))
			for s in [-0.35, 0.35]:
				draw_colored_polygon(PackedVector2Array([head + Vector2(s * r, -r * 0.2), head + Vector2(s * r + 0.18 * r, -r * 0.75),
					head + Vector2(s * r + 0.32 * r, -r * 0.15)]), dark)
			draw_circle(head + Vector2(f * r * 0.18, -r * 0.05), r * 0.09, Color(0.7, 0.85, 1.0))
		"bird":
			draw_circle(Vector2.ZERO, r, dark)
			draw_circle(Vector2(0, -r * 0.1), r * 0.85, c)
			draw_colored_polygon(PackedVector2Array([Vector2(f * r * 0.7, -r * 0.35), Vector2(f * r * 1.45, -r * 0.15),
				Vector2(f * r * 0.7, r * 0.05)]), Color(0.95, 0.8, 0.35))
			for i in 3:
				draw_line(Vector2(-f * r * 0.6, -r * (0.6 - i * 0.25)), Vector2(-f * r * 1.2, -r * (0.95 - i * 0.2)), c.lightened(0.3), 3.0)
			draw_circle(Vector2(f * r * 0.35, -r * 0.4), r * 0.12, Color(0.1, 0.05, 0.02))
		"rock":
			var pts := PackedVector2Array()
			for i in 9:
				var a := TAU * i / 9.0
				pts.append(Vector2.from_angle(a) * r * (0.85 + 0.15 * sin(a * 3.0 + 1.0)))
			draw_colored_polygon(pts, dark)
			var inner := PackedVector2Array()
			for q in pts:
				inner.append(q * 0.86 + Vector2(0, -r * 0.08))
			draw_colored_polygon(inner, c)
			draw_circle(Vector2(f * r * 0.3, -r * 0.3), r * 0.12, Color(1.0, 0.6, 0.2))
			draw_circle(Vector2(f * r * 0.05, -r * 0.3), r * 0.12, Color(1.0, 0.6, 0.2))
		"crab":
			for i in 3:
				for s in [-1.0, 1.0]:
					draw_line(Vector2(s * r * 0.6, r * (0.1 * i)), Vector2(s * r * 1.25, r * (0.25 + 0.2 * i)), dark, 3.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.2, 0.75))
			draw_circle(Vector2.ZERO, r, dark)
			draw_circle(Vector2(0, -r * 0.1), r * 0.88, c)
			draw_circle(Vector2(0, -r * 0.2), r * 0.45, c.lightened(0.35))
			draw_set_transform(Vector2.ZERO)
			draw_circle(Vector2(-r * 0.3, -r * 0.62), r * 0.12, Color(0.05, 0.05, 0.05))
			draw_circle(Vector2(r * 0.3, -r * 0.62), r * 0.12, Color(0.05, 0.05, 0.05))
		"drake":
			for s in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([Vector2(s * r * 0.3, -r * 0.3), Vector2(s * r * 1.6, -r * 1.1),
					Vector2(s * r * 1.3, -r * 0.2), Vector2(s * r * 1.5, r * 0.25), Vector2(s * r * 0.4, r * 0.2)]), c.darkened(0.25))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.9, 1.1))
			draw_circle(Vector2.ZERO, r * 0.7, dark)
			draw_circle(Vector2(0, -r * 0.08), r * 0.62, c)
			draw_set_transform(Vector2.ZERO)
			var head := Vector2(f * r * 0.55, -r * 0.75)
			draw_circle(head, r * 0.32, c.lightened(0.1))
			draw_circle(head + Vector2(f * r * 0.12, -r * 0.05), r * 0.07, Color(1.0, 0.95, 0.6))
			draw_line(Vector2(-f * r * 0.3, r * 0.5), Vector2(-f * r * 1.1, r * 0.9), c.darkened(0.3), 6.0)
		"baron":
			for i in 5:
				var a := -PI * 0.5 + (i - 2) * 0.45
				draw_colored_polygon(PackedVector2Array([Vector2.from_angle(a - 0.12) * r * 0.75, Vector2.from_angle(a) * r * 1.35,
					Vector2.from_angle(a + 0.12) * r * 0.75]), c.lightened(0.3))
			draw_circle(Vector2.ZERO, r, dark)
			draw_circle(Vector2(0, -r * 0.06), r * 0.9, c)
			draw_circle(Vector2(0, -r * 0.1), r * 0.55, c.darkened(0.3))
			draw_circle(Vector2(f * r * 0.25, -r * 0.35), r * 0.12, Color(0.75, 1.0, 0.4))
			draw_circle(Vector2(f * r * -0.05, -r * 0.35), r * 0.12, Color(0.75, 1.0, 0.4))
		_:
			super._draw_body()
