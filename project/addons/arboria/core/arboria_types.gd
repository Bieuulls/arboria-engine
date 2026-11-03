# ARBORIA ENGINE — Tipos Compartilhados (GDScript)
# Fase 1 da Modularização: Estruturas de dados compartilhadas entre módulos.
# Extraído de arboria_native_pipeline.gd (monolítico ~2312 linhas).

# class_name ArboriaTypes (registrado globalmente em res://scripts/arboria_types.gd)

# --- Constantes de Culling e Renderização ---

const FRUSTUM_PLANE_COUNT: int = 6
const MAX_LOD_LEVELS: int = 8
const DEFAULT_MAX_SCREEN_ERROR: float = 1.5
const HI_Z_TEMPORAL_BIAS: float = 0.001
const INVALID_HANDLE: int = 0xFFFFFFFF

# --- Resultado de Culling por Frame ---

class CullingResult:
	var visible_cluster_count: int = 0
	var total_triangles: int = 0
	var draw_indirect_count: int = 0
	var instances_tested: int = 0
	var instances_culled_frustum: int = 0
	var instances_culled_hiz: int = 0
	var clusters_tested_dag: int = 0
	var clusters_culled_dag: int = 0
	var clusters_tested_cone: int = 0
	var clusters_culled_cone: int = 0
	var clusters_tested_hiz: int = 0
	var clusters_culled_hiz: int = 0
	var clusters_visible_final: int = 0
	var cull_cpu_ms: float = 0.0
	var cull_gpu_ms: float = 0.0

	func reset():
		visible_cluster_count = 0
		total_triangles = 0
		draw_indirect_count = 0
		instances_tested = 0
		instances_culled_frustum = 0
		instances_culled_hiz = 0
		clusters_tested_dag = 0
		clusters_culled_dag = 0
		clusters_tested_cone = 0
		clusters_culled_cone = 0
		clusters_tested_hiz = 0
		clusters_culled_hiz = 0
		clusters_visible_final = 0
		cull_cpu_ms = 0.0
		cull_gpu_ms = 0.0

# --- Recurso de Malha na GPU ---

class MeshGPUResource:
	var mesh_id: int = 0
	var vertex_count: int = 0
	var triangle_count: int = 0
	var cluster_count: int = 0
	var lod_count: int = 0
	var gpu_clusters: Array = []
	var bounding_sphere_center: Vector3 = Vector3.ZERO
	var bounding_sphere_radius: float = 0.0
	var aabb_min: Vector3 = Vector3.ZERO
	var aabb_max: Vector3 = Vector3.ZERO
	var cluster_offset: int = 0
	var root_cluster_offset: int = 0

# --- Dados de Instância na GPU ---

class InstanceGPUData:
	var instance_id: int = 0
	var mesh_id: int = 0
	var model_matrix: Basis = Basis.IDENTITY
	var bounding_sphere: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var aabb_min: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var aabb_max: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var material_albedo: Color = Color(1.0, 1.0, 1.0, 1.0)
	var material_roughness: float = 0.5
	var material_metallic: float = 0.0
	var visibility_flags: int = 1
	var resource_generation: int = 0
	var cluster_offset: int = 0
	var cluster_count: int = 0
	var root_cluster_offset: int = 0
	var lod_count: int = 0
	var lod_mode: int = 0
	var forced_lod: int = 0
	var max_screen_error: float = 1.5

# --- Estatísticas de Streaming VRAM ---

class StreamingStats:
	var resident_pages: int = 0
	var evicted_pages: int = 0
	var page_faults: int = 0
	var vram_budget_bytes: int = 0
	var vram_used_bytes: int = 0
	var vram_resident_bytes: int = 0

	func reset():
		resident_pages = 0
		evicted_pages = 0
		page_faults = 0
		vram_used_bytes = 0
		vram_resident_bytes = 0
