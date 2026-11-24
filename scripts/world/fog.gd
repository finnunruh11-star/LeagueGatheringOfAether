class_name FogOfWar
extends Node2D
## Fog of war. Every unit sees `stats.vision` around itself (plus each team's fountain);
## map walls block sight. The host computes what both teams see (used by targeting
## rules and bots); every player's screen hides enemies, projectiles and effects their
## team can't see and darkens unseen ground. The darkness is rendered on the GPU in a
## small SubViewport (vision circles occluded by wall rectangles) stretched over the map.
## Maps can turn it off with "fog": false.

const SCALE := 16.0           # world pixels per fog texel
const MAX_SOURCES := 96
const MAX_WALLS := 32
const UPDATE_DT := 0.1
const FOUNTAIN_VISION := 900.0
const STEALTH_REVEAL := 250.0  # stealthed enemies are revealed this close to a champion
const STRENGTH := 0.68

const MASK_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 map_size = vec2(1000.0);
uniform int source_count = 0;
uniform vec4 sources[96];
uniform int wall_count = 0;
uniform vec4 walls[32];

bool blocked(vec2 a, vec2 b) {
	vec2 d = b - a;
	vec2 inv = vec2(abs(d.x) < 0.0001 ? 1e8 : 1.0 / d.x, abs(d.y) < 0.0001 ? 1e8 : 1.0 / d.y);
	for (int i = 0; i < wall_count; i++) {
		vec4 w = walls[i];
		vec2 t0 = (w.xy - a) * inv;
		vec2 t1 = (w.xy + w.zw - a) * inv;
		vec2 tmin = min(t0, t1);
		vec2 tmax = max(t0, t1);
		float enter = max(max(tmin.x, tmin.y), 0.0);
		float leave = min(min(tmax.x, tmax.y), 1.0);
		if (enter <= leave) {
			return true;
		}
	}
	return false;
}

