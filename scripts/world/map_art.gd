class_name MapArt
extends Node2D
## Procedural pixel-art look for GameMap (no art assets). Small tileable
## textures are generated once (cached between matches). All static layers are
## rendered once into texel-resolution SubViewports (1 texel = PX world px) and
## shown as a few sprites, so the whole map costs ~1 draw call per tile.
## Only the small fountain effects animate.

const PX := 2.0  # world pixels per texel
const FACE := 40.0  # cliff front-face height (20 texels)
const PAD := 320.0  # baked out-of-bounds margin around the map
const TILE := 4096  # max render-target edge in texels
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache := {}

var map: GameMap
var rng := RandomNumberGenerator.new()
var tex := {}
var macro: ImageTexture
var paths: Array = []  # [polyline, half width]: lanes, base connectors, dummy patches
var bands: Array = []  # [polygons, texture key, modulate], drawn in order
var plazas: Array = []  # [team, rim, floor]
var cliffs: Array = []
var flat: Array = []  # [dest, src, modulate] ground clutter
var tall: Array = []  # bushes, boulders and trees, drawn above the cliffs


func build(m: GameMap) -> void:
	map = m
	rng.seed = hash(str(m.data.get("name", "")) + str(m.size))
	var key := m.ground.to_html() + m.lane_color.to_html() + m.wall_color.to_html()
	if not _cache.has(key):
		_cache[key] = _make_textures()
	tex = _cache[key]
	macro = _macro_tex()
	_make_shapes()
	_scatter()
	tall.sort_custom(func(a, b): return a[0].end.y < b[0].end.y)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_layer(self, _draw_far)
	_bake([_draw_ground, _draw_soft, _draw_paths, _draw_sprites.bind(flat), _draw_cliffs, _draw_cliff_shade, _draw_sprites.bind(tall)])
	for t in 2:
		var spin := FountainSpin.new()
		var sparks := FountainSparks.new()
		spin.color = Game.TEAM_COLORS[t]
		sparks.color = spin.color
		spin.radius = m.fountain_radius
		spin.position = m.spawns[t]
		sparks.position = m.spawns[t]
		add_child(spin)
		add_child(sparks)


func _layer(parent: Node, fn: Callable) -> ArtLayer:
	var n := ArtLayer.new()
	n.fn = fn
	parent.add_child(n)
	return n


## Renders the static layers once (UPDATE_ONCE) into render targets.
func _bake(fns: Array) -> void:
	var origin := -Vector2(PAD, PAD)
	var full := Vector2i(((map.size + Vector2(PAD, PAD) * 2.0) / PX).ceil())
	for ix in range(0, full.x, TILE):
		for iy in range(0, full.y, TILE):
			var at := origin + Vector2(ix, iy) * PX
			var vp := SubViewport.new()
			vp.size = Vector2i(mini(TILE, full.x - ix), mini(TILE, full.y - iy))
			vp.disable_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
			vp.canvas_item_default_texture_repeat = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_REPEAT_ENABLED
			add_child(vp)
			vp.canvas_transform = Transform2D(0.0, Vector2.ONE / PX, 0.0, -at / PX)
			for fn: Callable in fns:
				var l := _layer(vp, fn)
				if fn == _draw_soft or fn == _draw_cliff_shade:
					l.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
					l.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			var spr := Sprite2D.new()
			spr.texture = vp.get_texture()
			spr.centered = false
			spr.position = at
			spr.scale = Vector2(PX, PX)
			spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(spr)


# ---------------------------------------------------------------- shapes ---

func _make_shapes() -> void:
	var nexus := [null, null]
	for s in map.structures:
		if s.kind == "nexus":
			nexus[s.team] = s.pos
	for l in map.lanes:
		paths.append([l, 75.0])
	for t in 2:
		var sp: Vector2 = map.spawns[t]
		var hub: Vector2 = sp if nexus[t] == null else nexus[t]
		for l in map.lanes:
			var e: Vector2 = l[0] if t == 0 else l[l.size() - 1]
			if hub.distance_to(e) > 4.0:
				paths.append([PackedVector2Array([hub, e]), 62.0])
		var parts: Array = [_circle(sp, clampf(map.fountain_radius * 0.56, 90.0, 160.0), 48)]
		if nexus[t] != null:
			parts.append(_circle(hub, 108.0, 40))
			parts.append_array(_offset_line(PackedVector2Array([sp, hub]), 74.0))
		for p in _union(parts):
			plazas.append([t, _grow(p, 9.0), p])
	var worn := []
	var rim := []
	var fill := []
	for p in paths:
		worn.append_array(_offset_line(p[0], p[1] + 12.0))
		rim.append_array(_offset_line(p[0], p[1]))
		fill.append_array(_offset_line(p[0], p[1] - 6.0))
	for d in map.dummies:  # just a subtle trampled patch, so it doesn't read as an obstacle
		worn.append_array(_offset_line(PackedVector2Array([d, d + Vector2(0.5, 0)]), 40.0))
	bands = [[worn, "grass", Color(1.16, 1.08, 0.78)], [rim, "dirt", Color(0.78, 0.76, 0.74)], [fill, "dirt", Color.WHITE]]
	for r in map.walls:
		cliffs.append(_cliff(r))


