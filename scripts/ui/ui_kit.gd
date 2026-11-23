class_name UiKit
extends RefCounted
## Tiny helpers for building UI in code.

static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.default_font_size = 18
	return _theme


static func row(parent: Node) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	return h


static func label(parent: Node, text: String, min_w := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(min_w, 0)
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func placeholder(def: Dictionary) -> Texture2D:
	if def.get("portrait") != null:
		return def.portrait
	if def.textures.has("__placeholder"):
		return def.textures["__placeholder"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(def.color.darkened(0.25))
	img.fill_rect(Rect2i(8, 8, 48, 48), def.color)
	var tex := ImageTexture.create_from_image(img)
	def.textures["__placeholder"] = tex
	return tex
