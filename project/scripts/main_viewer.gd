extends Node3D

const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

# Referencias aos nos
@onready var orbit_cam: Node3D = $CameraPivot
@onready var model_instance: MeshInstance3D = $ModelInstance
@onready var original_instance: MeshInstance3D = $OriginalInstance
@onready var wireframe_instance: MeshInstance3D = $WireframeInstance
@onready var world_env: WorldEnvironment = $WorldEnvironment

# Controles de UI
@onready var model_option: OptionButton = $UI/Panel/VBox/ModelOption
@onready var lod_slider: HSlider = $UI/Panel/VBox/LODSlider
@onready var lod_label: Label = $UI/Panel/VBox/LODLabel
@onready var dynamic_lod_check: CheckBox = $UI/Panel/VBox/DynamicLODCheck
@onready var gpu_pipeline_check: CheckBox = $UI/Panel/VBox/GPUPipelineCheck
@onready var multimesh_check: CheckBox = $UI/Panel/VBox/MultiMeshCheck
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

# Novo Pipeline Nativo V7 Forward+ e Instancia de Geometria Virtual
var native_pipeline: ArboriaNativePipeline
var native_instance: ArboriaInstance3D
var compositor_effect: ArboriaCompositorEffect

# Pipeline Legado (Fallback de Diagnóstico)
var gpu_pipeline: RefCounted = null
var current_vg_data: Dictionary = {}
var current_lod: int = 0
var current_model_name: String = ""
var current_vg_path: String = ""
var is_dynamic_lod: bool = false
var orbit_base_distance: float = 6.0
var stats_frame_counter: int = 0

# Materiais Legados / CPU
var material_cluster: StandardMaterial3D
var material_lit: StandardMaterial3D
var material_wire: StandardMaterial3D
var material_orig: StandardMaterial3D

func _ready() -> void:
	print("Inicializando Visualizador de Geometria Virtualizada (Arboria VG — Fase 3 / V7 Nativa)...")
	setup_materials()
	setup_native_pipeline()
	setup_ui()
	load_selected_model(0)

	if "--auto-quit" in OS.get_cmdline_user_args() or "--auto-quit" in OS.get_cmdline_args():
		get_tree().create_timer(1.5).timeout.connect(func(): get_tree().quit(0))

func setup_native_pipeline() -> void:
	# Inicializa o pipeline nativo Forward+
	native_pipeline = ArboriaNativePipeline.get_or_create_shared()

	# Cria a instancia de geometria virtualizada na cena
	native_instance = ArboriaInstance3D.new()
	native_instance.name = "NativeVirtualMeshInstance"
	add_child(native_instance)

	# Registra o CompositorEffect no WorldEnvironment (Depth Prepass + Main Opaque)
	if world_env:
		ArboriaCompositorEffect.attach_to_environment(world_env)
		if orbit_cam and orbit_cam.has_node("Camera3D"):
			orbit_cam.get_node("Camera3D").compositor = world_env.compositor

func _exit_tree() -> void:
	if native_instance and native_instance.is_inside_tree():
		native_instance.queue_free()
	if world_env and world_env.compositor:
		world_env.compositor.compositor_effects.clear()
	compositor_effect = null
	if native_pipeline:
		native_pipeline.cleanup()
	if gpu_pipeline and gpu_pipeline.has_method("destroy"):
		gpu_pipeline.destroy()

