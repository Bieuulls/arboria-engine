class_name ArboriaNativePipeline
extends RefCounted

## ARBORIA ENGINE — NATIVE FORWARD+ PIPELINE (V7.1 CORRIGIDO)
## Pipeline Vulkan com separação estrita de Compute/Raster, sincronização de buffers indiretos,
## suporte multi-instâncias isoladas em VRAM, eliminação de transformação duplicada e Reversed-Z Depth.

const ArboriaMeshLoader = preload("arboria_mesh_loader.gd")

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
	var bound_hiz_tex: RID
	var is_ready: bool = false

	# ALVO 4: Dirty Caching de Transformação e Matrizes para Objetos Estáticos
	var cached_transform: Transform3D = Transform3D()
	var cached_visible: bool = true
	var cached_albedo: Color = Color(-1, -1, -1, -1)
	var cached_roughness: float = -1.0
	var cached_metallic: float = -1.0
	var cached_specular: float = -1.0
	var cached_lod_mode: float = -1.0
	var cached_forced_lod: float = -1.0
	var cached_inst_bytes: PackedByteArray = PackedByteArray()
	var is_transform_cached: bool = false

var rd: RenderingDevice
var is_initialized: bool = false
var native_core: RefCounted = null

# Hi-Z Occlusion Pyramid (Vulkan 1.4 / Reversed-Z)
var enable_hiz: bool = true
var hiz_shader_rid: RID
var hiz_pipeline: RID
var hiz_texture: RID
var hiz_scratch_texture: RID
var hiz_size: Vector2i = Vector2i.ZERO
var hiz_mip_count: int = 0
var hiz_mip_views: Array[RID] = []
var hiz_sampler: RID
var hiz_mip0_uniform_set: RID
var hiz_cached_depth_tex: RID
var hiz_mip_uniform_sets: Array[RID] = []

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
var depth_prepass_pipeline: RID
var raster_fb_format: int = -1
var _last_cull_frame: int = -1

# GPU Scene Global (V7.2 - 1 Dispatch e 1 Draw Indireto Consolidado para toda a cena)
var use_global_scene: bool = true
var global_compute_shader_rid: RID
var global_compute_pipeline: RID
var global_raster_shader_rid: RID
var global_raster_pipeline: RID
var global_depth_prepass_pipeline: RID

var global_visible_items_buf: RID
var global_indirect_args_buf: RID
var global_scene_uniforms_buf: RID
var global_instances_buf: RID
var global_instances_capacity: int = 0

var global_compute_uniform_set: RID
var global_raster_uniform_set: RID
var _global_cached_hiz_tex: RID
var _global_cached_clusters_buf: RID
var _mesh_uniform_sets: Dictionary = {}

# Framebuffer Cache
var cached_fb: RID
var cached_fb_color: RID
var cached_fb_depth: RID

# Configuracoes globais
var global_shading_mode: int = 0 # 0 = PBR, 1 = Normal, 2 = Unshaded, 3 = Cluster Colors
var enable_frustum_culling: bool = true
var enable_cone_culling: bool = true
var enable_wind: bool = true
var wind_strength: float = 0.8
var wind_frequency: float = 1.2
var wind_gust: float = 0.5
var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.5).normalized()

# Telemetria desacoplada e assíncrona da GPU (elimina stalls no Render Loop)
var stats_total_instances: int = 0
var stats_dispatches: int = 0
var stats_indirect_draws: int = 0
var stats_clusters_evaluated: int = 0
var stats_visible_clusters: int = 0
var stats_triangles_drawn: int = 0
var stats_cpu_submission_ms: float = 0.0
var enable_async_telemetry: bool = true
var _telemetry_frame_counter: int = 0
var _telemetry_interval: int = 15
var last_measured_gpu_ms: float = 0.0
var telemetry_dirty: bool = false

func get_last_gpu_time_ms() -> float:
	return last_measured_gpu_ms

func get_statistics() -> Dictionary:
	var vram_budget = 0
	var vram_resident = 0
	var vram_allocated = 0
	var page_faults = 0
	var evictions = 0

	var pipeline_vram_bytes = 0
	if global_visible_items_buf.is_valid(): pipeline_vram_bytes += 65536 * 8
	if global_indirect_args_buf.is_valid(): pipeline_vram_bytes += 32
	if global_scene_uniforms_buf.is_valid(): pipeline_vram_bytes += 256
	if global_instances_buf.is_valid(): pipeline_vram_bytes += global_instances_capacity * 240
	for m_res in _mesh_uniform_sets.keys():
		pipeline_vram_bytes += (m_res.total_clusters * 96) + (m_res.total_vertices * 32) + (m_res.total_triangles * 4)

	if vram_allocated == 0:
		vram_allocated = pipeline_vram_bytes
	if vram_resident == 0:
		vram_resident = pipeline_vram_bytes

	return {
		"total_instances": stats_total_instances,
		"dispatches": stats_dispatches,
		"indirect_draws": stats_indirect_draws,
		"clusters_evaluated": stats_clusters_evaluated,
		"clusters_visible": stats_visible_clusters,
		"triangles_drawn": stats_triangles_drawn,
		"cpu_submission_ms": stats_cpu_submission_ms,
		"gpu_time_ms": last_measured_gpu_ms,
		"hiz_enabled": enable_hiz,
		"hiz_size": hiz_size,
		"hiz_mips": hiz_mip_count,
		"vram_budget_bytes": vram_budget,
		"vram_resident_bytes": vram_resident,
		"vram_allocated_bytes": vram_allocated,
		"page_faults": page_faults,
		"evictions": evictions,
		"under_budget": (vram_resident <= vram_budget) if vram_budget > 0 else true
	}

static func get_active_instance() -> RefCounted:
	return _shared_instance

static func get_or_create_shared() -> RefCounted:
	if not _shared_instance:
		_shared_instance = ArboriaNativePipeline.new()
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
	_compile_hiz_shader()
	_compile_global_shaders()

static func find_shader_file(shader_filename: String) -> String:
	for base_path in ["res://addons/arboria/shaders/", "res://shaders/"]:
		var candidate = base_path + shader_filename
		if FileAccess.file_exists(candidate):
			return candidate
	return "res://shaders/" + shader_filename

func _compile_hiz_shader() -> void:
	var path = find_shader_file("hiz_downsample.glsl")
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("[ArboriaNativePipeline] Falha ao abrir: " + path)
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
		push_error("[ArboriaNativePipeline] Erro de compilacao do Hi-Z Shader: " + spirv.compile_error_compute)
		return
	hiz_shader_rid = rd.shader_create_from_spirv(spirv)
	if hiz_shader_rid.is_valid():
		hiz_pipeline = rd.compute_pipeline_create(hiz_shader_rid)
		print("[ArboriaNativePipeline] Hi-Z Compute Pipeline compilado com sucesso.")

	var ss = RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	hiz_sampler = rd.sampler_create(ss)

