class_name ArboriaNativePipeline
extends RefCounted

## ARBORIA ENGINE — NATIVE FORWARD+ PIPELINE (V7.1 CORRIGIDO)
## Pipeline Vulkan com separação estrita de Compute/Raster, sincronização de buffers indiretos,
## suporte multi-instâncias isoladas em VRAM, eliminação de transformação duplicada e Reversed-Z Depth.

const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

static var _shared_instance = null

# Estrutura para malhas compartilhadas em VRAM (geometria bruta)
class MeshGPUResource:
	var mesh_path: String = ""
	var total_clusters: int = 0
	var total_vertices: int = 0
	var total_triangles: int = 0
	var total_groups: int = 0
	var groups_x: int = 1
	var bbox_min: Vector3 = Vector3.ZERO
	var bbox_max: Vector3 = Vector3.ZERO

	# Buffers geométricos compartilhados
	var in_clusters_buf: RID
	var in_vertices_buf: RID
	var in_triangles_buf: RID
	var selection_texture_rid: RID
	var c_mesh_id: int = -1
	var is_valid: bool = false

# Estrutura de dados GPU isolada por instância da cena
class InstanceGPUData:
	var instance_ref: WeakRef
	var mesh_path: String = ""
	var c_instance_id: int = -1
	var counter_buf: RID
	var out_visible_buf: RID
	var camera_ubo_buf: RID
	var instance_ubo_buf: RID
	var compute_uniform_set: RID
	var raster_uniform_set: RID
	var inst_albedo_tex: RID
	var inst_normal_tex: RID
	var inst_orm_tex: RID
	var is_ready: bool = false

var rd: RenderingDevice
var is_initialized: bool = false
var native_core: RefCounted = null

# Texturas PBR padrão e Sampler
var default_white_tex: RID
var default_normal_tex: RID
var default_orm_tex: RID
var default_sampler: RID

# Cache de texturas RD carregadas (Texture2D ID -> RID)
var _texture_cache: Dictionary = {}

# Cache de malhas GPU (mesh_path -> MeshGPUResource)
var _mesh_cache: Dictionary = {}

# Instâncias registradas
var _registered_instances: Array[Node3D] = []

# Mapeamento de instâncias para seus recursos GPU isolados (Instance ID -> InstanceGPUData)
var _instance_gpu_map: Dictionary = {}

# Pipelines e Shaders
var compute_shader_rid: RID
var compute_pipeline: RID
var raster_shader_rid: RID
var raster_pipeline: RID
var raster_fb_format: int = -1

# Framebuffer Cache
var cached_fb: RID
var cached_fb_color: RID
var cached_fb_depth: RID

# Configuracoes globais
var global_shading_mode: int = 0 # 0 = PBR, 1 = Normal, 2 = Unshaded, 3 = Cluster Colors
var enable_frustum_culling: bool = true
var enable_cone_culling: bool = true

# Telemetria desacoplada e assíncrona da GPU (elimina stalls no Render Loop)
var stats_total_instances: int = 0
var stats_dispatches: int = 0
var stats_indirect_draws: int = 0
var stats_clusters_evaluated: int = 0
var stats_visible_clusters: int = 0
var stats_triangles_drawn: int = 0
var enable_async_telemetry: bool = true
var _telemetry_frame_counter: int = 0
var _telemetry_interval: int = 15
var telemetry_dirty: bool = false

func get_statistics() -> Dictionary:
	return {
		"total_instances": stats_total_instances,
		"dispatches": stats_dispatches,
		"indirect_draws": stats_indirect_draws,
		"clusters_evaluated": stats_clusters_evaluated,
		"clusters_visible": stats_visible_clusters,
		"triangles_drawn": stats_triangles_drawn
	}

static func get_active_instance() -> RefCounted:
	return _shared_instance

static func get_or_create_shared() -> RefCounted:
	if not _shared_instance:
		var script_cls = load("res://scripts/arboria_native_pipeline.gd") as GDScript
		_shared_instance = script_cls.new()
	return _shared_instance

func request_telemetry_read() -> void:
	telemetry_dirty = true

