class_name Content
extends RefCounted
## Loads characters and maps from plain folders (characters/, maps/) next to the
## project or the exported executable. Files are read as raw bytes, so the exact
## same code builds characters that a client received from the host.

const ALLOWED_EXT := ["json", "png", "jpg", "jpeg", "webp", "svg", "bmp", "wav", "ogg", "txt"]
const MAX_FILE_BYTES := 8 * 1024 * 1024
const SLOTS := ["q", "w", "e", "r"]
const BASE_RADIUS := 24.0

## Every stat a unit can have. Percent-style stats are fractions (0.3 = 30%).
## Regen values are per second.
const DEFAULT_STATS := {
	"max_hp": 650.0,
	"hp_regen": 1.5,
	"hp_regen_percent": 0.0,     # bonus % of base health regen
	"max_mana": 0.0,             # 0 = manaless (abilities are free)
	"mana_regen": 0.0,
	"mana_regen_percent": 0.0,   # bonus % of base mana regen
	"move_speed": 330.0,         # flat
	"move_speed_bonus": 0.0,     # percent bonus
	"attack_damage": 60.0,
	"ability_power": 0.0,
	"attack_speed": 0.8,         # base attacks per second
	"bonus_attack_speed": 0.0,   # percent bonus; final = attack_speed * (1 + bonus)
	"attack_speed_cap": 2.5,
	"attack_range": 125.0,
	"armor": 20.0,
	"magic_resist": 30.0,
	"crit_chance": 0.0,
	"crit_damage": 1.75,
	"ability_haste": 0.0,
	"lethality": 0.0,            # flat armor pen (scales 60%..100% with your level)
	"armor_pen": 0.0,            # percent armor pen
	"magic_pen": 0.0,            # flat magic pen
	"magic_pen_percent": 0.0,
	"lifesteal": 0.0,            # heals % of basic attack / on-hit damage
	"omnivamp": 0.0,             # heals % of all damage
	"heal_power": 0.0,           # heal & shield power of heals/shields you give
	"heal_received": 0.0,        # bonus healing & shielding you receive
	"tenacity": 0.0,             # shortens stuns/roots/silences/slows
	"slow_resist": 0.0,
	"vision": 900.0,             # sight radius (fog of war)
	"size": 1.0,
	"damage_mult": 1.0,
	"damage_taken_mult": 1.0,
	"cooldown_mult": 1.0,
}

const DEFAULT_PER_LEVEL := {"max_hp": 75.0, "attack_damage": 3.5, "armor": 2.0, "magic_resist": 1.0, "hp_regen": 0.12,
	"ability_power": 8.0, "bonus_attack_speed": 0.025}

const EFFECT_TYPES := [
	"damage", "heal", "shield", "stun", "root", "silence", "slow", "dot", "hot", "buff",
	"invulnerable", "cleanse", "knockback", "pull", "dash", "teleport", "blink", "swap",
	"projectile", "area", "beam", "zone", "trap", "summon", "delay", "repeat", "random",
	"cooldown", "text", "sound",
	"mana", "gold", "mark", "remove", "counter", "stasis", "stealth", "spellshield", "grievous",
	"untargetable", "modify_damage", "transform", "vfx", "attack_reset", "item_cooldown",
	"shield_break", "fire_event",
]
const NESTED_KEYS := ["effects", "on_hit", "on_end", "on_expire", "on_death", "options"]
const ITEM_RARITIES := ["basic", "epic", "legendary", "mythic", "boots", "starter", "consumable", "jungle", "transform"]


static func root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	return OS.get_executable_path().get_base_dir() + "/"


static func characters_dir() -> String:
	return root_dir() + "characters"


static func maps_dir() -> String:
	return root_dir() + "maps"


static func items_dir() -> String:
	return root_dir() + "items"


# ---------------------------------------------------------------- reading ---