## Cliff = jagged outline (always inside the collision rect) split along a
## jagged lip into a lit top face and a darker front face along the bottom.
func _cliff(r: Rect2) -> Dictionary:
	var outline := _rock_outline(r)
	var inner := _grow(outline, -2.0)
	var cut := r.end.y - minf(FACE, r.size.y * 0.4)
	var lip := PackedVector2Array()
	var x := r.position.x - 20.0
	while x < r.end.x + 36.0:
		lip.append(Vector2(x, cut + roundf(rng.randf_range(-2.0, 2.0)) * 2.0))
		x += 16.0
	var below := lip.duplicate()
	below.append_array(PackedVector2Array([Vector2(x, r.end.y + 20.0), Vector2(r.position.x - 20.0, r.end.y + 20.0)]))
	var above := lip.duplicate()
	above.reverse()
	above.append_array(PackedVector2Array([Vector2(r.position.x - 20.0, r.position.y - 20.0), Vector2(x, r.position.y - 20.0)]))
	return {"outline": outline, "rect": r, "cut": cut, "bottom": r.end.y,
		"face": Geometry2D.intersect_polygons(inner, below),
		"top": Geometry2D.intersect_polygons(inner, above),
		"lip": Geometry2D.intersect_polyline_with_polygon(lip, inner)}


func _rock_outline(r: Rect2) -> PackedVector2Array:
	var rc := minf(14.0, minf(r.size.x, r.size.y) * 0.3)
	var jit := minf(5.0, minf(r.size.x, r.size.y) * 0.12)
	var a := r.position + Vector2(rc, rc)
	var b := r.end - Vector2(rc, rc)
	var ends := [Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]
	var pts := PackedVector2Array()
	for k in 4:
		var n := Vector2.from_angle(-PI / 2.0 + k * PI / 2.0)
		var p0: Vector2 = ends[(k + 3) % 4] + n * rc
		var p1: Vector2 = ends[k] + n * rc
		var steps := maxi(1, int(p0.distance_to(p1) / 22.0))
		for i in steps:
			pts.append(p0.lerp(p1, float(i) / steps) - (n * rng.randf_range(0.0, jit) if i > 0 else Vector2.ZERO))
		for i in 5:
			pts.append(ends[k] + Vector2.from_angle(-PI / 2.0 + (k + i / 5.0) * PI / 2.0) * rc)
	return pts


