class_name ItemGlyphs
extends RefCounted
## Primitive vector pictures for items (sword, bow, book, rune ...), drawn with CanvasItem draw calls.
## An item picks one with "glyph" in its json; otherwise BY_ID / its tags decide.

const STEEL := Color(0.86, 0.9, 0.95)
const STEEL_D := Color(0.5, 0.56, 0.66)
const WOOD := Color(0.62, 0.4, 0.22)
const GOLD := Color(1.0, 0.82, 0.3)
const PAPER := Color(0.95, 0.92, 0.8)
const GLASS := Color(0.8, 0.92, 1.0, 0.45)
const DARK := Color(0.1, 0.1, 0.14)
const OUT := Color(0, 0, 0, 0.55)
const RED := Color(0.95, 0.25, 0.3)

const BY_ID := {
	"sword": ["long_sword", "dorans_blade", "blade_of_the_ruined_king", "bloodthirster", "chempunk_chainsword", "deaths_dance",
		"divine_sunderer", "eclipse", "essence_reaver", "lord_dominiks_regards", "mortal_reminder", "maw_of_malmortius",
		"the_collector", "seryldas_grudge", "youmuus_ghostblade", "sanguine_blade", "phantom_dancer", "silvermere_dawn",
		"trinity_force", "cull", "goredrinker", "wits_end", "stormrazor", "hexdrinker", "guinsoos_rageblade"],
	"greatsword": ["b_f_sword", "infinity_edge"],
	"scimitar": ["mercurial_scimitar"],
	"dagger": ["dagger", "duskblade_of_draktharr", "edge_of_night", "navori_quickblades", "serpents_fang", "serrated_dirk",
		"rageknife", "axiom_arc", "emberknife", "hailblade", "kircheis_shard", "statikk_shiv"],
	"spear": ["spear_of_shojin", "umbral_glaive", "kraken_slayer", 	"last_whisper"],
		"bow": ["recurve_bow", "noonquiver", "immortal_shieldbow", "runaans_hurricane", "rapid_firecannon"],
	"axe": ["hearthbound_axe", "black_cleaver", "stridebreaker", "executioners_calling", "tiamat", "titanic_hydra",
		"ravenous_hydra", "hullbreaker"],
	"hammer": ["caulfields_warhammer"],
	"pickaxe": ["pickaxe"],
	"book": ["amplifying_tome", "lost_chapter", "fiendish_codex", "morellonomicon", "liandrys_anguish", "dark_seal", "rod_of_ages",
		"chemtech_putrifier", "imperial_mandate", "horizon_focus", "demonic_embrace", "mejais_soulstealer", "cosmic_drive",
		"night_harvester", "riftmaker", "shadowflame"],
	"rune": ["echoes_of_helia", "moonstone_renewer", "ludens_tempest", "shurelyas_battlesong", "redemption", "mikaels_blessing",
		"zekes_convergence", "knights_vow", "locket_of_the_iron_solari", "radiant_virtue", "forbidden_idol", "seekers_armguard",
		"bandleglass_mirror", "kindlegem"],
	"staff": ["needlessly_large_rod", "archangels_staff", "rabadons_deathcap", "void_staff", "staff_of_flowing_water"],
	"wand": ["blasting_wand", "ardent_censer", "leeching_leer", "lich_bane"],
	"shield": ["dorans_shield", "sunfire_aegis", "glacial_buckler", "aegis_of_the_legion", "evenshroud", "randuins_omen",
		"jaksho_the_protean", "gargoyle_stoneplate", "spirit_visage", "verdant_barrier"],
	"armor": ["cloth_armor", "chain_vest", "wardens_mail", "bramble_vest", "thornmail", "dead_mans_plate", "frozen_heart", "warmogs_armor"],
	"cloak": ["cloak_of_agility", "null_magic_mantle", "negatron_cloak", "spectres_cowl", "force_of_nature", "quicksilver_sash", "banshees_veil"],
	"boots": ["boots", "boots_of_swiftness", "berserkers_greaves", "ionian_boots_of_lucidity", "mercurys_treads", "mobility_boots",
		"plated_steelcaps", "sorcerers_shoes"],
	"potion": ["health_potion", "refillable_potion", "corrupting_potion", "elixir_of_iron", "elixir_of_sorcery", "elixir_of_wrath"],
	"crystal": ["ruby_crystal", "sapphire_crystal", "tear_of_the_goddess", "fimbulwinter", "catalyst_of_aeons"],
	"ring": ["dorans_ring", "faerie_charm"],
	"orb": ["oblivion_orb", "aether_wisp", "seraphs_embrace"],
	"heart": ["heartsteel", "giants_belt", "phage", "vampiric_scepter"],
	"hourglass": ["zhonyas_hourglass"],
	"eye": ["control_ward"],
	"whip": ["ironspike_whip"],
	"claw": ["prowlers_claw", "nashors_tooth"],
	"mask": ["abyssal_mask"],
	"wing": ["guardian_angel", "galeforce", "winged_moonplate"],
	"gauntlet": ["steraks_gage", "frostfire_gauntlet", "iceborn_gauntlet"],
	"crown": ["crown_of_the_shattered_queen"],
	"flame": ["bamis_cinder"],
	"snowflake": ["winters_approach", "everfrost", "rylais_crystal_scepter"],
	"drop": ["crystalline_bracer"],
	"bead": ["rejuvenation_bead"],
	"chain": ["anathemas_chains"],
	"stopwatch": ["stopwatch"],
	"gear": ["hextech_rocketbelt", "hextech_alternator", "turbo_chemtank"],
	"pendant": ["lifewell_pendant"],
	"chalice": ["chalice_of_blessing"],
	"bolt": ["zeal"],
	"star": ["sheen"],
	"egg": ["gustwalker_hatchling", "mosstomper_seedling", "scorchclaw_pup"],
	"gem": ["muramana", "manamune", "blighting_jewel"],
}
const GLYPHS := ["sword", "greatsword", "dagger", "spear", "bow", "axe", "hammer", "pickaxe", "book", "rune", "staff", "wand",
	"shield", "armor", "cloak", "boots", "potion", "crystal", "ring", "orb", "heart", "hourglass", "eye", "whip", "claw", "mask",
	"wing", "gauntlet", "crown", "flame", "snowflake", "drop", "bead", "chain", "stopwatch", "gear", "pendant", "chalice", "bolt",
	"star", "egg", "scimitar", "gem"]