func _init(p_rd: RenderingDevice = null):
	if p_rd:
		rd = p_rd
	else:
		rd = RenderingServer.get_rendering_device()

	if not rd:
		push_error("[ArboriaNativePipeline] RenderingDevice Vulkan nao disponivel!")
		return

	_shared_instance = self

	# Vinculacao oficial do backend nativo C++ por GDExtension
	if not GDExtensionManager.is_extension_loaded("res://arboria_native.gdextension"):
		var res = GDExtensionManager.load_extension("res://arboria_native.gdextension")
		if res == OK:
			print("[ArboriaNativePipeline] Backend Nativo C++ GDExtension vinculado com sucesso ao Godot.")
		else:
			push_warning("[ArboriaNativePipeline] GDExtension nao carregada (codigo: %d)" % res)

	# Instanciação ativa da classe ArboriaNativeCore no ClassDB
	if ClassDB.class_exists("ArboriaNativeCore"):
		native_core = ClassDB.instantiate("ArboriaNativeCore")
		if native_core:
			var sig = native_core.get_engine_signature()
			var valid = native_core.verify_engine_integrity()
			print("[ArboriaNativePipeline] ArboriaNativeCore C++ ativo: ", native_core.get_version())
			print("[ArboriaNativePipeline] Assinatura Criptografica: ", sig, " [Integridade: %s]" % ("VALIDADA" if valid else "VIOLADA"))
			if not valid:
				push_error("[SEGURANCA] Integridade do ARBORIA ENGINE violada ou token adulterado!")

	_setup_shaders()
	_init_default_textures()
	is_initialized = true
	print("[ArboriaNativePipeline] Inicializado com sucesso em Forward+ Vulkan (V7.2 Nativo Ativo & Assinado).")

func _init_default_textures() -> void:
	if not rd: return
	var fmt = RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = 1
	fmt.height = 1
	fmt.depth = 1
	fmt.array_layers = 1
	fmt.mipmaps = 1
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var view = RDTextureView.new()
	default_white_tex = rd.texture_create(fmt, view, [PackedByteArray([255, 255, 255, 255])])
	default_normal_tex = rd.texture_create(fmt, view, [PackedByteArray([128, 128, 255, 255])])
	default_orm_tex = rd.texture_create(fmt, view, [PackedByteArray([255, 255, 0, 255])])

	var samp_state = RDSamplerState.new()
	samp_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	samp_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	samp_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	samp_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	samp_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	default_sampler = rd.sampler_create(samp_state)

func _get_or_create_rd_texture(tex: Texture2D) -> RID:
	if not tex or not rd:
		return RID()
	var inst_id = tex.get_instance_id()
	if _texture_cache.has(inst_id):
		return _texture_cache[inst_id]

	var img = tex.get_image()
	if not img:
		return RID()

	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var fmt = RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = img.get_width()
	fmt.height = img.get_height()
	fmt.depth = 1
	fmt.array_layers = 1
	fmt.mipmaps = 1
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var view = RDTextureView.new()
	var rd_tex = rd.texture_create(fmt, view, [img.get_data()])
	_texture_cache[inst_id] = rd_tex
	return rd_tex

func _setup_shaders() -> void:
	_compile_compute_shader()
	_compile_raster_shader()

func _compile_compute_shader() -> void:
	var f = FileAccess.open("res://shaders/cull_clusters.glsl", FileAccess.READ)
	if not f:
		push_error("[ArboriaNativePipeline] Falha ao abrir res://shaders/cull_clusters.glsl")
		return
	var glsl_code = f.get_as_text()
	f.close()

	if glsl_code.begins_with("#[compute]"):
		glsl_code = glsl_code.substr(glsl_code.find("\n") + 1)

	var src = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = glsl_code
	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("[ArboriaNativePipeline] Erro de compilacao do Compute Shader: " + spirv.compile_error_compute)
		return
	compute_shader_rid = rd.shader_create_from_spirv(spirv)
	compute_pipeline = rd.compute_pipeline_create(compute_shader_rid)

func _compile_raster_shader() -> void:
	var f = FileAccess.open("res://shaders/arboria_forward_raster.glsl", FileAccess.READ)
	var full_text = ""
	if f:
		full_text = f.get_as_text()
		f.close()

	var vs_code = ""
	var fs_code = ""
	if full_text.contains("#[vertex]") and full_text.contains("#[fragment]"):
		var v_start = full_text.find("#[vertex]") + 9
		var f_start = full_text.find("#[fragment]")
		vs_code = full_text.substr(v_start, f_start - v_start).strip_edges()
		fs_code = full_text.substr(f_start + 11).strip_edges()
	else:
		push_error("[ArboriaNativePipeline] Falha ao ler secoes do arboria_forward_raster.glsl")
		return

	var src = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_vertex = vs_code
	src.source_fragment = fs_code
	var spirv = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_vertex != "" or spirv.compile_error_fragment != "":
		push_error("[ArboriaNativePipeline] Erro de compilacao do Raster Shader: " + spirv.compile_error_vertex + " " + spirv.compile_error_fragment)
		return
	raster_shader_rid = rd.shader_create_from_spirv(spirv)