static func _circle(c: Vector2, r: float, n: int, rot := 0.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in n:
		p.append(c + Vector2.from_angle(rot + TAU * i / n) * r)
	return p


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _offset_line(line: PackedVector2Array, d: float) -> Array:
	return Geometry2D.offset_polyline(line, d, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)


static func _grow(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var g := Geometry2D.offset_polygon(p, d, Geometry2D.JOIN_ROUND)
	return g[0] if g.size() > 0 else p


static func _union(parts: Array) -> Array:
	var out: Array = []
	for p in parts:
		var merged := false
		for i in out.size():
			var m := Geometry2D.merge_polygons(out[i], p)
			if m.size() == 1:
				out[i] = m[0]
				merged = true
				break
		if not merged:
			out.append(p)
	return out


# ------------------------------------------------------------ decorations ---

func _scatter() -> void:
	var s := map.size
	var step := 54.0
	for gx in int(s.x / step):
		for gy in int(s.y / step):
			var p := Vector2(gx + rng.randf(), gy + rng.randf()) * step
			var roll := rng.randf()
			if roll < 0.36 and _free(p, 10.0):
				_add(flat, "pebble" if roll < 0.025 else "tuft", p)
	for k in int(s.x * s.y / 260000.0):
		var c := Vector2(rng.randf_range(0.0, s.x), rng.randf_range(0.0, s.y))
		if not _free(c, 40.0):
			continue
		var kind := "flower%d" % (rng.randi() % 4)
		for j in rng.randi_range(3, 7):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 44.0)
			if _free(p, 10.0):
				_add(flat, kind, p)
	for pth in paths:  # grass creeping along the path edges
		var line: PackedVector2Array = pth[0]
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var seg := a.distance_to(b)
			var n := (b - a).normalized().orthogonal()
			var d := 0.0
			while d < seg:
				for side in [-1.0, 1.0]:
					var p: Vector2 = a.lerp(b, d / seg) + n * side * (pth[1] + rng.randf_range(6.0, 16.0))
					if rng.randf() < 0.5 and _free(p, 2.0):
						_add(flat, "tuft", p)
				d += rng.randf_range(16.0, 30.0)
	for wi in map.walls.size():  # bushes and boulders hugging the cliff bases, a few on top
		var r: Rect2 = map.walls[wi]
		var x := r.position.x + rng.randf_range(4.0, 30.0)
		while x < r.end.x - 4.0:
			_dress(Vector2(x, r.end.y + rng.randf_range(3.0, 9.0)), 0.5)
			x += rng.randf_range(24.0, 52.0)
		for side in [r.position.x - 5.0, r.end.x + 5.0]:
			var y := r.position.y + rng.randf_range(30.0, 60.0)
			while y < r.end.y:
				_dress(Vector2(side + rng.randf_range(-3.0, 3.0), y), 0.35)
				y += rng.randf_range(30.0, 60.0)
		var cut: float = cliffs[wi].cut
		if cut - r.position.y > 60.0 and r.size.x > 80.0:
			for k in int(r.size.x * (cut - r.position.y) / 45000.0):
				var p := Vector2(rng.randf_range(r.position.x + 24.0, r.end.x - 24.0), rng.randf_range(r.position.y + 34.0, cut - 12.0))
				_add(tall, "rock" if rng.randf() < 0.65 else "bush", p)
	_plant_forest()


func _dress(p: Vector2, chance: float) -> void:
	if rng.randf() < chance and _free(p, 14.0, false):
		_add(tall, "bush" if rng.randf() < 0.6 else "rock", p)


## Rows of trees just outside the playable area, fading into the dark.
func _plant_forest() -> void:
	var s := map.size
	for row in 5:
		var d := row * 48.0
		var shade := 0.95 - row * 0.13
		var x := -330.0 + rng.randf_range(0.0, 30.0)
		while x < s.x + 330.0:
			_add(tall, "tree", Vector2(x, 14.0 - d + rng.randf_range(-14.0, 8.0)), _tree_tint(shade))
			_add(tall, "tree", Vector2(x + rng.randf_range(-24.0, 24.0), s.y + 52.0 + d + rng.randf_range(-8.0, 14.0)), _tree_tint(shade))
			x += rng.randf_range(40.0, 66.0)
		var y := 30.0 + rng.randf_range(0.0, 30.0)
		while y < s.y + 40.0:
			_add(tall, "tree", Vector2(-18.0 - d + rng.randf_range(-14.0, 8.0), y), _tree_tint(shade))
			_add(tall, "tree", Vector2(s.x + 18.0 + d + rng.randf_range(-8.0, 14.0), y + rng.randf_range(-24.0, 24.0)), _tree_tint(shade))
			y += rng.randf_range(40.0, 66.0)


func _tree_tint(shade: float) -> Color:
	var k := shade * rng.randf_range(0.9, 1.06)
	return Color(k, k, k * 1.05)


func _free(p: Vector2, m: float, walls := true) -> bool:
	if p.x < m or p.y < m or p.x > map.size.x - m or p.y > map.size.y - m:
		return false
	if walls:
		for r in map.walls:
			if r.grow(m).has_point(p):
				return false
	for t in 2:
		if p.distance_to(map.spawns[t]) < map.fountain_radius + m:
			return false
	for st in map.structures:
		if p.distance_to(st.pos) < (120.0 if st.kind == "nexus" else 60.0) + m:
			return false
	for d in map.dummies:
		if p.distance_to(d) < 44.0 + m:
			return false
	for pth in paths:
		var line: PackedVector2Array = pth[0]
		for i in line.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])) < pth[1] + m:
				return false
	return true


## Sprites are anchored at their bottom centre ("foot"), snapped to the texel grid.
func _add(store: Array, kind: String, foot: Vector2, mod := Color.WHITE) -> void:
	var opts: Array = tex.spr[kind]
	var src: Rect2 = opts[rng.randi() % opts.size()]
	var sz := src.size * PX
	var dest := Rect2((foot - Vector2(sz.x * 0.5, sz.y)).snapped(Vector2(PX, PX)), sz)
	if rng.randf() < 0.5:
		dest.size.x = -dest.size.x  # negative width = horizontal flip
	store.append([dest, src, mod])


# --------------------------------------------------------------- drawing ---

func _tiled(c: CanvasItem, poly: PackedVector2Array, t: Texture2D, col := Color.WHITE) -> void:
	var k := 1.0 / (t.get_width() * PX)
	c.draw_colored_polygon(poly, col, Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO) * poly, t)


## Live (unbaked) dark ground beyond the baked margin, for zoomed-out views.
func _draw_far(c: CanvasItem) -> void:
	var s := map.size
	_tiled(c, _rect_poly(Rect2(-4096, -4096, s.x + 8192, s.y + 8192)), tex.grass, Color(0.225, 0.252, 0.27))


func _draw_ground(c: CanvasItem) -> void:
	var s := map.size
	_tiled(c, _rect_poly(Rect2(-PAD - 64.0, -PAD - 64.0, s.x + PAD * 2.0 + 128.0, s.y + PAD * 2.0 + 128.0)), tex.grass, Color(0.5, 0.56, 0.6))
	_tiled(c, _rect_poly(Rect2(Vector2.ZERO, s)), tex.grass)