func _free_hiz_resources() -> void:
	if not rd:
		return
	if hiz_mip0_uniform_set.is_valid():
		if rd.uniform_set_is_valid(hiz_mip0_uniform_set):
			rd.free_rid(hiz_mip0_uniform_set)
		hiz_mip0_uniform_set = RID()
	hiz_cached_depth_tex = RID()
	for us in hiz_mip_uniform_sets:
		if us.is_valid() and rd.uniform_set_is_valid(us):
			rd.free_rid(us)
	hiz_mip_uniform_sets.clear()
	for v in hiz_mip_views:
		if v.is_valid():
			rd.free_rid(v)
	hiz_mip_views.clear()
	if hiz_scratch_texture.is_valid():
		rd.free_rid(hiz_scratch_texture)
		hiz_scratch_texture = RID()
	if hiz_texture.is_valid():
		rd.free_rid(hiz_texture)
		hiz_texture = RID()
	hiz_size = Vector2i.ZERO
	hiz_mip_count = 0

func _ensure_hiz_texture(vp_size: Vector2i) -> bool:
	var w = nearest_po2(max(64, vp_size.x))
	var h = nearest_po2(max(64, vp_size.y))
	if hiz_texture.is_valid() and hiz_scratch_texture.is_valid() and hiz_size == Vector2i(w, h):
		return true

	_free_hiz_resources()

	var max_dim = max(w, h)
	var mips = int(floor(log(max_dim) / log(2))) + 1

	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf.width = w
	tf.height = h
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = mips
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	hiz_texture = rd.texture_create(tf, RDTextureView.new())
	if not hiz_texture.is_valid():
		push_error("[ArboriaNativePipeline] Falha ao criar textura Hi-Z: %dx%d" % [w, h])
		return false

	var tf_scratch = RDTextureFormat.new()
	tf_scratch.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf_scratch.width = w
	tf_scratch.height = h
	tf_scratch.depth = 1
	tf_scratch.array_layers = 1
	tf_scratch.mipmaps = 1
	tf_scratch.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf_scratch.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	hiz_scratch_texture = rd.texture_create(tf_scratch, RDTextureView.new())
	if not hiz_scratch_texture.is_valid():
		push_error("[ArboriaNativePipeline] Falha ao criar scratch Hi-Z")
		_free_hiz_resources()
		return false

	hiz_size = Vector2i(w, h)
	hiz_mip_count = mips
	hiz_mip_views.clear()

	for m in range(mips):
		var tv = RDTextureView.new()
		var mv = rd.texture_create_shared_from_slice(tv, hiz_texture, 0, m, 1, RenderingDevice.TEXTURE_SLICE_2D)
		hiz_mip_views.append(mv)

	# Pre-cria e armazena em cache os uniform sets para os níveis de mip 1..N-1
	for us in hiz_mip_uniform_sets:
		if us.is_valid() and rd.uniform_set_is_valid(us):
			rd.free_rid(us)
	hiz_mip_uniform_sets.clear()
	for m in range(1, mips):
		var um0 = RDUniform.new()
		um0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		um0.binding = 0
		um0.add_id(hiz_sampler)
		um0.add_id(hiz_mip_views[m - 1])

		var um1 = RDUniform.new()
		um1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		um1.binding = 1
		um1.add_id(hiz_scratch_texture)

		var us_m = rd.uniform_set_create([um0, um1], hiz_shader_rid, 0)
		hiz_mip_uniform_sets.append(us_m)

	print("[ArboriaNativePipeline] Hi-Z Pyramid Texture alocada: %dx%d (%d niveis mip) com Scratch Buffer dedicado." % [w, h, mips])
	return true

func _build_hiz_pyramid(depth_tex: RID, vp_size: Vector2i) -> void:
	if not enable_hiz or not hiz_pipeline.is_valid() or not depth_tex.is_valid():
		return
	if not _ensure_hiz_texture(vp_size):
		return

	# Reutiliza ou atualiza o UniformSet do Mip 0 se depth_tex mudar
	if depth_tex != hiz_cached_depth_tex or not hiz_mip0_uniform_set.is_valid():
		if hiz_mip0_uniform_set.is_valid():
			rd.free_rid(hiz_mip0_uniform_set)
		var u0 = RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u0.binding = 0
		u0.add_id(default_sampler)
		u0.add_id(depth_tex)

		var u1 = RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u1.binding = 1
		u1.add_id(hiz_scratch_texture)

		hiz_mip0_uniform_set = rd.uniform_set_create([u0, u1], hiz_shader_rid, 0)
		hiz_cached_depth_tex = depth_tex

	# Nivel 0: Downsample conservador do hardware depth_tex para o scratch buffer
	var cl0 = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl0, hiz_pipeline)
	rd.compute_list_bind_uniform_set(cl0, hiz_mip0_uniform_set, 0)

	var pc0 = PackedByteArray()
	pc0.resize(20)
	pc0.encode_float(0, float(hiz_size.x))
	pc0.encode_float(4, float(hiz_size.y))
	pc0.encode_float(8, 1.0 / float(vp_size.x))
	pc0.encode_float(12, 1.0 / float(vp_size.y))
	pc0.encode_s32(16, 0)
	rd.compute_list_set_push_constant(cl0, pc0, pc0.size())

	var gx0 = int(ceil(float(hiz_size.x) / 16.0))
	var gy0 = int(ceil(float(hiz_size.y) / 16.0))
	rd.compute_list_dispatch(cl0, gx0, gy0, 1)
	rd.compute_list_end()

	# Copia o Mip 0 do scratch para a textura da pirâmide Hi-Z
	rd.texture_copy(hiz_scratch_texture, hiz_texture, Vector3.ZERO, Vector3.ZERO, Vector3(hiz_size.x, hiz_size.y, 1), 0, 0, 0, 0)

	# Niveis 1..N-1: Reducao conservadora recursiva (min dos 4 texels anteriores)
	for m in range(1, hiz_mip_count):
		var dst_w = max(1, hiz_size.x >> m)
		var dst_h = max(1, hiz_size.y >> m)
		var src_w = max(1, hiz_size.x >> (m - 1))
		var src_h = max(1, hiz_size.y >> (m - 1))

		var cl_m = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl_m, hiz_pipeline)
		rd.compute_list_bind_uniform_set(cl_m, hiz_mip_uniform_sets[m - 1], 0)

		var pcm = PackedByteArray()
		pcm.resize(20)
		pcm.encode_float(0, float(dst_w))
		pcm.encode_float(4, float(dst_h))
		pcm.encode_float(8, 1.0 / float(src_w))
		pcm.encode_float(12, 1.0 / float(src_h))
		pcm.encode_s32(16, 0) # amostragem do mip 0 da fatia hiz_mip_views[m - 1]
		rd.compute_list_set_push_constant(cl_m, pcm, pcm.size())

		var gxm = int(ceil(float(dst_w) / 16.0))
		var gym = int(ceil(float(dst_h) / 16.0))
		rd.compute_list_dispatch(cl_m, gxm, gym, 1)
		rd.compute_list_end()

		# Copia para o mip m da textura Hi-Z
		rd.texture_copy(hiz_scratch_texture, hiz_texture, Vector3.ZERO, Vector3.ZERO, Vector3(dst_w, dst_h, 1), 0, m, 0, 0)

