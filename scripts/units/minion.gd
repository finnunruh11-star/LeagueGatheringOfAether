class_name Minion
extends Unit
## Lane minion with League's stats and targeting: it walks its lane and picks targets by League's
## call-for-help priority (enemy champions hurting allied champions first, then minions and
## turrets attacking allies, then the closest minion, then the closest champion). It keeps its
## target until a strictly more important one shows up, and gives up long chases of champions.

const CHAMPION_LEASH := 450.0     # a minion stops chasing a champion this far from where the chase began
const CHAMPION_DROP_RANGE := 700.0
const RETURN_DISTANCE := 40.0
const ACQUIRE_RANGE := 500.0      # targets are picked within this distance (edge to edge)
const HELP_RANGE := 1000.0        # allied champions this close call for help against champions hurting them
const AGGRO_MEMORY := 2.0         # seconds a champion's attack or targeted spell keeps calling for help
const RETARGET_EVERY := 0.25

const BODY_ART := [
	{
		"melee": preload("res://assets/minions/blue_melee.png"),
		"ranged": preload("res://assets/minions/blue_ranged.png"),
		"siege": preload("res://assets/minions/blue_siege.png"),
		"super": preload("res://assets/minions/blue_super.png"),
	},
	{
		"melee": preload("res://assets/minions/red_melee.png"),
		"ranged": preload("res://assets/minions/red_ranged.png"),
		"siege": preload("res://assets/minions/red_siege.png"),
		"super": preload("res://assets/minions/red_super.png"),
	},
]
const ART_ANCHOR := Vector2(0.5, 0.625)
const ART_SCALE := 3.3            # drawn sprite side per unit of gameplay radius (champion-like proportions)

## League's lane minions (patch 14+). Radii are League's gameplay radii; XP is the full award
## (World applies League's solo / shared multipliers).
const TYPES := {
	"melee": {"attack_speed": 1.25, "attack_range": 110.0, "radius": 48.0, "xp": 65.0, "ranged": false},
	"ranged": {"attack_speed": 0.667, "attack_range": 550.0, "radius": 48.0, "xp": 32.0, "ranged": true},
	"siege": {"attack_speed": 1.0, "attack_range": 300.0, "radius": 65.0, "xp": 100.0, "ranged": true},
	"super": {"attack_speed": 0.85, "attack_range": 170.0, "radius": 65.0, "xp": 100.0, "ranged": false,
		"armor": 100.0, "magic_resist": -30.0, "hp_regen": 13.5},
}

var lane := PackedVector2Array()
var wp := 1
var minion_type := "melee"
var think_t := 0.0
var chase_start := Vector2.ZERO
var chasing_champion := false
var returning_to_lane := false
var body_texture: Texture2D


## Health, attack damage, armor and gold of a minion type after `upgrades` upgrades (one every
## 90 seconds, i.e. every third wave; League counts the first wave as upgrade 1).
static func league_stats(type: String, upgrades: int) -> Dictionary:
	var x := clampi(upgrades, 0, 24) + 1
	var early := mini(x, 5)
	var late := maxi(x - 5, 0)
	match type:
		"ranged":
			return {"max_hp": 290.0 + 6.0 * early + 8.25 * late, "attack_damage": 22.5 + 1.5 * early + 4.5 * late,
				"armor": 0.0, "gold": 14.0}
		"siege":
			return {"max_hp": 850.0 + 62.0 * early + 87.0 * late, "attack_damage": 39.5 + 1.5 * x,
				"armor": 0.0, "gold": minf(57.0 + 3.0 * x, 90.0)}
		"super":
			return {"max_hp": 1500.0 + 100.0 * x, "attack_damage": 225.0 + 5.0 * x, "armor": 100.0,
				"gold": minf(57.0 + 3.0 * x, 90.0)}
	return {"max_hp": minf(455.0 + 22.0 * early + 32.25 * late + 0.15 * x * (x - 1), 1300.0),
		"attack_damage": minf(12.0 + 3.41 * late, 80.0), "armor": minf(0.085 * late * maxi(x - 6, 0) * 0.5, 16.0), "gold": 21.0}


## League minions walk at 325, gaining 25 movement speed every 5 minutes from 10:00 to 25:00.
static func league_move_speed(time: float) -> float:
	return 325.0 + 25.0 * clampf(floorf((time - 600.0) / 300.0) + 1.0, 0.0, 4.0)