static func read_character_packs(errors: PackedStringArray) -> Dictionary:
	var out := {}
	var base := characters_dir()
	var dir := DirAccess.open(base)
	if dir == null:
		errors.append("Characters folder not found: " + base)
		return out
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub.begins_with("_"):
			continue
		var path := base + "/" + sub
		if not FileAccess.file_exists(path + "/character.json"):
			errors.append("%s: missing character.json" % sub)
			continue
		var files := {}
		_collect(path, "", files, errors, sub)
		out[sub] = {"id": sub, "files": files}
	return out


static func _collect(abs_dir: String, rel: String, files: Dictionary, errors: PackedStringArray, label: String) -> void:
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	for f in d.get_files():
		if not ALLOWED_EXT.has(f.get_extension().to_lower()):
			continue
		var bytes := FileAccess.get_file_as_bytes(abs_dir + "/" + f)
		if bytes.size() > MAX_FILE_BYTES:
			errors.append("%s/%s%s: file too big (max 8 MB)" % [label, rel, f])
			continue
		files[rel + f] = bytes
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(abs_dir + "/" + sub, rel + sub + "/", files, errors, label)


static func read_maps(errors: PackedStringArray) -> Dictionary:
	var out := {}
	var base := maps_dir()
	var d := DirAccess.open(base)
	if d == null:
		errors.append("Maps folder not found: " + base)
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() != "json":
			continue
		var m = parse_json(FileAccess.get_file_as_bytes(base + "/" + f), "maps/" + f, errors)
		if m is Dictionary:
			out[f.get_basename()] = m
	return out


## All files of the items/ folder (json + images) as one pack, sent to clients like characters.
static func read_item_pack(errors: PackedStringArray) -> Dictionary:
	var files := {}
	if DirAccess.dir_exists_absolute(items_dir()):
		_collect(items_dir(), "", files, errors, "items")
	return {"id": "items", "files": files}


static func build_items(pack: Dictionary, errors: PackedStringArray) -> Dictionary:
	var out := {}
	var holder := {"id": "items", "pack": pack, "textures": {}}
	for f in pack.files:
		if f.get_extension().to_lower() != "json" or f.get_file().begins_with("_"):
			continue
		var raw = parse_json(pack.files[f], "items/" + f, errors)
		if not (raw is Dictionary):
			continue
		var id := str(f.get_file().get_basename())
		var it := _item(id, raw, holder, errors)
		if not it.is_empty():
			out[id] = it
	for id in out:
		for c in out[id].from:
			if not out.has(c):
				errors.append("items/%s.json: component '%s' does not exist" % [id, c])
		out[id].from = out[id].from.filter(func(c): return out.has(c))
		if out[id].get("transform_into", "") != "" and not out.has(out[id].transform_into):
			errors.append("items/%s.json: transform target '%s' does not exist" % [id, out[id].transform_into])
	# Which items each item builds into (for the shop's recipe view).
	for id in out:
		out[id].into = []
	for id in out:
		for c in out[id].from:
			if not out[c].into.has(id):
				out[c].into.append(id)
	return out


