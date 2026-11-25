class_name FogOfWar
extends Node2D
## Fog of war and brush. Every unit sees `stats.vision` around itself (plus each team's
## fountain); map walls block sight. Brush hides whatever stands inside it from anyone who
## doesn't have a vision source (champion, minion, ward...) inside that same brush; units in
## brush still see out normally. The host computes what both teams see (used by targeting
## rules and bots); every player's screen hides enemies, projectiles and effects their team
## can't see and darkens unseen ground. The darkness is rendered on the GPU in a small
## SubViewport (vision circles ray-marched over the map's sight grid) stretched over the map.
## Maps can turn the darkness off with "fog": false (the lobby too); brush still works then.

const SCALE := 16.0           # world pixels per fog texel (bigger maps use coarser texels)
const MAX_TEXELS := 450000.0
const MAX_SOURCES := 96
const UPDATE_DT := 0.1
const FOUNTAIN_VISION := 900.0
const STEALTH_REVEAL := 250.0  # stealthed enemies are revealed this close to a champion
const STRENGTH := 0.68
const BRUSH_ALPHA := 0.55      # your own team's units look faded while hidden in brush

const MASK_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform vec2 map_size = vec2(1000.0);
uniform vec2 sight_size = vec2(1.0);
uniform float sight_cell = 16.0;
uniform sampler2D sight_tex : filter_nearest;
uniform int source_count = 0;
uniform vec4 sources[96];

float cell_at(vec2 p) {
	ivec2 c = clamp(ivec2(floor(p / sight_cell)), ivec2(0), ivec2(sight_size) - ivec2(1));
	return floor(texelFetch(sight_tex, c, 0).r * 255.0 + 0.5);
}

bool blocked(vec2 a, vec2 b) {
	int steps = int(distance(a, b) / (sight_cell * 1.5)) + 1;
	for (int k = 1; k < steps; k++) {
		if (cell_at(mix(a, b, float(k) / float(steps))) > 254.5) {
			return true;
		}
	}
	return false;
}