const TINTS := {
	"health_potion": Color(0.95, 0.28, 0.32), "refillable_potion": Color(0.95, 0.28, 0.32), "corrupting_potion": Color(0.7, 0.3, 0.9),
	"elixir_of_iron": Color(0.7, 0.72, 0.78), "elixir_of_sorcery": Color(0.4, 0.55, 1.0), "elixir_of_wrath": Color(1.0, 0.4, 0.25),
	"control_ward": Color(0.9, 0.3, 0.4), "ruby_crystal": Color(0.95, 0.25, 0.3), "sapphire_crystal": Color(0.3, 0.55, 1.0),
	"heartsteel": Color(0.95, 0.35, 0.4), "giants_belt": Color(0.95, 0.35, 0.4), "tear_of_the_goddess": Color(0.4, 0.7, 1.0),
	"fimbulwinter": Color(0.5, 0.8, 1.0), "everfrost": Color(0.5, 0.85, 1.0), "winters_approach": Color(0.5, 0.8, 1.0),
	"bamis_cinder": Color(1.0, 0.5, 0.2),
}

static var _by_id := {}
static var _cache := {}


## The glyph name for an item dictionary ("" never - there is always a fallback).
static func glyph_for(it: Dictionary) -> String:
	var id := str(it.get("id", ""))
	if _cache.has(id):
		return _cache[id]
	var g := str(it.get("glyph", ""))
	if not GLYPHS.has(g):
		if _by_id.is_empty():
			for k in BY_ID:
				for i in BY_ID[k]:
					if not _by_id.has(i):
						_by_id[i] = k
		g = _by_id.get(id, "")
		if g == "":
			g = _from_tags(it.get("tags", []))
	if id != "":
		_cache[id] = g
	return g


static func _from_tags(tags: Array) -> String:
	var order := [["Boots", "boots"], ["Consumable", "potion"], ["Jungle", "egg"], ["SpellBlock", "cloak"], ["Armor", "armor"],
		["SpellDamage", "book"], ["CriticalStrike", "sword"], ["Damage", "sword"], ["AttackSpeed", "dagger"], ["Health", "heart"],
		["Mana", "crystal"], ["ManaRegen", "crystal"], ["HealthRegen", "heart"]]
	for o in order:
		if tags.has(o[0]):
			return o[1]
	return "rune"


