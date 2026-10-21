extends Node3D

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

# Referencias aos nos
@onready var orbit_cam: Node3D = $CameraPivot
@onready var model_instance: MeshInstance3D = $ModelInstance
@onready var original_instance: MeshInstance3D = $OriginalInstance
@onready var wireframe_instance: MeshInstance3D = $WireframeInstance

# Controles de UI
@onready var model_option: OptionButton = $UI/Panel/VBox/ModelOption
@onready var lod_slider: HSlider = $UI/Panel/VBox/LODSlider
@onready var lod_label: Label = $UI/Panel/VBox/LODLabel
@onready var dynamic_lod_check: CheckBox = $UI/Panel/VBox/DynamicLODCheck
@onready var gpu_pipeline_check: CheckBox = $UI/Panel/VBox/GPUPipelineCheck
@onready var auto_orbit_check: CheckBox = $UI/Panel/VBox/AutoOrbitCheck
@onready var frustum_cull_check: CheckBox = $UI/Panel/VBox/FrustumCullCheck
@onready var cluster_color_check: CheckBox = $UI/Panel/VBox/ClusterColorCheck
@onready var wireframe_check: CheckBox = $UI/Panel/VBox/WireframeCheck
@onready var compare_check: CheckBox = $UI/Panel/VBox/CompareCheck
@onready var cluster_spin: SpinBox = $UI/Panel/VBox/ClusterSpin
@onready var isolate_cluster_check: CheckBox = $UI/Panel/VBox/IsolateClusterCheck

# Labels de Estatisticas
@onready var stat_triangles: Label = $UI/StatsPanel/VBox/StatTriangles
@onready var stat_clusters: Label = $UI/StatsPanel/VBox/StatClusters
@onready var stat_error: Label = $UI/StatsPanel/VBox/StatError
@onready var stat_ratio: Label = $UI/StatsPanel/VBox/StatRatio
@onready var stat_fps: Label = $UI/StatsPanel/VBox/StatFPS
@onready var stat_cam_dist: Label = $UI/StatsPanel/VBox/StatCamDist
@onready var stat_gpu_time: Label = $UI/StatsPanel/VBox/StatGPUTime
@onready var stat_vram: Label = $UI/StatsPanel/VBox/StatVRAM
@onready var stat_comparison: Label = $UI/StatsPanel/VBox/StatComparison

# Pipeline de GPU e Dados
var gpu_pipeline: VGGPUPipeline
var current_vg_data: Dictionary = {}
var current_lod: int = 0
var current_model_name: String = ""
var is_dynamic_lod: bool = false
var orbit_base_distance: float = 6.0
var stats_frame_counter: int = 0

# Materiais Legados / CPU
var material_cluster: StandardMaterial3D
var material_lit: StandardMaterial3D
var material_wire: StandardMaterial3D
var material_orig: StandardMaterial3D

func _ready() -> void:
	print("Inicializando Visualizador de Geometria Virtualizada (Arboria VG — Fase 3)...")
	setup_materials()
	setup_ui()
	gpu_pipeline = VGGPUPipeline.new()
	load_selected_model(0)

func setup_materials() -> void:
	# Material com cores de clusters (Vertex Colors ativadas)
	material_cluster = StandardMaterial3D.new()
	material_cluster.vertex_color_use_as_albedo = true
	material_cluster.roughness = 0.4
	material_cluster.cull_mode = BaseMaterial3D.CULL_BACK

	# Material lit convencional cinza PBR
	material_lit = StandardMaterial3D.new()
	material_lit.albedo_color = Color(0.8, 0.82, 0.85)
	material_lit.roughness = 0.5
	material_lit.cull_mode = BaseMaterial3D.CULL_BACK

	# Material de wireframe
	material_wire = StandardMaterial3D.new()
	material_wire.albedo_color = Color(0.0, 1.0, 0.6)
	material_wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_wire.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Material do modelo original de comparacao (PBR cinza/azul industrial)
	material_orig = StandardMaterial3D.new()
	material_orig.albedo_color = Color(0.9, 0.5, 0.25)
	material_orig.roughness = 0.5
	material_orig.cull_mode = BaseMaterial3D.CULL_BACK

