extends RefCounted
class_name ArboriaGeometryValidator

static func validate_obj_text(lines: PackedStringArray) -> Dictionary:
	var errors := PackedStringArray()
	var vertex_count := 0
	var uv_count := 0
	var normal_count := 0
	var triangle_count := 0
	for line_number in range(lines.size()):
		var trimmed := lines[line_number].strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		var parts := trimmed.split(" ", false)
		if parts.is_empty(): continue
		match parts[0]:
			"v":
				if parts.size() < 4 or not _finite_numbers(parts, 1, 3):
					errors.append("line %d: malformed or non-finite vertex" % (line_number + 1))
				else: vertex_count += 1
			"vt":
				if parts.size() < 3 or not _finite_numbers(parts, 1, 2): errors.append("line %d: malformed or non-finite UV" % (line_number + 1))
				else: uv_count += 1
			"vn":
				if parts.size() < 4 or not _finite_numbers(parts, 1, 3): errors.append("line %d: malformed or non-finite normal" % (line_number + 1))
				else: normal_count += 1
			"f":
				if parts.size() != 4:
					errors.append("line %d: Baker intermediate requires triangulated faces" % (line_number + 1))
				else:
					var face_valid := true
					for i in range(1, 4):
						var refs := parts[i].split("/")
						if refs.size() != 3 or not _positive_integer(refs[0]) or not _positive_integer(refs[1]) or not _positive_integer(refs[2]):
							face_valid = false
							break
						if int(refs[0]) > vertex_count or int(refs[1]) > uv_count or int(refs[2]) > normal_count:
							face_valid = false
							break
					if face_valid:
						triangle_count += 1
					else:
						errors.append("line %d: face references invalid vertex/UV/normal" % (line_number + 1))
	if vertex_count == 0: errors.append("no vertices")
	if triangle_count == 0: errors.append("no valid triangles")
	return {"valid": errors.is_empty(), "errors": errors, "vertices": vertex_count, "uvs": uv_count, "normals": normal_count, "triangles": triangle_count}

static func _positive_integer(value: String) -> bool:
	if value.is_empty():
		return false
	for character in value:
		if not character.is_valid_int() or character == "+" or character == "-":
			return false
	return int(value) > 0

static func _finite_numbers(parts: PackedStringArray, start: int, count: int) -> bool:
	for i in range(start, start + count):
		if i >= parts.size() or not parts[i].is_valid_float():
			return false
		var value := float(parts[i])
		if is_nan(value) or is_inf(value):
			return false
	return true