void fragment() {
	vec2 p = UV * map_size;
	float v = 0.0;
	for (int i = 0; i < source_count; i++) {
		vec4 s = sources[i];
		float d = distance(p, s.xy);
		if (d < s.z) {
			float f = 1.0 - smoothstep(s.z - 90.0, s.z, d);
			if (f > v && !blocked(s.xy, p)) {
				v = f;
			}
		}
	}
	COLOR = vec4(v, v, v, 1.0);
}
"""

const OVERLAY_SHADER := """
shader_type canvas_item;
uniform vec4 fog_color : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform float strength = 0.6;
void fragment() {
	float v = texture(TEXTURE, UV).r;
	COLOR = vec4(fog_color.rgb, (1.0 - v) * strength);
}
"""

var world: World
var enabled := true
var vis := [{}, {}]       # team -> {net_id: true}: enemy units that team can see right now
var sources := [[], []]   # team -> [Vector3(x, y, radius)]
var reveals := [[], []]   # team -> [Vector3] true-sight sources (control wards)
var walls: Array[Rect2] = []
var vp: SubViewport = null
var mask_mat: ShaderMaterial
var overlay: Sprite2D
var overlay_mat: ShaderMaterial
var minimap_mat: ShaderMaterial
var _t := 0.0
var _strength := STRENGTH


func setup(w: World) -> void:
	world = w
	enabled = bool(w.map.data.get("fog", true)) and bool(w.config.get("fog", true))
	walls = w.map.walls
	if not enabled:
		return
	z_index = 8
	var cells := Vector2i(ceili(w.map.size.x / SCALE), ceili(w.map.size.y / SCALE))
	vp = SubViewport.new()
	vp.size = cells
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(cells)
	mask_mat = ShaderMaterial.new()
	mask_mat.shader = _shader(MASK_SHADER)
	mask_mat.set_shader_parameter("map_size", Vector2(cells) * SCALE)
	var wl := PackedVector4Array()
	for r in walls.slice(0, MAX_WALLS):
		wl.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	wl.resize(MAX_WALLS)
	mask_mat.set_shader_parameter("walls", wl)
	mask_mat.set_shader_parameter("wall_count", mini(walls.size(), MAX_WALLS))
	rect.material = mask_mat
	vp.add_child(rect)
	overlay = Sprite2D.new()
	overlay.centered = false
	overlay.texture = vp.get_texture()
	overlay.scale = Vector2(SCALE, SCALE)
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = _shader(OVERLAY_SHADER)
	overlay.material = overlay_mat
	add_child(overlay)
	minimap_mat = ShaderMaterial.new()
	minimap_mat.shader = overlay_mat.shader
	minimap_mat.set_shader_parameter("strength", 0.7)


static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


## Texture of the fog mask (white = visible) for the minimap, or null without fog.
func mask_texture() -> Texture2D:
	return vp.get_texture() if vp != null else null


# ----------------------------------------------------------------- vision ---

func _physics_process(delta: float) -> void:
	if not enabled or world == null or not world.started:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = UPDATE_DT
	for t in 2:
		if world.is_server or t == world.local_team:
			_collect(t)
			_compute(t)


func _collect(team: int) -> void:
	var src: Array = [_v3(world.map.spawn_point(team), FOUNTAIN_VISION)]
	var rev: Array = []
	for u in world.units:
		if u.team != team or u.dead:
			continue
		var r: float = u.stats.get("vision", 0.0)
		if r <= 0.0:
			continue
		src.append(_v3(u.global_position, r))
		if u.reveal:
			rev.append(_v3(u.global_position, r))
	sources[team] = src
	reveals[team] = rev


func _compute(team: int) -> void:
	var old: Dictionary = vis[team]
	var seen := {}
	var src: Array = sources[team]
	for u in world.units:
		if u.team == team:
			continue
		if u.team > 1 or u.is_structure:
			seen[u.net_id] = true
			continue
		if u.dead:
			if old.has(u.net_id):
				seen[u.net_id] = true
			continue
		if u.flags & Unit.F_STEALTH and not _revealed(u, team):
			continue
		if _sees(src, u.global_position, u.radius):
			seen[u.net_id] = true
	vis[team] = seen


func _revealed(u: Unit, team: int) -> bool:
	for c in world.champions.values():
		if c.team == team and not c.dead and c.global_position.distance_to(u.global_position) < STEALTH_REVEAL:
			return true
	return _sees(reveals[team], u.global_position, u.radius)


func _sees(src: Array, p: Vector2, pad: float) -> bool:
	for s in src:
		var sp := Vector2(s.x, s.y)
		if sp.distance_to(p) <= s.z + pad and los(sp, p):
			return true
	return false


## True if no wall blocks the straight line from a to b.
func los(a: Vector2, b: Vector2) -> bool:
	for r in walls:
		if seg_hits_rect(a, b, r):
			return false
	return true


static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p := a[axis]
		var dv := b[axis] - p
		var lo := r.position[axis]
		var hi := r.end[axis]
		if absf(dv) < 0.0001:
			if p < lo or p > hi:
				return false
		else:
			var ta := (lo - p) / dv
			var tb := (hi - p) / dv
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true


func sees(u: Unit, team: int) -> bool:
	return team > 1 or vis[team].has(u.net_id)


## Whether a point is inside `team`'s vision (projectiles, zones, effects).
func point_visible(p: Vector2, team: int) -> bool:
	if not enabled or team > 1:
		return true
	return _sees(sources[team], p, 0.0)


static func _v3(p: Vector2, r: float) -> Vector3:
	return Vector3(p.x, p.y, r)


# ---------------------------------------------------------------- visuals ---

func _process(delta: float) -> void:
	if not enabled or world == null:
		return
	var lt := world.local_team
	var reveal_all := world.ended
	_strength = move_toward(_strength, 0.0 if reveal_all else STRENGTH, delta * 0.8)
	overlay_mat.set_shader_parameter("strength", _strength)
	minimap_mat.set_shader_parameter("strength", _strength * 1.15)
	_update_mask(lt)
	var seen: Dictionary = vis[clampi(lt, 0, 1)]
	for u in world.units:
		var want := 1.0
		if u.team != lt and not reveal_all and lt <= 1 and u.team <= 1 and not u.is_structure:
			want = 1.0 if seen.has(u.net_id) else 0.0
		if u.modulate.a != want:
			u.modulate.a = move_toward(u.modulate.a, want, delta * 7.0)
		u.visible = u.modulate.a > 0.01
	for e in world.entities.values():
		if e is Projectile or e is Zone:
			e.visible = reveal_all or e.team == lt or point_visible(e.global_position, lt)


## Feeds the local team's vision circles to the mask shader every frame (smooth edges).
func _update_mask(team: int) -> void:
	var arr := PackedVector4Array()
	var minor := PackedVector4Array()
	var sp := world.map.spawn_point(clampi(team, 0, 1))
	arr.append(Vector4(sp.x, sp.y, FOUNTAIN_VISION, 0.0))
	for u in world.units:
		if u.team != team or u.dead:
			continue
		var r: float = u.stats.get("vision", 0.0)
		if r <= 0.0:
			continue
		var v := Vector4(u.global_position.x, u.global_position.y, r, 0.0)
		if u is Minion:
			minor.append(v)
		else:
			arr.append(v)
	arr.append_array(minor)
	var n := mini(arr.size(), MAX_SOURCES)
	arr.resize(MAX_SOURCES)
	mask_mat.set_shader_parameter("sources", arr)
	mask_mat.set_shader_parameter("source_count", n)