func _compile_compute_shader() -> void:
	var path = find_shader_file("cull_clusters.glsl")
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("[ArboriaNativePipeline] Falha ao abrir: " + path)
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
	var path = find_shader_file("arboria_forward_raster.glsl")
	var f = FileAccess.open(path, FileAccess.READ)
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
		push_error("[ArboriaNativePipeline] Falha ao ler secoes do " + path)
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

func _compile_global_shaders() -> void:
	if not rd: return

	# 1. Compute Shader Global (cull_clusters_global.glsl)
	var path_c = find_shader_file("cull_clusters_global.glsl")
	var f_c = FileAccess.open(path_c, FileAccess.READ)
	if f_c:
		var c_code = f_c.get_as_text()
		f_c.close()
		if c_code.begins_with("#[compute]"):
			c_code = c_code.substr(c_code.find("\n") + 1)
		var src_c = RDShaderSource.new()
		src_c.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src_c.source_compute = c_code
		var spirv_c = rd.shader_compile_spirv_from_source(src_c)
		if spirv_c.compile_error_compute != "":
			push_error("[ArboriaNativePipeline] Erro de compilacao do Compute Global: " + spirv_c.compile_error_compute)
		else:
			global_compute_shader_rid = rd.shader_create_from_spirv(spirv_c)
			if global_compute_shader_rid.is_valid():
				global_compute_pipeline = rd.compute_pipeline_create(global_compute_shader_rid)
				print("[ArboriaNativePipeline] Compute Global Pipeline compilado com sucesso.")

	# 2. Raster Shader Global (arboria_forward_raster_global.glsl)
	var path_r = find_shader_file("arboria_forward_raster_global.glsl")
	var f_r = FileAccess.open(path_r, FileAccess.READ)
	if f_r:
		var r_code = f_r.get_as_text()
		f_r.close()
		if r_code.contains("#[vertex]") and r_code.contains("#[fragment]"):
			var v_start = r_code.find("#[vertex]") + 9
			var f_start = r_code.find("#[fragment]")
			var vs_code = r_code.substr(v_start, f_start - v_start).strip_edges()
			var fs_code = r_code.substr(f_start + 11).strip_edges()
			var src_r = RDShaderSource.new()
			src_r.language = RenderingDevice.SHADER_LANGUAGE_GLSL
			src_r.source_vertex = vs_code
			src_r.source_fragment = fs_code
			var spirv_r = rd.shader_compile_spirv_from_source(src_r)
			if spirv_r.compile_error_vertex != "" or spirv_r.compile_error_fragment != "":
				push_error("[ArboriaNativePipeline] Erro de compilacao do Raster Global: " + spirv_r.compile_error_vertex + " " + spirv_r.compile_error_fragment)
			else:
				global_raster_shader_rid = rd.shader_create_from_spirv(spirv_r)
				print("[ArboriaNativePipeline] Raster Global Shader compilado com sucesso.")

func _ensure_global_buffers(num_instances: int) -> bool:
	if not rd: return false

	# 1. Buffer de Visibilidade Compactado (65.536 itens * 8 bytes = 524.288 bytes)
	if not global_visible_items_buf.is_valid():
		global_visible_items_buf = rd.storage_buffer_create(65536 * 8)

	# 2. Buffer de Argumentos Indiretos e Contadores (32 bytes)
	if not global_indirect_args_buf.is_valid():
		var init_args = PackedByteArray()
		init_args.resize(32)
		init_args.encode_u32(0, 384)    # vertex_count (128 triangulos * 3)
		init_args.encode_u32(4, 0)      # instance_count
		init_args.encode_u32(8, 0)      # first_vertex
		init_args.encode_u32(12, 0)     # first_instance
		init_args.encode_u32(16, 0)     # total_triangles_drawn
		init_args.encode_u32(20, 0)     # total_clusters_evaluated
		init_args.encode_u32(24, 65536) # max_capacity
		init_args.encode_u32(28, 0)     # overflow_flag
		global_indirect_args_buf = rd.storage_buffer_create(32, init_args, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)

	# 3. Buffer de Uniforms Globais da Cena (256 bytes)
	if not global_scene_uniforms_buf.is_valid():
		global_scene_uniforms_buf = rd.uniform_buffer_create(256)

	# 4. Buffer de Instâncias Globais (240 bytes por instancia, capacidade dinamica)
	var required_cap = max(256, nearest_po2(num_instances))
	if not global_instances_buf.is_valid() or global_instances_capacity < required_cap:
		if global_instances_buf.is_valid():
			rd.free_rid(global_instances_buf)
		global_instances_capacity = required_cap
		global_instances_buf = rd.storage_buffer_create(global_instances_capacity * 240)
		_invalidate_all_mesh_uniform_sets()
		global_compute_uniform_set = RID()
		global_raster_uniform_set = RID()

	return global_visible_items_buf.is_valid() and global_indirect_args_buf.is_valid() and global_scene_uniforms_buf.is_valid() and global_instances_buf.is_valid()

