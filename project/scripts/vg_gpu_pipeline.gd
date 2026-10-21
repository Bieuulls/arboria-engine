extends RefCounted
class_name VGGPUPipeline

# ARBORIA VIRTUAL GEOMETRY — PIPELINE DE GPU REAL (VULKAN COMPUTE + GODOT FORWARD+)
# Frustum Culling, Normal Cone Backface Culling, DAG LOD Selection 100% na GPU.

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

# Buffers de GPU
var in_clusters_buf: RID
var out_visible_buf: RID
var counter_buf: RID
var ubo_buf: RID
var selection_texture_rid: RID
var uniform_set: RID

# Texturas de Geometria e Metadados para o Vertex Shader
var vertex_texture: ImageTexture
var index_texture: ImageTexture
var meta_texture: ImageTexture
var selection_texture_rd: Texture2DRD

# Recursos de Cena
var template_mesh: ArrayMesh
var multimesh: MultiMesh
var multimesh_instance: MultiMeshInstance3D
var render_material: ShaderMaterial

# Metadados da Malha Carregada
var total_clusters: int = 0
var total_vertices: int = 0
var total_triangles: int = 0
var group_count: int = 0
var is_ready: bool = false

# Estatisticas em Tempo Real
var stat_visible_clusters: int = 0
var stat_triangles_drawn: int = 0
var stat_total_evaluated: int = 0
var stat_gpu_time_us: float = 0.0
var stat_cpu_submit_time_us: float = 0.0
var stat_vram_bytes: int = 0
var is_async_pending: bool = false

func _init(p_rd: RenderingDevice = null) -> void:
	if p_rd:
		rd = p_rd
	else:
		rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("ERRO CRITICO: RenderingDevice Vulkan indisponivel!")
		return
	init_compute_shader()