func _draw_soft(c: CanvasItem) -> void:
	var s := map.size
	c.draw_texture_rect(macro, Rect2(Vector2.ZERO, s), false)
	var corners := [Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]
	var out := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var clear := Color(0, 0, 0, 0)
	var rim := Color(0, 0, 0, 0.3)
	var far := Color(0, 0, 0, 0.55)
	var o := 300.0
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var inward: Vector2 = (b - a).normalized().orthogonal() * 60.0
		c.draw_polygon(PackedVector2Array([a, b, b + inward, a + inward]), PackedColorArray([rim, rim, clear, clear]))
		c.draw_polygon(PackedVector2Array([a, b, b + out[(k + 1) % 4] * o, a + out[k] * o]), PackedColorArray([clear, clear, far, far]))
	var big := PAD + 256.0
	c.draw_rect(Rect2(-big, -big, s.x + 2.0 * big, big - o), far)
	c.draw_rect(Rect2(-big, s.y + o, s.x + 2.0 * big, big - o), far)
	c.draw_rect(Rect2(-big, -o, big - o, s.y + 2.0 * o), far)
	c.draw_rect(Rect2(s.x + o, -o, big - o, s.y + 2.0 * o), far)


func _draw_paths(c: CanvasItem) -> void:
	for b in bands:
		for p in b[0]:
			_tiled(c, p, tex[b[1]], b[2])
	var edge := Color(0.17, 0.16, 0.17)
	var curb := Color(0.62, 0.6, 0.56)
	for pl in plazas:
		var tc: Color = Game.TEAM_COLORS[pl[0]]
		c.draw_colored_polygon(pl[1], edge)
		_tiled(c, pl[2], tex.stone, Color(0.95, 0.95, 0.95).lerp(tc, 0.16))
		var loop: PackedVector2Array = pl[2].duplicate()
		loop.append(loop[0])
		c.draw_polyline(loop, curb, 2.0)
	for st in map.structures:
		var tc: Color = Game.TEAM_COLORS[st.team]
		if st.kind == "nexus":
			c.draw_arc(st.pos, 96.0, 0.0, TAU, 64, Color(tc, 0.5), 4.0)
			for i in 6:
				var q: Vector2 = st.pos + Vector2.from_angle(TAU * i / 6.0) * 96.0
				c.draw_colored_polygon(_circle(q, 8.0, 4), Color(tc.lightened(0.35), 0.8))
		else:
			c.draw_colored_polygon(_circle(st.pos, 57.0, 8, PI / 8.0), edge)
			_tiled(c, _circle(st.pos, 53.0, 8, PI / 8.0), tex.stone, Color(0.92, 0.92, 0.92).lerp(tc, 0.12))
	for t in 2:
		var tc: Color = Game.TEAM_COLORS[t]
		var sp: Vector2 = map.spawns[t]
		var rad := map.fountain_radius
		c.draw_circle(sp, rad, Color(tc, 0.07))
		c.draw_arc(sp, rad, 0.0, TAU, 128, Color(tc.darkened(0.35), 0.75), 6.0)
		c.draw_arc(sp, rad - 14.0, 0.0, TAU, 128, Color(tc, 0.3), 2.0)
		c.draw_colored_polygon(_circle(sp, 54.0, 8, PI / 8.0), edge)
		_tiled(c, _circle(sp, 50.0, 8, PI / 8.0), tex.stone, Color(1.1, 1.1, 1.1))
		c.draw_colored_polygon(_circle(sp, 38.0, 8, PI / 8.0), edge)
		c.draw_colored_polygon(_circle(sp, 35.0, 8, PI / 8.0), tc.darkened(0.55))


func _draw_cliffs(c: CanvasItem) -> void:
	for w in cliffs:
		var r: Rect2 = w.rect.grow(-3.0)
		c.draw_rect(Rect2(r.position + Vector2(8, 10), r.size), Color(0, 0, 0, 0.2))
		c.draw_rect(Rect2(r.position + Vector2(16, 20), r.size), Color(0, 0, 0, 0.13))
	var top_col := map.wall_color.lightened(0.14)
	var edge := _tone(map.wall_color, -0.7)
	var rim := _tone(top_col, 0.22)
	var lip := _tone(top_col, 0.42)
	for w in cliffs:
		c.draw_colored_polygon(w.outline, edge)
		var h: float = w.bottom - w.cut
		for p in w.face:
			var uv := PackedVector2Array()
			for v in p:
				uv.append(Vector2(v.x / (64.0 * PX), clampf((v.y - w.cut) / h, 0.0, 1.0)))
			c.draw_colored_polygon(p, Color.WHITE, uv, tex.face)
		for p in w.top:
			_tiled(c, p, tex.rock)
			var loop: PackedVector2Array = p.duplicate()
			loop.append(loop[0])
			c.draw_polyline(loop, rim, 2.0)
		for l in w.lip:
			c.draw_polyline(l, lip, 2.0)


## Soft light/dark patches over the cliff tops (breaks up the texture tiling).
func _draw_cliff_shade(c: CanvasItem) -> void:
	var k := macro.get_size() / map.size
	for w in cliffs:
		var r: Rect2 = w.rect
		var top := Rect2(r.position, Vector2(r.size.x, w.cut - r.position.y))
		c.draw_texture_rect_region(macro, top, Rect2(top.position * k, top.size * k), Color(1, 1, 1, 1.6))


func _draw_sprites(c: CanvasItem, list: Array) -> void:
	var atlas: Texture2D = tex.atlas
	for s in list:
		c.draw_texture_rect_region(atlas, s[0], s[1], s[2])