static func draw(ci: CanvasItem, r: Rect2, it: Dictionary) -> void:
	var g := glyph_for(it)
	var col: Color = TINTS.get(str(it.get("id", "")), it.get("color", Color.GRAY))
	var pen := Pen.new()
	pen.ci = ci
	pen.c = r.get_center()
	pen.s = minf(r.size.x, r.size.y) * 0.5 * 0.92
	match g:
		"sword": _sword(pen, col)
		"greatsword": _greatsword(pen, col)
		"dagger": _dagger(pen, col)
		"scimitar": _scimitar(pen, col)
		"spear": _spear(pen, col)
		"bow": _bow(pen, col)
		"axe": _axe(pen, col)
		"hammer": _hammer(pen, col)
		"pickaxe": _pickaxe(pen, col)
		"book": _book(pen, col)
		"rune": _rune(pen, col)
		"staff": _staff(pen, col)
		"wand": _wand(pen, col)
		"shield": _shield(pen, col)
		"armor": _armor(pen, col)
		"cloak": _cloak(pen, col)
		"boots": _boots(pen, col)
		"potion": _potion(pen, col)
		"crystal": _crystal(pen, col)
		"gem": _gem(pen, col)
		"ring": _ring(pen, col)
		"orb": _orb(pen, col)
		"heart": _heart(pen, col)
		"hourglass": _hourglass(pen, col)
		"eye": _eye(pen, col)
		"whip": _whip(pen, col)
		"claw": _claw(pen, col)
		"mask": _mask(pen, col)
		"wing": _wing(pen, col)
		"gauntlet": _gauntlet(pen, col)
		"crown": _crown(pen, col)
		"flame": _flame(pen, col)
		"snowflake": _snowflake(pen, col)
		"drop": _drop(pen, col)
		"bead": _bead(pen, col)
		"chain": _chain(pen, col)
		"stopwatch": _stopwatch(pen, col)
		"gear": _gear(pen, col)
		"pendant": _pendant(pen, col)
		"chalice": _chalice(pen, col)
		"bolt": _bolt(pen, col)
		"star": _star(pen, col)
		"egg": _egg(pen, col)


class Pen:
	var ci: CanvasItem
	var c: Vector2
	var s: float
	var rot := 0.0
	var ofs := Vector2.ZERO

	func p(v: Vector2) -> Vector2:
		return c + (v + ofs).rotated(rot) * s

	func px(w: float) -> float:
		return maxf(1.5, w * s)

	func poly(pts: Array, col: Color, outline := true) -> void:
		var v := PackedVector2Array()
		for q in pts:
			v.append(p(q))
		ci.draw_colored_polygon(v, col)
		if outline:
			v.append(v[0])
			ci.draw_polyline(v, ItemGlyphs.OUT, 1.5)

	func rect(x: float, y: float, w: float, h: float, col: Color, outline := true) -> void:
		poly([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], col, outline)

	func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
		ci.draw_line(p(a), p(b), col, px(w), true)

	func lines(pts: Array, col: Color, w: float) -> void:
		var v := PackedVector2Array()
		for q in pts:
			v.append(p(q))
		ci.draw_polyline(v, col, px(w), true)

	func circle(v: Vector2, rad: float, col: Color, outline := true) -> void:
		ci.draw_circle(p(v), rad * s, col)
		if outline:
			ci.draw_arc(p(v), rad * s, 0, TAU, 20, ItemGlyphs.OUT, 1.5, true)

	func arc(v: Vector2, rad: float, a0: float, a1: float, col: Color, w: float) -> void:
		ci.draw_arc(p(v), rad * s, a0 + rot, a1 + rot, 24, col, px(w), true)


static func _hilt(g: Pen, col: Color, y: float, w := 0.38) -> void:
	g.rect(-w, y, w * 2.0, 0.12, col)
	g.rect(-0.06, y + 0.12, 0.12, 0.38, WOOD)
	g.circle(Vector2(0, y + 0.6), 0.1, GOLD)


static func _blade(g: Pen, w: float, top: float, bottom: float) -> void:
	g.poly([Vector2(0, top), Vector2(w, top + 0.2), Vector2(w, bottom), Vector2(-w, bottom), Vector2(-w, top + 0.2)], STEEL)
	g.line(Vector2(0, top + 0.2), Vector2(0, bottom - 0.05), STEEL_D, 0.05)