func setup_raster_pipeline(color_fmt: int, depth_fmt: int) -> bool:
	if raster_pipeline.is_valid() and raster_fb_format != -1:
		return true

	var color_att = RDAttachmentFormat.new()
	color_att.format = color_fmt
	color_att.usage_flags = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	var depth_att = RDAttachmentFormat.new()
	depth_att.format = depth_fmt
	depth_att.usage_flags = RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT

	raster_fb_format = rd.framebuffer_format_create([color_att, depth_att])

	var blend = RDPipelineColorBlendState.new()
	blend.attachments.append(RDPipelineColorBlendStateAttachment.new())

	# CONTRATO REVERSED-Z VULKAN: COMPARE_OP_GREATER_OR_EQUAL (Z=1 Near, Z=0 Far/Sky)
	var depth_state = RDPipelineDepthStencilState.new()
	depth_state.enable_depth_test = true
	depth_state.enable_depth_write = true
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL

	var raster_state = RDPipelineRasterizationState.new()
	raster_state.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	raster_state.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE

	raster_pipeline = rd.render_pipeline_create(
		raster_shader_rid,
		raster_fb_format,
		-1,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		raster_state,
		RDPipelineMultisampleState.new(),
		depth_state,
		blend
	)
	return raster_pipeline.is_valid()

func get_or_load_mesh(path: String) -> Dictionary:
	if _mesh_cache.has(path):
		var cached: MeshGPUResource = _mesh_cache[path]
		return {
			"bbox_min": cached.bbox_min,
			"bbox_max": cached.bbox_max,
			"clusters": cached.total_clusters,
			"vertices": cached.total_vertices,
			"triangles": cached.total_triangles
		}

	var data = ArboriaMeshLoader.load_from_file(path)
	if data.is_empty():
		push_error("[ArboriaNativePipeline] Falha ao carregar malha: " + path)
		return {}

	var res = _upload_mesh_to_gpu(path, data)
	if res:
		_mesh_cache[path] = res
		return {
			"bbox_min": res.bbox_min,
			"bbox_max": res.bbox_max,
			"clusters": res.total_clusters,
			"vertices": res.total_vertices,
			"triangles": res.total_triangles
		}
	return {}

func _upload_mesh_to_gpu(path: String, data: Dictionary) -> MeshGPUResource:
	var res = MeshGPUResource.new()
	res.mesh_path = path

	var clusters = data.get("clusters", [])
	var groups = data.get("groups", [])
	var vertices = data.get("vertices", PackedVector3Array())
	var normals = data.get("normals", PackedVector3Array())
	var uvs = data.get("uvs", PackedVector2Array())
	var triangles = data.get("triangle_bytes", PackedByteArray())

	res.total_clusters = clusters.size()
	res.total_vertices = vertices.size()
	res.total_groups = groups.size()
	res.total_triangles = triangles.size() / 3
	res.bbox_min = data.get("bbox_min", Vector3(-1, -1, -1))
	res.bbox_max = data.get("bbox_max", Vector3(1, 1, 1))
	res.groups_x = int(ceil(float(res.total_clusters) / 64.0))

	if not rd:
		res.is_valid = true
		return res

	# 1. InClusters (96 bytes por cluster)
	var c_bytes = PackedByteArray()
	c_bytes.resize(res.total_clusters * 96)
	for i in range(res.total_clusters):
		var c = clusters[i]
		var b = i * 96

		var center = c["center"]
		c_bytes.encode_float(b + 0, center.x)
		c_bytes.encode_float(b + 4, center.y)
		c_bytes.encode_float(b + 8, center.z)
		c_bytes.encode_float(b + 12, c["radius"])

		c_bytes.encode_float(b + 16, c["normal_cone"][0])
		c_bytes.encode_float(b + 20, c["normal_cone"][1])
		c_bytes.encode_float(b + 24, c["normal_cone"][2])
		c_bytes.encode_float(b + 28, c["normal_cone"][3])

		var gid = c["group_id"]
		if gid >= 0 and gid < groups.size():
			var g = groups[gid]
			var gc = g["center"]
			c_bytes.encode_float(b + 32, gc.x)
			c_bytes.encode_float(b + 36, gc.y)
			c_bytes.encode_float(b + 40, gc.z)
			c_bytes.encode_float(b + 44, g["error"])
		else:
			c_bytes.encode_float(b + 32, 0.0)
			c_bytes.encode_float(b + 36, 0.0)
			c_bytes.encode_float(b + 40, 0.0)
			c_bytes.encode_float(b + 44, 999999.0)

		var rgid = c["refined_group"]
		if rgid >= 0 and rgid < groups.size():
			var rg = groups[rgid]
			var rgc = rg["center"]
			c_bytes.encode_float(b + 48, rgc.x)
			c_bytes.encode_float(b + 52, rgc.y)
			c_bytes.encode_float(b + 56, rgc.z)
			c_bytes.encode_float(b + 60, rg["error"])
		else:
			c_bytes.encode_float(b + 48, 0.0)
			c_bytes.encode_float(b + 52, 0.0)
			c_bytes.encode_float(b + 56, 0.0)
			c_bytes.encode_float(b + 60, -1.0)

		c_bytes.encode_u32(b + 64, c["vertex_offset"])
		c_bytes.encode_u32(b + 68, c["vertex_count"])
		c_bytes.encode_u32(b + 72, c["triangle_offset"])
		c_bytes.encode_u32(b + 76, c["triangle_count"])

		c_bytes.encode_u32(b + 80, c["cluster_id"])
		c_bytes.encode_u32(b + 84, c["lod_level"])
		c_bytes.encode_u32(b + 88, c["group_id"])
		c_bytes.encode_s32(b + 92, -1 if c["refined_group"] == 4294967295 else c["refined_group"])

	res.in_clusters_buf = rd.storage_buffer_create(c_bytes.size(), c_bytes)

	# 2. Out Selection Texture
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.width = 2048
	tf.height = max(1, int(ceil(float(res.total_clusters) / 2048.0)))
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	res.selection_texture_rid = rd.texture_create(tf, RDTextureView.new(), [])

	# 3. InVertices (32 bytes = 2x vec4)
	var raw_v_bytes = PackedByteArray()
	raw_v_bytes.resize(res.total_vertices * 32)
	for vi in range(res.total_vertices):
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
	res.in_vertices_buf = rd.storage_buffer_create(raw_v_bytes.size(), raw_v_bytes)

	# 4. InTriangles (uint32 compactados)
	var aligned_t_size = int(ceil(float(triangles.size()) / 4.0)) * 4
	var t_bytes = PackedByteArray()
	t_bytes.resize(max(4, aligned_t_size))
	for ti in range(triangles.size()):
		t_bytes[ti] = triangles[ti]
	res.in_triangles_buf = rd.storage_buffer_create(t_bytes.size(), t_bytes)

	# Registro e validacao ativa no VGRuntime C++ (API Tipada Etapa 1)
	if native_core:
		var global_path = ProjectSettings.globalize_path(path)
		if native_core.has_method("register_mesh"):
			res.c_mesh_id = native_core.register_mesh(global_path)
		elif native_core.has_method("load_mesh"):
			res.c_mesh_id = native_core.load_mesh(global_path)
		var c_clusters = native_core.get_mesh_clusters_count(res.c_mesh_id)
		print("[ArboriaNativePipeline C++] Malha registrada no VGRuntime: Handle/ID %d, Clusters: %d" % [res.c_mesh_id, c_clusters])

	res.is_valid = true
	print("[ArboriaNativePipeline] Upload GPU concluido: ", path, " (", res.total_clusters, " clusters, ", (c_bytes.size() + raw_v_bytes.size() + t_bytes.size()) / 1024, " KB)")
	return res