# -------------------------------------------------------------- textures ---

## Pixel-art style shading: light tones drift warm/yellow, dark tones cool/blue.
static func _tone(c: Color, k: float) -> Color:
	return c.lerp(Color(1.0, 0.96, 0.74), k) if k >= 0.0 else c.lerp(Color(0.03, 0.06, 0.14), -k)


static func _at(s: int, x: int, y: int) -> int:
	return posmod(y, s) * s + posmod(x, s)


static func _dither(x: int, y: int) -> float:
	return (BAYER[(y & 3) * 4 + (x & 3)] - 7.5) / 16.0


func _make_textures() -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = 7331
	var d := {
		"grass": _grass_tex(r, map.ground),
		"dirt": _dirt_tex(r, map.lane_color),
		"rock": _rock_tex(r, map.wall_color.lightened(0.14)),
		"face": _face_tex(r, map.wall_color),
		"stone": _stone_tex(r, Color(0.5, 0.49, 0.47)),
	}
	d.merge(_atlas(r))
	return d


## Seamless value noise: random cells blown up by a cubic resize of a 3x3
## repeat, keeping only the middle copy (C++ does the heavy lifting).
func _noise(r: RandomNumberGenerator, w: int, h: int, cx: int, cy: int) -> PackedByteArray:
	var src := PackedByteArray()
	src.resize(cx * cy)
	for i in src.size():
		src[i] = r.randi() & 255
	var cell := Image.create_from_data(cx, cy, false, Image.FORMAT_L8, src)
	var big := Image.create_empty(cx * 3, cy * 3, false, Image.FORMAT_L8)
	for i in 3:
		for j in 3:
			big.blit_rect(cell, Rect2i(0, 0, cx, cy), Vector2i(i * cx, j * cy))
	big.resize(w * 3, h * 3, Image.INTERPOLATE_CUBIC)
	return big.get_region(Rect2i(w, h, w, h)).get_data()


## Palette-index buffer -> texture.
func _image(idx: PackedByteArray, w: int, h: int, pal: Array) -> ImageTexture:
	var lut := PackedInt32Array()
	for c: Color in pal:
		var v := c.r8 | (c.g8 << 8) | (c.b8 << 16) | (c.a8 << 24)
		lut.append(v - 0x100000000 if v >= 0x80000000 else v)
	var px := PackedInt32Array()
	px.resize(idx.size())
	for i in idx.size():
		px[i] = lut[idx[i]]
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px.to_byte_array()))


func _grass_tex(r: RandomNumberGenerator, g: Color) -> ImageTexture:
	var s := 128
	var a := _noise(r, s, s, 4, 4)
	var b := _noise(r, s, s, 16, 16)
	var idx := PackedByteArray()
	idx.resize(s * s)
	for y in s:
		for x in s:
			var i := y * s + x
			var v: float = (a[i] * 0.6 + b[i] * 0.4) / 255.0 + _dither(x, y) * 0.13
			idx[i] = 1 if v < 0.4 else (2 if v < 0.6 else 3)
	for k in 320:  # blades: bright tip, lit stem, dark root
		var x := r.randi() % s
		var y := r.randi() % s
		idx[_at(s, x, y)] = 4 if r.randf() < 0.45 else 3
		idx[_at(s, x, y + 1)] = 3
		idx[_at(s, x, y + 2)] = 1
	for k in 180:
		idx[_at(s, r.randi() % s, r.randi() % s)] = 0
	return _image(idx, s, s, [_tone(g, -0.24), _tone(g, -0.1), g, _tone(g, 0.08), _tone(g, 0.18)])


func _dirt_tex(r: RandomNumberGenerator, c: Color) -> ImageTexture:
	var s := 128
	var a := _noise(r, s, s, 6, 6)
	var b := _noise(r, s, s, 32, 32)
	var idx := PackedByteArray()
	idx.resize(s * s)
	for y in s:
		for x in s:
			var i := y * s + x
			var v: float = (a[i] * 0.5 + b[i] * 0.5) / 255.0 + _dither(x, y) * 0.16
			idx[i] = 1 if v < 0.38 else (2 if v < 0.62 else 3)
	for k in 110:  # pebbles casting a small shadow
		var x := r.randi() % s
		var y := r.randi() % s
		for j in r.randi_range(1, 2):
			idx[_at(s, x + j, y)] = 4
			idx[_at(s, x + j, y + 1)] = 0
	for k in 240:
		idx[_at(s, r.randi() % s, r.randi() % s)] = 1 if r.randf() < 0.6 else 0
	return _image(idx, s, s, [_tone(c, -0.38), _tone(c, -0.15), c, _tone(c, 0.1), _tone(c, 0.24)])


