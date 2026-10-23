extends RefCounted
class_name ArboriaMeshLoader

# Carrega e decodifica arquivo binario .vgmesh gerado pelo Baker C++
static func load_from_file(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		if file_path.begins_with("res://assets/"):
			var fname = file_path.trim_prefix("res://assets/")
			var search_names = [fname]
			if fname == "dense_rock_test.vgmesh" or fname == "dense_rock_verified.vgmesh":
				search_names.append("dense_rock.vgmesh")
			for sn in search_names:
				var candidate_paths = [
					"res://../assets/" + sn,
					ProjectSettings.globalize_path("res://../assets/" + sn),
					ProjectSettings.globalize_path("res://assets/" + sn)
				]
				for cp in candidate_paths:
					file = FileAccess.open(cp, FileAccess.READ)
					if file:
						break
				if file:
					break
	if not file:
		push_error("Falha ao abrir arquivo: " + file_path)
		return {}

	var magic_buf = file.get_buffer(8)
	var magic = magic_buf.get_string_from_utf8()
	if magic != "ARBORIA2" and magic != "ARBORIA1":
		push_error("Magic invalido no arquivo .vgmesh: " + magic)
		return {}

	var version = file.get_32()
	var total_vertices = file.get_32()
	var total_indices = file.get_32()
	var total_triangles = file.get_32()
	var cluster_count = file.get_32()
	var lod_count = file.get_32()

	var bbox_min = Vector3(file.get_float(), file.get_float(), file.get_float())
	var bbox_max = Vector3(file.get_float(), file.get_float(), file.get_float())
	var group_count = file.get_32()
	var base_triangles = file.get_32()
	var _res0 = file.get_32()
	var _res1 = file.get_32()

	var lods = []
	if magic == "ARBORIA2":
		for i in range(lod_count):
			var lod_desc = {
				"lod_level": file.get_32(),
				"cluster_offset": file.get_32(),
				"cluster_count": file.get_32(),
				"triangle_count": file.get_32(),
				"max_error": file.get_float(),
				"triangle_ratio": file.get_float()
			}
			lods.append(lod_desc)
	else:
		lods.append({
			"lod_level": 0,
			"cluster_offset": 0,
			"cluster_count": cluster_count,
			"triangle_count": total_triangles,
			"max_error": 0.0,
			"triangle_ratio": 1.0
		})

	var clusters = []
	for i in range(cluster_count):
		var c = {}
		c["cluster_id"] = file.get_32()
		c["lod_level"] = file.get_32()
		if magic == "ARBORIA2":
			c["group_id"] = file.get_32()
			c["refined_group"] = file.get_32()
		else:
			c["group_id"] = 0
			c["refined_group"] = -1
		c["center"] = Vector3(file.get_float(), file.get_float(), file.get_float())
		c["radius"] = file.get_float()
		c["normal_cone"] = [file.get_float(), file.get_float(), file.get_float(), file.get_float()]
		c["lod_error"] = file.get_float()
		c["vertex_offset"] = file.get_32()
		c["vertex_count"] = file.get_32()
		c["triangle_offset"] = file.get_32()
		c["triangle_count"] = file.get_32()
		clusters.append(c)

	var groups = []
	if magic == "ARBORIA2" and group_count > 0:
		for i in range(group_count):
			var g = {
				"group_id": file.get_32(),
				"depth": file.get_32(),
				"center": Vector3(file.get_float(), file.get_float(), file.get_float()),
				"radius": file.get_float(),
				"error": file.get_float()
			}
			groups.append(g)

	# Leitura do Vertex Buffer (32 bytes por vertice)
	var v_bytes = file.get_buffer(total_vertices * 32)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()

	vertices.resize(total_vertices)
	normals.resize(total_vertices)
	uvs.resize(total_vertices)

	for vi in range(total_vertices):
		var offset = vi * 32
		var px = v_bytes.decode_float(offset)
		var py = v_bytes.decode_float(offset + 4)
		var pz = v_bytes.decode_float(offset + 8)
		var nx = v_bytes.decode_float(offset + 12)
		var ny = v_bytes.decode_float(offset + 16)
		var nz = v_bytes.decode_float(offset + 20)
		var u  = v_bytes.decode_float(offset + 24)
		var v  = v_bytes.decode_float(offset + 28)

		vertices[vi] = Vector3(px, py, pz)
		normals[vi] = Vector3(nx, ny, nz)
		uvs[vi] = Vector2(u, v)

	# Leitura do Triangle Index Buffer (uint8_t)
	var triangle_bytes = file.get_buffer(total_triangles * 3)

	return {
		"magic": magic,
		"version": version,
		"bbox_min": bbox_min,
		"bbox_max": bbox_max,
		"lods": lods,
		"clusters": clusters,
		"groups": groups,
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"triangle_bytes": triangle_bytes,
		"base_triangles": base_triangles
	}

# Gera cor distinta e estavel para visualizacao de cada cluster
static func get_cluster_color(cluster_id: int) -> Color:
	var hue = fmod(float(cluster_id) * 0.618033988749895, 1.0)
	return Color.from_hsv(hue, 0.85, 0.95)

# Constroi o ArrayMesh para o LOD solicitado ou cluster isolado
static func build_mesh_surface(vg_data: Dictionary, target_lod: int, color_clusters: bool = true, isolate_cluster_id: int = -1) -> ArrayMesh:
	if vg_data.is_empty():
		return null

	var clusters = vg_data["clusters"]
	var vertices = vg_data["vertices"]
	var normals = vg_data["normals"]
	var uvs = vg_data["uvs"]
	var tri_bytes: PackedByteArray = vg_data["triangle_bytes"]

	var out_verts = PackedVector3Array()
	var out_norms = PackedVector3Array()
	var out_uvs = PackedVector2Array()
	var out_colors = PackedColorArray()
	var out_indices = PackedInt32Array()

	var vert_base_index = 0

	for c in clusters:
		if isolate_cluster_id >= 0:
			if c["cluster_id"] != isolate_cluster_id:
				continue
		else:
			if c["lod_level"] != target_lod:
				continue

		var c_color = get_cluster_color(c["cluster_id"]) if color_clusters else Color(1, 1, 1, 1)

		# Adiciona vertices do cluster
		var v_start = c["vertex_offset"]
		var v_count = c["vertex_count"]

		for vi in range(v_count):
			var global_v_idx = v_start + vi
			out_verts.append(vertices[global_v_idx])
			out_norms.append(normals[global_v_idx])
			out_uvs.append(uvs[global_v_idx])
			out_colors.append(c_color)

		# Adiciona indices dos triangulos do cluster
		var t_start = c["triangle_offset"]
		var t_count = c["triangle_count"]

		for ti in range(t_count * 3):
			var local_idx = tri_bytes[t_start + ti]
			out_indices.append(vert_base_index + local_idx)

		vert_base_index += v_count

	if out_verts.is_empty():
		return null

	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = out_verts
	surface_array[Mesh.ARRAY_NORMAL] = out_norms
	surface_array[Mesh.ARRAY_TEX_UV] = out_uvs
	surface_array[Mesh.ARRAY_COLOR] = out_colors
	surface_array[Mesh.ARRAY_INDEX] = out_indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	return mesh

# Carregador comparativo do OBJ original para verificacao lado a lado
static func load_original_obj(obj_path: String) -> ArrayMesh:
	var file = FileAccess.open(obj_path, FileAccess.READ)
	if not file:
		return null

	var positions = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()

	var out_verts = PackedVector3Array()
	var out_norms = PackedVector3Array()
	var out_uvs = PackedVector2Array()
	var out_indices = PackedInt32Array()

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		var tokens = line.split(" ", false)
		if tokens.is_empty():
			continue

		var prefix = tokens[0]
		if prefix == "v" and tokens.size() >= 4:
			positions.append(Vector3(tokens[1].to_float(), tokens[2].to_float(), tokens[3].to_float()))
		elif prefix == "vn" and tokens.size() >= 4:
			normals.append(Vector3(tokens[1].to_float(), tokens[2].to_float(), tokens[3].to_float()))
		elif prefix == "vt" and tokens.size() >= 3:
			uvs.append(Vector2(tokens[1].to_float(), tokens[2].to_float()))
		elif prefix == "f" and tokens.size() >= 4:
			for i in range(1, tokens.size() - 1):
				var f_tokens = [tokens[0+1], tokens[i], tokens[i+1]]
				for vt in f_tokens:
					var parts = vt.split("/")
					var p_idx = parts[0].to_int() - 1
					var t_idx = parts[1].to_int() - 1 if parts.size() > 1 and not parts[1].is_empty() else 0
					var n_idx = parts[2].to_int() - 1 if parts.size() > 2 and not parts[2].is_empty() else 0

					var v_pos = positions[p_idx] if p_idx >= 0 and p_idx < positions.size() else Vector3.ZERO
					var v_norm = normals[n_idx] if n_idx >= 0 and n_idx < normals.size() else Vector3.UP
					var v_uv = uvs[t_idx] if t_idx >= 0 and t_idx < uvs.size() else Vector2.ZERO

					out_indices.append(out_verts.size())
					out_verts.append(v_pos)
					out_norms.append(v_norm)
					out_uvs.append(v_uv)

	if out_verts.is_empty():
		return null

	var surface_array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = out_verts
	surface_array[Mesh.ARRAY_NORMAL] = out_norms
	surface_array[Mesh.ARRAY_TEX_UV] = out_uvs
	surface_array[Mesh.ARRAY_INDEX] = out_indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	return mesh

# Constroi malha de arestas de wireframe (PRIMITIVE_LINES)
static func build_wireframe_mesh(vg_data: Dictionary, target_lod: int, isolate_cluster_id: int = -1) -> ArrayMesh:
	if vg_data.is_empty():
		return null

	var clusters = vg_data["clusters"]
	var vertices = vg_data["vertices"]
	var tri_bytes: PackedByteArray = vg_data["triangle_bytes"]

	var out_verts = PackedVector3Array()
	var out_indices = PackedInt32Array()
	var vert_base = 0

	for c in clusters:
		if isolate_cluster_id >= 0 and c["cluster_id"] != isolate_cluster_id:
			continue
		elif isolate_cluster_id < 0 and c["lod_level"] != target_lod:
			continue

		var v_start = c["vertex_offset"]
		var v_count = c["vertex_count"]
		for vi in range(v_count):
			out_verts.append(vertices[v_start + vi])

		var t_start = c["triangle_offset"]
		var t_count = c["triangle_count"]
		for ti in range(t_count):
			var idx0 = vert_base + tri_bytes[t_start + ti * 3 + 0]
			var idx1 = vert_base + tri_bytes[t_start + ti * 3 + 1]
			var idx2 = vert_base + tri_bytes[t_start + ti * 3 + 2]

			# 3 arestas por triangulo
			out_indices.append(idx0)
			out_indices.append(idx1)
			out_indices.append(idx1)
			out_indices.append(idx2)
			out_indices.append(idx2)
			out_indices.append(idx0)

		vert_base += v_count

	if out_verts.is_empty():
		return null

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_verts
	arrays[Mesh.ARRAY_INDEX] = out_indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

static var _shape_cache: Dictionary = {}

static func get_cached_convex_shape(file_path: String, vg_data: Dictionary = {}) -> ConvexPolygonShape3D:
	var key = file_path + ":convex"
	if _shape_cache.has(key):
		return _shape_cache[key]
	
	var data = vg_data
	if not (data.has("vertices") and data["vertices"] is PackedVector3Array):
		data = load_from_file(file_path)
		
	if data.is_empty() or not data.has("vertices"):
		return null
		
	var shape = ConvexPolygonShape3D.new()
	var verts: PackedVector3Array = data["vertices"]
	if verts.size() > 512:
		var stride = maxi(1, verts.size() / 256)
		var sampled = PackedVector3Array()
		for i in range(0, verts.size(), stride):
			sampled.append(verts[i])
		shape.points = sampled
	else:
		shape.points = verts
		
	_shape_cache[key] = shape
	return shape

static func get_cached_concave_shape(file_path: String, vg_data: Dictionary = {}, target_lod: int = 0) -> ConcavePolygonShape3D:
	var key = "%s:concave:%d" % [file_path, target_lod]
	if _shape_cache.has(key):
		return _shape_cache[key]
		
	var data = vg_data
	if not (data.has("clusters") and data.has("vertices") and data["vertices"] is PackedVector3Array and data["clusters"] is Array):
		data = load_from_file(file_path)
		
	if data.is_empty() or not data.has("clusters") or not data.has("vertices"):
		return null
		
	var clusters = data["clusters"]
	var vertices: PackedVector3Array = data["vertices"]
	var tri_bytes: PackedByteArray = data["triangle_bytes"]
	
	var faces = PackedVector3Array()
	for c in clusters:
		if c["lod_level"] != target_lod:
			continue
		var v_start = c["vertex_offset"]
		var t_start = c["triangle_offset"]
		var t_count = c["triangle_count"]
		for ti in range(t_count):
			var idx0 = v_start + tri_bytes[t_start + ti * 3 + 0]
			var idx1 = v_start + tri_bytes[t_start + ti * 3 + 1]
			var idx2 = v_start + tri_bytes[t_start + ti * 3 + 2]
			faces.append(vertices[idx0])
			faces.append(vertices[idx1])
			faces.append(vertices[idx2])
			
	if faces.is_empty():
		return null
		
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	_shape_cache[key] = shape
	return shape

static func get_cached_box_shape(file_path: String, vg_data: Dictionary = {}) -> BoxShape3D:
	var key = file_path + ":box"
	if _shape_cache.has(key):
		return _shape_cache[key]
		
	var data = vg_data
	if not data.has("bbox_min") or not data.has("bbox_max"):
		data = load_from_file(file_path)
		
	if data.is_empty() or not data.has("bbox_min"):
		return null
		
	var bmin: Vector3 = data["bbox_min"]
	var bmax: Vector3 = data["bbox_max"]
	var size = (bmax - bmin).abs()
	var shape = BoxShape3D.new()
	shape.size = size
	_shape_cache[key] = shape
	return shape