func setup(d: Dictionary) -> void:
	kind = "minion"
	team = int(d.team)
	minion_type = str(d.get("type", "melee"))
	if not TYPES.has(minion_type):
		minion_type = "melee"
	if team >= 0 and team < BODY_ART.size():
		body_texture = BODY_ART[team].get(minion_type)
	var t: Dictionary = TYPES[minion_type]
	var upgrades := clampi(int(d.get("upgrades", 0)), 0, 25)
	var grown := league_stats(minion_type, upgrades)
	base_stats.max_hp = grown.max_hp
	base_stats.attack_damage = grown.attack_damage
	base_stats.armor = grown.armor
	base_stats.magic_resist = float(t.get("magic_resist", 0.0))
	base_stats.attack_speed = t.attack_speed
	base_stats.attack_range = t.attack_range
	base_stats.move_speed = league_move_speed(world.time)
	base_stats.hp_regen = float(t.get("hp_regen", 0.0))
	var ov = world.map.data.get("minion_stats", {})
	if ov is Dictionary and ov.get(minion_type) is Dictionary:
		for k in ov[minion_type]:
			base_stats[k] = float(ov[minion_type][k])
	base_radius = float(t.radius)
	xp_value = t.xp
	gold_value = grown.gold
	base_stats.vision = 650.0
	color = Game.TEAM_COLORS[team].lerp(Color.WHITE, 0.15)
	attack_def = {"ranged": t.ranged, "speed": 900.0, "color": color.lightened(0.4), "size": 5.0, "sprite": "", "char": "", "on_hit": []}
	separate = true
	display_name = {"ranged": "Caster Minion", "siege": "Cannon Minion", "super": "Super Minion"}.get(minion_type, "Melee Minion")
	global_position = d.pos
	lane = world.map.lane(team, int(d.get("lane", 0)))


## Minions bump into each other with a smaller body than the area they can be hit in (like champions).
func pathing_radius() -> float:
	return radius * 0.6


func _think(delta: float) -> void:
	if returning_to_lane:
		if global_position.distance_to(chase_start) > RETURN_DISTANCE:
			move_goal = chase_start
			return
		returning_to_lane = false
	if chasing_champion and (not valid_target(attack_target)
			or global_position.distance_to(chase_start) >= CHAMPION_LEASH
			or global_position.distance_to(attack_target.global_position) > maxf(CHAMPION_DROP_RANGE, attack_reach(attack_target))):
		chasing_champion = false
		attack_target = null
		cancel_attack_windup()
		if global_position.distance_to(chase_start) > RETURN_DISTANCE:
			returning_to_lane = true
			move_goal = chase_start
			return
	think_t -= delta
	if think_t <= 0.0:
		think_t = RETARGET_EVERY + randf() * 0.05
		_retarget()
	if attack_target != null or lane.size() < 2:
		move_goal = null
		return
	while wp < lane.size() - 1:
		var seg := lane[wp + 1] - lane[wp]
		if global_position.distance_to(lane[wp]) < 80.0 or (global_position - lane[wp]).dot(seg) > 0.0:
			wp += 1
		else:
			break
	move_goal = lane[wp]


## Keeps the current target unless a strictly more important one is around (League's rule), and
## never lets go of a turret it is already hitting.
func _retarget() -> void:
	var cur = attack_target if attack_target != null and _keeps(attack_target) else null
	if cur == null and attack_target != null:
		cancel_attack_windup()
		attack_target = null
	if cur != null and (cur.is_structure or target_priority(cur) >= 8):
		return
	var best := _best_target(target_priority(cur) if cur != null else 0, cur)
	if best == null:
		return
	cancel_attack_windup()
	attack_target = best
	if best.is_champion and not chasing_champion:
		chase_start = global_position
	chasing_champion = best.is_champion


## The target a minion without one would pick right now, or null.
func _find_target() -> Unit:
	return _best_target(0)


## The most important acquirable target above priority `above` (the closest one on ties).
func _best_target(above: int, skip = null) -> Unit:
	var best: Unit = null
	var best_p := above
	var best_d := INF
	for u: Unit in world.units:
		if u == skip or not _acquirable(u):
			continue
		var p := target_priority(u)
		if p <= above:
			continue
		var d: float = global_position.distance_to(u.global_position) - u.radius
		if p > best_p or (p == best_p and d < best_d):
			best = u
			best_p = p
			best_d = d
	return best


## League's target priority (higher wins): 8 champion hurting an allied champion, 7 minion or pet
## attacking an allied champion, 6 minion or pet attacking an allied minion, 5 turret shooting an
## allied minion, 4 champion hurting an allied minion, 3 any minion or pet, 2 any champion,
## 1 any other structure.
func target_priority(u: Unit) -> int:
	if u.is_structure:
		var shot = u.attack_target
		return 5 if is_instance_valid(shot) and shot is Minion and shot.team == team else 1
	if u.is_champion:
		var victim = _champion_victim(u)
		if victim is Champion:
			return 8
		return 4 if victim is Minion else 2
	var at = u.attack_target
	if is_instance_valid(at) and at.team == team:
		if at.is_champion:
			return 7
		if at is Minion:
			return 6
	return 3


## The ally an enemy champion just hit with an attack or a targeted spell (calls for help), or null.
func _champion_victim(u: Unit):
	if world.time - u.aggro_time > AGGRO_MEMORY:
		return null
	var v = world.entities.get(u.aggro_target_id)
	if not (v is Unit) or v.dead or v.team != team:
		return null
	if v is Champion and v.global_position.distance_to(global_position) > HELP_RANGE:
		return null
	return v


func _hostile(u: Unit) -> bool:
	return u.team != team and u.team <= 1 and not u.dead and not u.is_ward and u.targetable() and u.visible_to(team) \
		and not (u.is_structure and u.is_protected())