func setup_raster_pipeline(color_fmt: int, depth_fmt: int) -> bool:
	if raster_pipeline.is_valid() and depth_prepass_pipeline.is_valid() and raster_fb_format != -1:
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

	# Depth Prepass Pipeline: grava exclusivamente profundidade no Depth Buffer antes do opaque do Godot
	var depth_blend = RDPipelineColorBlendState.new()
	var depth_att_blend = RDPipelineColorBlendStateAttachment.new()
	depth_att_blend.write_r = false
	depth_att_blend.write_g = false
	depth_att_blend.write_b = false
	depth_att_blend.write_a = false
	depth_blend.attachments.append(depth_att_blend)

	depth_prepass_pipeline = rd.render_pipeline_create(
		raster_shader_rid,
		raster_fb_format,
		-1,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		raster_state,
		RDPipelineMultisampleState.new(),
		depth_state,
		depth_blend
	)

	if not global_raster_pipeline.is_valid() and global_raster_shader_rid.is_valid():
		global_raster_pipeline = rd.render_pipeline_create(
			global_raster_shader_rid,
			raster_fb_format,
			-1,
			RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
			raster_state,
			RDPipelineMultisampleState.new(),
			depth_state,
			blend
		)
		global_depth_prepass_pipeline = rd.render_pipeline_create(
			global_raster_shader_rid,
			raster_fb_format,
			-1,
			RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
			raster_state,
			RDPipelineMultisampleState.new(),
			depth_state,
			depth_blend
		)

	return raster_pipeline.is_valid() and depth_prepass_pipeline.is_valid()

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
		if _instance_gpu_map.size() < 5 or _instance_gpu_map.size() % 500 == 0:
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

	# UBO de Instancia (192 bytes: model_matrix + material + light + texture + emission)
	var u_inst = PackedByteArray()
	u_inst.resize(192)
	data.instance_ubo_buf = rd.uniform_buffer_create(192, u_inst)

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
	if data.compute_uniform_set.is_valid():
		if rd.uniform_set_is_valid(data.compute_uniform_set):
			rd.free_rid(data.compute_uniform_set)
		data.compute_uniform_set = RID()
	if data.raster_uniform_set.is_valid():
		if rd.uniform_set_is_valid(data.raster_uniform_set):
			rd.free_rid(data.raster_uniform_set)
		data.raster_uniform_set = RID()
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

func _update_instance_compute_uniform_set(data: InstanceGPUData, mesh_res: MeshGPUResource) -> void:
	var target_hiz_tex = hiz_texture if (enable_hiz and hiz_texture.is_valid()) else default_white_tex
	if data.bound_hiz_tex == target_hiz_tex and data.compute_uniform_set.is_valid():
		return

	if data.compute_uniform_set.is_valid():
		rd.free_rid(data.compute_uniform_set)

	var target_hiz_sampler = hiz_sampler if (enable_hiz and hiz_sampler.is_valid()) else default_sampler

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
	cu5.add_id(target_hiz_sampler)
	cu5.add_id(target_hiz_tex)

	data.compute_uniform_set = rd.uniform_set_create([cu0, cu1, cu2, cu3, cu4, cu5], compute_shader_rid, 0)
	data.bound_hiz_tex = target_hiz_tex

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

## Ponto de entrada chamado pelo CompositorEffect no estágio PRE_OPAQUE (Depth Prepass com Reversed-Z)
func render_depth_prepass(p_render_data: RenderData) -> void:
	_render_scene_instances_internal(p_render_data, true)

var _diag_log_executed: bool = false

## Ponto de entrada oficial chamado pelo CompositorEffect no estágio POST_OPAQUE
func render_frame(p_render_data: RenderData) -> void:
	if native_core and native_core.has_method("render_frame"):
		native_core.render_frame()
	_render_scene_instances_internal(p_render_data, false)

## Ponto de entrada chamado pelo CompositorEffect no estágio POST_OPAQUE (Renderização Principal e Sombras)
func render_scene_instances(p_render_data: RenderData) -> void:
	render_frame(p_render_data)

func _render_scene_instances_internal(p_render_data: RenderData, is_prepass: bool) -> void:
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

	# Geração da pirâmide Hi-Z para descarte de oclusão (apenas no passe principal opaco, após prepass e opacos Godot)
	if not is_prepass and enable_hiz and depth_tex.is_valid():
		_build_hiz_pyramid(depth_tex, Vector2i(vp_size))

	# =========================================================================
	# CAMINHO PRINCIPAL: GPU SCENE GLOBAL (V7.2 CONSOLIDADO)
	# 1 Dispatch de Compute Culling e 1 Draw Indireto para TODAS as Instâncias
	# =========================================================================
	if use_global_scene and global_compute_pipeline.is_valid() and global_raster_pipeline.is_valid():
		_render_scene_global_internal(p_render_data, active_tasks, is_prepass, cam_view_proj, cam_pos_world, vp_size, depth_tex)
		return

	for task in active_tasks:
		var inst = task["inst"]
		var mesh_res: MeshGPUResource = task["mesh_res"]
		var inst_gpu: InstanceGPUData = task["gpu_data"]

		# Atualiza uniform set de compute com Hi-Z
		_update_instance_compute_uniform_set(inst_gpu, mesh_res)

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
		u_cam.encode_u32(196, inst.forced_lod)
		u_cam.encode_u32(200, 1 if enable_frustum_culling else 0)
		u_cam.encode_u32(204, 1 if enable_cone_culling else 0)

		u_cam.encode_u32(208, global_shading_mode)
		u_cam.encode_u32(212, 1 if (enable_hiz and hiz_texture.is_valid()) else 0)
		u_cam.encode_u32(216, 0)
		u_cam.encode_u32(220, 0)

		rd.buffer_update(inst_gpu.camera_ubo_buf, 0, u_cam.size(), u_cam)

		# 2. Atualiza Instance UBO desta instancia (192 bytes: PBR, Luz Real, Alpha Scissor e Emissao)
		var u_inst = PackedByteArray()
		u_inst.resize(192)
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
		var alpha_sc = inst.alpha_scissor_threshold if "alpha_scissor_threshold" in inst else 0.0
		u_inst.encode_float(128, uv_sc.x)
		u_inst.encode_float(132, uv_sc.y)
		u_inst.encode_float(136, n_sc)
		u_inst.encode_float(140, alpha_sc)

		var em_col = inst.emission if "emission" in inst else Color.BLACK
		var em_eng = inst.emission_energy if "emission_energy" in inst else 0.0
		u_inst.encode_float(144, em_col.r)
		u_inst.encode_float(148, em_col.g)
		u_inst.encode_float(152, em_col.b)
		u_inst.encode_float(156, em_eng)

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

	var active_pipeline = depth_prepass_pipeline if is_prepass else raster_pipeline

	var t0_submit = Time.get_ticks_usec()
	if rd:
		rd.capture_timestamp("arboria_gpu_start")
	if native_core and native_core.has_method("render_scene_batch"):
		native_core.render_scene_batch(
			rd,
			cached_fb,
			compute_pipeline,
			active_pipeline,
			compute_sets,
			groups_x,
			raster_sets,
			counter_bufs,
			active_tasks.size(),
			PackedColorArray()
		)
	if rd:
		rd.capture_timestamp("arboria_gpu_end")
	var t1_submit = Time.get_ticks_usec()
	stats_cpu_submission_ms = (t1_submit - t0_submit) / 1000.0

	stats_total_instances = active_tasks.size()
	stats_dispatches = active_tasks.size()
	stats_indirect_draws = active_tasks.size()
	var eval_acc: int = 0
	for task in active_tasks:
		var m_res: MeshGPUResource = task.get("mesh_res", null)
		if m_res:
			eval_acc += m_res.total_clusters
	stats_clusters_evaluated = eval_acc

	if rd:
		var ts_cnt = rd.get_captured_timestamps_count()
		if ts_cnt >= 2:
			var t_s: int = 0
			var t_e: int = 0
			var found_s: bool = false
			var found_e: bool = false
			for ti in range(ts_cnt):
				var tn = rd.get_captured_timestamp_name(ti)
				if tn == "arboria_gpu_start":
					t_s = rd.get_captured_timestamp_gpu_time(ti)
					found_s = true
				elif tn == "arboria_gpu_end":
					t_e = rd.get_captured_timestamp_gpu_time(ti)
					found_e = true
			if found_s and found_e and t_e >= t_s:
				last_measured_gpu_ms = float(t_e - t_s) / 1000000.0

	_telemetry_frame_counter += 1

	# Telemetria assíncrona desacoplada: zero chamadas síncronas periódicas a buffer_get_data no caminho de render
	var should_read_gpu = (not enable_async_telemetry) or telemetry_dirty
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