static func _sword(g: Pen, col: Color) -> void:
	g.rot = 0.785
	_blade(g, 0.14, -1.0, 0.2)
	_hilt(g, col, 0.2)


static func _greatsword(g: Pen, col: Color) -> void:
	g.rot = 0.785
	_blade(g, 0.24, -1.05, 0.15)
	_hilt(g, col, 0.15, 0.5)
	g.circle(Vector2(0, 0.0), 0.08, col.lightened(0.3))


static func _dagger(g: Pen, col: Color) -> void:
	g.rot = 0.785
	g.ofs = Vector2(0, 0.15)
	_blade(g, 0.13, -0.8, 0.15)
	_hilt(g, col, 0.15, 0.3)


static func _scimitar(g: Pen, col: Color) -> void:
	g.rot = 0.785
	g.poly([Vector2(-0.02, -1.0), Vector2(0.28, -0.65), Vector2(0.4, -0.1), Vector2(0.14, 0.2), Vector2(-0.14, 0.2), Vector2(-0.08, -0.45)], STEEL)
	_hilt(g, col, 0.2)


static func _spear(g: Pen, col: Color) -> void:
	g.rot = 0.785
	g.line(Vector2(0, -0.4), Vector2(0, 1.0), WOOD, 0.1)
	g.poly([Vector2(0, -1.05), Vector2(0.2, -0.6), Vector2(0.07, -0.45), Vector2(-0.07, -0.45), Vector2(-0.2, -0.6)], STEEL)
	g.circle(Vector2(0, -0.38), 0.09, col)


static func _bow(g: Pen, col: Color) -> void:
	g.ofs = Vector2(-0.25, 0)
	g.arc(Vector2(-0.45, 0), 1.0, -1.0, 1.0, WOOD, 0.12)
	g.line(Vector2(0.09, -0.84), Vector2(0.09, 0.84), STEEL, 0.03)
	g.line(Vector2(-0.35, 0), Vector2(0.85, 0), STEEL_D, 0.05)
	g.poly([Vector2(1.0, 0), Vector2(0.7, -0.14), Vector2(0.7, 0.14)], STEEL)
	g.poly([Vector2(-0.35, 0), Vector2(-0.6, -0.15), Vector2(-0.5, 0), Vector2(-0.6, 0.15)], col)


static func _axe(g: Pen, col: Color) -> void:
	g.rot = 0.5
	g.line(Vector2(0, -0.8), Vector2(0, 1.0), WOOD, 0.12)
	g.poly([Vector2(0.06, -0.8), Vector2(0.6, -0.95), Vector2(0.9, -0.4), Vector2(0.6, 0.15), Vector2(0.06, -0.1)], STEEL)
	g.lines([Vector2(0.6, -0.95), Vector2(0.9, -0.4), Vector2(0.6, 0.15)], col, 0.06)
	g.poly([Vector2(-0.06, -0.7), Vector2(-0.4, -0.55), Vector2(-0.06, -0.4)], STEEL_D)


static func _hammer(g: Pen, col: Color) -> void:
	g.rot = 0.6
	g.line(Vector2(0, -0.4), Vector2(0, 1.0), WOOD, 0.12)
	g.rect(-0.6, -0.85, 1.2, 0.5, STEEL_D)
	g.rect(-0.6, -0.65, 1.2, 0.1, col, false)


static func _pickaxe(g: Pen, col: Color) -> void:
	g.rot = 0.6
	g.line(Vector2(0, -0.6), Vector2(0, 1.0), WOOD, 0.12)
	g.poly([Vector2(-0.95, -0.3), Vector2(-0.5, -0.7), Vector2(0, -0.78), Vector2(0.5, -0.7), Vector2(0.95, -0.3),
		Vector2(0.6, -0.48), Vector2(0, -0.55), Vector2(-0.6, -0.48)], STEEL)


static func _star_pts(radius: float, inner: float, n: int, at := Vector2.ZERO) -> Array:
	var pts := []
	for i in n * 2:
		pts.append(at + Vector2.from_angle(i * PI / n - PI / 2.0) * (radius if i % 2 == 0 else inner))
	return pts


static func _book(g: Pen, col: Color) -> void:
	g.rect(-0.55, -0.72, 1.15, 1.5, PAPER)
	g.rect(-0.65, -0.82, 1.15, 1.5, col.darkened(0.25))
	g.rect(-0.65, -0.82, 0.18, 1.5, col.darkened(0.55))
	g.poly(_star_pts(0.3, 0.1, 4, Vector2(0.02, -0.07)), GOLD)