func init_compute_shader() -> void:
	var code = FileAccess.get_file_as_string("res://shaders/cull_clusters.glsl")
	if code.begins_with("#[compute]"):
		code = code.substr(code.find("\n") + 1)

	var src = RDShaderSource.new()
	src.source_compute = code
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL

	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("Falha ao compilar Compute Shader: " + spirv.compile_error_compute)
		return

	shader_rid = rd.shader_create_from_spirv(spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not rd.compute_pipeline_is_valid(pipeline_rid):
		push_error("Falha ao criar Pipeline de Computacao Vulkan!")

func cleanup() -> void:
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		uniform_set = RID()
	if in_clusters_buf.is_valid():
		rd.free_rid(in_clusters_buf)
		in_clusters_buf = RID()
	if out_visible_buf.is_valid():
		rd.free_rid(out_visible_buf)
		out_visible_buf = RID()
	if counter_buf.is_valid():
		rd.free_rid(counter_buf)
		counter_buf = RID()
	if ubo_buf.is_valid():
		rd.free_rid(ubo_buf)
		ubo_buf = RID()
	if selection_texture_rid.is_valid():
		rd.free_rid(selection_texture_rid)
		selection_texture_rid = RID()
	selection_texture_rd = null
	vertex_texture = null
	index_texture = null
	meta_texture = null
	template_mesh = null
	multimesh = null
	multimesh_instance = null
	render_material = null
	is_ready = false

func load_vgmesh(vg_data: Dictionary) -> bool:
	if not rd or not rd.compute_pipeline_is_valid(pipeline_rid):
		return false

	cleanup()

	var clusters = vg_data["clusters"]
	var groups = vg_data["groups"]
	var vertices: PackedVector3Array = vg_data["vertices"]
	var normals: PackedVector3Array = vg_data["normals"]
	var uvs: PackedVector2Array = vg_data["uvs"]
	var tri_bytes: PackedByteArray = vg_data["triangle_bytes"]

	total_clusters = clusters.size()
	total_vertices = vertices.size()
	total_triangles = tri_bytes.size() / 3
	group_count = groups.size()
	stat_vram_bytes = 0

	# 1. Cria InClusters Buffer (96 bytes por cluster)
	var c_bytes = PackedByteArray()
	c_bytes.resize(total_clusters * 96)

	for i in range(total_clusters):
		var c = clusters[i]
		var b = i * 96

		# center_radius (vec4)
		c_bytes.encode_float(b + 0, c["center"].x)
		c_bytes.encode_float(b + 4, c["center"].y)
		c_bytes.encode_float(b + 8, c["center"].z)
		c_bytes.encode_float(b + 12, c["radius"])

		# cone_axis_cutoff (vec4)
		c_bytes.encode_float(b + 16, c["normal_cone"][0])
		c_bytes.encode_float(b + 20, c["normal_cone"][1])
		c_bytes.encode_float(b + 24, c["normal_cone"][2])
		c_bytes.encode_float(b + 28, c["normal_cone"][3])

		# group_bounds_error (vec4)
		var gid = c["group_id"]
		if gid >= 0 and gid < groups.size():
			var g = groups[gid]
			c_bytes.encode_float(b + 32, g["center"].x)
			c_bytes.encode_float(b + 36, g["center"].y)
			c_bytes.encode_float(b + 40, g["center"].z)
			c_bytes.encode_float(b + 44, g["error"])
		else:
			c_bytes.encode_float(b + 32, 0.0)
			c_bytes.encode_float(b + 36, 0.0)
			c_bytes.encode_float(b + 40, 0.0)
			c_bytes.encode_float(b + 44, 1e7)

		# refined_bounds_error (vec4)
		var rgid = c["refined_group"]
		if rgid >= 0 and rgid < groups.size() and rgid != 4294967295:
			var rg = groups[rgid]
			c_bytes.encode_float(b + 48, rg["center"].x)
			c_bytes.encode_float(b + 52, rg["center"].y)
			c_bytes.encode_float(b + 56, rg["center"].z)
			c_bytes.encode_float(b + 60, rg["error"])
		else:
			c_bytes.encode_float(b + 48, 0.0)
			c_bytes.encode_float(b + 52, 0.0)
			c_bytes.encode_float(b + 56, 0.0)
			c_bytes.encode_float(b + 60, -1.0)

		# data_offsets (uvec4)
		c_bytes.encode_u32(b + 64, c["vertex_offset"])
		c_bytes.encode_u32(b + 68, c["vertex_count"])
		c_bytes.encode_u32(b + 72, c["triangle_offset"])
		c_bytes.encode_u32(b + 76, c["triangle_count"])

		# cluster_info (uvec4)
		c_bytes.encode_u32(b + 80, c["cluster_id"])
		c_bytes.encode_u32(b + 84, c["lod_level"])
		c_bytes.encode_u32(b + 88, c["group_id"])
		c_bytes.encode_s32(b + 92, -1 if c["refined_group"] == 4294967295 else c["refined_group"])

	in_clusters_buf = rd.storage_buffer_create(c_bytes.size(), c_bytes)
	stat_vram_bytes += c_bytes.size()

	# 2. OutVisibleClusters Buffer
	out_visible_buf = rd.storage_buffer_create(max(4, total_clusters * 4))
	stat_vram_bytes += total_clusters * 4

	# 3. OutCounterAndDrawArgs Buffer (24 bytes: VkDrawIndirectCommand + Telemetria)
	var cnt_bytes = PackedByteArray()
	cnt_bytes.resize(24)
	cnt_bytes.encode_u32(0, 384) # vertex_count
	cnt_bytes.encode_u32(4, 0)   # instance_count
	cnt_bytes.encode_u32(8, 0)   # first_vertex
	cnt_bytes.encode_u32(12, 0)  # first_instance
	cnt_bytes.encode_u32(16, 0)  # total_triangles_drawn
	cnt_bytes.encode_u32(20, 0)  # total_clusters_evaluated
	counter_buf = rd.storage_buffer_create(24, cnt_bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)
	stat_vram_bytes += 24

	# 4. Camera Uniforms Buffer (208 bytes)
	var u_bytes = PackedByteArray()
	u_bytes.resize(208)
	ubo_buf = rd.uniform_buffer_create(208, u_bytes)
	stat_vram_bytes += 208

	# 5. Out Selection Texture (Texture2D RD)
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.width = 2048
	tf.height = max(1, int(ceil(float(total_clusters) / 2048.0)))
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	selection_texture_rid = rd.texture_create(tf, RDTextureView.new(), [])
	selection_texture_rd = Texture2DRD.new()
	selection_texture_rd.texture_rd_rid = selection_texture_rid
	stat_vram_bytes += tf.width * tf.height * 16

	# 6. Cria Uniform Set para o Compute Shader
	var u0 = RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(in_clusters_buf)

	var u1 = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(out_visible_buf)

	var u2 = RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u2.binding = 2
	u2.add_id(counter_buf)

	var u3 = RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u3.binding = 3
	u3.add_id(ubo_buf)

	var u4 = RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u4.binding = 4
	u4.add_id(selection_texture_rid)

	uniform_set = rd.uniform_set_create([u0, u1, u2, u3, u4], shader_rid, 0)

	# 7. Prepara Texturas de Geometria e Metadados para o Vertex Shader
	# A. Textura de Geometria (Vertices: pos, normal, uv)
	# 2 pixels por vertice em RGBAF: Pixel 0 = (x, y, z, u), Pixel 1 = (nx, ny, nz, v)
	var total_v_pixels = total_vertices * 2
	var v_tex_w = 2048
	var v_tex_h = max(1, int(ceil(float(total_v_pixels) / float(v_tex_w))))
	var v_data_bytes = PackedByteArray()
	v_data_bytes.resize(v_tex_w * v_tex_h * 16) # 16 bytes por pixel (RGBAF)

	for vi in range(total_vertices):
		var p0_byte = vi * 32
		var p1_byte = vi * 32 + 16
		var p = vertices[vi]
		var n = normals[vi]
		var uv = uvs[vi]

		v_data_bytes.encode_float(p0_byte + 0, p.x)
		v_data_bytes.encode_float(p0_byte + 4, p.y)
		v_data_bytes.encode_float(p0_byte + 8, p.z)
		v_data_bytes.encode_float(p0_byte + 12, uv.x)

		v_data_bytes.encode_float(p1_byte + 0, n.x)
		v_data_bytes.encode_float(p1_byte + 4, n.y)
		v_data_bytes.encode_float(p1_byte + 8, n.z)
		v_data_bytes.encode_float(p1_byte + 12, uv.y)

	var v_img = Image.create_from_data(v_tex_w, v_tex_h, false, Image.FORMAT_RGBAF, v_data_bytes)
	vertex_texture = ImageTexture.create_from_image(v_img)
	stat_vram_bytes += v_data_bytes.size()

	# B. Textura de Indices dos Triangulos (R8 uint)
	var idx_count = tri_bytes.size()
	var idx_w = 2048
	var idx_h = max(1, int(ceil(float(idx_count) / float(idx_w))))
	var idx_data = PackedByteArray()
	idx_data.resize(idx_w * idx_h)
	for ti in range(idx_count):
		idx_data[ti] = tri_bytes[ti]

	var idx_img = Image.create_from_data(idx_w, idx_h, false, Image.FORMAT_R8, idx_data)
	index_texture = ImageTexture.create_from_image(idx_img)
	stat_vram_bytes += idx_data.size()

	# C. Textura de Metadados dos Clusters (RGBA32F amostragem direta)
	# x = vertex_offset, y = vertex_count, z = triangle_offset, w = triangle_count
	var meta_w = 2048
	var meta_h = max(1, int(ceil(float(total_clusters) / float(meta_w))))
	var meta_data = PackedByteArray()
	meta_data.resize(meta_w * meta_h * 16)

	for ci in range(total_clusters):
		var cl = clusters[ci]
		var mb = ci * 16
		meta_data.encode_float(mb + 0, float(cl["vertex_offset"]))
		meta_data.encode_float(mb + 4, float(cl["vertex_count"]))
		meta_data.encode_float(mb + 8, float(cl["triangle_offset"]))
		meta_data.encode_float(mb + 12, float(cl["triangle_count"]))

	var meta_img = Image.create_from_data(meta_w, meta_h, false, Image.FORMAT_RGBAF, meta_data)
	meta_texture = ImageTexture.create_from_image(meta_img)
	stat_vram_bytes += meta_data.size()

	# 8. Constroi Template Mesh (384 vertices = 128 triangulos)
	build_template_mesh()

	# 9. Inicializa MultiMesh e Material com AABB Real
	setup_multimesh(vg_data)

	is_ready = true
	print("✅ Pipeline GPU Virtual Geometry pronto para execução! Total Clusters: ", total_clusters, " | VRAM: ", (stat_vram_bytes / 1024), " KB")
	return true

func build_template_mesh() -> void:
	template_mesh = ArrayMesh.new()
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var uvs = PackedVector2Array()

	# 128 triangulos * 3 vertices = 384 vertices
	verts.resize(384)
	norms.resize(384)
	uvs.resize(384)

	for i in range(384):
		verts[i] = Vector3.ZERO
		norms[i] = Vector3.UP
		uvs[i] = Vector2.ZERO

	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	template_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

func setup_multimesh(vg_data: Dictionary) -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.use_custom_data = false
	multimesh.mesh = template_mesh
	multimesh.instance_count = total_clusters

	# Limites espaciais reais da geometria para o frustum culling do Godot
	var bmin = vg_data.get("bbox_min", Vector3(-10, -10, -10))
	var bmax = vg_data.get("bbox_max", Vector3(10, 10, 10))
	var model_aabb = AABB(bmin, bmax - bmin).grow(0.5)
	multimesh.custom_aabb = model_aabb

	# Define todas as instancias na origem
	for i in range(total_clusters):
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)

	render_material = ShaderMaterial.new()
	var shader = load("res://shaders/vg_cluster_render.gdshader")
	render_material.shader = shader

	# Configura Uniforms de Textura no Material
	render_material.set_shader_parameter("cluster_selection_texture", selection_texture_rd)
	render_material.set_shader_parameter("vertex_data_texture", vertex_texture)
	render_material.set_shader_parameter("index_data_texture", index_texture)
	render_material.set_shader_parameter("cluster_meta_texture", meta_texture)
	render_material.set_shader_parameter("debug_cluster_colors", true)

	if not multimesh_instance:
		multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.multimesh = multimesh
	multimesh_instance.material_override = render_material
	multimesh_instance.custom_aabb = model_aabb

