extends RefCounted

const MAX_BYTES := 8 * 1024 * 1024
const MAX_JSON_BYTES := 128 * 1024
const MAX_FILES := 64
const MAX_DEPTH := 4
const MAX_PIXELS := 12 * 1024 * 1024
const EXTENSIONS := ["json", "png", "webp"]


static func read_folder(path: String) -> Dictionary:
	var id := path.trim_suffix("/").get_file()
	if not _valid_id(id):
		return {"error": "Use a folder name starting with a letter or digit and containing only letters, digits, _ or - (up to 48 characters)."}
	var files := {}
	var error := _collect(path, "", files, [MAX_BYTES], 0)
	if not error.is_empty():
		return {"error": error}
	return {"id": id, "files": files}


static func _collect(path: String, prefix: String, files: Dictionary, budget: Array, depth: int) -> String:
	var dir := DirAccess.open(path)
	if dir == null:
		return "Could not open the character folder."
	for name in dir.get_files():
		var ext := name.get_extension().to_lower()
		if not ext in EXTENSIONS or name.begins_with("."):
			continue
		var rel := prefix + name
		if dir.is_link(name) or not _valid_path(rel):
			return "Invalid file path in character folder: " + rel
		if files.size() >= MAX_FILES:
			return "A suggestion can include at most %d files." % MAX_FILES
		var file := FileAccess.open(path.path_join(name), FileAccess.READ)
		if file == null:
			return "Could not read " + rel
		var size := file.get_length()
		if size <= 0 or size > int(budget[0]) or (ext == "json" and size > MAX_JSON_BYTES):
			return "Empty file or upload size limit exceeded at " + rel
		var bytes := file.get_buffer(size)
		if bytes.size() != size:
			return "Could not read all of " + rel
		files[rel] = bytes
		budget[0] -= size
	for name in dir.get_directories():
		if name.begins_with(".") or dir.is_link(name) or depth >= MAX_DEPTH:
			continue
		var error := _collect(path.path_join(name), prefix + name + "/", files, budget, depth + 1)
		if not error.is_empty():
			return error
	return ""


static func inspect(id: String, files: Dictionary) -> Dictionary:
	if not _valid_id(id) or files.is_empty() or files.size() > MAX_FILES or not files.has("character.json"):
		return {"error": "Choose a character folder with a valid folder name and a character.json file."}
	var remaining := MAX_BYTES
	var pixels := 0
	var documents := {}
	for path in files:
		if not path is String or not _valid_path(path) or not files[path] is PackedByteArray:
			return {"error": "Invalid file in character suggestion."}
		var bytes: PackedByteArray = files[path]
		var ext: String = path.get_extension().to_lower()
		if bytes.is_empty() or bytes.size() > remaining or (ext == "json" and bytes.size() > MAX_JSON_BYTES):
			return {"error": "Empty file or upload size limit exceeded at " + path}
		remaining -= bytes.size()
		if ext == "json":
			var errors := PackedStringArray()
			var raw = Content.parse_json(bytes, path, errors)
			if not raw is Dictionary or not _valid_json(raw):
				return {"error": "Invalid or overly complex JSON in " + path}
			documents[path] = raw
		else:
			var size := _image_size(bytes, ext)
			pixels += size.x * size.y
			if size.x < 1 or size.y < 1 or size.x > 4096 or size.y > 4096 or pixels > MAX_PIXELS:
				return {"error": "Invalid image or image size limit exceeded at " + path}
	var raw: Dictionary = documents["character.json"]
	if not _valid_character_fields(raw):
		return {"error": "Invalid stats, color, attack or sprite fields in character.json."}
	var abilities = raw.get("abilities", {})
	if not abilities is Dictionary:
		return {"error": "Character abilities must be an object."}
	var names := PackedStringArray()
	for slot in Content.SLOTS:
		if not abilities.has(slot):
			continue
		var ability = abilities[slot]
		if ability is String:
			ability = documents.get("abilities/%s.json" % ability)
		if not ability is Dictionary or not _valid_ability_fields(ability):
			return {"error": "Missing or invalid ability for %s." % slot.to_upper()}
		names.append("%s: %s" % [slot.to_upper(), str(ability.get("name", slot.to_upper())).left(72)])
	return {
		"name": str(raw.get("name", id)).replace("\n", " ").left(72),
		"title": str(raw.get("title", "")).left(120),
		"description": str(raw.get("description", "")).left(400),
		"abilities": "\n".join(names),
	}


static func _valid_id(id: String) -> bool:
	return not id.is_empty() and id.length() <= 48 and not id.begins_with("_") and not id.begins_with("-") \
		and ("a" + id.replace("-", "_")).is_valid_ascii_identifier()


