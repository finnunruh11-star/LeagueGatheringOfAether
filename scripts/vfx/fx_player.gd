class_name FxPlayer
extends RefCounted
## Turns gameplay FX events (sent by the host) into visuals on every client.

const DIRECTIONAL := ["burst", "claw", "streaks", "fire", "claw_red", "streaks_red", "wave", "magic"]
const COL_PHYSICAL := Color(1.0, 0.74, 0.32)
const COL_MAGIC := Color(0.66, 0.62, 1.0)
const COL_HURT := Color(1.0, 0.32, 0.26)
const COL_HEAL := Color(0.45, 1.0, 0.45)


## Returns true if the event kind was handled here.
static func play(w: World, kind: String, d: Dictionary) -> bool:
	match kind:
		"hit": hit(w, d)
		"heal": heal(w, d)
		"death": death(w, d)
		"cast": cast(w, d)
		"levelup": levelup(w, d)
		"spawn": spawn(w, d)
		"blink": blink(w, d)
		"blast": blast(w, d)
		"kill": kill(w, d)
		_: return false
	return true


static func kill(w: World, d: Dictionary) -> void:
	if d.get("tower", false):
		var ours: bool = int(d.get("t", -1)) == w.local_team
		w.hud.show_banner("TOWER LOST" if ours else "TOWER DESTROYED!", Color(1, 0.4, 0.35) if ours else Color(1, 0.85, 0.3))
		return
	var killer = w.entities.get(int(d.get("k", 0)))
	var victim = w.entities.get(int(d.get("v", 0)))
	if victim is Champion:
		w.hud.announce_kill(int(d.get("k", 0)), victim.net_id, d.get("a", []), str(d.get("kk", "champion" if killer is Champion else "")),
			int(d.get("kt", killer.team if killer is Unit else 2)))
	w._sfx("death", null, -6.0)
	var lc = w.local_champion
	if lc != null and int(d.get("k", 0)) == lc.net_id:
		w.hud.show_banner("ENEMY SLAIN!", Color(1, 0.85, 0.3))
		w._sfx("level", null, -10.0)


static func _unit(w: World, d: Dictionary):
	var u = w.entities.get(int(d.get("v", -1)))
	return u if is_instance_valid(u) else null


## Plays a library effect; directional ones spray away from `pos` along `ang`.
static func sprite(w: World, style: String, pos: Vector2, ang: float, scale: float, col: Color) -> void:
	var tint := col.lightened(0.25) if Vfx.tintable(style) else Color.WHITE
	if style in DIRECTIONAL:
		Vfx.play(w.fx_layer, style, pos + Vector2.from_angle(ang) * 46.0 * scale, ang, scale, tint)
	else:
		Vfx.play(w.fx_layer, style, pos, randf() * TAU, scale, tint)


static func hit(w: World, d: Dictionary) -> void:
	var victim = _unit(w, d)
	var pos: Vector2 = victim.global_position if victim else d.p
	var rad: float = victim.radius if victim else 20.0
	var col: Color = d.get("c", Color.WHITE)
	var ang: float = d.get("r", 0.0)
	var amt: float = d.get("a", 0.0)
	var style := str(d.get("x", "spark"))
	var lay := w.fx_layer
	var sc := clampf(rad / 24.0, 0.7, 2.2) * 1.5
	var at := pos + Vector2(randf_range(-0.3, 0.3), randf_range(-0.6, 0.0)) * rad
	match style:
		"slash":
			Vfx.play(lay, Vfx.slash_for(col), at, ang, sc * 0.7)
			Vfx.play(lay, "spark", at, ang, sc * 0.5, Color(1, 1, 1, 0.9))
		"dot":
			Vfx.play(lay, "twinkle", at, randf() * TAU, sc * 0.4, col.lightened(0.35))
		"ability":
			Vfx.play(lay, "star", at, randf() * TAU, sc * 0.9, col.lightened(0.3))
			Vfx.particles(lay, at, col.lightened(0.35), 10, 300.0, 0.4, 3.5)
		"none":
			pass
		_:
			if Vfx.has(style):
				sprite(w, style, at, ang, sc * (0.55 if style in DIRECTIONAL else 0.85), col)
			else:
				Vfx.play(lay, "spark", at, ang, sc * 0.7, col.lightened(0.25))
	if victim != null:
		victim.hit_react(ang, amt)
	var lc = w.local_champion
	var on_me: bool = lc != null and victim == lc
	var mine: bool = lc != null and int(d.get("s", 0)) == lc.net_id
	var important: bool = victim != null and (victim.is_champion or victim is Dummy)
	if amt >= 1.0 and (important or mine or on_me):
		var c := COL_HURT if on_me else (Color.WHITE if d.get("t") == "true" else (COL_PHYSICAL if d.get("t") == "physical" else COL_MAGIC))
		number(w, pos + Vector2(randf_range(-16, 16), -rad - 46), str(int(round(amt))), c, amt, style == "dot")
	if on_me and style != "dot":
		w.shake(clampf(amt / 30.0, 2.0, 9.0))
		w.hud.hurt(amt / maxf(lc.stats.max_hp, 1.0))
	if (on_me or mine) and style != "dot":
		w._sfx("hit", pos, -13.0)


