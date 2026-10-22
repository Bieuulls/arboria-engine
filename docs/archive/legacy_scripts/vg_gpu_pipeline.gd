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

# Buffers de Geometria Real para Rasterizacao Indireta
var in_vertices_buf: RID
var in_triangles_buf: RID

# Pipeline de Rasterizacao Indireta Real (Vulkan draw_list_draw_indirect)
var indirect_shader_rid: RID
var indirect_render_pipeline: RID
var indirect_uniform_set: RID
var indirect_framebuffer: RID
var indirect_color_tex: RID
var indirect_depth_tex: RID
var indirect_target_size: Vector2i = Vector2i(512, 512)

# Controle de Integracao Direta no Viewport (Missao 2)
var enable_indirect_draw: bool = true
var debug_force_zero_instances: bool = false
var vp_framebuffer: RID
var vp_depth_tex: RID
var vp_last_size: Vector2i = Vector2i.ZERO

# Texturas de Geometria e Metadados para o Vertex Shader
var vertex_texture: ImageTexture
var index_texture: ImageTexture
var meta_texture: ImageTexture
var selection_texture_rd: Texture2DRD

# Recursos de Cena e Fallback Legado (Missao 3: MultiMesh isolado como fallback opcional)
var template_mesh: ArrayMesh
var multimesh: MultiMesh
var multimesh_instance: MultiMeshInstance3D
var render_material: ShaderMaterial
var cached_vg_data: Dictionary = {}
var multimesh_fallback_enabled: bool = false

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
	# 0. Limpa parametros do material para evitar validacao de RID liberado pelo RenderingServer
	if render_material:
		render_material.set_shader_parameter("cluster_selection_texture", null)
		render_material.set_shader_parameter("vertex_data_texture", null)
		render_material.set_shader_parameter("index_data_texture", null)
		render_material.set_shader_parameter("cluster_meta_texture", null)

	# 1. Libera Uniform Sets primeiro (para evitar invalidacao automatica)
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		uniform_set = RID()
	if indirect_uniform_set.is_valid():
		rd.free_rid(indirect_uniform_set)
		indirect_uniform_set = RID()

	# 2. Libera Pipelines e Framebuffers
	if indirect_render_pipeline.is_valid():
		rd.free_rid(indirect_render_pipeline)
		indirect_render_pipeline = RID()
	if indirect_framebuffer.is_valid():
		rd.free_rid(indirect_framebuffer)
		indirect_framebuffer = RID()
	if vp_framebuffer.is_valid():
		rd.free_rid(vp_framebuffer)
		vp_framebuffer = RID()

	# 3. Libera Texturas e Buffers
	if indirect_color_tex.is_valid():
		rd.free_rid(indirect_color_tex)
		indirect_color_tex = RID()
	if indirect_depth_tex.is_valid():
		rd.free_rid(indirect_depth_tex)
		indirect_depth_tex = RID()
	if vp_depth_tex.is_valid():
		rd.free_rid(vp_depth_tex)
		vp_depth_tex = RID()
	if in_vertices_buf.is_valid():
		rd.free_rid(in_vertices_buf)
		in_vertices_buf = RID()
	if in_triangles_buf.is_valid():
		rd.free_rid(in_triangles_buf)
		in_triangles_buf = RID()
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
	if indirect_shader_rid.is_valid():
		rd.free_rid(indirect_shader_rid)
		indirect_shader_rid = RID()
	selection_texture_rd = null
	vertex_texture = null
	index_texture = null
	meta_texture = null
	template_mesh = null
	multimesh = null
	multimesh_instance = null
	render_material = null
	is_ready = false