## Targets are picked within ACQUIRE_RANGE (or the attack range, if longer); champions hurting an
## allied champion are picked from further away. (Cheap checks first: this runs for every unit.)
func _acquirable(u: Unit) -> bool:
	if u.team == team or u.team > 1 or u.dead or u.is_ward:
		return false
	var d := global_position.distance_to(u.global_position)
	var in_range := d - u.radius - radius <= maxf(ACQUIRE_RANGE, stats.attack_range)
	if not in_range and not (u.is_champion and d <= HELP_RANGE):
		return false
	if not _hostile(u):
		return false
	return in_range or _champion_victim(u) is Champion


## Whether to keep attacking the current target: still hostile and not run off too far.
func _keeps(u) -> bool:
	if not is_instance_valid(u) or not _hostile(u):
		return false
	var d := global_position.distance_to(u.global_position)
	if u.is_champion and _champion_victim(u) is Champion:
		return d <= HELP_RANGE
	return d - u.radius - radius <= maxf(ACQUIRE_RANGE, stats.attack_range) + 200.0


func _on_death() -> void:
	world.despawn_later(self, 0.4)


## League: minions deal 50% less damage to champions; against structures melee, caster and super
## minions deal 50% less to turrets, cannons 25% less; against inhibitors and the Nexus melee and
## caster minions deal 50% less, cannons 50% less and super minions 87.5% less.
func attack_damage_against(t) -> float:
	if t.is_structure:
		var turret: bool = t is Tower and not t.is_inhibitor and not t.is_nexus
		var mult := 0.5
		if minion_type == "siege":
			mult = 0.75 if turret else 0.5
		elif minion_type == "super":
			mult = 0.5 if turret else 0.125
		return stats.attack_damage * mult * stats.structure_damage_mult
	return stats.attack_damage * (0.5 if t.is_champion else 1.0)


func _draw_body() -> void:
	if body_texture != null:
		var size := Vector2.ONE * radius * ART_SCALE
		var tint := Color(0.8, 0.9, 1.0) if flags & F_SLOW else Color.WHITE
		if flash > 0.0:
			tint *= Color(1.6, 1.6, 1.6)
		if facing < 0.0:
			draw_set_transform(_body_offset(), 0.0, _squash_scale() * Vector2(-1, 1))
		draw_texture_rect(body_texture, Rect2(-size * ART_ANCHOR, size), false, tint)
		return
	var c := body_color()
	var r := radius
	var f := facing
	if minion_type == "siege":
		draw_rect(Rect2(-r, -r * 0.55, r * 2.0, r * 1.1), c.darkened(0.35))
		draw_circle(Vector2(-r * 0.55, r * 0.45), r * 0.4, c)
		draw_circle(Vector2(r * 0.55, r * 0.45), r * 0.4, c)
		draw_line(Vector2(0, -r * 0.35), Vector2(f * r * 1.3, -r * 0.55), c.lightened(0.5), 7.0)
		return
	elif minion_type == "ranged":
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 1.3), Vector2(r * 0.95, r * 0.2), Vector2(0, r), Vector2(-r * 0.95, r * 0.2)]), c.darkened(0.4))
		draw_colored_polygon(PackedVector2Array([Vector2(0, -r * 1.12), Vector2(r * 0.7, r * 0.1), Vector2(0, r * 0.72), Vector2(-r * 0.7, r * 0.1)]), c)
		var orb := Vector2(f * r * 1.15, -r * 0.35)
		draw_line(Vector2(f * r * 0.55, r * 0.7), orb, Color(0.45, 0.32, 0.2), 2.0)
		draw_circle(orb, 4.5, Color(c.lightened(0.5), 0.35))
		draw_circle(orb, 2.8, c.lightened(0.75))
	else:
		draw_circle(Vector2.ZERO, r, c.darkened(0.4))
		draw_circle(Vector2(0, -r * 0.1), r * 0.85, c)
		if minion_type == "super":
			draw_arc(Vector2.ZERO, r * 0.68, 0.0, TAU, 24, c.lightened(0.7), 3.0, true)
		var swing := 0.0
		if windup_left > 0.0:
			swing = -0.75 * (1.0 - windup_left / windup_duration)
		elif anim == ANIM_ATTACK:
			swing = 1.0
		var hand := Vector2(f * r * 0.75, r * 0.1)
		var tip := hand + Vector2(f * cos(-1.1 + swing * 1.6), sin(-1.1 + swing * 1.6)) * r * 1.25
		draw_line(hand, tip, Color(0.88, 0.9, 0.95), 2.5)
		draw_line(hand + Vector2(0, -3), hand + Vector2(0, 3), Color(0.5, 0.4, 0.3), 2.0)
	draw_circle(Vector2(f * r * 0.32, -r * 0.3), 1.8, Color(0.05, 0.05, 0.08))
	draw_circle(Vector2(f * r * 0.02, -r * 0.3), 1.8, Color(0.05, 0.05, 0.08))


func bar_width() -> float:
	return 46.0 if radius < 60.0 else 62.0


func bar_height() -> float:
	return 4.0


func bar_top() -> float:
	return -radius * 1.35 - 18.0 if body_texture != null else super.bar_top()