## Embossed noise (lit from the top-left) plus short cracks.
func _rock_tex(r: RandomNumberGenerator, c: Color) -> ImageTexture:
	var s := 128
	var a := _noise(r, s, s, 6, 6)
	var b := _noise(r, s, s, 24, 24)
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for i in s * s:
		hgt[i] = a[i] * 0.6 + b[i] * 0.4
	var idx := PackedByteArray()
	idx.resize(s * s)
	for y in s:
		for x in s:
			var i := y * s + x
			var lit := (hgt[_at(s, x - 1, y - 1)] - hgt[_at(s, x + 1, y + 1)]) / 38.0 + _dither(x, y) * 0.7
			var base := 2 + (1 if hgt[i] > 170.0 else (-1 if hgt[i] < 85.0 else 0))
			idx[i] = clampi(base + roundi(lit), 1, 4)
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for k in 7:
		var p := Vector2i(r.randi() % s, r.randi() % s)
		var dir: Vector2i = dirs[r.randi() % dirs.size()]
		for j in r.randi_range(4, 9):
			idx[_at(s, p.x, p.y)] = 0
			var hi := _at(s, p.x + 1, p.y + 1)
			if idx[hi] != 0:
				idx[hi] = 4
			p += dir
			if r.randf() < 0.4:
				p += Vector2i(r.randi_range(-1, 1), r.randi_range(-1, 1))
	return _image(idx, s, s, [_tone(c, -0.5), _tone(c, -0.2), c, _tone(c, 0.12), _tone(c, 0.26)])


## 64x20 strip for the cliff front faces: streaky rock lit from the left,
## darkening towards the foot, with a bright lip and a few cracks.
func _face_tex(r: RandomNumberGenerator, c: Color) -> ImageTexture:
	var w := 64
	var h := 20
	var a := _noise(r, w, h, 16, 2)
	var b := _noise(r, w, h, 32, 5)
	var idx := PackedByteArray()
	idx.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			var j := y * w + (x + 1) % w
			var n := a[i] * 0.65 + b[i] * 0.35
			var lit := (n - a[j] * 0.65 - b[j] * 0.35) / 22.0
			var v := 2.9 - 2.6 * y / h + (n - 128.0) / 110.0 + lit + _dither(x, y) * 0.6
			idx[i] = clampi(roundi(v), 0, 3)
	for x in w:
		idx[x] = 4 if idx[x] >= 2 else 3
		idx[(h - 1) * w + x] = 0
	for k in 8:
		var x := r.randi() % w
		var y0 := r.randi_range(2, 7)
		for y in range(y0, mini(h - 2, y0 + r.randi_range(3, 8))):
			idx[y * w + x] = 0
	return _image(idx, w, h, [_tone(c, -0.62), _tone(c, -0.42), _tone(c, -0.22), _tone(c, -0.02), _tone(c, 0.25)])


## Flagstones in running bond with bevelled edges.
func _stone_tex(r: RandomNumberGenerator, c: Color) -> ImageTexture:
	var s := 96
	var rh := 12
	var n := _noise(r, s, s, 24, 24)
	var idx := PackedByteArray()
	idx.resize(s * s)
	var lx := PackedInt32Array()
	var wd := PackedInt32Array()
	var tn := PackedInt32Array()
	lx.resize(s)
	wd.resize(s)
	tn.resize(s)
	for y0 in range(0, s, rh):
		var start := r.randi() % s
		var x := 0
		while x < s:
			var w := r.randi_range(12, 24)
			if s - x - w < 10:
				w = s - x
			var t: int = [1, 2, 2, 3][r.randi() % 4]
			for j in w:
				var xx := (start + x + j) % s
				lx[xx] = j
				wd[xx] = w
				tn[xx] = t
			x += w
		for ly in rh:
			for xx in s:
				var i := (y0 + ly) * s + xx
				var t := tn[xx]
				var v := t
				if ly == 0 or lx[xx] == 0:
					v = 0
				elif ly == 1 or lx[xx] == 1:
					v = mini(t + 1, 4)
				elif ly == rh - 1 or lx[xx] == wd[xx] - 1:
					v = maxi(t - 1, 1)
				elif n[i] > 190:
					v = mini(t + 1, 4)
				elif n[i] < 60:
					v = maxi(t - 1, 1)
				idx[i] = v
	return _image(idx, s, s, [_tone(c, -0.5), _tone(c, -0.2), c, _tone(c, 0.12), _tone(c, 0.26)])


## Large soft light/dark patches stretched over the whole map (breaks up tiling).
func _macro_tex() -> ImageTexture:
	var w := int(map.size.x / 32.0) + 1
	var h := int(map.size.y / 32.0) + 1
	var n := _noise(rng, w, h, maxi(2, int(map.size.x / 450.0)), maxi(2, int(map.size.y / 450.0)))
	var out := PackedByteArray()
	out.resize(w * h * 4)
	for i in w * h:
		var v := n[i] / 255.0
		var dark := v < 0.5
		out[i * 4] = 8 if dark else 230
		out[i * 4 + 1] = 16 if dark else 240
		out[i * 4 + 2] = 30 if dark else 140
		out[i * 4 + 3] = int(clampf((0.5 - v) * 0.42 if dark else (v - 0.56) * 0.3, 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out))


# ---------------------------------------------------------- sprite atlas ---