func destroy() -> void:
	cleanup()
	if rd:
		if pipeline_rid.is_valid():
			rd.free_rid(pipeline_rid)
			pipeline_rid = RID()
		if shader_rid.is_valid():
			rd.free_rid(shader_rid)
			shader_rid = RID()

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

	# 4. Camera Uniforms Buffer (224 bytes)
	var u_bytes = PackedByteArray()
	u_bytes.resize(224)
	ubo_buf = rd.uniform_buffer_create(224, u_bytes)
	stat_vram_bytes += 224

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

	# 7. Buffers de Geometria Real para Rasterizacao Indireta via SSBO (Caminho Principal)
	# 32 bytes por vertice: vec4(pos.xyz, uv.x) + vec4(norm.xyz, uv.y)
	var raw_v_bytes = PackedByteArray()
	raw_v_bytes.resize(total_vertices * 32)
	for vi in range(total_vertices):
		var p0_byte = vi * 32
		var p1_byte = vi * 32 + 16
		var p = vertices[vi]
		var n = normals[vi]
		var uv = uvs[vi]

		raw_v_bytes.encode_float(p0_byte + 0, p.x)
		raw_v_bytes.encode_float(p0_byte + 4, p.y)
		raw_v_bytes.encode_float(p0_byte + 8, p.z)
		raw_v_bytes.encode_float(p0_byte + 12, uv.x)

		raw_v_bytes.encode_float(p1_byte + 0, n.x)
		raw_v_bytes.encode_float(p1_byte + 4, n.y)
		raw_v_bytes.encode_float(p1_byte + 8, n.z)
		raw_v_bytes.encode_float(p1_byte + 12, uv.y)

	in_vertices_buf = rd.storage_buffer_create(raw_v_bytes.size(), raw_v_bytes)
	stat_vram_bytes += raw_v_bytes.size()

	var tri_padded_size = int(ceil(float(tri_bytes.size()) / 4.0)) * 4
	var tri_buf_data = PackedByteArray()
	tri_buf_data.resize(tri_padded_size)
	for ti in range(tri_bytes.size()):
		tri_buf_data[ti] = tri_bytes[ti]
	in_triangles_buf = rd.storage_buffer_create(tri_padded_size, tri_buf_data)
	stat_vram_bytes += tri_padded_size

	# 8. Cache dos dados para fallback diagnostico sob demanda (MultiMesh desativado no caminho principal)
	cached_vg_data = vg_data
	is_ready = true

	# 9. Inicializa Pipeline de Rasterizacao Indireta (Vulkan GLSL 450 Vertex Pulling)
	if not indirect_render_pipeline.is_valid():
		setup_indirect_raster_pipeline(512, 512)

	print("✅ Pipeline GPU Virtual Geometry pronto para execução! Total Clusters: ", total_clusters, " | VRAM: ", (stat_vram_bytes / 1024), " KB")
	return true

func setup_multimesh_fallback(p_vg_data: Dictionary = {}) -> MultiMeshInstance3D:
	# Fallback de Diagnostico Legado: Aloca recursos MultiMesh apenas sob demanda
	var data = p_vg_data if not p_vg_data.is_empty() else cached_vg_data
	if data.is_empty():
		return null

	if multimesh_instance and multimesh_instance.multimesh:
		multimesh_fallback_enabled = true
		multimesh_instance.visible = true
		return multimesh_instance

	var vertices: PackedVector3Array = data["vertices"]
	var normals: PackedVector3Array = data["normals"]
	var uvs: PackedVector2Array = data["uvs"]
	var tri_bytes: PackedByteArray = data["triangle_bytes"]
	var clusters = data["clusters"]

	# Cria Texturas de Geometria e Metadados exclusivamente para o MultiMesh
	var total_v_pixels = total_vertices * 2
	var v_tex_w = 2048
	var v_tex_h = max(1, int(ceil(float(total_v_pixels) / float(v_tex_w))))
	var v_data_bytes = PackedByteArray()
	v_data_bytes.resize(v_tex_w * v_tex_h * 16)
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

	var idx_count = tri_bytes.size()
	var idx_w = 2048
	var idx_h = max(1, int(ceil(float(idx_count) / float(idx_w))))
	var idx_data = PackedByteArray()
	idx_data.resize(idx_w * idx_h)
	for ti in range(idx_count):
		idx_data[ti] = tri_bytes[ti]
	var idx_img = Image.create_from_data(idx_w, idx_h, false, Image.FORMAT_R8, idx_data)
	index_texture = ImageTexture.create_from_image(idx_img)

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

	build_template_mesh()

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = false
	multimesh.use_custom_data = false
	multimesh.mesh = template_mesh
	multimesh.instance_count = total_clusters

	var bmin = data.get("bbox_min", Vector3(-10, -10, -10))
	var bmax = data.get("bbox_max", Vector3(10, 10, 10))
	var model_aabb = AABB(bmin, bmax - bmin).grow(0.5)
	multimesh.custom_aabb = model_aabb

	for i in range(total_clusters):
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)

	render_material = ShaderMaterial.new()
	render_material.shader = load("res://shaders/vg_cluster_render.gdshader")
	render_material.set_shader_parameter("cluster_selection_texture", selection_texture_rd)
	render_material.set_shader_parameter("vertex_data_texture", vertex_texture)
	render_material.set_shader_parameter("index_data_texture", index_texture)
	render_material.set_shader_parameter("cluster_meta_texture", meta_texture)
	render_material.set_shader_parameter("debug_cluster_colors", true)

	if not multimesh_instance:
		multimesh_instance = MultiMeshInstance3D.new()
		multimesh_instance.name = "VGClusterMultiMeshFallback"
	multimesh_instance.multimesh = multimesh
	multimesh_instance.material_override = render_material
	multimesh_instance.custom_aabb = model_aabb
	multimesh_instance.visible = true
	multimesh_fallback_enabled = true
	return multimesh_instance