static func _item(id: String, raw: Dictionary, holder: Dictionary, errors: PackedStringArray) -> Dictionary:
	var where := "items/%s.json" % id
	var it := {"id": id}
	it.name = str(raw.get("name", id.capitalize()))
	it.cost = int(raw.get("cost", 0))
	it.from = []
	var fr = raw.get("from", [])
	if fr is Array:
		for c in fr:
			it.from.append(str(c))
	it.rarity = str(raw.get("rarity", "legendary"))
	if not ITEM_RARITIES.has(it.rarity):
		errors.append("%s: unknown rarity '%s'" % [where, it.rarity])
	it.tags = raw.get("tags", []) if raw.get("tags") is Array else []
	it.description = str(raw.get("description", ""))
	it.groups = []
	var g = raw.get("group", [])
	if g is String and g != "":
		it.groups.append(g)
	elif g is Array:
		for x in g:
			it.groups.append(str(x))
	it.limit = int(raw.get("limit", 1 if it.rarity in ["legendary", "mythic", "boots", "jungle"] else 0))
	it.stack = maxi(int(raw.get("stack", 1)), 1)
	it.charges = maxi(int(raw.get("charges", 0)), 0)
	it.refill = bool(raw.get("refill", it.charges > 0))
	it.min_level = int(raw.get("min_level", 0))
	it.display = raw.get("display") if raw.get("display") is String or raw.get("display") is float or raw.get("display") is int else null
	it.consumable = bool(raw.get("consumable", it.rarity == "consumable"))
	it.buyable = bool(raw.get("buyable", it.rarity != "transform"))
	it.transform_into = str(raw.get("transform_into", ""))
	it.color = parse_color(raw.get("color"), _item_color(it))
	it.short = str(raw.get("short", _abbrev(it.name)))
	it.stats = {}
	it.stats_mult = {}
	it.mythic_stats = {}
	it.dynamic = false
	for pair in [["stats", it.stats], ["stats_mult", it.stats_mult], ["mythic_stats", it.mythic_stats]]:
		var src = raw.get(pair[0], {})
		if not (src is Dictionary):
			continue
		for k in src:
			var v = src[k]
			if v is float or v is int:
				pair[1][k] = float(v)
			elif v is String:
				pair[1][k] = v
				it.dynamic = true
			else:
				errors.append("%s: %s.%s must be a number or an expression" % [where, pair[0], k])
	it.passives = []
	var ps = raw.get("passives", [])
	if ps is Dictionary:
		ps = [ps]
	if ps is Array:
		for p in ps:
			if p is Dictionary:
				it.passives.append(p)
				_validate(p.get("effects", []), "%s passive '%s'" % [where, p.get("name", "?")], errors)
	it.active = null
	var a = raw.get("active")
	if a is Dictionary:
		var ab := _ability(a, "item", {"id": id, "pack": holder.pack, "textures": holder.textures}, errors)
		ab.cooldown = a.get("cooldown", 60.0)
		ab.consume = bool(a.get("consume", it.consumable))
		it.active = ab
	it.icon = texture(holder, raw.icon) if raw.has("icon") else null
	return it


static func _item_color(it: Dictionary) -> Color:
	var tags: Array = it.tags
	if tags.has("SpellDamage"):
		return Color(0.55, 0.45, 1.0)
	if tags.has("CriticalStrike") or tags.has("AttackSpeed"):
		return Color(1.0, 0.78, 0.3)
	if tags.has("Damage"):
		return Color(1.0, 0.45, 0.3)
	if tags.has("Armor") or tags.has("SpellBlock"):
		return Color(0.55, 0.8, 0.95)
	if tags.has("Health"):
		return Color(0.45, 0.9, 0.45)
	if tags.has("ManaRegen") or tags.has("Mana"):
		return Color(0.35, 0.6, 1.0)
	return Color(0.75, 0.75, 0.8)


static func _abbrev(n: String) -> String:
	var out := ""
	for w in n.replace("'", "").replace("-", " ").split(" ", false):
		if w.to_lower() in ["of", "the", "s"]:
			continue
		out += w.substr(0, 1).to_upper()
	return out.substr(0, 3)


## Parses JSON with readable errors. Lines starting with // are treated as comments.
static func parse_json(bytes, label: String, errors: PackedStringArray):
	if bytes == null or (bytes is PackedByteArray and bytes.is_empty()):
		errors.append(label + ": file not found or empty")
		return null
	var text: String = bytes.get_string_from_utf8() if bytes is PackedByteArray else str(bytes)
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].strip_edges().begins_with("//"):
			lines[i] = ""
	var j := JSON.new()
	if j.parse("\n".join(lines)) != OK:
		errors.append("%s: JSON error on line %d: %s" % [label, j.get_error_line(), j.get_error_message()])
		return null
	return j.data


# --------------------------------------------------------------- building ---