func _get_or_create_instance_gpu_data(inst: Node3D, mesh_res: MeshGPUResource) -> InstanceGPUData:
	var inst_id = inst.get_instance_id()
	if _instance_gpu_map.has(inst_id):
		var existing: InstanceGPUData = _instance_gpu_map[inst_id]
		if existing.mesh_path == mesh_res.mesh_path and existing.is_ready:
			return existing
		else:
			_free_instance_gpu_data(existing)

	var data = InstanceGPUData.new()
	data.instance_ref = weakref(inst)
	data.mesh_path = mesh_res.mesh_path

	if not rd:
		_instance_gpu_map[inst_id] = data
		return data

	# Registro ativo no VGSceneBridge C++ (Handle Geracional de 64 bits)
	if native_core:
		if native_core.has_method("register_instance"):
			data.c_instance_id = native_core.register_instance(mesh_res.c_mesh_id)
		elif native_core.has_method("scene_create_instance"):
			data.c_instance_id = native_core.scene_create_instance(mesh_res.c_mesh_id)
		print("[ArboriaNativePipeline C++] Instancia registrada no VGSceneBridge: Handle %d (Malha: %d)" % [data.c_instance_id, mesh_res.c_mesh_id])

	# Buffer de saida com clusters visiveis desta instancia
	data.out_visible_buf = rd.storage_buffer_create(max(4, mesh_res.total_clusters * 4))

	# Buffer de argumentos indiretos (24 bytes: 16b VkDrawIndirectCommand + 8b counters)
	var cnt_bytes = PackedByteArray()
	cnt_bytes.resize(24)
	cnt_bytes.encode_u32(0, 384) # vertex_count (128 tris * 3)
	cnt_bytes.encode_u32(4, 0)   # instance_count
	cnt_bytes.encode_u32(8, 0)   # first_vertex
	cnt_bytes.encode_u32(12, 0)  # first_instance
	cnt_bytes.encode_u32(16, 0)  # total_triangles_drawn
	cnt_bytes.encode_u32(20, 0)  # total_clusters_evaluated
	data.counter_buf = rd.storage_buffer_create(24, cnt_bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)

	# UBO de Camera (224 bytes)
	var u_cam = PackedByteArray()
	u_cam.resize(224)
	data.camera_ubo_buf = rd.uniform_buffer_create(224, u_cam)

	# UBO de Instancia (160 bytes: model_matrix + material + light)
	var u_inst = PackedByteArray()
	u_inst.resize(160)
	data.instance_ubo_buf = rd.uniform_buffer_create(160, u_inst)

	# Compute Uniform Set (Set 0)
	var cu0 = RDUniform.new()
	cu0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cu0.binding = 0
	cu0.add_id(mesh_res.in_clusters_buf)

	var cu1 = RDUniform.new()
	cu1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cu1.binding = 1
	cu1.add_id(data.out_visible_buf)

	var cu2 = RDUniform.new()
	cu2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	cu2.binding = 2
	cu2.add_id(data.counter_buf)

	var cu3 = RDUniform.new()
	cu3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	cu3.binding = 3
	cu3.add_id(data.camera_ubo_buf)

	var cu4 = RDUniform.new()
	cu4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	cu4.binding = 4
	cu4.add_id(mesh_res.selection_texture_rid)

	var cu5 = RDUniform.new()
	cu5.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	cu5.binding = 5
	cu5.add_id(default_sampler)
	cu5.add_id(default_white_tex)

	data.compute_uniform_set = rd.uniform_set_create([cu0, cu1, cu2, cu3, cu4, cu5], compute_shader_rid, 0)

	# Raster Uniform Set (Set 0)
	var ru0 = RDUniform.new()
	ru0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ru0.binding = 0
	ru0.add_id(mesh_res.in_clusters_buf)

	var ru1 = RDUniform.new()
	ru1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ru1.binding = 1
	ru1.add_id(data.out_visible_buf)

	var ru3 = RDUniform.new()
	ru3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	ru3.binding = 3
	ru3.add_id(data.camera_ubo_buf)

	var ru5 = RDUniform.new()
	ru5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ru5.binding = 5
	ru5.add_id(mesh_res.in_vertices_buf)

	var ru6 = RDUniform.new()
	ru6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	ru6.binding = 6
	ru6.add_id(mesh_res.in_triangles_buf)

	var ru7 = RDUniform.new()
	ru7.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	ru7.binding = 7
	ru7.add_id(data.instance_ubo_buf)

	var albedo_tex_rid = default_white_tex
	var normal_tex_rid = default_normal_tex
	var orm_tex_rid = default_orm_tex

	if "albedo_texture" in inst and inst.albedo_texture:
		var r = _get_or_create_rd_texture(inst.albedo_texture)
		if r.is_valid(): albedo_tex_rid = r
	if "normal_texture" in inst and inst.normal_texture:
		var r = _get_or_create_rd_texture(inst.normal_texture)
		if r.is_valid(): normal_tex_rid = r
	if "orm_texture" in inst and inst.orm_texture:
		var r = _get_or_create_rd_texture(inst.orm_texture)
		if r.is_valid(): orm_tex_rid = r

	data.inst_albedo_tex = albedo_tex_rid
	data.inst_normal_tex = normal_tex_rid
	data.inst_orm_tex = orm_tex_rid

	var ru8 = RDUniform.new()
	ru8.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ru8.binding = 8
	ru8.add_id(default_sampler)
	ru8.add_id(albedo_tex_rid)

	var ru9 = RDUniform.new()
	ru9.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ru9.binding = 9
	ru9.add_id(default_sampler)
	ru9.add_id(normal_tex_rid)

	var ru10 = RDUniform.new()
	ru10.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ru10.binding = 10
	ru10.add_id(default_sampler)
	ru10.add_id(orm_tex_rid)

	data.raster_uniform_set = rd.uniform_set_create([ru0, ru1, ru3, ru5, ru6, ru7, ru8, ru9, ru10], raster_shader_rid, 0)
	data.is_ready = true

	_instance_gpu_map[inst_id] = data
	return data