func disable_multimesh_fallback() -> void:
	multimesh_fallback_enabled = false
	if multimesh_instance:
		multimesh_instance.visible = false

func setup_multimesh(p_vg_data: Dictionary = {}) -> void:
	setup_multimesh_fallback(p_vg_data)

func build_template_mesh() -> void:
	template_mesh = ArrayMesh.new()
	var verts = PackedVector3Array()
	var norms = PackedVector3Array()
	var uvs = PackedVector2Array()

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
	debug_colors: bool = true,
	model_transform: Transform3D = Transform3D.IDENTITY,
	shading_mode: int = 3
) -> void:
	if not is_ready:
		return

	var t0 = Time.get_ticks_usec()

	# 1. Extrai matriz Model-View-Projection (MVP) e Planos de Frustum no espaco local
	var cam_pos_world = camera.global_position if camera.is_inside_tree() else camera.position
	var v_trans = (camera.global_transform if camera.is_inside_tree() else camera.transform).affine_inverse()
	var aspect = max(0.01, viewport_size.x / max(1.0, viewport_size.y))
	var proj = Projection.create_perspective(camera.fov, aspect, camera.near, camera.far)
	# No Vulkan, o eixo Y do NDC e invertido (+Y para baixo) em relacao ao OpenGL para alinhamento nativo com o Viewport
	proj[1][1] = -proj[1][1]

	var mvp_mat: Projection
	var cam_pos: Vector3
	if model_transform != Transform3D.IDENTITY:
		var model_proj = Projection(model_transform)
		mvp_mat = proj * Projection(v_trans) * model_proj
		cam_pos = model_transform.affine_inverse() * cam_pos_world
	else:
		mvp_mat = proj * Projection(v_trans)
		cam_pos = cam_pos_world

	var f_planes = extract_frustum_planes_from_matrix(mvp_mat)

	# 2. Atualiza UBO Buffer
	var u_bytes = PackedByteArray()
	u_bytes.resize(224)

	# view_proj (MVP mat4 column-major)
	for col in range(4):
		for row in range(4):
			u_bytes.encode_float((col * 4 + row) * 4, mvp_mat[col][row])

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

	# render_params (uvec4)
	u_bytes.encode_u32(208, shading_mode)
	u_bytes.encode_u32(212, 0)
	u_bytes.encode_u32(216, 0)
	u_bytes.encode_u32(220, 0)

	rd.buffer_update(ubo_buf, 0, 224, u_bytes)

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
	if render_material:
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