func setup_materials() -> void:
	material_cluster = StandardMaterial3D.new()
	material_cluster.vertex_color_use_as_albedo = true
	material_cluster.roughness = 0.4
	material_cluster.cull_mode = BaseMaterial3D.CULL_BACK

	material_lit = StandardMaterial3D.new()
	material_lit.albedo_color = Color(0.8, 0.82, 0.85)
	material_lit.roughness = 0.5
	material_lit.cull_mode = BaseMaterial3D.CULL_BACK

	material_wire = StandardMaterial3D.new()
	material_wire.albedo_color = Color(0.0, 1.0, 0.6)
	material_wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_wire.cull_mode = BaseMaterial3D.CULL_DISABLED

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

	gpu_pipeline_check.toggled.connect(func(enabled: bool):
		if enabled:
			multimesh_check.set_pressed_no_signal(false)
		refresh_mesh()
	)
	multimesh_check.toggled.connect(func(enabled: bool):
		if enabled:
			gpu_pipeline_check.set_pressed_no_signal(false)
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

	current_vg_path = vg_file
	print("Carregando .vgmesh no Renderizador Nativo Forward+: ", vg_file)
	current_vg_data = ArboriaMeshLoader.load_from_file(vg_file)
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

	# Associa a malha na instância de geometria virtualizada nativa
	if native_instance:
		native_instance.mesh_path = vg_file
		native_instance.lod_mode = 0 if dynamic_lod_check.button_pressed else 1
		native_instance.forced_lod = current_lod
		native_instance.max_screen_error = 1.5

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
	var orig_mesh = ArboriaMeshLoader.load_original_obj(obj_file)
	if orig_mesh:
		original_instance.mesh = orig_mesh
		original_instance.material_override = material_orig
	original_instance.visible = compare_check.button_pressed

	refresh_mesh()

func refresh_mesh() -> void:
	if current_vg_data.is_empty():
		return

	var is_multimesh = multimesh_check.button_pressed
	var is_gpu_native = gpu_pipeline_check.button_pressed and not is_multimesh
	var color_clusters = cluster_color_check.button_pressed
	var isolate = int(cluster_spin.value) if isolate_cluster_check.button_pressed else -1

	# Atualiza modo de shading no pipeline nativo
	if native_pipeline:
		if color_clusters:
			native_pipeline.global_shading_mode = 3 # Cluster Debug Colors
		else:
			native_pipeline.global_shading_mode = 0 # Forward+ PBR

	if is_gpu_native:
		# MODO PRINCIPAL: Instancia nativa Forward+ no CompositorEffect (sem viewport secundario)
		model_instance.visible = false
		if native_instance:
			native_instance.visible = true
			native_instance.lod_mode = 0 if dynamic_lod_check.button_pressed else 1
			native_instance.forced_lod = current_lod
			native_instance.max_screen_error = 1.5
		if compositor_effect:
			compositor_effect.active = true
		if gpu_pipeline:
			gpu_pipeline.disable_multimesh_fallback()

	elif is_multimesh:
		# MODO DIAGNOSTICO FALLBACK: MultiMesh
		if native_instance:
			native_instance.visible = false
		if compositor_effect:
			compositor_effect.active = false
		model_instance.visible = false
		if gpu_pipeline:
			var mm = gpu_pipeline.setup_multimesh_fallback(current_vg_data)
			if mm and not mm.is_inside_tree():
				add_child(mm)
			if mm:
				mm.visible = true

	else:
		# MODO DIAGNOSTICO CPU
		if native_instance:
			native_instance.visible = false
		if compositor_effect:
			compositor_effect.active = false
		if gpu_pipeline:
			gpu_pipeline.disable_multimesh_fallback()
		model_instance.visible = true
		var mesh = ArboriaMeshLoader.build_mesh_surface(current_vg_data, current_lod, color_clusters, isolate)
		if mesh:
			model_instance.mesh = mesh
			model_instance.material_override = material_cluster if color_clusters else material_lit

	if wireframe_check.button_pressed:
		var wire_mesh = ArboriaMeshLoader.build_wireframe_mesh(current_vg_data, current_lod, isolate)
		wireframe_instance.mesh = wire_mesh
		wireframe_instance.material_override = material_wire
		wireframe_instance.visible = true
	else:
		wireframe_instance.visible = false

	update_stats_display()

func update_stats_display() -> void:
	if current_vg_data.is_empty():
		return

	var is_gpu_native = gpu_pipeline_check.button_pressed and not multimesh_check.button_pressed
	var base_triangles = current_vg_data.get("base_triangles", 1)

	if is_gpu_native and native_pipeline:
		var vis_tris = native_pipeline.stats_triangles_drawn
		var vis_c = native_pipeline.stats_visible_clusters
		var tot_c = current_vg_data["clusters"].size()
		var ratio = (float(vis_tris) / max(1.0, float(base_triangles))) * 100.0

		stat_triangles.text = "Triangulos GPU: %s / %s" % [str(vis_tris), str(base_triangles)]
		stat_clusters.text = "Clusters GPU: %d / %d" % [vis_c, tot_c]
		stat_error.text = "Tolerancia Erro: %.2f px" % (1.5 if dynamic_lod_check.button_pressed else 0.0)
		stat_ratio.text = "Reducao Geometria: %.1f%% do base" % ratio
		stat_gpu_time.text = "Forward+ Nativo: Reversed-Z Ativo"
		stat_vram.text = "Memoria VRAM: Compartilhada"
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
		stat_gpu_time.text = "Tempo GPU: Fallback Ativo"
		stat_vram.text = "Memória VRAM: Em RAM do Sistema"
		stat_comparison.text = "vs Convencional: %d vs %d tris" % [active_tris, base_triangles]

func _process(delta: float) -> void:
	var fps = Engine.get_frames_per_second()
	stat_fps.text = "FPS: %d (%.2f ms)" % [fps, 1000.0 / max(1, fps)]
	var cam_dist = orbit_cam.target_distance
	stat_cam_dist.text = "Distancia Camera: %.2f m" % cam_dist

	# Movimentacao automatica da camera quando ativada
	if auto_orbit_check.button_pressed:
		orbit_cam.yaw += delta * 0.4
		var time_s = float(Time.get_ticks_msec()) * 0.001
		orbit_cam.target_distance = orbit_base_distance * (1.0 + 0.45 * sin(time_s * 0.8))
		orbit_cam.pitch = -0.3 + 0.2 * sin(time_s * 0.5)
		orbit_cam.update_camera_transform()

	# Atualizacao das estatisticas
	stats_frame_counter += 1
	if stats_frame_counter >= 10:
		stats_frame_counter = 0
		update_stats_display()

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
		if native_instance:
			native_instance.position = Vector3(-sep_dist, 0, 0)
	else:
		original_instance.position = Vector3.ZERO
		model_instance.position = Vector3.ZERO
		if native_instance:
			native_instance.position = Vector3.ZERO