static func build_character(pack: Dictionary, errors: PackedStringArray):
	var id: String = pack.id
	var files: Dictionary = pack.files
	var raw = parse_json(files.get("character.json"), id + "/character.json", errors)
	if not (raw is Dictionary):
		if raw != null:
			errors.append(id + "/character.json: top level must be an object { ... }")
		return null
	var def := {"id": id, "pack": pack, "textures": {}}
	def.name = str(raw.get("name", id.capitalize()))
	def.title = str(raw.get("title", ""))
	def.description = str(raw.get("description", ""))
	def.color = parse_color(raw.get("color"), hash_color(id))

	var stats := DEFAULT_STATS.duplicate()
	var rs = raw.get("stats", {})
	if rs is Dictionary:
		for k in rs:
			if rs[k] is float or rs[k] is int:
				stats[k] = float(rs[k])
			else:
				errors.append("%s: stat '%s' must be a number" % [id, k])
	def.stats = stats

	var per_level := DEFAULT_PER_LEVEL.duplicate()
	var pl = raw.get("per_level", {})
	if pl is Dictionary:
		for k in pl:
			per_level[k] = float(pl[k])
	def.per_level = per_level

	var atk = raw.get("attack", {})
	if not (atk is Dictionary):
		atk = {}
	var ranged := bool(atk.get("ranged", stats.attack_range > 200.0))
	def.attack = {
		"ranged": ranged,
		"speed": float(atk.get("projectile_speed", 1100.0)),
		"color": parse_color(atk.get("projectile_color"), def.color.lightened(0.3)),
		"size": float(atk.get("projectile_size", 7.0)),
		"sprite": str(atk.get("projectile_sprite", "")),
		"hit_vfx": str(atk.get("hit_vfx", "")),
		"on_hit": atk.get("on_hit", []),
		"char": id,
	}
	_validate(def.attack.on_hit, id + " attack.on_hit", errors)

	var passive = raw.get("passive", null)
	if passive is Dictionary:
		var p := {
			"name": str(passive.get("name", "Passive")),
			"description": str(passive.get("description", "")),
			"triggers": [],
			"icon": null,
		}
		var trig = passive.get("triggers", [])
		if trig is Dictionary:
			trig = [trig]
		if trig is Array:
			for t in trig:
				if t is Dictionary:
					p.triggers.append(t)
					_validate(t.get("effects", []), "%s passive (%s)" % [id, t.get("on", "?")], errors)
		if passive.has("icon"):
			p.icon = texture(def, passive.icon)
		def.passive = p
	else:
		def.passive = {"name": "No passive", "description": "", "triggers": [], "icon": null}

	def.abilities = {}
	var abilities = raw.get("abilities", {})
	if not (abilities is Dictionary):
		abilities = {}
	for slot in SLOTS:
		var a = abilities.get(slot)
		if a is String:
			var fname := "abilities/%s.json" % a
			a = parse_json(files.get(fname), id + "/" + fname, errors)
		if a is Dictionary:
			def.abilities[slot] = _ability(a, slot, def, errors)

	def.portrait = texture(def, raw.get("portrait", "portrait.png"), true)
	def.sprite = _sprite(raw.get("sprite"), def, errors)
	return def


static func _ability(a: Dictionary, slot: String, def: Dictionary, errors: PackedStringArray) -> Dictionary:
	var ab := a.duplicate(true)
	ab.slot = slot
	ab.name = str(a.get("name", slot.to_upper()))
	ab.description = str(a.get("description", ""))
	ab.cooldown = a.get("cooldown", 6.0)
	ab.targeting = str(a.get("targeting", "direction"))
	ab.range = a.get("range", 700.0)
	ab.cast_time = a.get("cast_time", 0.0)
	ab.cost = a.get("cost", 0.0)
	ab.cost_type = str(a.get("cost_type", "mana"))
	ab.max_rank = int(a.get("max_rank", 3 if slot == "r" else 5))
	var ul = a.get("unlock_levels", [6, 11, 16] if slot == "r" else [1, 3, 5, 7, 9])
	ab.unlock_levels = ul if ul is Array else [1, 3, 5, 7, 9]
	# Abilities without any per-rank values get stronger automatically with rank.
	ab.auto_rank = bool(a.get("auto_rank", not _has_rank_values(a)))
	var effects = a.get("effects", [])
	if effects is Dictionary:
		effects = [effects]
	ab.effects = effects
	ab.icon = texture(def, a.icon) if a.has("icon") else null
	if not ab.targeting in ["direction", "point", "self", "unit", "ally"]:
		errors.append("%s %s: unknown targeting '%s' (use direction, point, self, unit or ally)" % [def.id, slot, ab.targeting])
	_validate(effects, "%s %s (%s)" % [def.id, slot.to_upper(), ab.name], errors)
	# Indicator hint: radius of the first area/zone effect, if any.
	ab.indicator_radius = _find_radius(effects)
	ab.indicator = _indicator(effects)
	return ab