func setup_ui() -> void:
	model_option.clear()
	model_option.add_item("Dense Scanned Rock (16,000 tris)", 0)
	model_option.add_item("Pine Tree Trunk (35,000 tris)", 1)
	model_option.add_item("Granite Boulder PBR (320 tris)", 2)
	model_option.item_selected.connect(_on_model_selected)

	lod_slider.value_changed.connect(_on_lod_slider_changed)
	dynamic_lod_check.toggled.connect(_on_dynamic_lod_toggled)
	gpu_pipeline_check.toggled.connect(func(_b):
		if gpu_pipeline:
			gpu_pipeline.poll_stats_async()
		refresh_mesh()
	)
	cluster_color_check.toggled.connect(func(_b): refresh_mesh())
	wireframe_check.toggled.connect(_on_wireframe_toggled)
	compare_check.toggled.connect(_on_compare_toggled)
	isolate_cluster_check.toggled.connect(func(_b): refresh_mesh())
	cluster_spin.value_changed.connect(func(_v): refresh_mesh())

func _on_model_selected(index: int) -> void:
	load_selected_model(index)

func load_selected_model(index: int) -> void:
	var vg_file = ""
	var obj_file = ""

	match index:
		0:
			vg_file = "res://assets/dense_rock_test.vgmesh"
			obj_file = "res://assets/dense_rock_test.obj"
			current_model_name = "Dense Scanned Rock"
		1:
			vg_file = "res://assets/pine_trunk_complex.vgmesh"
			obj_file = "res://assets/pine_trunk_complex.obj"
			current_model_name = "Pine Tree Trunk"
		2:
			vg_file = "res://assets/boulder_granite.vgmesh"
			obj_file = "res://assets/boulder_granite.obj"
			current_model_name = "Granite Boulder"

	print("Carregando .vgmesh no Pipeline GPU: ", vg_file)
	current_vg_data = VGMeshLoader.load_from_file(vg_file)
	if current_vg_data.is_empty():
		push_error("Erro ao carregar dados do .vgmesh!")
		return

	var lod_count = current_vg_data["lods"].size()
	lod_slider.max_value = max(0, lod_count - 1)
	lod_slider.value = 0
	current_lod = 0

	var total_clusters = current_vg_data["clusters"].size()
	cluster_spin.max_value = max(0, total_clusters - 1)
	cluster_spin.value = 0

	# Carrega no Pipeline de GPU Real
	if gpu_pipeline:
		gpu_pipeline.load_vgmesh(current_vg_data)
		if gpu_pipeline.multimesh_instance and not gpu_pipeline.multimesh_instance.is_inside_tree():
			add_child(gpu_pipeline.multimesh_instance)

	# Ajusta camera ao centro e raio do modelo
	var bmin = current_vg_data["bbox_min"]
	var bmax = current_vg_data["bbox_max"]
	var center = (bmin + bmax) * 0.5
	var size = (bmax - bmin).length()
	orbit_cam.target_offset = center
	orbit_cam.target_distance = size * 1.6
	orbit_base_distance = orbit_cam.target_distance
	orbit_cam.update_camera_transform()

	# Carrega modelo original OBJ para comparacao side-by-side se disponivel
	var orig_mesh = VGMeshLoader.load_original_obj(obj_file)
	if orig_mesh:
		original_instance.mesh = orig_mesh
		original_instance.material_override = material_orig
	original_instance.visible = compare_check.button_pressed

	refresh_mesh()