static func _rune(g: Pen, col: Color) -> void:
	g.poly([Vector2(0, -0.92), Vector2(0.72, -0.46), Vector2(0.72, 0.46), Vector2(0, 0.92), Vector2(-0.72, 0.46), Vector2(-0.72, -0.46)],
		Color(0.32, 0.34, 0.42))
	g.poly([Vector2(0, -0.7), Vector2(0.55, -0.35), Vector2(0.55, 0.35), Vector2(0, 0.7), Vector2(-0.55, 0.35), Vector2(-0.55, -0.35)],
		Color(0.2, 0.21, 0.28), false)
	g.circle(Vector2.ZERO, 0.45, Color(col.r, col.g, col.b, 0.25), false)
	var b := col.lightened(0.35)
	g.line(Vector2(0, -0.5), Vector2(0, 0.5), b, 0.1)
	g.line(Vector2(0, -0.05), Vector2(-0.33, -0.45), b, 0.1)
	g.line(Vector2(0, -0.05), Vector2(0.33, -0.45), b, 0.1)
	g.line(Vector2(-0.22, 0.28), Vector2(0.22, 0.28), b, 0.1)


static func _staff(g: Pen, col: Color) -> void:
	g.rot = 0.785
	g.line(Vector2(0, -0.5), Vector2(0, 1.0), WOOD, 0.1)
	g.arc(Vector2(0, -0.62), 0.36, 0.2, PI - 0.2, GOLD, 0.07)
	g.circle(Vector2(0, -0.62), 0.28, col)
	g.circle(Vector2(-0.09, -0.71), 0.08, Color(1, 1, 1, 0.65), false)


static func _wand(g: Pen, col: Color) -> void:
	g.rot = 0.785
	g.line(Vector2(0, -0.3), Vector2(0, 1.0), WOOD, 0.12)
	g.poly(_star_pts(0.46, 0.18, 4, Vector2(0, -0.6)), col)


static func _shield(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.7, -0.8), Vector2(0.7, -0.8), Vector2(0.7, 0.1), Vector2(0, 0.95), Vector2(-0.7, 0.1)], col.darkened(0.1))
	g.poly([Vector2(-0.5, -0.62), Vector2(0.5, -0.62), Vector2(0.5, 0.02), Vector2(0, 0.72), Vector2(-0.5, 0.02)], col.darkened(0.5), false)
	g.line(Vector2(0, -0.62), Vector2(0, 0.7), col.lightened(0.2), 0.06)
	g.circle(Vector2(0, -0.12), 0.2, STEEL)


static func _armor(g: Pen, col: Color) -> void:
	var c := col.lerp(STEEL, 0.4)
	g.poly([Vector2(-0.9, -0.7), Vector2(-0.4, -0.82), Vector2(-0.2, -0.6), Vector2(0.2, -0.6), Vector2(0.4, -0.82), Vector2(0.9, -0.7),
		Vector2(0.75, -0.1), Vector2(0.55, -0.1), Vector2(0.55, 0.85), Vector2(-0.55, 0.85), Vector2(-0.55, -0.1), Vector2(-0.75, -0.1)], c)
	g.rect(-0.55, 0.4, 1.1, 0.14, col.darkened(0.45))
	g.line(Vector2(0, -0.5), Vector2(0, 0.4), c.darkened(0.3), 0.05)
	g.circle(Vector2(0, 0.47), 0.09, GOLD)


static func _cloak(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.35, -0.85), Vector2(0.35, -0.85), Vector2(0.85, 0.85), Vector2(0.3, 0.65), Vector2(0, 0.9), Vector2(-0.3, 0.65), Vector2(-0.85, 0.85)], col)
	g.line(Vector2(0, -0.6), Vector2(0, 0.7), col.darkened(0.35), 0.05)
	g.line(Vector2(-0.3, -0.6), Vector2(-0.45, 0.6), col.darkened(0.3), 0.04)
	g.line(Vector2(0.3, -0.6), Vector2(0.45, 0.6), col.darkened(0.3), 0.04)
	g.circle(Vector2(0, -0.72), 0.1, GOLD)


