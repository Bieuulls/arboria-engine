class_name ArboriaNativePipeline
extends RefCounted

## ARBORIA ENGINE — NATIVE FORWARD+ PIPELINE (V7.0)
## Gerencia recursos GPU compartilhados, despacho de compute culling,
## argumentos indiretos e rasterizacao com Reversed-Z Depth integrado ao Godot Forward+.

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

static var _shared_instance: ArboriaNativePipeline = null

# Estrutura interna para malhas carregadas em VRAM
class MeshGPUResource:
	var mesh_path: String = ""
	var total_clusters: int = 0
	var total_vertices: int = 0
	var total_triangles: int = 0
	var total_groups: int = 0
	var groups_x: int = 1
	var bbox_min: Vector3 = Vector3.ZERO
	var bbox_max: Vector3 = Vector3.ZERO
	
	# SSBO RIDs
	var in_clusters_buf: RID
	var out_visible_buf: RID
	var counter_buf: RID
	var in_vertices_buf: RID
	var in_triangles_buf: RID
	var selection_texture_rid: RID
	var compute_uniform_set: RID
	var is_valid: bool = false

var rd: RenderingDevice
var is_initialized: bool = false

# Cache de malhas GPU (mesh_path -> MeshGPUResource)
var _mesh_cache: Dictionary = {}

# Instâncias registradas
var _registered_instances: Array[Node3D] = []

# Pipelines e Shaders
var compute_shader_rid: RID
var compute_pipeline: RID
var raster_shader_rid: RID
var raster_pipeline: RID
var raster_fb_format: int = -1

# UBOs globais de frame
var camera_ubo_buf: RID
var instance_ubo_buf: RID

# Framebuffer Cache
var cached_fb: RID
var cached_fb_color: RID
var cached_fb_depth: RID

# Configuracoes globais
var global_shading_mode: int = 0 # 0 = PBR, 1 = Normal, 2 = Unshaded, 3 = Cluster Colors
var enable_frustum_culling: bool = true
var enable_cone_culling: bool = true

# Telemetria
var stats_total_instances: int = 0
var stats_visible_clusters: int = 0
var stats_triangles_drawn: int = 0

static func get_active_instance() -> RefCounted:
	return _shared_instance

static func get_or_create_shared() -> RefCounted:
	if not _shared_instance:
		var script_cls = load("res://scripts/arboria_native_pipeline.gd") as GDScript
		_shared_instance = script_cls.new()
	return _shared_instance

func _init(p_rd: RenderingDevice = null):
	if p_rd:
		rd = p_rd
	else:
		rd = RenderingServer.get_rendering_device()

	if not rd:
		push_error("[ArboriaNativePipeline] RenderingDevice Vulkan nao disponivel!")
		return

	_shared_instance = self
	_setup_shaders_and_ubos()
	is_initialized = true
	print("[ArboriaNativePipeline] Inicializado com sucesso em Forward+ Vulkan.")