static func extract_frustum_planes_from_matrix(m: Projection) -> Array[Plane]:
	var planes: Array[Plane] = []
	var r0 = Vector4(m[0][0], m[1][0], m[2][0], m[3][0])
	var r1 = Vector4(m[0][1], m[1][1], m[2][1], m[3][1])
	var r2 = Vector4(m[0][2], m[1][2], m[2][2], m[3][2])
	var r3 = Vector4(m[0][3], m[1][3], m[2][3], m[3][3])

	var raw_planes = [
		r3 + r0, # Left
		r3 - r0, # Right
		r3 + r1, # Bottom
		r3 - r1, # Top
		r2,      # Near (Vulkan 0..1 depth)
		r3 - r2  # Far
	]

	for p in raw_planes:
		var n = Vector3(p.x, p.y, p.z)
		var len_n = n.length()
		if len_n > 0.00001:
			planes.append(Plane(n / len_n, p.w / len_n))
		else:
			planes.append(Plane(Vector3.UP, 0.0))

	return planes

func dispatch_culling(
	camera: Camera3D,
	viewport_size: Vector2,
	max_screen_error: float = 1.5,
	lod_mode: int = 0, # 0 = Auto DAG, 1 = Forced LOD
	forced_lod: int = 0,
	enable_frustum: bool = true,
	enable_cone: bool = true,
	debug_colors: bool = true
) -> void:
	if not is_ready:
		return

	var t0 = Time.get_ticks_usec()

	# 1. Extrai matriz View-Proj e Planos de Frustum matematicamente
	var cam_pos = camera.global_position if camera.is_inside_tree() else camera.position
	var v_trans = (camera.global_transform if camera.is_inside_tree() else camera.transform).affine_inverse()
	var aspect = max(0.01, viewport_size.x / max(1.0, viewport_size.y))
	var proj = Projection.create_perspective(camera.fov, aspect, camera.near, camera.far)

	var vp_mat = proj * Projection(v_trans)
	var f_planes = extract_frustum_planes_from_matrix(vp_mat)

	# 2. Atualiza UBO Buffer
	var u_bytes = PackedByteArray()
	u_bytes.resize(208)

	# view_proj (mat4 column-major)
	for col in range(4):
		for row in range(4):
			u_bytes.encode_float((col * 4 + row) * 4, vp_mat[col][row])

	# 6 Frustum Planes (vec4 plane)
	for i in range(min(6, f_planes.size())):
		var pl = f_planes[i]
		var p_off = 64 + i * 16
		u_bytes.encode_float(p_off + 0, pl.normal.x)
		u_bytes.encode_float(p_off + 4, pl.normal.y)
		u_bytes.encode_float(p_off + 8, pl.normal.z)
		u_bytes.encode_float(p_off + 12, pl.d)

	# camera_pos_fov (vec4)
	u_bytes.encode_float(160, cam_pos.x)
	u_bytes.encode_float(164, cam_pos.y)
	u_bytes.encode_float(168, cam_pos.z)
	var fov_rad = deg_to_rad(camera.fov)
	var fov_factor = tan(fov_rad * 0.5)
	u_bytes.encode_float(172, fov_factor)

	# viewport_params (vec4)
	u_bytes.encode_float(176, viewport_size.x)
	u_bytes.encode_float(180, viewport_size.y)
	u_bytes.encode_float(184, max_screen_error)
	u_bytes.encode_float(188, float(lod_mode))

	# count_params (uvec4)
	u_bytes.encode_u32(192, total_clusters)
	u_bytes.encode_u32(196, forced_lod)
	u_bytes.encode_u32(200, 1 if enable_frustum else 0)
	u_bytes.encode_u32(204, 1 if enable_cone else 0)

	rd.buffer_update(ubo_buf, 0, 208, u_bytes)

	# 3. Zera os contadores dinamicos na GPU preservando vertex_count = 384 em offset 0
	# Offset 4 = instance_count (4B), first_vertex (4B), first_instance (4B), total_triangles (4B), total_evaluated (4B)
	rd.buffer_clear(counter_buf, 4, 20)
	rd.texture_clear(selection_texture_rid, Color(0, 0, 0, 0), 0, 1, 0, 1)

	# 4. Dispara o Compute Shader na GPU Vulkan com Timestamps Reais de GPU
	rd.capture_timestamp("vg_cull_begin")
	var groups_x = int(ceil(float(total_clusters) / 64.0))
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, groups_x, 1, 1)
	rd.compute_list_end()
	rd.capture_timestamp("vg_cull_end")

	# 5. ZERO LEITURA BLOQUEANTE NO CAMINHO DE RENDERIZACAO
	# A GPU executa a selecao e escreve na Texture2DRD e no VkDrawIndirectCommand.
	# O Vertex Shader puxa diretamente da textura sem qualquer sincronizacao de volta para a CPU no frame.
	render_material.set_shader_parameter("debug_cluster_colors", debug_colors)

	# Mede tempo de submissao CPU estritamente separado do tempo GPU
	stat_cpu_submit_time_us = float(Time.get_ticks_usec() - t0)