static func number(w: World, pos: Vector2, text: String, col: Color, amt: float, small := false) -> void:
	var f := Fx.new()
	var size := 13 if small else int(15 + clampf(amt / 14.0, 0.0, 17.0))
	f.setup("num", {"pos": pos, "text": text, "color": col, "size": size, "big": amt >= 150.0 and not small,
		"drift": randf_range(-30, 30), "dur": 0.7 if small else 0.95})
	w.fx_layer.add_child(f)


static func heal(w: World, d: Dictionary) -> void:
	var u = _unit(w, d)
	var pos: Vector2 = u.global_position if u else d.p
	var rad: float = d.get("r", 24.0)
	Vfx.flash(w.fx_layer, pos, Color(0.35, 1.0, 0.45, 0.55), rad * 1.8, 0.4)
	Vfx.particles(w.fx_layer, pos, Color(0.55, 1.0, 0.55), 10, 90.0, 0.8, 3.0, Vector2(0, -140), Vector2.UP, 70.0, true)
	number(w, pos + Vector2(randf_range(-12, 12), -rad - 34), "+%d" % int(d.get("a", 0)), COL_HEAL, float(d.get("a", 0)))


static func death(w: World, d: Dictionary) -> void:
	var pos: Vector2 = d.p
	var rad: float = d.get("r", 20.0)
	var col: Color = d.get("c", Color.WHITE)
	var kind := str(d.get("k", ""))
	var lay := w.fx_layer
	match kind:
		"tower":
			for i in 7:
				var a := TAU * i / 7.0 + randf() * 0.4
				w.schedule_visual(i * 0.06, func(): Vfx.play(lay, "fire", pos + Vector2.from_angle(a) * rad * 0.8, a, 1.4))
			Vfx.play(lay, "smoke", pos, 0.0, rad / 28.0, Color(1.3, 1.3, 1.3))
			Vfx.flash(lay, pos, Color(1, 0.8, 0.5, 0.9), rad * 5.0, 0.5)
			Vfx.flash(lay, pos, Color(1, 0.9, 0.7, 0.8), rad * 6.0, 0.6, Vfx.ring(), 1.6)
			Vfx.particles(lay, pos, Color(0.55, 0.55, 0.6), 40, 520.0, 1.0, 6.0, Vector2(0, 300))
			Vfx.particles(lay, pos, col.lightened(0.3), 24, 420.0, 0.8, 4.0, Vector2.ZERO, Vector2.UP, 180.0, true)
			w.shake_at(pos, 16.0)
		"champion":
			Vfx.play(lay, "smoke", pos, 0.0, rad / 30.0, Color(1.2, 1.2, 1.2))
			Vfx.flash(lay, pos, Color(1, 1, 1, 0.8), rad * 3.0, 0.35)
			Vfx.particles(lay, pos, col, 26, 380.0, 0.8, 5.0, Vector2(0, 260))
			Vfx.particles(lay, pos, Color(0.85, 0.9, 1.0), 12, 80.0, 1.2, 3.0, Vector2(0, -90), Vector2.UP, 40.0, true)
			var me = w.local_champion
			w.shake_at(pos, 12.0 if me != null and int(d.get("v", -1)) == me.net_id else 6.0)
		_:
			Vfx.play(lay, "smoke", pos, 0.0, maxf(rad / 34.0, 0.35), Color(1.25, 1.25, 1.25))
			Vfx.particles(lay, pos, col, 10, 240.0, 0.5, 3.5, Vector2(0, 260))


static func cast(w: World, d: Dictionary) -> void:
	var u = _unit(w, d)
	var pos: Vector2 = u.global_position if u else d.p
	var col: Color = d.get("c", Color.WHITE)
	Vfx.flash(w.fx_layer, pos + Vector2(0, 14), Color(col, 0.75), 46.0, 0.35, Vfx.ring(), 1.7)
	Vfx.particles(w.fx_layer, pos, col.lightened(0.4), 8, 160.0, 0.45, 3.0, Vector2(0, -60), Vector2.UP, 180.0, true)


