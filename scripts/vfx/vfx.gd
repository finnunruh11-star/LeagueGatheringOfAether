class_name Vfx
extends RefCounted
## Visual-only helpers: pixel-art sprite-sheet effects from assets/vfx, particle
## bursts and glow textures. Nothing here affects gameplay.

const DIR := "res://assets/vfx/"
## name: [file, frame width, frame height, frames, fps, tintable]
const LIB := {
	"spark": ["impact1.png", 64, 64, 4, 22, true],
	"splat": ["impact2.png", 64, 64, 7, 18, true],
	"star": ["impact3.png", 64, 64, 5, 18, true],
	"twinkle": ["impact4.png", 64, 64, 5, 18, true],
	"burst": ["impact5.png", 128, 64, 6, 16, true],
	"claw": ["impact6.png", 128, 64, 7, 18, true],
	"streaks": ["impact7.png", 128, 64, 7, 18, true],
	"spark_red": ["impact1_color.png", 64, 64, 4, 22, false],
	"poison": ["impact2_color.png", 64, 64, 7, 16, false],
	"star_red": ["impact3_color.png", 64, 64, 5, 18, false],
	"twinkle_red": ["impact4_color.png", 64, 64, 5, 18, false],
	"fire": ["impact5_color.png", 128, 64, 6, 16, false],
	"claw_red": ["impact6_color.png", 128, 64, 7, 18, false],
	"streaks_red": ["impact7_color.png", 128, 64, 7, 18, false],
	"magic": ["warlock1.png", 128, 128, 8, 14, false],
	"wave": ["warlock2.png", 192, 128, 13, 22, false],
	"smoke": ["warlock3.png", 128, 128, 8, 14, false],
}
const SLASH_FRAMES := [9, 7, 9]
## Approximate hue of the 5 slash palettes: lime, red, violet, orange, cyan.
const SLASH_HUES := [0.2, 0.0, 0.78, 0.08, 0.53]

static var _frames := {}
static var _add_mat: CanvasItemMaterial
static var _fade: Gradient
static var _dot: Texture2D
static var _ring: Texture2D


static func has(effect: String) -> bool:
	return LIB.has(effect) or effect.begins_with("slash")


static func tintable(effect: String) -> bool:
	return LIB.has(effect) and LIB[effect][5]


static func _info(effect: String) -> Array:
	if LIB.has(effect):
		return LIB[effect]
	if effect.begins_with("slash") and effect.length() >= 9:
		var style := clampi(int(effect.substr(5, 1)), 1, 3)
		return ["%s.png" % effect, 128, 128, SLASH_FRAMES[style - 1], 26, false]
	return []


static func frames(effect: String) -> SpriteFrames:
	if _frames.has(effect):
		return _frames[effect]
	var info := _info(effect)
	var sf: SpriteFrames = null
	if not info.is_empty() and ResourceLoader.exists(DIR + str(info[0])):
		var tex: Texture2D = load(DIR + info[0])
		sf = SpriteFrames.new()
		sf.set_animation_loop("default", false)
		sf.set_animation_speed("default", info[4])
		var cols: int = maxi(1, tex.get_width() / info[1])
		for i in info[3]:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2((i % cols) * info[1], (i / cols) * info[2], info[1], info[2])
			sf.add_frame("default", at)
	_frames[effect] = sf
	return sf


## Plays a one-shot sprite effect. Directional art faces right; it is flipped
## so it never renders upside down.
static func play(parent: Node, effect: String, pos: Vector2, rot := 0.0, scale := 1.0, tint := Color.WHITE,
		additive := false, speed := 1.0) -> AnimatedSprite2D:
	var sf := frames(effect)
	if sf == null or parent == null:
		return null
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.position = pos
	s.rotation = rot
	var flip := absf(wrapf(rot, -PI, PI)) > PI * 0.5
	s.scale = Vector2(scale, -scale if flip else scale)
	s.modulate = tint
	s.speed_scale = speed
	if additive:
		s.material = add_material()
	parent.add_child(s)
	s.play("default")
	s.animation_finished.connect(s.queue_free)
	return s


## Picks a slash animation whose palette best matches a color.
static func slash_for(c: Color) -> String:
	var pal := 5
	if c.s > 0.22:
		var best := 99.0
		for i in 5:
			var d := absf(wrapf(c.h - SLASH_HUES[i], -0.5, 0.5))
			if d < best:
				best = d
				pal = i + 1
	return "slash%d_c%d" % [1 + randi() % 3, pal]


static func add_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## Shared opaque-to-transparent ramp for particles.
static func fade_ramp() -> Gradient:
	if _fade == null:
		_fade = Gradient.new()
		_fade.set_color(0, Color(1, 1, 1, 1))
		_fade.set_color(1, Color(1, 1, 1, 0))
	return _fade


## Soft round glow (white, fades to transparent).
static func glow() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot = t
	return _dot


## Soft ring (bright edge, transparent center) for shockwaves.
static func ring() -> Texture2D:
	if _ring == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 0.9, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		_ring = t
	return _ring


## One-shot burst of pixel-square particles.
static func particles(parent: Node, pos: Vector2, color: Color, amount := 12, speed := 240.0, life := 0.5,
		size := 4.0, gravity := Vector2.ZERO, direction := Vector2.UP, spread := 180.0, additive := false) -> CPUParticles2D:
	if parent == null:
		return null
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.damping_min = speed * 0.6
	p.damping_max = speed * 1.4
	p.gravity = gravity
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.2
	p.color = color
	p.color_ramp = fade_ramp()
	if additive:
		p.material = add_material()
	parent.add_child(p)
	p.emitting = true
	parent.get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p


## Additive glowing sprite that scales up and fades out (flashes, shockwaves).
static func flash(parent: Node, pos: Vector2, color: Color, radius: float, dur := 0.25, tex: Texture2D = null,
		grow := 1.25) -> Sprite2D:
	if parent == null:
		return null
	var s := Sprite2D.new()
	s.texture = tex if tex != null else glow()
	s.position = pos
	s.material = add_material()
	s.modulate = color
	var base := radius * 2.0 / s.texture.get_width()
	s.scale = Vector2.ONE * base * 0.6
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * base * grow, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(s, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(s.queue_free)
	return s