func poll_timestamps() -> void:
	var count = rd.get_captured_timestamps_count()
	var t_begin_gpu: int = 0
	var t_end_gpu: int = 0
	var found_begin: bool = false
	var found_end: bool = false
	for i in range(count):
		var tname = rd.get_captured_timestamp_name(i)
		if tname == "vg_cull_begin":
			t_begin_gpu = rd.get_captured_timestamp_gpu_time(i)
			found_begin = true
		elif tname == "vg_cull_end":
			t_end_gpu = rd.get_captured_timestamp_gpu_time(i)
			found_end = true
	if found_begin and found_end and t_end_gpu >= t_begin_gpu:
		# Converte nanosegundos da GPU para microsegundos
		stat_gpu_time_us = float(t_end_gpu - t_begin_gpu) * 0.001

func poll_stats_async() -> void:
	# Leitura assincrona / desacoplada exclusiva para telemetria da UI
	# NUNCA executada no caminho critico de desenho; utiliza buffer_get_data_async
	if not is_ready or is_async_pending:
		return
	is_async_pending = true
	poll_timestamps()
	rd.buffer_get_data_async(counter_buf, _on_stats_received, 0, 24)

func _on_stats_received(bytes: PackedByteArray) -> void:
	is_async_pending = false
	if bytes.size() >= 24:
		# Byte 0..3: vertex_count (deve ser sempre 384)
		# Byte 4..7: instance_count (clusters visiveis selecionados pela GPU)
		stat_visible_clusters = bytes.decode_u32(4)
		# Byte 16..19: total_triangles_drawn
		stat_triangles_drawn = bytes.decode_u32(16)
		# Byte 20..23: total_clusters_evaluated
		stat_total_evaluated = bytes.decode_u32(20)