static func _valid_path(path: String) -> bool:
	if path.length() > 180 or path.contains("\\") or path.contains(":") or not path.get_extension().to_lower() in EXTENSIONS:
		return false
	var parts := path.split("/")
	if parts.size() > MAX_DEPTH + 1:
		return false
	for part in parts:
		if part.is_empty() or part.begins_with("."):
			return false
		for ch in part:
			if ch.unicode_at(0) < 32:
				return false
	return true


static func _valid_json(value, depth := 0) -> bool:
	if depth > 20:
		return false
	if value is Dictionary:
		if value.size() > 256:
			return false
		for k in value:
			if not _valid_json(k, depth + 1) or not _valid_json(value[k], depth + 1):
				return false
	elif value is Array:
		if value.size() > 256:
			return false
		for item in value:
			if not _valid_json(item, depth + 1):
				return false
	elif value is String:
		# Pack strings can reach BBCode labels. Never accept embedded resource tags.
		return value.length() <= 4096 and not value.containsn("[img")
	elif value is float:
		return is_finite(value) and absf(value) <= 1.0e9
	return true


static func _valid_character_fields(raw: Dictionary) -> bool:
	for key in ["stats", "per_level"]:
		var stats = raw.get(key, {})
		if not stats is Dictionary:
			return false
		for value in stats.values():
			if not _is_number(value):
				return false
	var attack = raw.get("attack", {})
	if not attack is Dictionary or not _valid_color(raw.get("color")) or not _valid_color(attack.get("projectile_color")):
		return false
	if not _is_number(attack.get("projectile_speed", 1100)) or not _is_number(attack.get("projectile_size", 7)):
		return false
	var sprite = raw.get("sprite")
	if not sprite is Dictionary:
		return sprite == null or sprite is String
	var offset = sprite.get("offset", [0, 0])
	if not offset is Array or offset.size() != 2 or not _is_number(offset[0]) or not _is_number(offset[1]):
		return false
	for key in ["frame_width", "frame_height", "scale"]:
		var value = sprite.get(key, 1)
		if not _is_number(value) or value <= 0 or value > 4096 or (key != "scale" and value < 1):
			return false
	var animations = sprite.get("animations", {"idle": {}})
	if not animations is Dictionary or animations.size() > 32:
		return false
	for anim in animations.values():
		if not anim is Dictionary:
			return false
		for key in ["row", "start", "frames", "fps"]:
			var value = anim.get(key, 1)
			if not _is_number(value) or value < (1 if key == "frames" else 0) or value > 256:
				return false
	return true


static func _valid_ability_fields(ability: Dictionary) -> bool:
	var ranks = ability.get("max_rank", 1)
	if not _is_number(ranks) or ranks < 1 or ranks > 21:
		return false
	var levels = ability.get("unlock_levels", [])
	if not levels is Array:
		return false
	for level in levels:
		if not _is_number(level):
			return false
	return not ability.has("recast") or (ability.recast is Dictionary and _valid_ability_fields(ability.recast))


static func _valid_color(color) -> bool:
	if color == null or color is String:
		return true
	if not color is Array or color.size() not in [3, 4]:
		return false
	for channel in color:
		if not _is_number(channel):
			return false
	return true


static func _is_number(value) -> bool:
	return value is float or value is int


static func build(pack: Dictionary, errors: PackedStringArray):
	var files: Dictionary = pack.files
	for path in files:
		var ext: String = path.get_extension().to_lower()
		if ext == "json":
			continue
		var image := Image.new()
		var bytes: PackedByteArray = files[path]
		var result := image.load_png_from_buffer(bytes) if ext == "png" else image.load_webp_from_buffer(bytes)
		if result != OK or image.get_size() != _image_size(bytes, ext):
			errors.append("Could not decode " + path)
			return null
	return Content.build_character(pack, errors)


static func _image_size(bytes: PackedByteArray, ext: String) -> Vector2i:
	if ext == "png":
		if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) \
				or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
			return Vector2i.ZERO
		return Vector2i(_big_endian_32(bytes, 16), _big_endian_32(bytes, 20))
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WEBP":
		return Vector2i.ZERO
	match bytes.slice(12, 16).get_string_from_ascii():
		"VP8 ":
			if bytes.size() >= 30 and bytes.slice(23, 26) == PackedByteArray([157, 1, 42]):
				return Vector2i(bytes.decode_u16(26) & 0x3fff, bytes.decode_u16(28) & 0x3fff)
		"VP8L":
			if bytes.size() >= 25 and bytes[20] == 0x2f:
				var bits := bytes.decode_u32(21)
				return Vector2i((bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1)
		"VP8X":
			if bytes.size() >= 30 and not (bytes[20] & 2): # No animated WebP.
				return Vector2i(1 + (bytes.decode_u32(24) & 0xffffff), 1 + (bytes.decode_u16(27) | (bytes[29] << 16)))
	return Vector2i.ZERO


static func _big_endian_32(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]