static func _boots(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.4, -0.85), Vector2(0.15, -0.85), Vector2(0.15, 0.0), Vector2(0.85, 0.3), Vector2(0.85, 0.75), Vector2(-0.4, 0.75)], WOOD.lerp(col, 0.35))
	g.rect(-0.45, -0.9, 0.65, 0.22, col.lightened(0.2))
	g.rect(-0.4, 0.62, 1.25, 0.14, DARK)


static func _potion(g: Pen, col: Color) -> void:
	g.circle(Vector2(0, 0.3), 0.58, GLASS)
	g.rect(-0.17, -0.7, 0.34, 0.55, GLASS)
	g.circle(Vector2(0, 0.34), 0.47, col, false)
	g.rect(-0.22, -0.92, 0.44, 0.22, WOOD)
	g.circle(Vector2(-0.2, 0.18), 0.1, Color(1, 1, 1, 0.55), false)


static func _crystal(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.5, -0.4), Vector2(-0.25, -0.85), Vector2(0.25, -0.85), Vector2(0.5, -0.4), Vector2(0, 0.92)], col)
	g.poly([Vector2(-0.5, -0.4), Vector2(-0.25, -0.85), Vector2(0.0, -0.4)], col.lightened(0.4), false)
	g.poly([Vector2(0.0, -0.4), Vector2(0.5, -0.4), Vector2(0, 0.92)], col.darkened(0.25), false)
	g.line(Vector2(-0.5, -0.4), Vector2(0.5, -0.4), col.lightened(0.5), 0.04)


static func _gem(g: Pen, col: Color) -> void:
	g.rot = 0.0
	g.poly([Vector2(0, -0.9), Vector2(0.7, 0), Vector2(0, 0.9), Vector2(-0.7, 0)], col)
	g.poly([Vector2(0, -0.9), Vector2(0.7, 0), Vector2(0, 0)], col.lightened(0.35), false)
	g.poly([Vector2(0, 0), Vector2(0.7, 0), Vector2(0, 0.9)], col.darkened(0.3), false)


static func _ring(g: Pen, col: Color) -> void:
	g.arc(Vector2(0, 0.2), 0.52, 0, TAU, GOLD, 0.16)
	g.poly([Vector2(0, -0.8), Vector2(0.22, -0.52), Vector2(0, -0.24), Vector2(-0.22, -0.52)], col)


static func _orb(g: Pen, col: Color) -> void:
	g.circle(Vector2.ZERO, 0.78, col.darkened(0.35))
	g.circle(Vector2.ZERO, 0.62, col, false)
	g.arc(Vector2.ZERO, 0.4, 0.5, 3.0, col.lightened(0.45), 0.07)
	g.circle(Vector2(-0.27, -0.3), 0.18, Color(1, 1, 1, 0.5), false)


static func _heart(g: Pen, col: Color) -> void:
	g.circle(Vector2(-0.33, -0.25), 0.42, col, false)
	g.circle(Vector2(0.33, -0.25), 0.42, col, false)
	g.poly([Vector2(-0.73, -0.12), Vector2(0.73, -0.12), Vector2(0, 0.88)], col, false)
	g.circle(Vector2(-0.4, -0.38), 0.12, Color(1, 1, 1, 0.5), false)


static func _hourglass(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.5, -0.76), Vector2(0.5, -0.76), Vector2(0, 0)], GLASS)
	g.poly([Vector2(0, 0), Vector2(0.5, 0.76), Vector2(-0.5, 0.76)], GLASS)
	g.poly([Vector2(-0.28, -0.6), Vector2(0.28, -0.6), Vector2(0, -0.1)], col, false)
	g.poly([Vector2(0, 0.2), Vector2(0.4, 0.76), Vector2(-0.4, 0.76)], col, false)
	g.rect(-0.62, -0.92, 1.24, 0.16, GOLD)
	g.rect(-0.62, 0.76, 1.24, 0.16, GOLD)


static func _eye(g: Pen, col: Color) -> void:
	var top := []
	var bottom := []
	for i in 13:
		var x := -0.9 + i * 0.15
		var h := 0.55 * (1.0 - pow(x / 0.9, 2))
		top.append(Vector2(x, -h))
		bottom.push_front(Vector2(x, h))
	g.poly(top + bottom, PAPER)
	g.circle(Vector2.ZERO, 0.33, col)
	g.circle(Vector2.ZERO, 0.14, DARK, false)
	g.circle(Vector2(-0.08, -0.08), 0.05, Color(1, 1, 1, 0.8), false)