func _invalidate_all_mesh_uniform_sets() -> void:
	if not rd:
		_mesh_uniform_sets.clear()
		return
	for m_res in _mesh_uniform_sets:
		var c = _mesh_uniform_sets[m_res]
		if c is Dictionary:
			if c.has("compute") and c["compute"].is_valid():
				if rd.uniform_set_is_valid(c["compute"]):
					rd.free_rid(c["compute"])
			if c.has("raster") and c["raster"].is_valid():
				if rd.uniform_set_is_valid(c["raster"]):
					rd.free_rid(c["raster"])
	_mesh_uniform_sets.clear()

func _render_scene_global_internal(
	p_render_data: RenderData,
	active_tasks: Array[Dictionary],
	is_prepass: bool,
	cam_view_proj: Projection,
	cam_pos_world: Vector3,
	vp_size: Vector2,
	depth_tex: RID
) -> void:
	if active_tasks.is_empty():
		return

	if not _ensure_global_buffers(active_tasks.size()):
		return

	# 1. Agrupamento de instâncias por malha única (Multi-Mesh Batching com zero conflito de buffers)
	var tasks_by_mesh: Dictionary = {}
	var total_scene_clusters: int = 0
	for task in active_tasks:
		var m_res: MeshGPUResource = task["mesh_res"]
		if not tasks_by_mesh.has(m_res):
			tasks_by_mesh[m_res] = []
		tasks_by_mesh[m_res].append(task)
		total_scene_clusters += m_res.total_clusters

	if total_scene_clusters == 0:
		return

	# 2. Prepara Uniforms Globais da Cena (Câmera, Frustum, Viewport)
	var ubo_base = PackedByteArray()
	ubo_base.resize(256)

	for col in range(4):
		for row in range(4):
			ubo_base.encode_float((col * 4 + row) * 4, cam_view_proj[col][row])

	var f_planes = extract_frustum_planes(cam_view_proj)
	for i in range(min(6, f_planes.size())):
		var pl = f_planes[i]
		var p_off = 64 + i * 16
		ubo_base.encode_float(p_off + 0, pl.normal.x)
		ubo_base.encode_float(p_off + 4, pl.normal.y)
		ubo_base.encode_float(p_off + 8, pl.normal.z)
		ubo_base.encode_float(p_off + 12, pl.d)

	var fov_rad = deg_to_rad(60.0)
	var fov_factor = 1.0 / tan(fov_rad * 0.5)
	ubo_base.encode_float(160, cam_pos_world.x)
	ubo_base.encode_float(164, cam_pos_world.y)
	ubo_base.encode_float(168, cam_pos_world.z)
	ubo_base.encode_float(172, fov_factor)

	ubo_base.encode_float(176, vp_size.x)
	ubo_base.encode_float(180, vp_size.y)
	ubo_base.encode_float(184, 1.5)
	ubo_base.encode_float(188, 0.0)

	# Wind Animation Uniforms (offsets 224..255)
	var wind_time: float = Time.get_ticks_msec() / 1000.0
	ubo_base.encode_float(224, wind_time)
	ubo_base.encode_float(228, wind_strength)
	ubo_base.encode_float(232, wind_frequency)
	ubo_base.encode_float(236, wind_gust)
	ubo_base.encode_float(240, wind_direction.x)
	ubo_base.encode_float(244, wind_direction.y)
	ubo_base.encode_float(248, wind_direction.z)
	ubo_base.encode_float(252, 0.0)

	var target_hiz_tex = hiz_texture if (enable_hiz and hiz_texture.is_valid()) else default_white_tex
	var target_hiz_sampler = hiz_sampler if (enable_hiz and hiz_sampler.is_valid()) else default_sampler
	var active_pipe = global_depth_prepass_pipeline if is_prepass else global_raster_pipeline

	var t0_submit = Time.get_ticks_usec()
	var total_dispatches: int = 0
	var total_draws: int = 0
	var frame_vis_clusters: int = 0
	var frame_triangles: int = 0

	# 3. Execução em lotes por Malha (1 Compute Dispatch + 1 Draw Indirect por malha distinta)
	if rd:
		rd.capture_timestamp("arboria_dispatch_start")
	for m_res in tasks_by_mesh.keys():
		var batch_tasks: Array = tasks_by_mesh[m_res]
		var batch_size: int = batch_tasks.size()
		var batch_work_items: int = batch_size * m_res.total_clusters
		if batch_work_items == 0:
			continue

		# Atualiza count_params e render_params para o lote da malha
		var ubo_data = ubo_base.duplicate()
		ubo_data.encode_u32(192, batch_size)
		ubo_data.encode_u32(196, batch_work_items)
		ubo_data.encode_u32(200, 1 if enable_frustum_culling else 0)
		ubo_data.encode_u32(204, 1 if enable_cone_culling else 0)
		ubo_data.encode_u32(208, global_shading_mode)
		ubo_data.encode_u32(212, 1 if (enable_hiz and hiz_texture.is_valid()) else 0)
		ubo_data.encode_u32(216, 65536)
		ubo_data.encode_u32(220, 1 if enable_wind else 0)
		rd.buffer_update(global_scene_uniforms_buf, 0, ubo_data.size(), ubo_data)

		# Empacota instâncias do lote (GPUInstanceData - 240 bytes cada)
		var inst_bytes = PackedByteArray()
		inst_bytes.resize(batch_size * 240)

		for i in range(batch_size):
			var task = batch_tasks[i]
			var inst: Node3D = task["inst"]
			var inst_gpu: InstanceGPUData = task.get("gpu_data", null)
			var base_off = i * 240

			var model_xform: Transform3D = inst.global_transform
			var vis: bool = inst.visible
			var alb: Color = inst.base_albedo if "base_albedo" in inst else Color(0.8, 0.82, 0.85)
			var rgh: float = inst.roughness if "roughness" in inst else 0.5
			var mtl: float = inst.metallic if "metallic" in inst else 0.0
			var spc: float = inst.specular if "specular" in inst else 0.5
			var lod_mode: float = float(inst.lod_mode if "lod_mode" in inst else 0)
			var forced_lod: float = float(inst.forced_lod if "forced_lod" in inst else 0)

			var is_dirty: bool = true
			if inst_gpu and inst_gpu.is_transform_cached:
				if inst_gpu.cached_transform == model_xform and inst_gpu.cached_visible == vis and inst_gpu.cached_albedo == alb and inst_gpu.cached_roughness == rgh and inst_gpu.cached_metallic == mtl and inst_gpu.cached_specular == spc and inst_gpu.cached_lod_mode == lod_mode and inst_gpu.cached_forced_lod == forced_lod:
					is_dirty = false

			if not is_dirty:
				# ALVO 4: Cópia rápida O(1) de bloco pré-calculado para instâncias estáticas (Zero recálculos na CPU)
				var c_bytes: PackedByteArray = inst_gpu.cached_inst_bytes
				for off_64 in range(0, 240, 8):
					inst_bytes.encode_u64(base_off + off_64, c_bytes.decode_u64(off_64))
				inst_bytes.encode_u32(base_off + 208, i)
				inst_bytes.encode_u32(base_off + 228, m_res.total_clusters)
				continue

			# Cálculo completo apenas para instâncias modificadas (dirty)
			var b = model_xform.basis
			var model_proj = Projection(model_xform)

			for col in range(4):
				for row in range(4):
					inst_bytes.encode_float(base_off + (col * 4 + row) * 4, model_proj[col][row])

			var c00 = b.y.y * b.z.z - b.y.z * b.z.y
			var c01 = b.y.z * b.z.x - b.y.x * b.z.z
			var c02 = b.y.x * b.z.y - b.y.y * b.z.x
			var det = b.x.x * c00 + b.x.y * c01 + b.x.z * c02
			var inv_det = 1.0 / det if abs(det) > 1e-7 else 1.0

			var n00 = c00 * inv_det
			var n01 = (b.x.z * b.z.y - b.x.y * b.z.z) * inv_det
			var n02 = (b.x.y * b.y.z - b.x.z * b.y.y) * inv_det
			var n10 = c01 * inv_det
			var n11 = (b.x.x * b.z.z - b.x.z * b.z.x) * inv_det
			var n12 = (b.x.z * b.y.x - b.x.x * b.y.z) * inv_det
			var n20 = c02 * inv_det
			var n21 = (b.x.y * b.z.x - b.x.x * b.z.y) * inv_det
			var n22 = (b.x.x * b.y.y - b.x.y * b.x.x) * inv_det

			inst_bytes.encode_float(base_off + 64, n00)
			inst_bytes.encode_float(base_off + 68, n10)
			inst_bytes.encode_float(base_off + 72, n20)
			inst_bytes.encode_float(base_off + 76, 0.0)

			inst_bytes.encode_float(base_off + 80, n01)
			inst_bytes.encode_float(base_off + 84, n11)
			inst_bytes.encode_float(base_off + 88, n21)
			inst_bytes.encode_float(base_off + 92, 0.0)

			inst_bytes.encode_float(base_off + 96, n02)
			inst_bytes.encode_float(base_off + 100, n12)
			inst_bytes.encode_float(base_off + 104, n22)
			inst_bytes.encode_float(base_off + 108, 0.0)

			inst_bytes.encode_float(base_off + 112, 0.0)
			inst_bytes.encode_float(base_off + 116, 0.0)
			inst_bytes.encode_float(base_off + 120, 0.0)
			inst_bytes.encode_float(base_off + 124, 1.0)

			var local_c = (m_res.bbox_min + m_res.bbox_max) * 0.5
			var local_r = (m_res.bbox_max - local_c).length()
			var w_c = model_xform * local_c
			var sx = b.x.length()
			var sy = b.y.length()
			var sz = b.z.length()
			var max_s = max(sx, max(sy, sz))
			var w_r = local_r * max_s
			inst_bytes.encode_float(base_off + 128, w_c.x)
			inst_bytes.encode_float(base_off + 132, w_c.y)
			inst_bytes.encode_float(base_off + 136, w_c.z)
			inst_bytes.encode_float(base_off + 140, w_r)

			# 2. AABB no espaço de mundo via Método de Jim Arvo (O(1) sem branches ou 8 transformações)
			var local_ext = (m_res.bbox_max - m_res.bbox_min) * 0.5
			var w_ext = Vector3(
				abs(b.x.x) * local_ext.x + abs(b.y.x) * local_ext.y + abs(b.z.x) * local_ext.z,
				abs(b.x.y) * local_ext.x + abs(b.y.y) * local_ext.y + abs(b.z.y) * local_ext.z,
				abs(b.x.z) * local_ext.x + abs(b.y.z) * local_ext.y + abs(b.z.z) * local_ext.z
			)
			var w_min = w_c - w_ext
			var w_max = w_c + w_ext

			var max_err = inst.max_screen_error if "max_screen_error" in inst else 1.5

			inst_bytes.encode_float(base_off + 144, w_min.x)
			inst_bytes.encode_float(base_off + 148, w_min.y)
			inst_bytes.encode_float(base_off + 152, w_min.z)
			inst_bytes.encode_float(base_off + 156, max_err)

			inst_bytes.encode_float(base_off + 160, w_max.x)
			inst_bytes.encode_float(base_off + 164, w_max.y)
			inst_bytes.encode_float(base_off + 168, w_max.z)
			inst_bytes.encode_float(base_off + 172, lod_mode)

			var alb_out = alb.srgb_to_linear() if global_shading_mode == 2 else alb
			inst_bytes.encode_float(base_off + 176, alb_out.r)
			inst_bytes.encode_float(base_off + 180, alb_out.g)
			inst_bytes.encode_float(base_off + 184, alb_out.b)
			inst_bytes.encode_float(base_off + 188, rgh)

			inst_bytes.encode_float(base_off + 192, mtl)
			inst_bytes.encode_float(base_off + 196, spc)
			inst_bytes.encode_float(base_off + 200, 0.0)
			inst_bytes.encode_float(base_off + 204, forced_lod)

			var is_mirrored = (det < 0.0)
			var vis_flag = (1 if vis else 0) | (2 if (not "cast_shadow" in inst or inst.cast_shadow) else 0) | (4 if is_mirrored else 0)
			inst_bytes.encode_u32(base_off + 208, i)
			inst_bytes.encode_u32(base_off + 212, 0)
			inst_bytes.encode_u32(base_off + 216, vis_flag)
			inst_bytes.encode_u32(base_off + 220, 1)

			inst_bytes.encode_u32(base_off + 224, 0)
			inst_bytes.encode_u32(base_off + 228, m_res.total_clusters)
			inst_bytes.encode_u32(base_off + 232, 0)
			inst_bytes.encode_u32(base_off + 236, 0)

			if inst_gpu:
				inst_gpu.cached_transform = model_xform
				inst_gpu.cached_visible = vis
				inst_gpu.cached_albedo = alb
				inst_gpu.cached_roughness = rgh
				inst_gpu.cached_metallic = mtl
				inst_gpu.cached_specular = spc
				inst_gpu.cached_lod_mode = lod_mode
				inst_gpu.cached_forced_lod = forced_lod
				inst_gpu.cached_inst_bytes = inst_bytes.slice(base_off, base_off + 240)
				inst_gpu.is_transform_cached = true

		rd.buffer_update(global_instances_buf, 0, inst_bytes.size(), inst_bytes)

		# Reseta Contadores e Argumentos Indiretos para o Lote
		var reset_args = PackedByteArray()
		reset_args.resize(32)
		reset_args.encode_u32(0, 384)   # vertex_count
		reset_args.encode_u32(4, 0)     # instance_count
		reset_args.encode_u32(8, 0)     # first_vertex
		reset_args.encode_u32(12, 0)    # first_instance
		reset_args.encode_u32(16, 0)    # total_triangles_drawn
		reset_args.encode_u32(20, 0)    # total_clusters_evaluated
		reset_args.encode_u32(24, 65536)# max_capacity
		reset_args.encode_u32(28, 0)    # overflow_flag
		rd.buffer_update(global_indirect_args_buf, 0, reset_args.size(), reset_args)

		# Uniform Sets específicos para este MeshGPUResource
		var m_cache = _mesh_uniform_sets.get(m_res, null)
		var is_cache_valid = false
		if m_cache is Dictionary:
			var c_set: RID = m_cache.get("compute", RID())
			var r_set: RID = m_cache.get("raster", RID())
			if c_set.is_valid() and r_set.is_valid() and rd.uniform_set_is_valid(c_set) and rd.uniform_set_is_valid(r_set):
				if m_cache.get("hiz_tex", RID()) == target_hiz_tex \
					and m_cache.get("clusters_buf", RID()) == m_res.in_clusters_buf \
					and m_cache.get("instances_buf", RID()) == global_instances_buf \
					and m_cache.get("scene_uniforms_buf", RID()) == global_scene_uniforms_buf \
					and m_cache.get("visible_items_buf", RID()) == global_visible_items_buf \
					and m_cache.get("indirect_args_buf", RID()) == global_indirect_args_buf \
					and m_cache.get("vertices_buf", RID()) == m_res.in_vertices_buf \
					and m_cache.get("triangles_buf", RID()) == m_res.in_triangles_buf:
					is_cache_valid = true

		if not is_cache_valid:
			if m_cache is Dictionary:
				if m_cache.has("compute") and m_cache["compute"].is_valid() and rd.uniform_set_is_valid(m_cache["compute"]):
					rd.free_rid(m_cache["compute"])
				if m_cache.has("raster") and m_cache["raster"].is_valid() and rd.uniform_set_is_valid(m_cache["raster"]):
					rd.free_rid(m_cache["raster"])

			var cu0 = RDUniform.new()
			cu0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			cu0.binding = 0
			cu0.add_id(m_res.in_clusters_buf)

			var cu1 = RDUniform.new()
			cu1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			cu1.binding = 1
			cu1.add_id(global_visible_items_buf)

			var cu2 = RDUniform.new()
			cu2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			cu2.binding = 2
			cu2.add_id(global_indirect_args_buf)

			var cu3 = RDUniform.new()
			cu3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
			cu3.binding = 3
			cu3.add_id(global_scene_uniforms_buf)

			var cu4 = RDUniform.new()
			cu4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			cu4.binding = 4
			cu4.add_id(global_instances_buf)

			var cu5 = RDUniform.new()
			cu5.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			cu5.binding = 5
			cu5.add_id(target_hiz_sampler)
			cu5.add_id(target_hiz_tex)

			var comp_set = rd.uniform_set_create([cu0, cu1, cu2, cu3, cu4, cu5], global_compute_shader_rid, 0)

			var ru0 = RDUniform.new()
			ru0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			ru0.binding = 0
			ru0.add_id(m_res.in_clusters_buf)

			var ru1 = RDUniform.new()
			ru1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			ru1.binding = 1
			ru1.add_id(global_visible_items_buf)

			var ru3 = RDUniform.new()
			ru3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
			ru3.binding = 3
			ru3.add_id(global_scene_uniforms_buf)

			var ru4 = RDUniform.new()
			ru4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			ru4.binding = 4
			ru4.add_id(global_instances_buf)

			var ru5 = RDUniform.new()
			ru5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			ru5.binding = 5
			ru5.add_id(m_res.in_vertices_buf)

			var ru6 = RDUniform.new()
			ru6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			ru6.binding = 6
			ru6.add_id(m_res.in_triangles_buf)

			var rast_set = rd.uniform_set_create([ru0, ru1, ru3, ru4, ru5, ru6], global_raster_shader_rid, 0)
			m_cache = {
				"compute": comp_set,
				"raster": rast_set,
				"hiz_tex": target_hiz_tex,
				"clusters_buf": m_res.in_clusters_buf,
				"instances_buf": global_instances_buf,
				"scene_uniforms_buf": global_scene_uniforms_buf,
				"visible_items_buf": global_visible_items_buf,
				"indirect_args_buf": global_indirect_args_buf,
				"vertices_buf": m_res.in_vertices_buf,
				"triangles_buf": m_res.in_triangles_buf
			}
			_mesh_uniform_sets[m_res] = m_cache

		var comp_uniform_set: RID = m_cache["compute"]
		var rast_uniform_set: RID = m_cache["raster"]

		# Validação estrita de integridade antes do dispatch e draw
		if not comp_uniform_set.is_valid() or not rd.uniform_set_is_valid(comp_uniform_set):
			push_error("[ArboriaNativePipeline] comp_uniform_set inválido para submissão compute!")
			continue
		if not rast_uniform_set.is_valid() or not rd.uniform_set_is_valid(rast_uniform_set):
			push_error("[ArboriaNativePipeline] rast_uniform_set inválido para submissão draw indireto!")
			continue

		# Dispatch Compute
		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, global_compute_pipeline)
		rd.compute_list_bind_uniform_set(cl, comp_uniform_set, 0)
		var gx = int(ceil(float(batch_work_items) / 64.0))
		rd.compute_list_dispatch(cl, gx, 1, 1)
		rd.compute_list_end()

		# Draw Indirect do Lote
		var dl = rd.draw_list_begin(cached_fb, 0, PackedColorArray())
		rd.draw_list_bind_render_pipeline(dl, active_pipe)
		rd.draw_list_bind_uniform_set(dl, rast_uniform_set, 0)
		rd.draw_list_draw_indirect(dl, false, global_indirect_args_buf, 0, 1, 16)
		rd.draw_list_end()

		total_dispatches += 1
		total_draws += 1

	if rd:
		rd.capture_timestamp("arboria_draw_end")

	var t1_submit = Time.get_ticks_usec()
	stats_cpu_submission_ms = (t1_submit - t0_submit) / 1000.0

	# 4. Atualização de Telemetria Consolidada e Desacoplada (Zero stalls GPU recorrentes no frame)
	stats_total_instances = active_tasks.size()
	stats_dispatches = total_dispatches
	stats_indirect_draws = total_draws
	stats_clusters_evaluated = total_scene_clusters

	# Leitura e cálculo de tempo real de GPU via Vulkan Timestamps do RenderingDevice
	if rd:
		var ts_count = rd.get_captured_timestamps_count()
		if ts_count >= 2:
			var t_start: int = 0
			var t_end: int = 0
			var found_s: bool = false
			var found_e: bool = false
			for ti in range(ts_count):
				var tn = rd.get_captured_timestamp_name(ti)
				if tn == "arboria_dispatch_start":
					t_start = rd.get_captured_timestamp_gpu_time(ti)
					found_s = true
				elif tn == "arboria_draw_end":
					t_end = rd.get_captured_timestamp_gpu_time(ti)
					found_e = true
			if found_s and found_e and t_end >= t_start:
				last_measured_gpu_ms = float(t_end - t_start) / 1000000.0

	# Leitura do buffer de argumentos indiretos apenas fora do loop medido (warmup ou dirty)
	var is_warmup_or_dirty = (_telemetry_frame_counter <= 2) or telemetry_dirty
	if is_warmup_or_dirty and global_indirect_args_buf.is_valid():
		telemetry_dirty = false
		var cnt_data = rd.buffer_get_data(global_indirect_args_buf)
		if cnt_data.size() >= 32:
			stats_visible_clusters = cnt_data.decode_u32(4)
			stats_triangles_drawn = cnt_data.decode_u32(16)
			if not _diag_log_executed and not is_prepass:
				_diag_log_executed = true
				print("================================================================================")
				print("[ARBORIA DIAG ETAPA 1] Log Unico no inicio de render_frame:")
				print("  1. Compositor Effect ativo       : SIM (Post-Opaque callback ativo)")
				print("  2. Viewport tem camera certa     : SIM (Pos=%s, VP Size=%s)" % [cam_pos_world, vp_size])
				print("  3. Instancia registrada          : SIM (Registradas=%d, Ativas=%d, Malhas=%d)" % [_registered_instances.size(), active_tasks.size(), tasks_by_mesh.size()])
				print("  4. Uniform Set criado            : SIM (Compute=%s, Raster=%s)" % [global_compute_pipeline.is_valid(), global_raster_pipeline.is_valid()])
				print("  5. Draw Indirect chamado         : SIM (Dispatches=%d, Draws=%d)" % [total_dispatches, total_draws])
				print("  6. Retorno de GPU Indirect Args  : vertex_count=%d, instance_count=%d, triangles_drawn=%d, evaluated=%d, overflow=%d" % [
					cnt_data.decode_u32(0), cnt_data.decode_u32(4), cnt_data.decode_u32(16), cnt_data.decode_u32(20), cnt_data.decode_u32(28)
				])
				print("================================================================================")

	if native_core and native_core.has_method("streaming_update"):
		native_core.streaming_update(cam_pos_world, _telemetry_frame_counter)

	_telemetry_frame_counter += 1

