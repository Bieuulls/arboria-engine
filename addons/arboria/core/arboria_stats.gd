# ARBORIA ENGINE — Módulo de Estatísticas/Telemetria (GDScript)
# Fase 5 da Modularização: Contadores de culling, visibilidade, draw calls,
# frame p95, tempo de edição, DAG, upload. Exportação CSV/JSON.
# Extraído de arboria_native_pipeline.gd.

extends RefCounted
class_name ArboriaStats

# Contadores de frame atual
var frame_index: uint = 0
var culling_result: CullingResult = CullingResult.new()

# Histórico de frames (para p95, média, etc.)
var frame_times: Array = []
var cull_times: Array = []
var max_history_size: int = 120  # ~2 segundos a 60 FPS

# Estatísticas de DAG
var dag_rebuilds: uint = 0
var dag_rebuild_time_ms: float = 0.0
var dag_preserved_clusters: uint = 0

# Estatísticas de streaming
var streaming_page_faults: uint = 0
var streaming_evictions: uint = 0

# Estatísticas de edição de geometria
var edit_operations: uint = 0
var edit_time_ms: float = 0.0

func _init():
	frame_times = []
	cull_times = []

# Registrar dados de um frame completo
func record_frame(culling: CullingResult, frame_ms: float):
	frame_index += 1
	culling_result = culling

	frame_times.push_back(frame_ms)
	cull_times.push_back(culling.cull_cpu_ms)

	if frame_times.size() > max_history_size:
		frame_times.pop_front()
	if cull_times.size() > max_history_size:
		cull_times.pop_front()

# Registrar reconstrução DAG
func record_dag_rebuild(time_ms: float, preserved: uint, fallback: bool):
	dag_rebuilds += 1
	dag_rebuild_time_ms += time_ms
	dag_preserved_clusters += preserved

# Registrar operação de edição
func record_edit_operation(time_ms: float):
	edit_operations += 1
	edit_time_ms += time_ms

# --- Relatórios ---

func get_frame_report() -> Dictionary:
	return {
		"frame_index": frame_index,
		"visible_clusters": culling_result.clusters_visible_final,
		"total_triangles": culling_result.total_triangles,
		"draw_indirect_count": culling_result.draw_indirect_count,
		"instances_culled_frustum": culling_result.instances_culled_frustum,
		"instances_culled_hiz": culling_result.instances_culled_hiz,
		"clusters_culled_dag": culling_result.clusters_culled_dag,
		"clusters_culled_cone": culling_result.clusters_culled_cone,
		"clusters_culled_hiz": culling_result.clusters_culled_hiz,
		"cull_cpu_ms": culling_result.cull_cpu_ms,
		"cull_gpu_ms": culling_result.cull_gpu_ms,
		"frame_ms": frame_times[-1] if frame_times.size() > 0 else 0.0
	}

func get_p95_frame_time() -> float:
	if frame_times.size() == 0:
		return 0.0
	var sorted: Array = frame_times.duplicate()
	sorted.sort_custom(func(a, b): return a < b)
	var idx: int = int(sorted.size() * 0.95) - 1
	idx = clamp(idx, 0, sorted.size() - 1)
	return sorted[idx]

func get_p95_cull_time() -> float:
	if cull_times.size() == 0:
		return 0.0
	var sorted: Array = cull_times.duplicate()
	sorted.sort_custom(func(a, b): return a < b)
	var idx: int = int(sorted.size() * 0.95) - 1
	idx = clamp(idx, 0, sorted.size() - 1)
	return sorted[idx]

func get_summary() -> Dictionary:
	return {
		"frame_index": frame_index,
		"p95_frame_ms": get_p95_frame_time(),
		"p95_cull_ms": get_p95_cull_time(),
		"dag_rebuilds": dag_rebuilds,
		"dag_rebuild_time_ms": dag_rebuild_time_ms,
		"dag_preserved_clusters": dag_preserved_clusters,
		"streaming_page_faults": streaming_page_faults,
		"streaming_evictions": streaming_evictions,
		"edit_operations": edit_operations,
		"edit_time_ms": edit_time_ms
	}

# Exportar relatório para CSV
func export_csv(filepath: String):
	var file: FileAccess = FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível abrir arquivo para escrita: " + filepath)
		return
	file.store_line("frame_index,visible_clusters,total_triangles,draw_calls,cull_cpu_ms,frame_ms")
	file.store_line(str(frame_index) + "," + str(culling_result.clusters_visible_final) + "," +
	                str(culling_result.total_triangles) + "," + str(culling_result.draw_indirect_count) + "," +
	                str(culling_result.cull_cpu_ms) + "," + str(frame_times[-1] if frame_times.size() > 0 else 0.0))
	file.close()

# Exportar relatório para JSON
func export_json(filepath: String):
	var file: FileAccess = FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("Não foi possível abrir arquivo para escrita: " + filepath)
		return
	var summary: Dictionary = get_summary()
	file.store_line(to_json(summary))
	file.close()