func _atlas(r: RandomNumberGenerator) -> Dictionary:
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	var spr := {}
	var cur := [1, 1, 0]
	var g := map.ground
	var leaf := [_tone(g, -0.68), _tone(g, -0.34), _tone(g, -0.1), _tone(g, 0.1), _tone(g, 0.26)]
	var bush := [_tone(g, -0.62), _tone(g, -0.22), _tone(g, 0.04), _tone(g, 0.2), _tone(g, 0.36)]
	var wc := map.wall_color.lightened(0.06)
	var stone := [_tone(wc, -0.62), _tone(wc, -0.28), wc, _tone(wc, 0.14), _tone(wc, 0.28)]
	var pc := map.wall_color.lerp(map.lane_color, 0.4)
	var pebble := [_tone(pc, -0.45), _tone(pc, -0.15), pc, _tone(pc, 0.15)]
	for sz in [36, 36, 30]:
		_canopy(img, _slot(spr, "tree", cur, sz, sz), sz, sz, leaf, r, r.randi_range(6, 8), 0.5, 0.42)
	for i in 2:
		_canopy(img, _slot(spr, "bush", cur, 14, 13), 14, 13, bush, r, 3, 0.4, 0.62)
	for i in 2:
		_blob(img, _slot(spr, "rock", cur, 12, 10), 12, 10, stone, r)
	for i in 3:
		_tuft(img, _slot(spr, "tuft", cur, 7, 5), 7, 5, [_tone(g, -0.25), _tone(g, 0.14), _tone(g, 0.32)], r)
	var petals := [Color(0.86, 0.85, 0.8), Color(0.95, 0.78, 0.3), Color(0.9, 0.52, 0.64), Color(0.58, 0.62, 0.95)]
	for i in petals.size():
		_flowers(img, _slot(spr, "flower%d" % i, cur, 8, 8), petals[i], _tone(g, 0.12), r)
	for i in 2:
		_pebble(img, _slot(spr, "pebble", cur, 5 + i, 4), 5 + i, 4, pebble)
	return {"atlas": ImageTexture.create_from_image(img), "spr": spr}


func _slot(spr: Dictionary, kind: String, cur: Array, w: int, h: int) -> Vector2i:
	if cur[0] + w + 1 > 128:
		cur[0] = 1
		cur[1] += cur[2] + 2
		cur[2] = 0
	var o := Vector2i(cur[0], cur[1])
	cur[0] += w + 2
	cur[2] = maxi(cur[2], h)
	if not spr.has(kind):
		spr[kind] = []
	spr[kind].append(Rect2(o, Vector2(w, h)))
	return o


static func _shadow(img: Image, o: Vector2i, w: int, h: int, sh: int) -> void:
	var c := Vector2((w - 1) * 0.5, h - sh - 1.0)
	for y in range(h - sh * 2 - 1, h):
		for x in w:
			var q := Vector2((x - c.x) / (w * 0.43), (y - c.y) / (sh + 1.0))
			if q.length_squared() <= 1.0:
				img.set_pixel(o.x + x, o.y + y, Color(0, 0, 0, 0.3))


static func _paint(img: Image, o: Vector2i, tone: Dictionary, pal: Array) -> void:
	for p: Vector2i in tone:
		var edge := not (tone.has(p + Vector2i.LEFT) and tone.has(p + Vector2i.RIGHT) and tone.has(p + Vector2i.UP) and tone.has(p + Vector2i.DOWN))
		img.set_pixel(o.x + p.x, o.y + p.y, pal[0] if edge else pal[tone[p]])


## Foliage seen from above: a cluster of shaded leaf balls (back ones first,
## a big one on top) with dark seams, outline and contact shadow.
func _canopy(img: Image, o: Vector2i, w: int, h: int, pal: Array, r: RandomNumberGenerator, n: int, spread: float, size: float) -> void:
	var sh := maxi(3, int(h * 0.14))
	var bh := h - sh
	_shadow(img, o, w, h, sh)
	var c := Vector2(w - 1, bh - 1) * 0.5
	var rv := Vector2(w, bh) * 0.5
	var balls := []
	var ph := r.randf() * TAU
	for k in n:
		var ang := ph + TAU * k / n + r.randf_range(-0.3, 0.3)
		balls.append([c + Vector2.from_angle(ang) * rv * spread * r.randf_range(0.8, 1.0), minf(rv.x, rv.y) * size * r.randf_range(0.85, 1.1)])
	balls.sort_custom(func(a, b): return a[0].y < b[0].y)
	balls.append([c + Vector2(-0.1, -0.15) * rv, minf(rv.x, rv.y) * size * 1.15])
	var tone := {}
	for bl in balls:
		var bc: Vector2 = bl[0]
		var br: float = bl[1]
		for y in range(maxi(0, floori(bc.y - br)), mini(bh, ceili(bc.y + br) + 1)):
			for x in range(maxi(0, floori(bc.x - br)), mini(w, ceili(bc.x + br) + 1)):
				var dq := (Vector2(x, y) - bc) / br
				var d2 := dq.length_squared()
				if d2 > 1.0:
					continue
				var key := Vector2i(x, y)
				var l := -(dq.x * 0.6 + dq.y * 0.8) + r.randf_range(-0.15, 0.15)
				var t := 1 if l < -0.45 else (2 if l < 0.1 else (3 if l < 0.55 else 4))
				tone[key] = 1 if d2 > 0.78 and tone.has(key) else t
	_paint(img, o, tone, pal)