func _setup_shaders_and_ubos() -> void:
	# 1. Aloca Camera UBO (224 bytes)
	var u_cam = PackedByteArray()
	u_cam.resize(224)
	camera_ubo_buf = rd.uniform_buffer_create(224, u_cam)

	# 2. Aloca Instance UBO (160 bytes: mat4 model + 4x vec4 params)
	var u_inst = PackedByteArray()
	u_inst.resize(160)
	instance_ubo_buf = rd.uniform_buffer_create(160, u_inst)

	# 3. Compila Compute Shader cull_clusters.glsl
	_compile_compute_shader()

	# 4. Compila Raster Shader arboria_forward_raster.glsl
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
	var vs_code = """#version 450
layout(location = 0) out vec3 v_world_normal;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out flat uint v_cluster_id;
layout(location = 3) out vec3 v_world_pos;

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
layout(set = 0, binding = 7, std140) uniform InstanceUniforms {
    mat4 model_matrix;
    vec4 material_albedo_rough;
    vec4 material_metal_spec;
    vec4 light_direction_energy;
    vec4 light_color;
} instance_ubo;

void main() {
    uint slot = gl_InstanceIndex;
    if (slot >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    uint cluster_id = visible_cluster_ids[slot];
    if (cluster_id >= ubo.count_params.x) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    GPUCluster c = clusters[cluster_id];

    uint tri_idx = gl_VertexIndex / 3;
    if (tri_idx >= c.data_offsets.w) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    uint byte_offset = c.data_offsets.z + gl_VertexIndex;
    uint word_idx = byte_offset / 4;
    uint byte_in_word = byte_offset % 4;
    uint word = packed_triangles[word_idx];
    uint local_v_idx = (word >> (byte_in_word * 8)) & 0xFFu;

    if (local_v_idx >= c.data_offsets.y) {
        gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
        return;
    }

    uint global_v_idx = c.data_offsets.x + local_v_idx;
    uint vert_entry_idx = global_v_idx * 2;

    vec4 pos_u = packed_vertices[vert_entry_idx + 0];
    vec4 norm_v = packed_vertices[vert_entry_idx + 1];

    vec4 world_p = instance_ubo.model_matrix * vec4(pos_u.xyz, 1.0);
    mat3 normal_matrix = transpose(inverse(mat3(instance_ubo.model_matrix)));
    vec3 world_n = normalize(normal_matrix * norm_v.xyz);

    gl_Position = ubo.view_proj * world_p;
    v_world_pos = world_p.xyz;
    v_world_normal = world_n;
    v_uv = vec2(pos_u.w, norm_v.w);
    v_cluster_id = cluster_id;
}
"""

	var fs_code = """#version 450
layout(location = 0) in vec3 v_world_normal;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_cluster_id;
layout(location = 3) in vec3 v_world_pos;

layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 3, std140) uniform CameraUniforms {
    mat4 view_proj;
    vec4 frustum_planes[6];
    vec4 camera_pos_fov;
    vec4 viewport_params;
    uvec4 count_params;
    uvec4 render_params;
} ubo;

layout(set = 0, binding = 7, std140) uniform InstanceUniforms {
    mat4 model_matrix;
    vec4 material_albedo_rough;
    vec4 material_metal_spec;
    vec4 light_direction_energy;
    vec4 light_color;
} instance_ubo;

void main() {
    uint mode = ubo.render_params.x;
    vec3 n = normalize(v_world_normal);

    if (mode == 0u) {
        // Forward+ PBR Real
        vec3 albedo = instance_ubo.material_albedo_rough.rgb;
        float roughness = instance_ubo.material_albedo_rough.w;
        float metallic = instance_ubo.material_metal_spec.x;
        float specular = instance_ubo.material_metal_spec.y;

        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        vec3 l_col = instance_ubo.light_color.rgb * instance_ubo.light_direction_energy.w;
        vec3 v_dir = normalize(ubo.camera_pos_fov.xyz - v_world_pos);

        float n_dot_l = max(dot(n, l_dir), 0.0);
        vec3 diffuse = albedo * (1.0 - metallic) * n_dot_l;

        vec3 h = normalize(l_dir + v_dir);
        float n_dot_h = max(dot(n, h), 0.0);
        float spec_power = max(2.0, (1.0 - roughness) * 128.0);
        float spec_factor = pow(n_dot_h, spec_power) * specular;
        vec3 spec_color = mix(vec3(0.04), albedo, metallic);
        vec3 specular_term = spec_color * spec_factor * n_dot_l;

        float sky_factor = n.y * 0.5 + 0.5;
        vec3 ambient_sky = vec3(0.12, 0.14, 0.18);
        vec3 ambient_ground = vec3(0.04, 0.04, 0.03);
        vec3 ambient = mix(ambient_ground, ambient_sky, sky_factor) * albedo * (1.0 - metallic);

        vec3 final_color = ambient + (diffuse + specular_term) * l_col;
        out_color = vec4(final_color, 1.0);

    } else if (mode == 1u) {
        // Normais de Superficie
        out_color = vec4(n * 0.5 + 0.5, 1.0);

    } else if (mode == 2u) {
        // Unshaded
        out_color = vec4(instance_ubo.material_albedo_rough.rgb, 1.0);

    } else {
        // Cluster Debug Colors
        float hue = fract(float(v_cluster_id) * 0.618033988749895);
        vec3 rgb = clamp(abs(fract(hue + vec3(0.0, 2.0/3.0, 1.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
        vec3 cluster_col = mix(rgb, vec3(1.0), 0.15);

        vec3 l_dir = normalize(instance_ubo.light_direction_energy.xyz);
        float diff = max(dot(n, l_dir), 0.25);
        out_color = vec4(cluster_col * diff, 1.0);
    }
}
"""

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

	# CONTRATO REVERSED-Z: COMPARE_OP_GREATER_OR_EQUAL
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

	var data = VGMeshLoader.load_from_file(path)
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

	# 2. OutVisibleClusters Buffer
	res.out_visible_buf = rd.storage_buffer_create(max(4, res.total_clusters * 4))

	# 3. OutCounterAndDrawArgs Buffer (24 bytes VkDrawIndirectCommand)
	var cnt_bytes = PackedByteArray()
	cnt_bytes.resize(24)
	cnt_bytes.encode_u32(0, 384) # vertex_count
	cnt_bytes.encode_u32(4, 0)   # instance_count
	cnt_bytes.encode_u32(8, 0)   # first_vertex
	cnt_bytes.encode_u32(12, 0)  # first_instance
	cnt_bytes.encode_u32(16, 0)  # total_triangles_drawn
	cnt_bytes.encode_u32(20, 0)  # total_clusters_evaluated
	res.counter_buf = rd.storage_buffer_create(24, cnt_bytes, RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT)

	# 4. Out Selection Texture
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.width = 2048
	tf.height = max(1, int(ceil(float(res.total_clusters) / 2048.0)))
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	res.selection_texture_rid = rd.texture_create(tf, RDTextureView.new(), [])

	# 5. InVertices (32 bytes = 2x vec4)
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

	# 6. InTriangles (uint32 compactados)
	var aligned_t_size = int(ceil(float(triangles.size()) / 4.0)) * 4
	var t_bytes = PackedByteArray()
	t_bytes.resize(max(4, aligned_t_size))
	for ti in range(triangles.size()):
		t_bytes[ti] = triangles[ti]
	res.in_triangles_buf = rd.storage_buffer_create(t_bytes.size(), t_bytes)

	# 7. Compute Uniform Set
	var u0 = RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(res.in_clusters_buf)

	var u1 = RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(res.out_visible_buf)

	var u2 = RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u2.binding = 2
	u2.add_id(res.counter_buf)

	var u3 = RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u3.binding = 3
	u3.add_id(camera_ubo_buf)

	var u4 = RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u4.binding = 4
	u4.add_id(res.selection_texture_rid)

	res.compute_uniform_set = rd.uniform_set_create([u0, u1, u2, u3, u4], compute_shader_rid, 0)
	res.is_valid = true

	print("[ArboriaNativePipeline] Upload GPU concluido: ", path, " (", res.total_clusters, " clusters, ", (c_bytes.size() + raw_v_bytes.size() + t_bytes.size()) / 1024, " KB)")
	return res