static func _whip(g: Pen, col: Color) -> void:
	var pts := []
	for i in 17:
		var t := i / 16.0
		pts.append(Vector2(-0.6 + 1.5 * t, 0.5 - 1.2 * t + 0.28 * sin(t * TAU * 1.5)))
	g.lines(pts, col.lerp(WOOD, 0.4), 0.09)
	g.line(Vector2(-0.9, 0.85), Vector2(-0.55, 0.45), WOOD, 0.2)
	g.line(Vector2(-0.95, 0.9), Vector2(-0.85, 0.8), GOLD, 0.24)


static func _claw(g: Pen, col: Color) -> void:
	for k in 3:
		var x := -0.6 + k * 0.5
		g.lines([Vector2(x, -0.9), Vector2(x + 0.28, 0.0), Vector2(x + 0.08, 0.9)], STEEL.lerp(col, 0.25), 0.15)


static func _mask(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(0.7, 0.1), Vector2(0.35, 0.85), Vector2(0, 0.95), Vector2(-0.35, 0.85), Vector2(-0.7, 0.1)], col.darkened(0.2))
	g.poly([Vector2(-0.58, -0.3), Vector2(-0.12, -0.12), Vector2(-0.3, 0.08), Vector2(-0.58, -0.02)], DARK)
	g.poly([Vector2(0.58, -0.3), Vector2(0.12, -0.12), Vector2(0.3, 0.08), Vector2(0.58, -0.02)], DARK)
	g.line(Vector2(-0.2, 0.55), Vector2(0.2, 0.55), DARK, 0.07)
	g.line(Vector2(0, 0.0), Vector2(0, 0.4), col.lightened(0.3), 0.05)


static func _wing(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.8, 0.8), Vector2(-0.9, -0.2), Vector2(-0.5, -0.7), Vector2(0.1, -0.9), Vector2(0.9, -0.85), Vector2(0.5, -0.5),
		Vector2(0.8, -0.35), Vector2(0.35, -0.05), Vector2(0.6, 0.15), Vector2(0.1, 0.35), Vector2(0.0, 0.8)], PAPER.lerp(col, 0.3))
	g.lines([Vector2(-0.75, 0.6), Vector2(-0.5, -0.2), Vector2(0.4, -0.7)], col.darkened(0.2), 0.04)


static func _gauntlet(g: Pen, col: Color) -> void:
	for i in 4:
		g.rect(-0.5 + i * 0.25, -0.8, 0.22, 0.45, STEEL)
	g.rect(-0.5, -0.4, 1.0, 0.9, STEEL.lerp(col, 0.3))
	g.poly([Vector2(0.5, -0.2), Vector2(0.85, -0.05), Vector2(0.75, 0.3), Vector2(0.5, 0.25)], STEEL)
	g.rect(-0.6, 0.5, 1.2, 0.4, col.darkened(0.15))


static func _crown(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.8, 0.55), Vector2(-0.85, -0.5), Vector2(-0.4, -0.1), Vector2(0, -0.8), Vector2(0.4, -0.1), Vector2(0.85, -0.5), Vector2(0.8, 0.55)], GOLD)
	g.rect(-0.8, 0.3, 1.6, 0.25, GOLD.darkened(0.25))
	g.circle(Vector2(0, -0.25), 0.11, col)
	g.circle(Vector2(-0.45, 0.42), 0.08, col)
	g.circle(Vector2(0.45, 0.42), 0.08, col)


static func _flame(g: Pen, col: Color) -> void:
	g.poly([Vector2(0.05, -0.95), Vector2(0.38, -0.4), Vector2(0.55, 0.1), Vector2(0.48, 0.5), Vector2(0, 0.9), Vector2(-0.48, 0.5),
		Vector2(-0.55, 0.0), Vector2(-0.25, -0.3), Vector2(-0.12, -0.15)], col)
	g.poly([Vector2(0, -0.1), Vector2(0.26, 0.35), Vector2(0, 0.75), Vector2(-0.26, 0.35)], Color(1.0, 0.9, 0.4), false)


static func _snowflake(g: Pen, col: Color) -> void:
	var c := col.lerp(Color.WHITE, 0.4)
	for i in 6:
		var d := Vector2.from_angle(i * PI / 3.0)
		g.line(Vector2.ZERO, d * 0.9, c, 0.09)
		var m := d * 0.55
		g.line(m, m + d.rotated(0.7) * 0.28, c, 0.07)
		g.line(m, m + d.rotated(-0.7) * 0.28, c, 0.07)