void fragment() {
	vec2 p = UV * map_size;
	float here = cell_at(p);
	float brush = here > 254.5 ? 0.0 : here;
	float v = 0.0;
	for (int i = 0; i < source_count; i++) {
		vec4 s = sources[i];
		float d = distance(p, s.xy);
		if (d < s.z) {
			float f = 1.0 - smoothstep(s.z - 90.0, s.z, d);
			if (f > v && (brush < 0.5 || abs(s.w - brush) < 0.5) && !blocked(s.xy, p)) {
				v = f;
				if (v > 0.999) {
					break;
				}
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
var map: GameMap
var enabled := true       # vision rules (fog and/or brush) are active
var dark := true          # unseen ground is darkened (fog of war proper)
var texel := SCALE        # world pixels per fog texel
var vis := [{}, {}]       # team -> {net_id: true}: enemy units that team can see right now
var sources := [[], []]   # team -> [Vector4(x, y, radius, brush id)]
var reveals := [[], []]   # team -> [Vector4] true-sight sources (control wards)
var vp: SubViewport = null
var mask_mat: ShaderMaterial
var overlay: Sprite2D
var overlay_mat: ShaderMaterial
var minimap_mat: ShaderMaterial
var _t := 0.0
var _strength := STRENGTH


func setup(w: World) -> void:
	world = w
	map = w.map
	dark = bool(map.data.get("fog", true)) and bool(w.config.get("fog", true))
	enabled = dark or not map.brushes.is_empty()
	if not dark:
		return
	z_index = 8
	texel = maxf(SCALE, ceilf(sqrt(map.size.x * map.size.y / MAX_TEXELS) / 4.0) * 4.0)
	var cells := Vector2i(ceili(map.size.x / texel), ceili(map.size.y / texel))
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
	mask_mat.set_shader_parameter("map_size", Vector2(cells) * texel)
	var img := Image.create_from_data(map.sight_cols, map.sight_rows, false, Image.FORMAT_L8, map.sight)
	mask_mat.set_shader_parameter("sight_tex", ImageTexture.create_from_image(img))
	mask_mat.set_shader_parameter("sight_size", Vector2(map.sight_cols, map.sight_rows))
	mask_mat.set_shader_parameter("sight_cell", GameMap.SIGHT_CELL)
	rect.material = mask_mat
	vp.add_child(rect)
	overlay = Sprite2D.new()
	overlay.centered = false
	overlay.texture = vp.get_texture()
	overlay.scale = Vector2(texel, texel)
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
	var sp := map.spawn_point(team)
	var src: Array = [Vector4(sp.x, sp.y, FOUNTAIN_VISION, map.brush_at(sp))]
	var rev: Array = []
	for u in world.units:
		if u.team != team or u.dead:
			continue
		var r: float = u.stats.get("vision", 0.0)
		if r <= 0.0:
			continue
		var v := Vector4(u.global_position.x, u.global_position.y, r, map.brush_at(u.global_position))
		src.append(v)
		if u.reveal:
			rev.append(v)
	sources[team] = src
	reveals[team] = rev


func _compute(team: int) -> void:
	var old: Dictionary = vis[team]
	var seen := {}
	var src: Array = sources[team]
	for u in world.units:
		if u.team == team:
			continue
		if u.is_structure or u is Dummy:
			seen[u.net_id] = true
			continue
		if u.dead:
			if old.has(u.net_id):
				seen[u.net_id] = true
			continue
		if u.flags & (Unit.F_REVEAL0 << team):
			seen[u.net_id] = true
			continue
		if u.flags & Unit.F_STEALTH and not _revealed(u, team):
			continue
		if _sees(src, u.global_position, u.radius, map.brush_at(u.global_position)):
			seen[u.net_id] = true
	vis[team] = seen


func _revealed(u: Unit, team: int) -> bool:
	for c in world.champions.values():
		if c.team == team and not c.dead and c.global_position.distance_to(u.global_position) < STEALTH_REVEAL:
			return true
	return _sees(reveals[team], u.global_position, u.radius, map.brush_at(u.global_position), true)


## Whether any source sees point `p` (padded by `pad`). Inside brush only sources in that same
## brush count; without fog of war everything outside brush is in sight (except for `strict`
## true-sight checks, which always need a source in range).
func _sees(src: Array, p: Vector2, pad: float, brush: int, strict := false) -> bool:
	if not dark and brush == 0 and not strict:
		return true
	for s: Vector4 in src:
		if brush > 0 and int(s.w) != brush:
			continue
		var sp := Vector2(s.x, s.y)
		if sp.distance_to(p) <= s.z + pad and map.sight_clear(sp, p):
			return true
	return false


## True if no wall blocks the straight line from a to b.
func los(a: Vector2, b: Vector2) -> bool:
	return map.sight_clear(a, b)


func sees(u: Unit, team: int) -> bool:
	return team > 1 or vis[team].has(u.net_id)


## Whether a point is inside `team`'s vision (projectiles, zones, effects).
func point_visible(p: Vector2, team: int) -> bool:
	if not enabled or team > 1:
		return true
	return _sees(sources[team], p, 0.0, map.brush_at(p))


## Whether `u` is standing in brush.
func in_brush(u: Unit) -> bool:
	return map.brush_at(u.global_position) > 0


# ---------------------------------------------------------------- visuals ---

func _process(delta: float) -> void:
	if not enabled or world == null:
		return
	var lt := world.local_team
	var reveal_all := world.ended
	if dark:
		_strength = move_toward(_strength, 0.0 if reveal_all else STRENGTH, delta * 0.8)
		overlay_mat.set_shader_parameter("strength", _strength)
		minimap_mat.set_shader_parameter("strength", _strength * 1.15)
		_update_mask(lt)
	var seen: Dictionary = vis[clampi(lt, 0, 1)]
	for u in world.units:
		var want := 1.0
		if u.team != lt and not reveal_all and lt <= 1 and not u.is_structure and not (u is Dummy):
			want = 1.0 if seen.has(u.net_id) else 0.0
		elif u.team == lt and not u.dead and not u.is_structure and map.brush_at(u.global_position) > 0:
			want = BRUSH_ALPHA
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
	var sp := map.spawn_point(clampi(team, 0, 1))
	arr.append(Vector4(sp.x, sp.y, FOUNTAIN_VISION, map.brush_at(sp)))
	for u in world.units:
		if u.team != team or u.dead:
			continue
		var r: float = u.stats.get("vision", 0.0)
		if r <= 0.0:
			continue
		var v := Vector4(u.global_position.x, u.global_position.y, r, map.brush_at(u.global_position))
		if u is Minion:
			minor.append(v)
		else:
			arr.append(v)
	arr.append_array(minor)
	var n := mini(arr.size(), MAX_SOURCES)
	arr.resize(MAX_SOURCES)
	mask_mat.set_shader_parameter("sources", arr)
	mask_mat.set_shader_parameter("source_count", n)