## True if an ability uses per-rank arrays ([60, 90, 120, ...]) or the `rank` variable anywhere.
static func _has_rank_values(v) -> bool:
	if v is Dictionary:
		for k in v:
			if k in ["color", "offset", "unlock_levels"]:
				continue
			if _has_rank_values(v[k]):
				return true
	elif v is Array:
		if not v.is_empty() and (v[0] is float or v[0] is int):
			return true
		for x in v:
			if _has_rank_values(x):
				return true
	elif v is String:
		return v.contains("rank")
	return false


## Describes how to draw the aiming indicator, from the ability's first effect.
static func _indicator(list) -> Dictionary:
	if not (list is Array):
		return {}
	for e in list:
		if not (e is Dictionary):
			continue
		match str(e.get("type", "")):
			"projectile":
				var count := int(_n(e.get("count"), 1.0))
				return {"shape": "line", "width": _n(e.get("radius"), 12.0) * 2.0, "count": count,
					"spread": _n(e.get("spread"), 0.0 if count == 1 else 30.0)}
			"beam":
				return {"shape": "line", "width": _n(e.get("width"), 70.0), "count": 1, "spread": 0.0}
			"dash":
				return {"shape": "dash", "length": _n(e.get("distance"), 350.0), "radius": _find_radius(e.get("on_end"))}
			"area":
				var r := _n(e.get("radius"), 150.0) + _n(e.get("scatter"), 0.0)
				if _n(e.get("angle"), 360.0) < 359.0:
					return {"shape": "cone", "radius": r, "angle": _n(e.get("angle"), 90.0)}
				return {"shape": "self" if str(e.get("at", "pos")) == "self" else "circle", "radius": r}
			"zone", "trap":
				return {"shape": "circle", "radius": _n(e.get("radius"), 150.0)}
			"teleport", "blink":
				return {"shape": "circle", "radius": 30.0}
			"repeat", "delay":
				var inner := _indicator(e.get("effects"))
				if not inner.is_empty():
					return inner
	return {}


static func _n(v, def: float) -> float:
	if v is Array and not v.is_empty():
		v = v[v.size() - 1]
	return float(v) if v is float or v is int else def


static func _find_radius(list) -> float:
	if not (list is Array):
		return 0.0
	for e in list:
		if e is Dictionary:
			if e.get("type") in ["area", "zone", "trap"] and _n(e.get("radius"), 0.0) > 0.0:
				return _n(e.get("radius"), 0.0)
			for k in ["effects", "on_end"]:
				var r := _find_radius(e.get(k))
				if r > 0.0:
					return r
	return 0.0


static func _validate(list, where: String, errors: PackedStringArray) -> void:
	if list == null:
		return
	if list is Dictionary:
		list = [list]
	if not (list is Array):
		errors.append(where + ": expected a list of effects [ ... ]")
		return
	for e in list:
		if not (e is Dictionary):
			errors.append(where + ": every effect must be an object { \"type\": ... }")
			continue
		var t := str(e.get("type", ""))
		if not EFFECT_TYPES.has(t):
			errors.append("%s: unknown effect type '%s'" % [where, t])
		if e.get("triggers") is Array:
			for tr in e.triggers:
				if tr is Dictionary:
					_validate(tr.get("effects", []), where + " > triggers", errors)
		for k in NESTED_KEYS:
			if e.has(k):
				if k == "options" and e[k] is Array:
					for o in e[k]:
						_validate(o, where + " > " + t, errors)
				else:
					_validate(e[k], where + " > " + t, errors)