static func levelup(w: World, d: Dictionary) -> void:
	var u = _unit(w, d)
	var pos: Vector2 = u.global_position if u else d.p
	var gold := Color(1.0, 0.84, 0.3)
	Vfx.flash(w.fx_layer, pos, Color(gold, 0.9), 70.0, 0.6, Vfx.ring(), 1.9)
	Vfx.flash(w.fx_layer, pos, Color(gold, 0.6), 60.0, 0.5)
	Vfx.particles(w.fx_layer, pos, gold, 24, 140.0, 1.0, 3.5, Vector2(0, -200), Vector2.UP, 40.0, true)
	var f := Fx.new()
	f.setup("num", {"pos": pos + Vector2(0, -78), "text": "LEVEL UP!", "color": gold, "size": 24, "big": true, "drift": 0.0, "dur": 1.3})
	w.fx_layer.add_child(f)
	w._sfx("level", pos, -8.0)


static func spawn(w: World, d: Dictionary) -> void:
	var pos: Vector2 = d.p
	var rad: float = d.get("r", 20.0)
	var col: Color = d.get("c", Color.WHITE)
	Vfx.play(w.fx_layer, "smoke", pos, 0.0, maxf(rad / 32.0, 0.5), Color(1.3, 1.3, 1.3))
	Vfx.flash(w.fx_layer, pos, Color(col, 0.8), rad * 2.2, 0.4, Vfx.ring(), 1.6)
	Vfx.particles(w.fx_layer, pos, col.lightened(0.3), 12, 200.0, 0.5, 3.0, Vector2.ZERO, Vector2.UP, 180.0, true)


static func blink(w: World, d: Dictionary) -> void:
	var col: Color = d.get("color", Color(0.6, 0.6, 1.0))
	for p in [d.from, d.to]:
		Vfx.play(w.fx_layer, "smoke", p, 0.0, 0.6, Color(1.3, 1.3, 1.3))
		Vfx.particles(w.fx_layer, p, col.lightened(0.3), 12, 220.0, 0.45, 3.0, Vector2.ZERO, Vector2.UP, 180.0, true)
	Vfx.flash(w.fx_layer, d.to, Color(col, 0.85), 60.0, 0.4, Vfx.ring(), 1.6)
	if not d.get("noline", false):
		var f := Fx.new()
		f.setup("line", {"from": d.from, "to": d.to, "color": Color(col, 0.6), "dur": 0.25})
		w.fx_layer.add_child(f)
	w._sfx("zap", d.to, -12.0)


static func blast(w: World, d: Dictionary) -> void:
	var pos: Vector2 = d.pos
	var r: float = d.get("radius", 100.0)
	var col: Color = d.get("color", Color.WHITE)
	var angle: float = d.get("angle", 360.0)
	var dir: Vector2 = d.get("dir", Vector2.RIGHT)
	var style := str(d.get("vfx", ""))
	var lay := w.fx_layer
	var f := Fx.new()
	f.setup("blast", d)
	lay.add_child(f)
	if angle >= 359.0:
		Vfx.flash(lay, pos, Color(col.lightened(0.3), 0.7), r * 0.9, 0.3)
		Vfx.flash(lay, pos, Color(col.lightened(0.4), 0.9), r, 0.4, Vfx.ring(), 1.25)
	if style != "" and Vfx.has(style):
		var sc := r / 40.0
		if style in DIRECTIONAL:
			var n := clampi(int(r / 50.0), 3, 8)
			for i in n:
				var a := TAU * i / n + randf() * 0.4
				sprite(w, style, pos, a, sc * 0.45, col)
		else:
			sprite(w, style, pos, 0.0, sc * 0.8, col)
	elif angle < 359.0:
		var half := deg_to_rad(angle) * 0.5
		for i in 4:
			var a := dir.angle() + randf_range(-half, half)
			Vfx.play(lay, "streaks", pos + Vector2.from_angle(a) * r * 0.45, a, r / 160.0, col.lightened(0.3))
	else:
		var n := clampi(int(r / 45.0), 3, 8)
		for i in n:
			var a := TAU * i / n + randf() * 0.5
			Vfx.play(lay, "burst", pos + Vector2.from_angle(a) * (46.0 * r / 150.0 + r * 0.15), a, r / 150.0, col.lightened(0.25))
		Vfx.play(lay, "star", pos, randf() * TAU, r / 45.0, col.lightened(0.45))
	Vfx.particles(lay, pos, col.lightened(0.2), clampi(int(r / 7.0), 8, 40), r * 2.6, 0.55, 4.0, Vector2.ZERO,
		dir if angle < 359.0 else Vector2.UP, angle * 0.5 if angle < 359.0 else 180.0)
	if r >= 160.0:
		w.shake_at(pos, r / 45.0)
	w._sfx("boom", pos, -14.0 + clampf(r / 40.0, 0.0, 7.0))