func _free_instance_gpu_data(data: InstanceGPUData) -> void:
	if not rd: return
	if native_core and data.c_instance_id != 0:
		if native_core.has_method("release_instance"):
			native_core.release_instance(data.c_instance_id)
		elif native_core.has_method("scene_destroy_instance"):
			native_core.scene_destroy_instance(data.c_instance_id)
		data.c_instance_id = 0
	if data.out_visible_buf.is_valid(): rd.free_rid(data.out_visible_buf)
	if data.counter_buf.is_valid(): rd.free_rid(data.counter_buf)
	if data.camera_ubo_buf.is_valid(): rd.free_rid(data.camera_ubo_buf)
	if data.instance_ubo_buf.is_valid(): rd.free_rid(data.instance_ubo_buf)
	data.is_ready = false

func register_instance(inst: Node3D) -> void:
	if not _registered_instances.has(inst):
		_registered_instances.append(inst)

func unregister_instance(inst: Node3D) -> void:
	_registered_instances.erase(inst)
	var inst_id = inst.get_instance_id()
	if _instance_gpu_map.has(inst_id):
		_free_instance_gpu_data(_instance_gpu_map[inst_id])
		_instance_gpu_map.erase(inst_id)

func mark_instance_dirty(_inst: Node3D) -> void:
	pass