func setup_indirect_raster_pipeline(w: int = 512, h: int = 512) -> bool:
	if not rd or not is_ready:
		return false

	indirect_target_size = Vector2i(w, h)

	# 1. Compila Shaders Vulkan Raster (GLSL 450) com Vertex Pulling Real de SSBOs
	var vs_code = """#version 450
layout(location = 0) out vec3 v_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out flat uint v_cluster_id;

struct GPUCluster {
    vec4 center_radius;
    vec4 cone_axis_cutoff;
    vec4 group_bounds_error;
    vec4 refined_bounds_error;
    uvec4 data_offsets;
    uvec4 cluster_info;
};

layout(set = 0, binding = 0, std430) readonly buffer InClusters {
    GPUCluster clusters[];
};
layout(set = 0, binding = 1, std430) readonly buffer OutVisibleClusters {
    uint visible_cluster_ids[];
};
layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;
} ubo;
layout(set = 0, binding = 5, std430) readonly buffer InVertices {
    vec4 packed_vertices[];
};
layout(set = 0, binding = 6, std430) readonly buffer InTriangles {
    uint packed_triangles[];
};

void main() {
    uint slot = gl_InstanceIndex;
    if (slot >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        v_normal = vec3(0.0, 1.0, 0.0);
        v_uv = vec2(0.0);
        v_cluster_id = 0u;
        return;
    }

    uint cluster_id = visible_cluster_ids[slot];
    if (cluster_id >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        v_normal = vec3(0.0, 1.0, 0.0);
        v_uv = vec2(0.0);
        v_cluster_id = 0u;
        return;
    }

    GPUCluster c = clusters[cluster_id];

    // Tratamento valido de triangulos excedentes (clusters incompletos < 128 triangulos)
    // Sem geracao de NaN: colapsa o vertice fora do volume NDC de visualizacao (Z > 1.0)
    uint tri_idx = gl_VertexIndex / 3;
    if (tri_idx >= c.data_offsets.w) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        v_normal = vec3(0.0, 1.0, 0.0);
        v_uv = vec2(0.0);
        v_cluster_id = cluster_id;
        return;
    }

    // Leitura segura do buffer de triangulos (SSBO InTriangles indexado por byte)
    uint byte_offset = c.data_offsets.z + gl_VertexIndex;
    uint word_idx = byte_offset / 4;
    uint byte_in_word = byte_offset % 4;
    uint word = packed_triangles[word_idx];
    uint local_v_idx = (word >> (byte_in_word * 8)) & 0xFFu;

    // Verificacao de limite local do vertice no cluster (c.data_offsets.y = vertex_count)
    if (local_v_idx >= c.data_offsets.y) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        v_normal = vec3(0.0, 1.0, 0.0);
        v_uv = vec2(0.0);
        v_cluster_id = cluster_id;
        return;
    }

    // Leitura segura do buffer de vertices (SSBO InVertices via indexacao global)
    uint global_v_idx = c.data_offsets.x + local_v_idx;
    uint vert_entry_idx = global_v_idx * 2;

    vec4 pos_u = packed_vertices[vert_entry_idx + 0];
    vec4 norm_v = packed_vertices[vert_entry_idx + 1];

    gl_Position = ubo.view_proj * vec4(pos_u.xyz, 1.0);
    v_normal = norm_v.xyz;
    v_uv = vec2(pos_u.w, norm_v.w);
    v_cluster_id = cluster_id;
}
"""

	var fs_code = """#version 450
layout(location = 0) in vec3 v_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_cluster_id;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;
} ubo;

void main() {
    uint mode = ubo.render_params.x;
    vec3 n = normalize(v_normal);

    if (mode == 0u) {
        // Modo 0: Unshaded neutro - para isolar silhueta, cobertura e fendas entre clusters
        out_color = vec4(0.8, 0.82, 0.85, 1.0);
    } else if (mode == 1u) {
        // Modo 1: Normais analiticas no espaco local [0, 1]
        out_color = vec4(n * 0.5 + 0.5, 1.0);
    } else if (mode == 2u) {
        // Modo 2: Iluminacao direcional PBR-equivalent ao StandardMaterial3D do Godot
        vec3 light_dir = normalize(vec3(0.5, 0.8, 0.6));
        float diff = max(dot(n, light_dir), 0.0);
        vec3 ambient = vec3(0.15);
        vec3 albedo = vec3(0.8, 0.82, 0.85);
        out_color = vec4(albedo * (diff + ambient), 1.0);
    } else {
        // Modo 3: Cores de depuracao de clusters (Golden Ratio hash)
        vec3 light_dir = normalize(vec3(0.5, 0.8, 0.6));
        float diff = max(dot(n, light_dir), 0.15);
        float hue = fract(float(v_cluster_id) * 0.618033988749895);
        vec3 rgb = clamp(abs(fract(hue + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        vec3 col = mix(rgb, vec3(1.0), 0.2) * diff;
        out_color = vec4(col, 1.0);
    }
}
"""

	var src = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = vs_code
	src.source_fragment = fs_code
	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_vertex != "" or spirv.compile_error_fragment != "":
		push_error("Erro compilacao indirect raster shader: " + spirv.compile_error_vertex + " " + spirv.compile_error_fragment)
		return false
	indirect_shader_rid = rd.shader_create_from_spirv(spirv)

	# 2. Texturas de Anexo: Cor (RGBA8_UNORM) e Profundidade (D32_SFLOAT)
	var tf_col = RDTextureFormat.new()
	tf_col.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf_col.width = w
	tf_col.height = h
	tf_col.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	indirect_color_tex = rd.texture_create(tf_col, RDTextureView.new(), [])

	var tf_depth = RDTextureFormat.new()
	tf_depth.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	tf_depth.width = w
	tf_depth.height = h
	tf_depth.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	indirect_depth_tex = rd.texture_create(tf_depth, RDTextureView.new(), [])

	indirect_framebuffer = rd.framebuffer_create([indirect_color_tex, indirect_depth_tex])

	# 3. Pipeline de Rasterizacao
	var blend = RDPipelineColorBlendState.new()
	blend.attachments.append(RDPipelineColorBlendStateAttachment.new())

	var depth_state = RDPipelineDepthStencilState.new()
	depth_state.enable_depth_test = true
	depth_state.enable_depth_write = true
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_LESS_OR_EQUAL

	var raster_state = RDPipelineRasterizationState.new()
	raster_state.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	raster_state.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE

	indirect_render_pipeline = rd.render_pipeline_create(
		indirect_shader_rid,
		rd.framebuffer_get_format(indirect_framebuffer),
		-1,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		raster_state,
		RDPipelineMultisampleState.new(),
		depth_state,
		blend
	)

	# 4. Uniform Set de Rasterizacao
	var u0 = RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(in_clusters_buf)

	var u1 = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(out_visible_buf)

	var u3 = RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u3.binding = 3
	u3.add_id(ubo_buf)

	var u5 = RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u5.binding = 5
	u5.add_id(in_vertices_buf)

	var u6 = RDUniform.new()
	u6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u6.binding = 6
	u6.add_id(in_triangles_buf)

	indirect_uniform_set = rd.uniform_set_create([u0, u1, u3, u5, u6], indirect_shader_rid, 0)
	return true