func register_instance(inst: Node3D) -> void:
	if not _registered_instances.has(inst):
		_registered_instances.append(inst)

func unregister_instance(inst: Node3D) -> void:
	_registered_instances.erase(inst)

func mark_instance_dirty(_inst: Node3D) -> void:
	# Marca necessidade de atualizacao do frame
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

	# Reset das estatisticas do frame
	stats_total_instances = 0
	stats_visible_clusters = 0
	stats_triangles_drawn = 0

	# 1. Abre a Draw List compartilhada do Forward+
	# CLEAR_FLAGS = 0 -> NAO LIMPAR COR, NAO LIMPAR Z!
	var dl = rd.draw_list_begin(cached_fb, 0, PackedColorArray())
	rd.draw_list_bind_render_pipeline(dl, raster_pipeline)

	# 2. Itera sobre cada instancia ativa
	for inst in _registered_instances:
		if not is_instance_valid(inst) or not inst.visible or inst.mesh_path == "":
			continue

		var mesh_res: MeshGPUResource = _mesh_cache.get(inst.mesh_path, null)
		if not mesh_res or not mesh_res.is_valid:
			continue

		stats_total_instances += 1
		var model_xform: Transform3D = inst.global_transform
		var mvp_mat: Projection = cam_proj * view_mat * Projection(model_xform)
		var cam_pos_local: Vector3 = model_xform.affine_inverse() * cam_pos_world
		var f_planes = extract_frustum_planes(mvp_mat)

		# Atualiza Camera UBO (224 bytes)
		var u_cam = PackedByteArray()
		u_cam.resize(224)
		for col in range(4):
			for row in range(4):
				u_cam.encode_float((col * 4 + row) * 4, mvp_mat[col][row])

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
		u_cam.encode_float(172, deg_to_rad(60.0))

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

		rd.buffer_update(camera_ubo_buf, 0, u_cam.size(), u_cam)

		# Atualiza Instance UBO (160 bytes: model_matrix + material + light)
		var u_inst = PackedByteArray()
		u_inst.resize(160)
		for col in range(4):
			for row in range(4):
				u_inst.encode_float((col * 4 + row) * 4, model_xform[col][row])

		# material_albedo_rough: rgb = albedo, w = roughness
		u_inst.encode_float(64, inst.base_albedo.r)
		u_inst.encode_float(68, inst.base_albedo.g)
		u_inst.encode_float(72, inst.base_albedo.b)
		u_inst.encode_float(76, inst.roughness)

		# material_metal_spec: x = metallic, y = specular
		u_inst.encode_float(80, inst.metallic)
		u_inst.encode_float(84, inst.specular)
		u_inst.encode_float(88, 0.0)
		u_inst.encode_float(92, 0.0)

		# light_direction_energy: xyz = dir, w = energy
		var l_dir = Vector3(0.5, 0.8, 0.6).normalized()
		u_inst.encode_float(96, l_dir.x)
		u_inst.encode_float(100, l_dir.y)
		u_inst.encode_float(102, l_dir.z)
		u_inst.encode_float(108, 1.2)

		# light_color: rgb = color, w = ambient
		u_inst.encode_float(112, 1.0)
		u_inst.encode_float(116, 0.98)
		u_inst.encode_float(120, 0.95)
		u_inst.encode_float(124, 0.2)

		rd.buffer_update(instance_ubo_buf, 0, u_inst.size(), u_inst)

		# 3. Despacha Compute Culling na GPU
		rd.buffer_clear(mesh_res.counter_buf, 4, 20)
		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, compute_pipeline)
		rd.compute_list_bind_uniform_set(cl, mesh_res.compute_uniform_set, 0)
		rd.compute_list_dispatch(cl, mesh_res.groups_x, 1, 1)
		rd.compute_list_end()

		# 4. Uniform Set do Rasterizador
		var u0 = RDUniform.new()
		u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u0.binding = 0
		u0.add_id(mesh_res.in_clusters_buf)

		var u1 = RDUniform.new()
		u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u1.binding = 1
		u1.add_id(mesh_res.out_visible_buf)

		var u3 = RDUniform.new()
		u3.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		u3.binding = 3
		u3.add_id(camera_ubo_buf)

		var u5 = RDUniform.new()
		u5.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u5.binding = 5
		u5.add_id(mesh_res.in_vertices_buf)

		var u6 = RDUniform.new()
		u6.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u6.binding = 6
		u6.add_id(mesh_res.in_triangles_buf)

		var u7 = RDUniform.new()
		u7.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		u7.binding = 7
		u7.add_id(instance_ubo_buf)

		var raster_set = rd.uniform_set_create([u0, u1, u3, u5, u6, u7], raster_shader_rid, 0)

		# 5. Desenho Indireto 100% GPU
		rd.draw_list_bind_uniform_set(dl, raster_set, 0)
		rd.draw_list_draw_indirect(dl, false, mesh_res.counter_buf, 0, 1, 16)

	rd.draw_list_end()

func cleanup() -> void:
	if not rd:
		return

	for path in _mesh_cache:
		var res: MeshGPUResource = _mesh_cache[path]
		if res.in_clusters_buf.is_valid(): rd.free_rid(res.in_clusters_buf)
		if res.out_visible_buf.is_valid(): rd.free_rid(res.out_visible_buf)
		if res.counter_buf.is_valid(): rd.free_rid(res.counter_buf)
		if res.in_vertices_buf.is_valid(): rd.free_rid(res.in_vertices_buf)
		if res.in_triangles_buf.is_valid(): rd.free_rid(res.in_triangles_buf)
		if res.selection_texture_rid.is_valid(): rd.free_rid(res.selection_texture_rid)
	_mesh_cache.clear()

	if cached_fb.is_valid():
		rd.free_rid(cached_fb)
		cached_fb = RID()
	if camera_ubo_buf.is_valid():
		rd.free_rid(camera_ubo_buf)
		camera_ubo_buf = RID()
	if instance_ubo_buf.is_valid():
		rd.free_rid(instance_ubo_buf)
		instance_ubo_buf = RID()
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

	is_initialized = false