func extract_frustum_planes(m: Projection) -> Array[Plane]:
	var planes: Array[Plane] = []
	var r0 = Vector4(m[0][0], m[1][0], m[2][0], m[3][0])
	var r1 = Vector4(m[0][1], m[1][1], m[2][1], m[3][1])
	var r2 = Vector4(m[0][2], m[1][2], m[2][2], m[3][2])
	var r3 = Vector4(m[0][3], m[1][3], m[2][3], m[3][3])

	var raw = [
		r3 + r0, # Left
		r3 - r0, # Right
		r3 + r1, # Bottom
		r3 - r1, # Top
		r2,      # Near (Reversed-Z)
		r3 - r2  # Far
	]

	for p in raw:
		var n = Vector3(p.x, p.y, p.z)
		var len_n = n.length()
		if len_n > 0.00001:
			planes.append(Plane(n / len_n, p.w / len_n))
		else:
			planes.append(Plane(Vector3.UP, 0.0))
	return planes

## Ponto de entrada de renderização chamado pelo CompositorEffect (POST_OPAQUE)
func render_scene_instances(p_render_data: RenderData) -> void:
	if not is_initialized or _registered_instances.is_empty():
		return

	var rb: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	var rsd: RenderSceneData = p_render_data.get_render_scene_data()
	if not rb or not rsd:
		return

	var color_tex = rb.get_color_texture()
	var depth_tex = rb.get_depth_texture()
	if not color_tex.is_valid() or not depth_tex.is_valid():
		return

	var col_fmt = rd.texture_get_format(color_tex)
	var dep_fmt = rd.texture_get_format(depth_tex)

	if not setup_raster_pipeline(col_fmt.format, dep_fmt.format):
		return

	# Framebuffer compartilhado nativo
	if color_tex != cached_fb_color or depth_tex != cached_fb_depth or not cached_fb.is_valid():
		if cached_fb.is_valid():
			rd.free_rid(cached_fb)
		cached_fb = rd.framebuffer_create([color_tex, depth_tex])
		cached_fb_color = color_tex
		cached_fb_depth = depth_tex

	if not cached_fb.is_valid():
		return

	var cam_proj: Projection = rsd.get_cam_projection()
	var cam_xform: Transform3D = rsd.get_cam_transform()
	var cam_pos_world: Vector3 = cam_xform.origin
	var view_mat: Projection = Projection(cam_xform.affine_inverse())
	var vp_size = Vector2(rb.get_internal_size())

	# Matriz View-Projection da Câmera (Sem model_transform para não duplicar no vertex shader!)
	var cam_view_proj: Projection = cam_proj * view_mat
	if Engine.get_process_frames() % 60 == 5:
		print("[RSD PROJ MATRIX] cam_proj: ", cam_proj)
		print("[RSD DEPTH FMT] dep_fmt: ", dep_fmt.format)

	# Coleta instâncias ativas válidas para este frame
	var active_tasks: Array[Dictionary] = []
	for inst in _registered_instances:
		if not is_instance_valid(inst) or not inst.visible or inst.mesh_path == "":
			continue

		var mesh_res: MeshGPUResource = _mesh_cache.get(inst.mesh_path, null)
		if not mesh_res:
			get_or_load_mesh(inst.mesh_path)
			mesh_res = _mesh_cache.get(inst.mesh_path, null)

		if not mesh_res or not mesh_res.is_valid:
			continue

		var inst_gpu = _get_or_create_instance_gpu_data(inst, mesh_res)
		if not inst_gpu or not inst_gpu.is_ready:
			continue

		active_tasks.append({
			"inst": inst,
			"mesh_res": mesh_res,
			"gpu_data": inst_gpu
		})

	if active_tasks.is_empty():
		return

	# =========================================================================
	# FASE 1: PREPARAÇÃO DE DADOS, SINCRONIZAÇÃO C++ E UPLOAD DE BUFFERS
	# =========================================================================
	
	# Extração da iluminação real da cena (DirectionalLight3D)
	var main_light: DirectionalLight3D = null
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene:
		main_light = tree.current_scene.find_child("*DirectionalLight3D*", true, false) as DirectionalLight3D
		if not main_light:
			for child in tree.current_scene.find_children("*", "DirectionalLight3D", true, false):
				if child is DirectionalLight3D:
					main_light = child
					break

	var light_dir = Vector3(0.5, 0.8, 0.6).normalized()
	var light_energy = 1.2
	var light_color = Color(1.0, 0.98, 0.95)
	var ambient_energy = 0.2

	if main_light and main_light.visible:
		light_dir = -main_light.global_transform.basis.z.normalized()
		light_energy = main_light.light_energy
		light_color = main_light.light_color

	for task in active_tasks:
		var inst = task["inst"]
		var mesh_res: MeshGPUResource = task["mesh_res"]
		var inst_gpu: InstanceGPUData = task["gpu_data"]

		var model_xform: Transform3D = inst.global_transform
		var cam_pos_local: Vector3 = model_xform.affine_inverse() * cam_pos_world
		var mvp_local = cam_proj * view_mat * Projection(model_xform)
		var f_planes = extract_frustum_planes(mvp_local)

		# Sincronizacao ativa de transformacao e LOD no VGSceneBridge C++
		if native_core and inst_gpu.c_instance_id > 0:
			var m = model_xform
			native_core.scene_set_transform_components(
				inst_gpu.c_instance_id,
				m.basis.x.x, m.basis.x.y, m.basis.x.z,
				m.basis.y.x, m.basis.y.y, m.basis.y.z,
				m.basis.z.x, m.basis.z.y, m.basis.z.z,
				m.origin.x, m.origin.y, m.origin.z
			)
			native_core.scene_set_lod(
				inst_gpu.c_instance_id,
				inst.max_screen_error,
				inst.lod_mode,
				inst.forced_lod
			)

		# 1. Atualiza Camera UBO desta instancia (224 bytes)
		var u_cam = PackedByteArray()
		u_cam.resize(224)

		for col in range(4):
			for row in range(4):
				u_cam.encode_float((col * 4 + row) * 4, cam_view_proj[col][row])

		for i in range(min(6, f_planes.size())):
			var pl = f_planes[i]
			var p_off = 64 + i * 16
			u_cam.encode_float(p_off + 0, pl.normal.x)
			u_cam.encode_float(p_off + 4, pl.normal.y)
			u_cam.encode_float(p_off + 8, pl.normal.z)
			u_cam.encode_float(p_off + 12, pl.d)

		u_cam.encode_float(160, cam_pos_local.x)
		u_cam.encode_float(164, cam_pos_local.y)
		u_cam.encode_float(168, cam_pos_local.z)
		var fov_rad = deg_to_rad(60.0)
		var fov_factor = 1.0 / tan(fov_rad * 0.5)
		u_cam.encode_float(172, fov_factor)

		u_cam.encode_float(176, vp_size.x)
		u_cam.encode_float(180, vp_size.y)
		u_cam.encode_float(184, inst.max_screen_error)
		u_cam.encode_float(188, float(inst.lod_mode))

		u_cam.encode_u32(192, mesh_res.total_clusters)
		u_cam.encode_u32(196, inst.lod_mode)
		u_cam.encode_u32(200, inst.forced_lod)
		u_cam.encode_u32(204, 0)

		u_cam.encode_u32(208, global_shading_mode)
		u_cam.encode_u32(212, 1 if enable_frustum_culling else 0)
		u_cam.encode_u32(216, 1 if enable_cone_culling else 0)
		u_cam.encode_u32(220, 0)

		rd.buffer_update(inst_gpu.camera_ubo_buf, 0, u_cam.size(), u_cam)

		# 2. Atualiza Instance UBO desta instancia (160 bytes: PBR e Luz Real)
		var u_inst = PackedByteArray()
		u_inst.resize(160)
		var model_proj = Projection(model_xform)
		for col in range(4):
			for row in range(4):
				u_inst.encode_float((col * 4 + row) * 4, model_proj[col][row])

		u_inst.encode_float(64, inst.base_albedo.r)
		u_inst.encode_float(68, inst.base_albedo.g)
		u_inst.encode_float(72, inst.base_albedo.b)
		u_inst.encode_float(76, inst.roughness)

		var has_tex = 1.0 if (("albedo_texture" in inst and inst.albedo_texture) or ("normal_texture" in inst and inst.normal_texture)) else 0.0
		u_inst.encode_float(80, inst.metallic)
		u_inst.encode_float(84, inst.specular)
		u_inst.encode_float(88, 0.0)
		u_inst.encode_float(92, has_tex)

		u_inst.encode_float(96, light_dir.x)
		u_inst.encode_float(100, light_dir.y)
		u_inst.encode_float(104, light_dir.z)
		u_inst.encode_float(108, light_energy)

		u_inst.encode_float(112, light_color.r)
		u_inst.encode_float(116, light_color.g)
		u_inst.encode_float(120, light_color.b)
		u_inst.encode_float(124, ambient_energy)

		var uv_sc = inst.uv_scale if "uv_scale" in inst else Vector2.ONE
		var n_sc = inst.normal_scale if "normal_scale" in inst else 1.0
		u_inst.encode_float(128, uv_sc.x)
		u_inst.encode_float(132, uv_sc.y)
		u_inst.encode_float(136, n_sc)
		u_inst.encode_float(140, 0.0)

		rd.buffer_update(inst_gpu.instance_ubo_buf, 0, u_inst.size(), u_inst)

		# 3. Zera os contadores no counter_buf antes do compute
		var reset_args = PackedByteArray()
		reset_args.resize(24)
		reset_args.encode_u32(0, 384)
		reset_args.encode_u32(4, 0)
		reset_args.encode_u32(8, 0)
		reset_args.encode_u32(12, 0)
		reset_args.encode_u32(16, 0)
		reset_args.encode_u32(20, 0)
		rd.buffer_update(inst_gpu.counter_buf, 0, reset_args.size(), reset_args)

	# =========================================================================
	# FASE 2 & 3: PIPELINE GRÁFICO 100% EXECUTADO EM C++ NATIVO
	# GPU Upload -> Compute Dispatch -> GPU Sync -> Indirect Draw -> Render Pass
	# =========================================================================
	var compute_sets: Array[RID] = []
	var groups_x: Array[int] = []
	var raster_sets: Array[RID] = []
	var counter_bufs: Array[RID] = []

	for task in active_tasks:
		var mesh_res: MeshGPUResource = task["mesh_res"]
		var inst_gpu: InstanceGPUData = task["gpu_data"]
		compute_sets.append(inst_gpu.compute_uniform_set)
		groups_x.append(mesh_res.groups_x)
		raster_sets.append(inst_gpu.raster_uniform_set)
		counter_bufs.append(inst_gpu.counter_buf)

	if native_core and native_core.has_method("render_scene_batch"):
		native_core.render_scene_batch(
			rd,
			cached_fb,
			compute_pipeline,
			raster_pipeline,
			compute_sets,
			groups_x,
			raster_sets,
			counter_bufs,
			active_tasks.size(),
			PackedColorArray()
		)

	stats_total_instances = active_tasks.size()
	stats_dispatches = active_tasks.size()
	stats_indirect_draws = active_tasks.size()
	var eval_acc: int = 0
	for task in active_tasks:
		var m_res: MeshGPUResource = task.get("mesh_res", null)
		if m_res:
			eval_acc += m_res.total_clusters
	stats_clusters_evaluated = eval_acc

	_telemetry_frame_counter += 1

	var should_read_gpu = (not enable_async_telemetry) or telemetry_dirty or (_telemetry_frame_counter % _telemetry_interval == 0)
	if should_read_gpu:
		telemetry_dirty = false
		var vis_acc = 0
		var tri_acc = 0
		for task in active_tasks:
			var inst_gpu: InstanceGPUData = task["gpu_data"]
			var cnt_data = rd.buffer_get_data(inst_gpu.counter_buf)
			if cnt_data.size() >= 24:
				vis_acc += cnt_data.decode_u32(4)
				tri_acc += cnt_data.decode_u32(16)
		stats_visible_clusters = vis_acc
		stats_triangles_drawn = tri_acc
		if _telemetry_frame_counter % 60 == 0:
			print("[ARBORIA GPU TELEMETRIA NÃO-BLOQUEANTE] Instancias: ", stats_total_instances, " Clusters: ", stats_visible_clusters, " Triangulos: ", stats_triangles_drawn)