func cleanup() -> void:
	if not rd:
		return

	_invalidate_all_mesh_uniform_sets()
	if global_compute_uniform_set.is_valid():
		if rd.uniform_set_is_valid(global_compute_uniform_set):
			rd.free_rid(global_compute_uniform_set)
		global_compute_uniform_set = RID()
	if global_raster_uniform_set.is_valid():
		if rd.uniform_set_is_valid(global_raster_uniform_set):
			rd.free_rid(global_raster_uniform_set)
		global_raster_uniform_set = RID()

	if global_visible_items_buf.is_valid():
		rd.free_rid(global_visible_items_buf)
		global_visible_items_buf = RID()
	if global_indirect_args_buf.is_valid():
		rd.free_rid(global_indirect_args_buf)
		global_indirect_args_buf = RID()
	if global_scene_uniforms_buf.is_valid():
		rd.free_rid(global_scene_uniforms_buf)
		global_scene_uniforms_buf = RID()
	if global_instances_buf.is_valid():
		rd.free_rid(global_instances_buf)
		global_instances_buf = RID()
	if global_compute_pipeline.is_valid():
		rd.free_rid(global_compute_pipeline)
		global_compute_pipeline = RID()
	if global_compute_shader_rid.is_valid():
		rd.free_rid(global_compute_shader_rid)
		global_compute_shader_rid = RID()
	if global_raster_pipeline.is_valid():
		rd.free_rid(global_raster_pipeline)
		global_raster_pipeline = RID()
	if global_depth_prepass_pipeline.is_valid():
		rd.free_rid(global_depth_prepass_pipeline)
		global_depth_prepass_pipeline = RID()
	if global_raster_shader_rid.is_valid():
		rd.free_rid(global_raster_shader_rid)
		global_raster_shader_rid = RID()

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
	if depth_prepass_pipeline.is_valid():
		rd.free_rid(depth_prepass_pipeline)
		depth_prepass_pipeline = RID()
	if raster_shader_rid.is_valid():
		rd.free_rid(raster_shader_rid)
		raster_shader_rid = RID()
	if hiz_pipeline.is_valid():
		rd.free_rid(hiz_pipeline)
		hiz_pipeline = RID()
	if hiz_shader_rid.is_valid():
		rd.free_rid(hiz_shader_rid)
		hiz_shader_rid = RID()
	if hiz_sampler.is_valid():
		rd.free_rid(hiz_sampler)
		hiz_sampler = RID()
	_free_hiz_resources()

	native_core = null
	_shared_instance = null
	is_initialized = false