static func _drop(g: Pen, col: Color) -> void:
	g.circle(Vector2(0, 0.3), 0.5, col, false)
	g.poly([Vector2(-0.47, 0.18), Vector2(0.47, 0.18), Vector2(0, -0.9)], col, false)
	g.circle(Vector2(-0.18, 0.28), 0.1, Color(1, 1, 1, 0.55), false)


static func _bead(g: Pen, col: Color) -> void:
	g.arc(Vector2(0, -0.15), 0.55, PI, TAU, WOOD, 0.05)
	g.circle(Vector2(0, 0.3), 0.45, col)
	g.circle(Vector2(-0.14, 0.15), 0.1, Color(1, 1, 1, 0.55), false)


static func _chain(g: Pen, col: Color) -> void:
	for i in 3:
		g.arc(Vector2(-0.45 + i * 0.45, -0.45 + i * 0.45), 0.34, 0, TAU, col if i == 1 else STEEL, 0.13)


static func _stopwatch(g: Pen, col: Color) -> void:
	g.rect(-0.1, -0.95, 0.2, 0.2, GOLD)
	g.circle(Vector2(0, 0.1), 0.7, PAPER)
	g.arc(Vector2(0, 0.1), 0.7, 0, TAU, GOLD, 0.1)
	g.arc(Vector2(0, 0.1), 0.5, -PI / 2.0, 0.6, col, 0.1)
	g.line(Vector2(0, 0.1), Vector2(0, -0.35), DARK, 0.06)
	g.line(Vector2(0, 0.1), Vector2(0.3, 0.25), DARK, 0.06)


static func _gear(g: Pen, col: Color) -> void:
	var pts := []
	for i in 8:
		var a := i * TAU / 8.0
		for d in [[-0.2, 0.65], [-0.12, 0.92], [0.12, 0.92], [0.2, 0.65]]:
			pts.append(Vector2.from_angle(a + d[0]) * d[1])
	g.poly(pts, STEEL.lerp(col, 0.35))
	g.circle(Vector2.ZERO, 0.28, DARK)


static func _pendant(g: Pen, col: Color) -> void:
	g.lines([Vector2(-0.75, -0.85), Vector2(-0.2, -0.2), Vector2(0, -0.1), Vector2(0.2, -0.2), Vector2(0.75, -0.85)], GOLD, 0.06)
	g.poly([Vector2(0, 0.0), Vector2(0.38, 0.4), Vector2(0, 0.9), Vector2(-0.38, 0.4)], col)
	g.poly([Vector2(0, 0.0), Vector2(0.38, 0.4), Vector2(0, 0.4)], col.lightened(0.35), false)


static func _chalice(g: Pen, col: Color) -> void:
	g.poly([Vector2(-0.6, -0.7), Vector2(0.6, -0.7), Vector2(0.45, -0.1), Vector2(0.1, 0.15), Vector2(0.1, 0.6), Vector2(0.45, 0.82),
		Vector2(-0.45, 0.82), Vector2(-0.1, 0.6), Vector2(-0.1, 0.15), Vector2(-0.45, -0.1)], GOLD)
	g.rect(-0.54, -0.64, 1.08, 0.2, col, false)


static func _bolt(g: Pen, col: Color) -> void:
	g.poly([Vector2(0.25, -0.95), Vector2(-0.5, 0.1), Vector2(-0.05, 0.1), Vector2(-0.25, 0.95), Vector2(0.55, -0.2), Vector2(0.1, -0.2)], col.lerp(GOLD, 0.4))


static func _star(g: Pen, col: Color) -> void:
	g.poly(_star_pts(0.95, 0.28, 4), col.lerp(GOLD, 0.5))
	g.circle(Vector2.ZERO, 0.12, Color(1, 1, 1, 0.8), false)


static func _egg(g: Pen, col: Color) -> void:
	var pts := []
	for i in 24:
		var a := i * TAU / 24.0
		pts.append(Vector2(0.58 * cos(a), (0.88 if sin(a) < 0.0 else 0.62) * sin(a) + 0.08))
	g.poly(pts, PAPER.lerp(col, 0.3))
	g.circle(Vector2(-0.2, -0.2), 0.12, col, false)
	g.circle(Vector2(0.2, 0.1), 0.1, col, false)
	g.circle(Vector2(-0.12, 0.4), 0.09, col, false)