func execute_indirect_draw(p_framebuffer: RID = RID(), p_render_pipeline: RID = RID(), p_uniform_set: RID = RID(), p_clear_color: bool = true) -> void:
	# Executa desenho indireto real via Vulkan RenderingDevice consumindo geometria .vgmesh
	if not is_ready or not counter_buf.is_valid():
		return
	var fb = p_framebuffer if p_framebuffer.is_valid() else indirect_framebuffer
	var pipe = p_render_pipeline if p_render_pipeline.is_valid() else indirect_render_pipeline
	var uset = p_uniform_set if p_uniform_set.is_valid() else indirect_uniform_set

	if not fb.is_valid() or not pipe.is_valid() or not uset.is_valid():
		push_error("execute_indirect_draw: framebuffer ou pipeline invalido!")
		return

	if not enable_indirect_draw:
		return

	if debug_force_zero_instances:
		rd.buffer_clear(counter_buf, 4, 4)

	var clear_flags = RenderingDevice.DRAW_CLEAR_DEPTH
	var clear_colors = PackedColorArray()
	if p_clear_color:
		clear_flags |= RenderingDevice.DRAW_CLEAR_COLOR_0
		clear_colors.append(Color(0, 0, 0, 0))

	var draw_list = rd.draw_list_begin(fb, clear_flags, clear_colors, 1.0, 0)
	rd.draw_list_bind_render_pipeline(draw_list, pipe)
	rd.draw_list_bind_uniform_set(draw_list, uset, 0)
	# draw_list_draw_indirect(draw_list, use_indices, buffer, offset, draw_count, stride)
	rd.draw_list_draw_indirect(draw_list, false, counter_buf, 0, 1, 16)
	rd.draw_list_end()

