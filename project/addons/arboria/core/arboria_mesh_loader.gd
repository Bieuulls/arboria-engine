extends RefCounted
class_name ArboriaMeshLoader

# Resolve caminhos de assets transparentemente: busca na pasta externa assets/ (fora do project/),
# caminhos relativos globais e subdiretórios de referência sem duplicar arquivos pesados no zip do projeto.
static func resolve_asset_path(file_path: String) -> String:
	if file_path.is_empty():
		return ""
	
	if FileAccess.file_exists(file_path):
		return file_path

	var clean = file_path.replace("\\", "/")
	var rel = clean
	if rel.begins_with("res://assets/"):
		rel = rel.trim_prefix("res://assets/")
	elif rel.begins_with("res://"):
		rel = rel.trim_prefix("res://")
	elif rel.begins_with("assets/"):
		rel = rel.trim_prefix("assets/")
	
	var search_names = [rel]
	if rel == "dense_rock_test.vgmesh" or rel == "dense_rock_verified.vgmesh":
		search_names.append("dense_rock.vgmesh")
	elif rel == "dense_rock.vgmesh":
		search_names.append("dense_rock_test.vgmesh")
	
	for sn in search_names:
		var candidates = [
			ProjectSettings.globalize_path("res://../assets_externos/" + sn),
			ProjectSettings.globalize_path("res://../assets_externos/jungle_ruins/" + sn),
			ProjectSettings.globalize_path("res://../assets/" + sn),
			"res://../assets/" + sn,
			ProjectSettings.globalize_path("res://../assets/reference/" + sn),
			ProjectSettings.globalize_path("res://../assets/downloads/" + sn),
			ProjectSettings.globalize_path(clean),
			ProjectSettings.globalize_path("res://assets/" + sn),
			"res://assets/" + sn
		]
		for c in candidates:
			if FileAccess.file_exists(c):
				return c
	return file_path

# Carregador de texturas PBR externas que funciona tanto para recursos internos quanto para
# texturas grandes armazenadas fora do projeto (assets/textures/) sem inflar o zip
static func load_texture(tex_path: String) -> Texture2D:
	if tex_path.is_empty():
		return null
	var resolved = resolve_asset_path(tex_path)
	if ResourceLoader.exists(resolved):
		return load(resolved)
	if ResourceLoader.exists(tex_path):
		return load(tex_path)
	if FileAccess.file_exists(resolved):
		var img = Image.new()
		var err = img.load(resolved)
		if err == OK:
			return ImageTexture.create_from_image(img)
	return null

# Carrega e decodifica arquivo binario .vgmesh gerado pelo Baker C++
static func load_from_file(file_path: String) -> Dictionary:
	var resolved = resolve_asset_path(file_path)
	var file = FileAccess.open(resolved, FileAccess.READ)
	if not file:
		file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Falha ao abrir arquivo: " + file_path + " (resolvido: " + resolved + ")")
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
	var cluster_size = 68 if magic == "ARBORIA2" else 60
	var c_bytes = file.get_buffer(cluster_count * cluster_size)
	clusters.resize(cluster_count)

	for i in range(cluster_count):
		var off = i * cluster_size
		var c = {}
		c["cluster_id"] = c_bytes.decode_u32(off)
		c["lod_level"] = c_bytes.decode_u32(off + 4)
		if magic == "ARBORIA2":
			c["group_id"] = c_bytes.decode_s32(off + 8)
			c["refined_group"] = c_bytes.decode_s32(off + 12)
			c["center"] = Vector3(c_bytes.decode_float(off + 16), c_bytes.decode_float(off + 20), c_bytes.decode_float(off + 24))
			c["radius"] = c_bytes.decode_float(off + 28)
			c["normal_cone"] = [c_bytes.decode_float(off + 32), c_bytes.decode_float(off + 36), c_bytes.decode_float(off + 40), c_bytes.decode_float(off + 44)]
			c["lod_error"] = c_bytes.decode_float(off + 48)
			c["vertex_offset"] = c_bytes.decode_u32(off + 52)
			c["vertex_count"] = c_bytes.decode_u32(off + 56)
			c["triangle_offset"] = c_bytes.decode_u32(off + 60)
			c["triangle_count"] = c_bytes.decode_u32(off + 64)
		else:
			c["group_id"] = 0
			c["refined_group"] = -1
			c["center"] = Vector3(c_bytes.decode_float(off + 8), c_bytes.decode_float(off + 12), c_bytes.decode_float(off + 16))
			c["radius"] = c_bytes.decode_float(off + 20)
			c["normal_cone"] = [c_bytes.decode_float(off + 24), c_bytes.decode_float(off + 28), c_bytes.decode_float(off + 32), c_bytes.decode_float(off + 36)]
			c["lod_error"] = c_bytes.decode_float(off + 40)
			c["vertex_offset"] = c_bytes.decode_u32(off + 44)
			c["vertex_count"] = c_bytes.decode_u32(off + 48)
			c["triangle_offset"] = c_bytes.decode_u32(off + 52)
			c["triangle_count"] = c_bytes.decode_u32(off + 56)
		clusters[i] = c

	var groups = []
	if magic == "ARBORIA2" and group_count > 0:
		var g_bytes = file.get_buffer(group_count * 28)
		groups.resize(group_count)
		for i in range(group_count):
			var off = i * 28
			groups[i] = {
				"group_id": g_bytes.decode_u32(off),
				"depth": g_bytes.decode_s32(off + 4),
				"center": Vector3(g_bytes.decode_float(off + 8), g_bytes.decode_float(off + 12), g_bytes.decode_float(off + 16)),
				"radius": g_bytes.decode_float(off + 20),
				"error": g_bytes.decode_float(off + 24)
			}

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

static var _array_mesh_cache: Dictionary = {}

static func get_cached_array_mesh(file_path: String, vg_data: Dictionary = {}, target_lod: int = 0) -> ArrayMesh:
	var key = file_path + "_lod_" + str(target_lod)
	if _array_mesh_cache.has(key):
		return _array_mesh_cache[key]
	if vg_data.is_empty() or not vg_data.has("normals"):
		vg_data = load_from_file(file_path)
	var m = build_mesh_surface(vg_data, target_lod, false)
	if m:
		_array_mesh_cache[key] = m
	return m

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
	var resolved = resolve_asset_path(obj_path)
	var file = FileAccess.open(resolved, FileAccess.READ)
	if not file:
		file = FileAccess.open(obj_path, FileAccess.READ)
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
		var stride = max(1, verts.size() / 256)
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