func execute_indirect_draw(framebuffer: RID, render_pipeline: RID, p_uniform_set: RID = RID()) -> void:
	# Executa desenho indireto real via Vulkan RenderingDevice
	# Consome counter_buf diretamente na GPU sem qualquer leitura CPU
	if not is_ready or not counter_buf.is_valid():
		return
	var clear_colors = PackedColorArray([Color(0, 0, 0, 0)])
	var draw_list = rd.draw_list_begin(framebuffer, RenderingDevice.DRAW_CLEAR_COLOR_0, clear_colors, 1.0, 0)
	rd.draw_list_bind_render_pipeline(draw_list, render_pipeline)
	if p_uniform_set.is_valid():
		rd.draw_list_bind_uniform_set(draw_list, p_uniform_set, 0)
	# draw_list_draw_indirect(draw_list, use_indices, buffer, offset, draw_count, stride)
	rd.draw_list_draw_indirect(draw_list, false, counter_buf, 0, 1, 16)
	rd.draw_list_end()

func get_stats() -> Dictionary:
	return {
		"visible_clusters": stat_visible_clusters,
		"total_clusters": total_clusters,
		"culled_clusters": total_clusters - stat_visible_clusters,
		"triangles_drawn": stat_triangles_drawn,
		"total_triangles": total_triangles,
		"clusters_evaluated": stat_total_evaluated,
		"gpu_time_us": stat_gpu_time_us,
		"cpu_submit_time_us": stat_cpu_submit_time_us,
		"vram_kb": stat_vram_bytes / 1024
	}