func render_to_viewport(
	viewport: Viewport,
	camera: Camera3D,
	model_transform: Transform3D = Transform3D.IDENTITY,
	max_screen_error: float = 1.5,
	lod_mode: int = 0,
	forced_lod: int = 0,
	enable_frustum: bool = true,
	enable_cone: bool = true,
	debug_colors: bool = true,
	shading_mode: int = 3,
	p_clear_color: bool = false,
	p_clear_color_val: Color = Color(0, 0, 0, 1)
) -> void:
	# Ponto de integracao nativa: executa o desenho indireto diretamente no Viewport 3D
	if not is_ready or not rd or not camera:
		return

	var vp_size = Vector2i(viewport.get_visible_rect().size)
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	# 1. Obtem textura RD do Viewport e gerencia Framebuffer
	var vp_rid = viewport.get_viewport_rid()
	var tex_rs = RenderingServer.viewport_get_texture(vp_rid)
	var tex_rd = RenderingServer.texture_get_rd_texture(tex_rs)
	if not tex_rd.is_valid():
		return

	if vp_size != vp_last_size or not vp_framebuffer.is_valid():
		_recreate_viewport_framebuffer(tex_rd, vp_size)

	if not vp_framebuffer.is_valid() or not indirect_render_pipeline.is_valid():
		return

	# 2. Se desenho indireto estiver desligado (Prova Negativa)
	if not enable_indirect_draw:
		if p_clear_color:
			# Limpa o framebuffer isolado para nao reter pixels de frames anteriores
			var clear_list = rd.draw_list_begin(
				vp_framebuffer,
				RenderingDevice.DRAW_CLEAR_COLOR_0 | RenderingDevice.DRAW_CLEAR_DEPTH,
				PackedColorArray([p_clear_color_val]),
				1.0,
				0
			)
			rd.draw_list_end()
		return

	# 3. Dispatch Compute Culling 100% na GPU
	dispatch_culling(
		camera,
		Vector2(vp_size),
		max_screen_error,
		lod_mode,
		forced_lod,
		enable_frustum,
		enable_cone,
		debug_colors,
		model_transform,
		shading_mode
	)

	# 4. Teste 2: Se flag de teste de instance_count = 0 estiver ativa, zera instance_count no VkDrawIndirectCommand
	if debug_force_zero_instances:
		rd.buffer_clear(counter_buf, 4, 4)

	# 5. Desenho Indireto nativo no Viewport
	# Se p_clear_color == false: limpa apenas depth buffer local para integrar sobre a cena Godot
	# Se p_clear_color == true: limpa cor e profundidade para renderizacao isolada
	var clear_flags = RenderingDevice.DRAW_CLEAR_DEPTH
	var clear_colors = PackedColorArray()
	if p_clear_color:
		clear_flags |= RenderingDevice.DRAW_CLEAR_COLOR_0
		clear_colors.append(p_clear_color_val)

	var draw_list = rd.draw_list_begin(vp_framebuffer, clear_flags, clear_colors, 1.0, 0)
	rd.draw_list_bind_render_pipeline(draw_list, indirect_render_pipeline)
	rd.draw_list_bind_uniform_set(draw_list, indirect_uniform_set, 0)
	rd.draw_list_draw_indirect(draw_list, false, counter_buf, 0, 1, 16)
	rd.draw_list_end()

func _recreate_viewport_framebuffer(tex_rd: RID, size: Vector2i) -> void:
	if vp_framebuffer.is_valid():
		rd.free_rid(vp_framebuffer)
		vp_framebuffer = RID()
	if vp_depth_tex.is_valid():
		rd.free_rid(vp_depth_tex)
		vp_depth_tex = RID()

	vp_last_size = size

	var tf_depth = RDTextureFormat.new()
	tf_depth.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	tf_depth.width = size.x
	tf_depth.height = size.y
	tf_depth.usage_bits = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
	vp_depth_tex = rd.texture_create(tf_depth, RDTextureView.new(), [])

	vp_framebuffer = rd.framebuffer_create([tex_rd, vp_depth_tex])

	if not indirect_render_pipeline.is_valid():
		setup_indirect_raster_pipeline(size.x, size.y)

func set_indirect_draw_enabled(enabled: bool) -> void:
	enable_indirect_draw = enabled

func set_debug_force_zero_instances(force_zero: bool) -> void:
	debug_force_zero_instances = force_zero

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