## Lumpy boulder lit from the top-left.
func _blob(img: Image, o: Vector2i, w: int, h: int, pal: Array, r: RandomNumberGenerator) -> void:
	var sh := 2
	var bh := h - sh
	_shadow(img, o, w, h, sh)
	var c := Vector2(w - 1, bh - 1) * 0.5
	var rv := Vector2(w, bh) * 0.5
	var ph := r.randf() * TAU
	var tone := {}
	for y in bh:
		for x in w:
			var q := Vector2((x - c.x) / rv.x, (y - c.y) / rv.y)
			if q.length() <= 1.0 - 0.1 * (0.5 + 0.5 * sin(q.angle() * 5.0 + ph)):
				var l := -(q.x * 0.55 + q.y * 0.8) + r.randf_range(-0.15, 0.15)
				tone[Vector2i(x, y)] = 1 if l < -0.3 else (2 if l < 0.25 else (3 if l < 0.65 else 4))
	_paint(img, o, tone, pal)


func _tuft(img: Image, o: Vector2i, w: int, h: int, pal: Array, r: RandomNumberGenerator) -> void:
	var x := r.randi_range(0, 1)
	while x < w:
		var bh := r.randi_range(2, h)
		var lean := r.randi_range(-1, 1)
		for j in bh:
			var px := clampi(x + (lean if j >= 2 else 0), 0, w - 1)
			img.set_pixel(o.x + px, o.y + h - 1 - j, pal[2] if j == bh - 1 else (pal[1] if j > 0 else pal[0]))
		x += r.randi_range(1, 2)


## A small patch of round 2x2 blossoms with leaves.
func _flowers(img: Image, o: Vector2i, petal: Color, leaf: Color, r: RandomNumberGenerator) -> void:
	for p: Vector2i in [Vector2i(0, 1), Vector2i(3, 0), Vector2i(6, 2), Vector2i(2, 4), Vector2i(5, 5)]:
		if r.randf() < 0.3:
			continue
		var q := o + p
		img.set_pixel(q.x, q.y + 2, leaf)
		img.set_pixel(q.x + 1, q.y + 2, leaf.darkened(0.3))
		img.set_pixel(q.x, q.y, petal.lightened(0.3))
		img.set_pixel(q.x + 1, q.y, petal)
		img.set_pixel(q.x, q.y + 1, petal)
		img.set_pixel(q.x + 1, q.y + 1, petal.darkened(0.3))


func _pebble(img: Image, o: Vector2i, w: int, h: int, pal: Array) -> void:
	for y in h:
		for x in w:
			var q := Vector2((x - (w - 1) * 0.5) / (w * 0.5), (y - (h - 1) * 0.5) / (h * 0.5))
			if q.length() <= 1.0:
				img.set_pixel(o.x + x, o.y + y, pal[3] if q.y < -0.2 else (pal[2] if q.y < 0.4 else pal[1]))


# ------------------------------------------------------------ node types ---

class ArtLayer extends Node2D:
	var fn: Callable

	func _draw() -> void:
		fn.call(self)


## Rotating rune dashes on the healing boundary plus a pulsing core glow,
## animated via rotation/modulate only, so the drawing stays cached.
class FountainSpin extends Node2D:
	var color := Color.WHITE
	var radius := 250.0
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		rotation = t * 0.15
		modulate.a = 0.75 + 0.25 * sin(t * 2.4)

	func _draw() -> void:
		var light := color.lightened(0.45)
		draw_circle(Vector2.ZERO, 64.0, Color(color, 0.07))
		draw_circle(Vector2.ZERO, 46.0, Color(color, 0.12))
		draw_circle(Vector2.ZERO, 30.0, Color(light, 0.3))
		draw_circle(Vector2.ZERO, 15.0, Color(light.lightened(0.5), 0.6))
		var dash := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			dash.append(Vector2.from_angle(a) * (radius - 7.0))
			dash.append(Vector2.from_angle(a + 0.1) * (radius - 7.0))
		draw_multiline(dash, Color(light, 0.6), 4.0)


## Sparks rising from the fountain: the only per-frame redraw (a few rects).
class FountainSparks extends Node2D:
	var color := Color.WHITE
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		var o := get_global_transform_with_canvas().origin
		var vs := get_viewport_rect().size
		if o.x > -100.0 and o.y > -100.0 and o.x < vs.x + 100.0 and o.y < vs.y + 100.0:
			queue_redraw()

	func _draw() -> void:
		var light := color.lightened(0.6)
		for i in 10:
			var ph := fmod(t * 0.4 + i * 0.37, 1.0)
			var p := Vector2.from_angle(i * 2.4) * (10.0 + 24.0 * fmod(i * 0.618, 1.0)) + Vector2(0, -80.0 * ph)
			draw_rect(Rect2((p - Vector2(2, 2)).round(), Vector2(4, 4)), Color(light, sin(ph * PI) * 0.8))