func refresh_mesh() -> void:
	if current_vg_data.is_empty():
		return

	var is_gpu = gpu_pipeline_check.button_pressed
	var color_clusters = cluster_color_check.button_pressed
	var isolate = int(cluster_spin.value) if isolate_cluster_check.button_pressed else -1

	if is_gpu and gpu_pipeline and gpu_pipeline.multimesh_instance:
		model_instance.visible = false
		gpu_pipeline.multimesh_instance.visible = true
	else:
		if gpu_pipeline and gpu_pipeline.multimesh_instance:
			gpu_pipeline.multimesh_instance.visible = false
		model_instance.visible = true
		var mesh = VGMeshLoader.build_mesh_surface(current_vg_data, current_lod, color_clusters, isolate)
		if mesh:
			model_instance.mesh = mesh
			model_instance.material_override = material_cluster if color_clusters else material_lit

	if wireframe_check.button_pressed:
		var wire_mesh = VGMeshLoader.build_wireframe_mesh(current_vg_data, current_lod, isolate)
		wireframe_instance.mesh = wire_mesh
		wireframe_instance.material_override = material_wire
		wireframe_instance.visible = true
	else:
		wireframe_instance.visible = false

	update_stats_display()

func update_stats_display() -> void:
	if current_vg_data.is_empty():
		return

	var is_gpu = gpu_pipeline_check.button_pressed
	var base_triangles = current_vg_data.get("base_triangles", 1)

	if is_gpu and gpu_pipeline and gpu_pipeline.is_ready:
		var stats = gpu_pipeline.get_stats()
		var vis_tris = stats["triangles_drawn"]
		var vis_c = stats["visible_clusters"]
		var tot_c = stats["total_clusters"]
		var ratio = (float(vis_tris) / max(1.0, float(base_triangles))) * 100.0

		stat_triangles.text = "Triangulos GPU: %s / %s" % [str(vis_tris), str(base_triangles)]
		stat_clusters.text = "Clusters GPU: %d / %d (Culled: %d)" % [vis_c, tot_c, tot_c - vis_c]
		stat_error.text = "Tolerancia Erro: %.2f px" % (1.5 if dynamic_lod_check.button_pressed else 0.0)
		stat_ratio.text = "Reducao Geometria: %.1f%% do base" % ratio
		stat_gpu_time.text = "GPU: %.3f ms | CPU Submit: %.3f ms" % [stats["gpu_time_us"] / 1000.0, stats["cpu_submit_time_us"] / 1000.0]
		stat_vram.text = "Memória VRAM Alocada: %d KB" % stats["vram_kb"]

		var reduction_percent = 100.0 - ratio
		stat_comparison.text = "vs Convencional: -%.1f%% triangulos (%s vs %s)" % [reduction_percent, str(vis_tris), str(base_triangles)]
	else:
		var lods = current_vg_data["lods"]
		var active_tris = 0
		var active_clusters = 0
		var max_err = 0.0
		var ratio = 100.0

		if current_lod < lods.size():
			var ld = lods[current_lod]
			active_tris = ld["triangle_count"]
			active_clusters = ld["cluster_count"]
			max_err = ld["max_error"]
			ratio = ld["triangle_ratio"] * 100.0

		lod_label.text = "Nivel de LOD: %d / %d" % [current_lod, lods.size() - 1]
		stat_triangles.text = "Triangulos Ativos: %s" % str(active_tris)
		stat_clusters.text = "Clusters Ativos: %d" % active_clusters
		stat_error.text = "Erro Metrico (max): %.4f" % max_err
		stat_ratio.text = "Reducao Geometria: %.1f%% do base" % ratio
		stat_gpu_time.text = "Tempo GPU Compute: 0.00 ms (Modo CPU)"
		stat_vram.text = "Memória VRAM: Em RAM do Sistema"
		stat_comparison.text = "vs Convencional: %d vs %d tris" % [active_tris, base_triangles]