static func _sprite(spec, def: Dictionary, errors: PackedStringArray):
	if spec == null:
		if def.pack.files.has("sprite.png"):
			spec = "sprite.png"
		else:
			return null
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	var scale := 1.0
	var offset := Vector2.ZERO
	var faces_left := false
	if spec is String:
		var tex := texture(def, spec)
		if tex == null:
			errors.append("%s: sprite '%s' not found" % [def.id, spec])
			return null
		frames.add_animation("idle")
		frames.add_frame("idle", tex)
		scale = (BASE_RADIUS * 2.6) / max(tex.get_width(), tex.get_height())
	elif spec is Dictionary:
		var sheet := texture(def, spec.get("sheet", "spritesheet.png"))
		if sheet == null:
			errors.append("%s: sprite sheet '%s' not found" % [def.id, spec.get("sheet", "spritesheet.png")])
			return null
		var fw := int(spec.get("frame_width", sheet.get_width()))
		var fh := int(spec.get("frame_height", sheet.get_height()))
		var cols: int = max(1, sheet.get_width() / max(fw, 1))
		var anims = spec.get("animations", {"idle": {"row": 0, "frames": 1}})
		for anim_name in anims:
			var a = anims[anim_name]
			if not (a is Dictionary):
				continue
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, float(a.get("fps", 8.0)))
			frames.set_animation_loop(anim_name, bool(a.get("loop", anim_name in ["idle", "walk"])))
			var first := int(a.get("row", 0)) * cols + int(a.get("start", 0))
			for i in int(a.get("frames", 1)):
				var idx := first + i
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2((idx % cols) * fw, (idx / cols) * fh, fw, fh)
				frames.add_frame(anim_name, at)
		if not frames.has_animation("idle"):
			errors.append(def.id + ": sprite needs at least an 'idle' animation")
			return null
		scale = float(spec.get("scale", (BASE_RADIUS * 2.6) / max(fw, fh)))
		var off = spec.get("offset", [0, 0])
		if off is Array and off.size() == 2:
			offset = Vector2(off[0], off[1])
		faces_left = bool(spec.get("faces_left", false))
	else:
		return null
	return {"frames": frames, "scale": scale, "offset": offset, "faces_left": faces_left}


## Returns a texture from a character's folder (cached). `quiet` skips nothing-found errors.
static func texture(def: Dictionary, rel, _quiet := false) -> Texture2D:
	if def == null or rel == null or str(rel) == "":
		return null
	var key := str(rel)
	if def.textures.has(key):
		return def.textures[key]
	var tex: Texture2D = null
	var bytes = def.pack.files.get(key)
	if bytes is PackedByteArray:
		var img := Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		match key.get_extension().to_lower():
			"png": err = img.load_png_from_buffer(bytes)
			"jpg", "jpeg": err = img.load_jpg_from_buffer(bytes)
			"webp": err = img.load_webp_from_buffer(bytes)
			"bmp": err = img.load_bmp_from_buffer(bytes)
			"svg": err = img.load_svg_from_buffer(bytes)
		if err == OK:
			tex = ImageTexture.create_from_image(img)
	def.textures[key] = tex
	return tex


static func char_texture(char_id: String, rel) -> Texture2D:
	var def = Game.characters.get(char_id)
	if def == null:
		return null
	return texture(def, rel)


static func parse_color(v, fallback: Color) -> Color:
	if v is String and v != "":
		return Color.from_string(v, fallback)
	if v is Array and v.size() >= 3:
		return Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
	return fallback


static func hash_color(s: String) -> Color:
	return Color.from_hsv(float(abs(s.hash()) % 360) / 360.0, 0.55, 0.9)