func cleanup() -> void:
	if not rd:
		return

	for inst_id in _instance_gpu_map:
		_free_instance_gpu_data(_instance_gpu_map[inst_id])
	_instance_gpu_map.clear()

	for path in _mesh_cache:
		var res: MeshGPUResource = _mesh_cache[path]
		if native_core and res.c_mesh_id != 0:
			if native_core.has_method("unregister_mesh"):
				native_core.unregister_mesh(res.c_mesh_id)
			res.c_mesh_id = 0
		if res.in_clusters_buf.is_valid(): rd.free_rid(res.in_clusters_buf)
		if res.in_vertices_buf.is_valid(): rd.free_rid(res.in_vertices_buf)
		if res.in_triangles_buf.is_valid(): rd.free_rid(res.in_triangles_buf)
		if res.selection_texture_rid.is_valid(): rd.free_rid(res.selection_texture_rid)
	_mesh_cache.clear()

	if native_core and native_core.has_method("shutdown"):
		native_core.shutdown()

	if default_white_tex.is_valid():
		rd.free_rid(default_white_tex)
		default_white_tex = RID()
	if default_normal_tex.is_valid():
		rd.free_rid(default_normal_tex)
		default_normal_tex = RID()
	if default_orm_tex.is_valid():
		rd.free_rid(default_orm_tex)
		default_orm_tex = RID()
	if default_sampler.is_valid():
		rd.free_rid(default_sampler)
		default_sampler = RID()

	for t_id in _texture_cache:
		var t_rid: RID = _texture_cache[t_id]
		if t_rid.is_valid():
			rd.free_rid(t_rid)
	_texture_cache.clear()

	if cached_fb.is_valid():
		rd.free_rid(cached_fb)
		cached_fb = RID()
	if compute_pipeline.is_valid():
		rd.free_rid(compute_pipeline)
		compute_pipeline = RID()
	if compute_shader_rid.is_valid():
		rd.free_rid(compute_shader_rid)
		compute_shader_rid = RID()
	if raster_pipeline.is_valid():
		rd.free_rid(raster_pipeline)
		raster_pipeline = RID()
	if raster_shader_rid.is_valid():
		rd.free_rid(raster_shader_rid)
		raster_shader_rid = RID()

	native_core = null
	_shared_instance = null
	is_initialized = false