func _process(delta: float) -> void:
	var fps = Engine.get_frames_per_second()
	stat_fps.text = "FPS: %d (%.2f ms)" % [fps, 1000.0 / max(1, fps)]
	var cam_dist = orbit_cam.target_distance
	stat_cam_dist.text = "Distancia Camera: %.2f m" % cam_dist

	# 1. Movimentacao Automatica da Camera para Demonstracao em Tempo Real
	if auto_orbit_check.button_pressed:
		orbit_cam.yaw += delta * 0.4
		var time_s = float(Time.get_ticks_msec()) * 0.001
		orbit_cam.target_distance = orbit_base_distance * (1.0 + 0.45 * sin(time_s * 0.8))
		orbit_cam.pitch = -0.3 + 0.2 * sin(time_s * 0.5)
		orbit_cam.update_camera_transform()

	# 2. Execucao do Pipeline de GPU Real por Frame (100% na GPU)
	if gpu_pipeline_check.button_pressed and gpu_pipeline and gpu_pipeline.is_ready:
		var cam: Camera3D = orbit_cam.camera
		var vp_size = get_viewport().get_visible_rect().size
		var lod_mode = 0 if dynamic_lod_check.button_pressed else 1
		var frustum_on = frustum_cull_check.button_pressed
		var cluster_colors_on = cluster_color_check.button_pressed

		# Disparo do Compute Shader (100% na GPU, zero leitura bloqueante para desenho)
		gpu_pipeline.dispatch_culling(
			cam,
			vp_size,
			1.5,
			lod_mode,
			current_lod,
			frustum_on,
			true,
			cluster_colors_on
		)

		# Atualiza estatisticas na UI de forma desacoplada (a cada 10 frames)
		stats_frame_counter += 1
		if stats_frame_counter >= 10:
			stats_frame_counter = 0
			gpu_pipeline.poll_stats_async()
			update_stats_display()
	elif is_dynamic_lod and not current_vg_data.is_empty():
		evaluate_dynamic_lod_cpu(cam_dist)

func evaluate_dynamic_lod_cpu(dist: float) -> void:
	var lods = current_vg_data["lods"]
	var lod_count = lods.size()
	if lod_count <= 1:
		return

	var target_pixel_tolerance = 1.5
	var screen_factor = 720.0 * 0.5

	var selected_lod = 0
	for i in range(lod_count - 1, -1, -1):
		var err = lods[i]["max_error"]
		var proj_err = (err / max(dist, 0.1)) * screen_factor
		if proj_err <= target_pixel_tolerance:
			selected_lod = i
			break

	if selected_lod != current_lod:
		current_lod = selected_lod
		lod_slider.set_value_no_signal(current_lod)
		refresh_mesh()

func _on_lod_slider_changed(value: float) -> void:
	if not is_dynamic_lod:
		current_lod = int(value)
		refresh_mesh()

func _on_dynamic_lod_toggled(enabled: bool) -> void:
	is_dynamic_lod = enabled
	lod_slider.editable = not enabled
	if not enabled:
		current_lod = int(lod_slider.value)
		refresh_mesh()

func _on_wireframe_toggled(enabled: bool) -> void:
	wireframe_instance.visible = enabled
	refresh_mesh()

func _on_compare_toggled(enabled: bool) -> void:
	original_instance.visible = enabled
	var sep_dist = orbit_cam.target_distance * 0.35
	if enabled:
		original_instance.position = Vector3(sep_dist, 0, 0)
		model_instance.position = Vector3(-sep_dist, 0, 0)
		if gpu_pipeline and gpu_pipeline.multimesh_instance:
			gpu_pipeline.multimesh_instance.position = Vector3(-sep_dist, 0, 0)
	else:
		original_instance.position = Vector3.ZERO
		model_instance.position = Vector3.ZERO
		if gpu_pipeline and gpu_pipeline.multimesh_instance:
			gpu_pipeline.multimesh_instance.position = Vector3.ZERO
