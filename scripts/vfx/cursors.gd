class_name Cursors
extends RefCounted
## Procedurally drawn mouse cursors.

static var _attack: ImageTexture


## Red crosshair shown while hovering an enemy (or attack-move is armed).
static func attack() -> Texture2D:
	if _attack == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var c := Vector2(15.5, 15.5)
		for x in 32:
			for y in 32:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := p.distance_to(c)
				var tick := (absf(p.x - c.x) < 1.3 and (p.y < 9.5 or p.y > 21.5)) or (absf(p.y - c.y) < 1.3 and (p.x < 9.5 or p.x > 21.5))
				if absf(d - 9.0) < 1.3 or tick or d < 1.8:
					img.set_pixel(x, y, Color(1.0, 0.25, 0.2))
				elif absf(d - 9.0) < 2.6 or d < 3.0 or ((absf(p.x - c.x) < 2.6 and (p.y < 10.5 or p.y > 20.5)) or (absf(p.y - c.y) < 2.6 and (p.x < 10.5 or p.x > 20.5))):
					if p.x > 0.5 and p.y > 0.5 and p.x < 31.5 and p.y < 31.5:
						img.set_pixel(x, y, Color(0.1, 0.0, 0.0, 0.9))
		_attack = ImageTexture.create_from_image(img)
	return _attack
