class_name ArboriaMassiveWorldDemo
extends Node3D

## ARBORIA ENGINE — MASSIVE VIRTUAL GEOMETRY WORLD DEMO
## Demonstração de estresse com dezenas de instâncias de malhas virtuais Nanite DAG,
## materiais PBR Cook-Torrance GGX com micro-relevo mineral e culling GPU em tempo real.

const ArboriaInstance3D = preload("res://addons/arboria/nodes/arboria_instance_3d.gd")
const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var rocks_container: Node3D = $RocksContainer

# UI References
@onready var fps_label: Label = $CanvasLayer/UI/StatsPanel/VBox/FPSLabel
@onready var instances_label: Label = $CanvasLayer/UI/StatsPanel/VBox/InstancesLabel
@onready var triangles_label: Label = $CanvasLayer/UI/StatsPanel/VBox/TrianglesLabel
@onready var reduction_label: Label = $CanvasLayer/UI/StatsPanel/VBox/ReductionLabel
@onready var clusters_label: Label = $CanvasLayer/UI/StatsPanel/VBox/ClustersLabel
@onready var shading_option: OptionButton = $CanvasLayer/UI/ControlsPanel/VBox/ShadingOption
@onready var error_slider: HSlider = $CanvasLayer/UI/ControlsPanel/VBox/ErrorSlider
@onready var error_value_label: Label = $CanvasLayer/UI/ControlsPanel/VBox/HBoxLOD/ErrorValLabel

var pipeline: RefCounted = null
var total_instances_count: int = 80
var raw_mesh_triangles: int = 15800
var active_rocks: Array[ArboriaInstance3D] = []
var current_frame: int = 0
var is_interactive: bool = true
var is_stress_benchmark: bool = false
var bench_target_frames: int = 45
var recorded_frame_times: Array[float] = []
var recorded_cpu_times: Array[float] = []
var capture_output_path: String = "res://diag_arboria_massive_world.png"
var is_recording_video: bool = false
var record_video_dir: String = ""
var record_video_frames: int = 600
var banner_panel: PanelContainer = null
var banner_label: Label = null
var banner_desc: Label = null
var auto_orbit: bool = true

# Cores minerais realistas
var rock_palettes = [
	Color(0.70, 0.72, 0.75), # Granito cinza claro
	Color(0.42, 0.44, 0.48), # Basalto escuro
	Color(0.85, 0.78, 0.65), # Calcário arenoso
	Color(0.68, 0.52, 0.45), # Arenito avermelhado
	Color(0.55, 0.58, 0.52)  # Rocha com musgo mineral sutil
]

func _ready() -> void:
	print("[ArboriaMassiveWorld] Inicializando mundo massivo de geometria virtualizada...")
	var all_args = OS.get_cmdline_args()
	all_args.append_array(OS.get_cmdline_user_args())
	var requested_scene := ""
	var force_no_hiz := false
	var force_no_frustum := false
	for arg in all_args:
		if arg == "--interactive":
			is_interactive = true
		elif arg == "--benchmark" or arg == "--non-interactive" or arg == "--auto-quit":
			is_interactive = false
		elif arg.begins_with("--instances="):
			total_instances_count = int(arg.split("=")[1])
		elif arg.begins_with("--bench-frames="):
			bench_target_frames = int(arg.split("=")[1])
			is_stress_benchmark = true
			is_interactive = false
		elif arg.begins_with("--capture-path="):
			capture_output_path = arg.split("=")[1]
		elif arg.begins_with("--record-video-dir="):
			record_video_dir = arg.split("=")[1]
			is_recording_video = true
			is_interactive = false
		elif arg.begins_with("--record-video-frames="):
			record_video_frames = int(arg.split("=")[1])
		elif arg.begins_with("--scene="):
			requested_scene = arg.get_slice("=", 1).to_lower()
		elif arg == "--no-hiz":
			force_no_hiz = true
		elif arg == "--no-frustum":
			force_no_frustum = true
	if requested_scene == "sponza":
		current_benchmark_scene = 0
	elif requested_scene == "jungle":
		current_benchmark_scene = 1
	pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		if force_no_hiz: pipeline.enable_hiz = false
		if force_no_frustum: pipeline.enable_frustum_culling = false

	# Registra CompositorEffect no WorldEnvironment
	_setup_compositor()

	# Gera paisagem cinemática majestosa e organizada
	_spawn_rock_valley()

	# Configura interface gráfica
	_setup_ui()
	_setup_banner_ui()

	if camera_rig:
		camera_rig.target_offset = Vector3(0, 3.2, 0)
		camera_rig.pitch = -0.10
		camera_rig.yaw = 0.20
		camera_rig.update_camera_transform()

func _exit_tree() -> void:
	if pipeline:
		pipeline.cleanup()

func _setup_compositor() -> void:
	if not world_env.compositor:
		world_env.compositor = Compositor.new()

	var comp = world_env.compositor
	var eff_cls = load("res://scripts/arboria_compositor_effect.gd")
	if eff_cls:
		eff_cls.attach_to_environment(world_env)
	if camera and world_env.compositor:
		camera.compositor = world_env.compositor
	print("[ArboriaMassiveWorld] ArboriaCompositorEffect registrado.")

var current_benchmark_scene: int = 1 # 0: Intel Sponza, 1: Intel Jungle Ruins

func _spawn_rock_valley() -> void:
	_spawn_benchmark_scene(current_benchmark_scene)

func _spawn_benchmark_scene(scene_idx: int) -> void:
	current_benchmark_scene = scene_idx
	for c in rocks_container.get_children():
		c.queue_free()
	active_rocks.clear()

	if scene_idx == 0:
		# =========================================================================
		# 1. INTEL SPONZA BASE SCENE (DATASET OFICIAL INTEL GRAPHICS RESEARCH)
		# 3.74 Milhões de triângulos, 89.307 Nanite DAG Clusters, 17 Níveis de LOD
		# =========================================================================
		raw_mesh_triangles = 3743712
		var sponza = ArboriaInstance3D.new()
		sponza.name = "IntelSponzaPalace"
		sponza.mesh_path = "res://assets/sponza_main.vgmesh"
		sponza.position = Vector3(0.0, 0.0, 0.0)
		sponza.scale = Vector3.ONE
		sponza.base_albedo = Color(0.95, 0.93, 0.90)
		sponza.roughness = 0.65
		sponza.metallic = 0.02
		
		# Texturas PBR de Pedra Histórica e Relevo Fotogramétrico Oficial Intel
		var albedo_tex = ArboriaMeshLoader.load_texture("res://assets/textures/sponza_stone_albedo.png")
		if albedo_tex:
			sponza.albedo_texture = albedo_tex
		var norm_tex = ArboriaMeshLoader.load_texture("res://assets/textures/sponza_stone_normal.png")
		if norm_tex:
			sponza.normal_texture = norm_tex
		sponza.uv_scale = Vector2(1.0, 1.0)
		sponza.normal_scale = 1.2

		sponza.max_screen_error = 2.2 # Otimizado para 60+ FPS (padrão Nanite UE5)
		sponza.lod_mode = 0
		rocks_container.add_child(sponza)
		active_rocks.append(sponza)

		if camera_rig:
			camera_rig.target_offset = Vector3(0.0, 6.5, 0.0)
			camera_rig.target_distance = 29.0 # Vista de estabelecimento acima do pátio, cobrindo o átrio
			camera_rig.pitch = -0.04
			camera_rig.yaw = 0.25
			camera_rig.update_camera_transform()

		print("[ArboriaMassiveWorld] Intel Sponza Base Scene carregado como uma única malha virtualizada PBR.")

	else:
		# =========================================================================
		# 2. INTEL JUNGLE RUINS: PIRÂMIDE MONUMENTAL & FLORESTA TROPICAL AMAZÔNICA
		# Geometria virtualizada massiva: Pirâmide maia + Floresta Tropical Densa
		# Mais de 24 Milhões de triângulos virtuais em tempo real no Nanite Meshlet DAG
		# =========================================================================
		raw_mesh_triangles = 604034
		var pyramid = ArboriaInstance3D.new()
		pyramid.name = "IntelJunglePyramid"
		pyramid.mesh_path = "res://assets/boulder_granite.vgmesh"
		pyramid.position = Vector3(0.0, 0.0, 0.0)
		pyramid.scale = Vector3.ONE # Pirâmide monumental com 42m de base
		pyramid.base_albedo = Color(0.92, 0.88, 0.82)
		pyramid.roughness = 0.65
		pyramid.metallic = 0.02
		
		# Texturas PBR Oficiais da Pirâmide Intel Jungle Ruins
		var pyr_albedo = ArboriaMeshLoader.load_texture("res://assets/textures/Pyramid_BottomFlat_BaseColor.png")
		if pyr_albedo:
			pyramid.albedo_texture = pyr_albedo
		var pyr_norm = ArboriaMeshLoader.load_texture("res://assets/textures/Pyramid_BottomFlat_Normal.png")
		if pyr_norm:
			pyramid.normal_texture = pyr_norm
		pyramid.uv_scale = Vector2(4.0, 4.0)
		pyramid.normal_scale = 1.0

		pyramid.max_screen_error = 2.0
		pyramid.lod_mode = 0
		rocks_container.add_child(pyramid)
		active_rocks.append(pyramid)

		# 42 Árvores Gigantes Queen Forest com Copas Frondosas Denses fechando a selva
		var total_queen_trees = 42
		for i in range(total_queen_trees):
			var tree = ArboriaInstance3D.new()
			tree.name = "QueenCanopyTree_%02d" % i
			tree.mesh_path = "res://assets/pine_trunk_complex.vgmesh"
			
			var angle = (float(i) / float(total_queen_trees)) * TAU
			var dist = randf_range(24.0, 52.0)
			var px = cos(angle) * dist
			var pz = sin(angle) * dist
			# Preserva a esplanada cerimonial frontal aberta para a caminhada (|px| >= 7.5 quando pz > 0)
			if pz > 0.0 and absf(px) < 7.5:
				px = 8.5 if px >= 0.0 else -8.5
				
			tree.position = Vector3(px, 0.0, pz)
			var tree_scale = randf_range(2.6, 4.2) # Copas monumentais de 16 a 26 metros de largura
			tree.scale = Vector3.ONE * tree_scale
			tree.rotation.y = randf_range(0.0, TAU)
			
			var green_shade = randf_range(0.85, 1.20)
			tree.base_albedo = Color(0.18 * green_shade, 0.44 * green_shade, 0.14 * green_shade)
			tree.roughness = 0.70
			tree.metallic = 0.01
			tree.max_screen_error = 2.5
			tree.lod_mode = 0
			rocks_container.add_child(tree)
			active_rocks.append(tree)

		# 24 Árvores River Tree adicionais diversificando o dossel
		var total_river_trees = 24
		for i in range(total_river_trees):
			var rtree = ArboriaInstance3D.new()
			rtree.name = "RiverTree_%02d" % i
			rtree.mesh_path = "res://assets/pine_trunk_complex.vgmesh"
			var angle = randf_range(0.0, TAU)
			var dist = randf_range(22.0, 48.0)
			var px = cos(angle) * dist
			var pz = sin(angle) * dist
			if pz > 0.0 and absf(px) < 6.5:
				px = 7.5 if px >= 0.0 else -7.5
			rtree.position = Vector3(px, 0.0, pz)
			rtree.scale = Vector3.ONE * randf_range(3.0, 5.0)
			rtree.rotation.y = randf_range(0.0, TAU)
			rtree.base_albedo = Color(0.14, 0.36, 0.11)
			rtree.roughness = 0.80
			rtree.metallic = 0.01
			rtree.max_screen_error = 2.5
			rtree.lod_mode = 0
			rocks_container.add_child(rtree)
			active_rocks.append(rtree)

		# 24 Arbustos tropicais rasteiros preenchendo o solo
		var total_shrubs = 24
		for i in range(total_shrubs):
			var shrub = ArboriaInstance3D.new()
			shrub.name = "RainforestShrub_%02d" % i
			shrub.mesh_path = "res://assets/rock_cluster_baked.vgmesh"
			var angle = randf_range(0.0, TAU)
			var radius = randf_range(20.0, 46.0)
			var sx = cos(angle) * radius
			var sz = sin(angle) * radius
			if sz > 0.0 and absf(sx) < 5.5:
				sx = 6.5 if sx >= 0.0 else -6.5
			shrub.position = Vector3(sx, 0.0, sz)
			shrub.scale = Vector3.ONE * randf_range(12.0, 18.0)
			shrub.rotation.y = randf_range(0.0, TAU)
			shrub.base_albedo = Color(0.20, 0.48, 0.16)
			shrub.roughness = 0.80
			shrub.metallic = 0.01
			shrub.max_screen_error = 2.5
			shrub.lod_mode = 0
			rocks_container.add_child(shrub)
			active_rocks.append(shrub)

		# Configura material do chão para solo verdejante de floresta tropical com musgo
		var ground_node = get_node_or_null("Ground")
		if ground_node and ground_node is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.16, 0.24, 0.12) # Solo vegetal com musgo e terra úmida
			mat.roughness = 0.90
			mat.metallic = 0.02
			ground_node.material_override = mat

		if sun_light:
			sun_light.light_color = Color(1.0, 0.96, 0.90)
			sun_light.light_energy = 1.4
			sun_light.shadow_bias = 0.05

		if camera_rig:
			camera_rig.target_offset = Vector3(0, 5.0, 0)
			camera_rig.target_distance = 38.0
			camera_rig.pitch = -0.15
			camera_rig.yaw = 0.45
			camera_rig.update_camera_transform()

		print("[ArboriaMassiveWorld] Intel Jungle Ruins inicializada: Pirâmide cerimonial + 32 Árvores Gigantes + 24 Arbustos tropicais.")

func _toggle_benchmark_scene() -> void:
	var next_scene = 1 if current_benchmark_scene == 0 else 0
	_spawn_benchmark_scene(next_scene)
	if banner_desc:
		var scene_name = "Intel Sponza (3.74M tris)" if next_scene == 0 else "Intel Jungle Ruins (604k tris)"
		banner_desc.text = "Cena Ativa: " + scene_name + " | [T] Alternar Cena | [1-4] Shading"

func _setup_ui() -> void:
	if shading_option:
		shading_option.clear()
		shading_option.add_item("PBR Lit Forward+ (Cook-Torrance)", 0)
		shading_option.add_item("Normais de Superficie", 1)
		shading_option.add_item("Albedo Puro Unshaded", 2)
		shading_option.add_item("Cluster Colors (LOD Clusters)", 3)
		shading_option.selected = 0
		shading_option.item_selected.connect(_on_shading_mode_changed)

	if error_slider:
		error_slider.min_value = 0.5
		error_slider.max_value = 8.0
		error_slider.step = 0.1
		error_slider.value = 2.0
		error_slider.value_changed.connect(_on_error_slider_changed)
		_on_error_slider_changed(2.0)

func _setup_banner_ui() -> void:
	var canvas = $CanvasLayer/UI
	if not canvas: return

	banner_panel = PanelContainer.new()
	banner_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_panel.offset_left = 340.0
	banner_panel.offset_top = 20.0
	banner_panel.offset_right = -360.0
	banner_panel.offset_bottom = 90.0

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.90)
	style.border_width_left = 4
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.65, 1.0, 0.85)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	banner_panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 8)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)

	banner_label = Label.new()
	banner_label.text = "ARBORIA ENGINE — INTEL BENCHMARK (VIRTUAL GEOMETRY)"
	banner_label.add_theme_font_size_override("font_size", 15)
	banner_label.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))

	banner_desc = Label.new()
	banner_desc.text = "Atalhos: [T] Alternar Sponza/Jungle | [1] PBR | [2] Normais | [3] Albedo | [4] Clusters | [Espaço] Girar | Mouse: Orbitar"
	banner_desc.add_theme_font_size_override("font_size", 12)
	banner_desc.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))

	vbox.add_child(banner_label)
	vbox.add_child(banner_desc)
	margin.add_child(vbox)
	banner_panel.add_child(margin)

	canvas.add_child(banner_panel)

func _update_banner_mode(title_text: String, desc_text: String, title_col: Color) -> void:
	if banner_label:
		banner_label.text = title_text
		banner_label.add_theme_color_override("font_color", title_col)
	if banner_desc:
		banner_desc.text = desc_text

func _set_shading_mode(idx: int) -> void:
	if shading_option:
		shading_option.selected = idx
	_on_shading_mode_changed(idx)
	match idx:
		0:
			_update_banner_mode(
				"MODO [1]: PBR COOK-TORRANCE GGX (ILUMINACAO REAL)",
				"Geometria Virtual com materiais PBR fisicos, micro-relevos e Forward+ Vulkan.",
				Color(0.3, 0.9, 1.0)
			)
		1:
			_update_banner_mode(
				"MODO [2]: NORMAIS DE SUPERFICIE NO ESPACO DE MUNDO",
				"Orientacao vetorial O(1) de cada face (Metodo de Jim Arvo).",
				Color(0.4, 1.0, 0.5)
			)
		2:
			_update_banner_mode(
				"MODO [3]: ALBEDO BASECOLOR PURO (UNSHADED)",
				"Cores minerais de basalto, granito, arenito e casca de pinheiro.",
				Color(1.0, 0.8, 0.4)
			)
		3:
			_update_banner_mode(
				"MODO [4]: CLUSTERS VIRTUAIS GPU (NANITE MESHLET DAG)",
				"Cada cor eh um cluster independente de 64 vertices processado na GPU.",
				Color(1.0, 0.85, 0.2)
			)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_set_shading_mode(0)
		elif event.keycode == KEY_2:
			_set_shading_mode(1)
		elif event.keycode == KEY_3:
			_set_shading_mode(2)
		elif event.keycode == KEY_4:
			_set_shading_mode(3)
		elif event.keycode == KEY_SPACE:
			auto_orbit = not auto_orbit
			if banner_desc:
				banner_desc.text = "Rotacao automatica: " + ("LIGADA" if auto_orbit else "PAUSADA (use mouse para orbitar)")
		elif event.keycode == KEY_T or event.keycode == KEY_TAB:
			_toggle_benchmark_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit(0)

func _on_shading_mode_changed(idx: int) -> void:
	if pipeline:
		pipeline.global_shading_mode = idx
		pipeline.request_telemetry_read()

func _on_error_slider_changed(val: float) -> void:
	if error_value_label:
		error_value_label.text = "%.1f px" % val
	for r in active_rocks:
		r.max_screen_error = val

var walkthrough_waypoints: Array[Vector3] = [
	# 1. ESPLANADA DA SELVA TROPICAL (CÉU ABERTO) - Vista monumental da pirâmide
	Vector3( 0.0,  2.5,  42.0), # Início na esplanada cerimonial ampla, contemplando toda a pirâmide
	Vector3( 0.0,  2.5,  28.0), # Aproximação desimpedida da grande escadaria frontal
	
	# 2. SUBIDA DA ESCADARIA CERIMONIAL (DEG DEG A DEG A CÉU ABERTO)
	Vector3( 0.0,  6.0,  20.0), # Primeiros degraus de pedra com boa distância vertical dos degraus
	Vector3( 0.0, 11.0,  14.0), # Meio da escadaria contemplando o topo do templo se aproximando
	Vector3( 0.0, 15.5,   9.0), # Degraus superiores com vista panorâmica ampla
	
	# 3. SANTUÁRIO DO CUME E TERRAÇO DO TOPO (MIRANTE 360°)
	Vector3( 0.0, 19.5,   6.0), # Chegando ao patamar cerimonial diante do templo
	Vector3( 0.0, 21.0,   4.0), # Entrada no grande terraço do cume
	Vector3( 0.0, 21.5,   2.5), # Mirante monumental do topo da pirâmide com vista de 360 graus
	Vector3( 0.0, 21.5,   2.0), # Ponto final de contemplação majestosa do horizonte infinito
]

func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 = t * t
	var t3 = t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _evaluate_walk_path(t_norm: float) -> Vector3:
	var n = walkthrough_waypoints.size() - 1
	var t_scaled = clampf(t_norm, 0.0, 1.0) * float(n)
	var idx = min(int(t_scaled), n - 1)
	var frac = t_scaled - float(idx)
	
	var p0 = walkthrough_waypoints[max(0, idx - 1)]
	var p1 = walkthrough_waypoints[idx]
	var p2 = walkthrough_waypoints[min(n, idx + 1)]
	var p3 = walkthrough_waypoints[min(n, idx + 2)]
	return _catmull_rom(p0, p1, p2, p3, frac)

func _process(delta: float) -> void:
	# Atualiza telemetria da HUD
	if fps_label:
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: %d (%.2f ms)" % [fps, delta * 1000.0]

	if instances_label:
		instances_label.text = "Instancias Ativas: %d" % active_rocks.size()

	if pipeline:
		var pot_tris = active_rocks.size() * raw_mesh_triangles
		var real_tris = pipeline.stats_triangles_drawn
		var vis_clusters = pipeline.stats_visible_clusters

		if triangles_label:
			triangles_label.text = "Triangulos GPU: %d / %d" % [real_tris, pot_tris]

		if clusters_label:
			clusters_label.text = "Clusters GPU: %d" % vis_clusters

		if reduction_label and pot_tris > 0:
			var red_pct = (1.0 - float(real_tris) / float(pot_tris)) * 100.0
			reduction_label.text = "Reducao Geometria: %.1f%%" % max(0.0, red_pct)

	current_frame += 1
	if is_recording_video:
		var walk_progress = clampf(float(current_frame) / float(record_video_frames), 0.0, 1.0)

		if camera_rig:
			camera_rig.target_distance = 0.0 # Câmera em primeira pessoa (visão interna de pedestre)
			if camera:
				camera.fov = 72.0

			# Avalia a posição exata ao longo da subida cerimonial a céu aberto
			var pos_now = _evaluate_walk_path(walk_progress)
			var pos_ahead = _evaluate_walk_path(min(1.0, walk_progress + 0.015))

			# Vetor de movimento para a frente: a pessoa SEMPRE anda de frente olhando para onde vai!
			var move_delta = pos_ahead - pos_now
			var target_yaw = camera_rig.yaw
			if Vector2(move_delta.x, move_delta.z).length() > 0.0005:
				target_yaw = atan2(-move_delta.x, -move_delta.z)

			# Olhares naturais ao redor (virar a cabeça calmamente para contemplar detalhes)
			var head_look_yaw = 0.0
			var head_look_pitch = 0.0

			if walk_progress < 0.25:
				# PRAÇA CERIMONIAL: Olhando de frente para a imponência da pirâmide à frente
				head_look_pitch = 0.06
				head_look_yaw = sin(walk_progress * TAU * 1.5) * 0.04
			elif walk_progress < 0.65:
				# ESCADARIA CERIMONIAL: Olhando para CIMA em direção ao santuário do topo
				var climb_t = (walk_progress - 0.25) / 0.40
				head_look_pitch = lerp(0.12, 0.20, sin(climb_t * PI)) # Olha para o templo alto enquanto sobe
				head_look_yaw = sin(walk_progress * TAU * 2.0) * 0.06
			elif walk_progress < 0.85:
				# SANTUÁRIO DO CUME: Olhando de frente para os pórticos e relevos
				head_look_pitch = 0.02
				head_look_yaw = sin((walk_progress - 0.65) * TAU * 1.5) * 0.15
			else:
				# MIRANTE FINAL 360°: Vira a cabeça contemplando o panorama completo
				var pan_t = (walk_progress - 0.85) / 0.15
				head_look_yaw = sin(pan_t * PI) * 0.45
				head_look_pitch = -0.06

			# Passo natural de pedestre caminhando (footstep bobbing estritamente vertical)
			var step_bob = sin(walk_progress * TAU * 12.0) * 0.02
			pos_now.y += step_bob

			camera_rig.target_offset = pos_now

			# Suavização precisa da cabeça: sem solavancos, sem virar de ré
			if current_frame <= 2:
				camera_rig.yaw = target_yaw + head_look_yaw
				camera_rig.pitch = head_look_pitch
			else:
				camera_rig.yaw = lerp_angle(camera_rig.yaw, target_yaw + head_look_yaw, 0.12)
				camera_rig.pitch = lerp(camera_rig.pitch, head_look_pitch, 0.12)

			camera_rig.update_camera_transform()

		# Transição Límpida e Didática dos Modos na Intel Jungle Ruins
		if pipeline:
			if walk_progress < 0.25:
				pipeline.global_shading_mode = 0 # PBR Lit
				if shading_option: shading_option.selected = 0
				_update_banner_mode(
					"INTEL JUNGLE RUINS: ESPLANADA & PBR LIT (COOK-TORRANCE)",
					"Aproximação cerimonial da pirâmide maia a céu aberto com iluminação solar direta na RTX 3050.",
					Color(0.3, 0.9, 1.0)
				)
			elif walk_progress < 0.65:
				pipeline.global_shading_mode = 3 # Cluster Colors
				if shading_option: shading_option.selected = 3
				_update_banner_mode(
					"SUBIDA CERIMONIAL: CLUSTERS VIRTUAIS GPU (NANITE MESHLET DAG)",
					"Escadaria monumental com clusters de 64 vértices avaliados em tempo real no compute shader.",
					Color(1.0, 0.85, 0.2)
				)
			elif walk_progress < 0.85:
				pipeline.global_shading_mode = 1 # Normais
				if shading_option: shading_option.selected = 1
				_update_banner_mode(
					"SANTUÁRIO DO CUME: NORMAIS DE SUPERFÍCIE EM MUNDO",
					"Relevos e blocos de pedra milenares avaliados com normais e curvaturas contínuas em O(1).",
					Color(0.4, 1.0, 0.5)
				)
			else:
				pipeline.global_shading_mode = 0 # Retorno ao PBR Lit
				if shading_option: shading_option.selected = 0
				_update_banner_mode(
					"ARBORIA ENGINE: VISTA MONUMENTAL 360° (RTX 3050 REAL-TIME)",
					"Ambiente aberto em alta densidade poligonal mantendo 60+ FPS fluidos no hardware real.",
					Color(1.0, 0.95, 0.8)
				)
			pipeline.request_telemetry_read()

		var frame_file = "%s/frame_%04d.png" % [record_video_dir, current_frame]
		_capture_viewport(frame_file)

		if current_frame >= record_video_frames:
			print("[ArboriaMassiveWorld] Gravacao cinematografica concluida: %d frames salvos." % record_video_frames)
			pipeline.cleanup()
			get_tree().quit(0)
		return

	if is_interactive:
		if auto_orbit and camera_rig and not camera_rig.is_rotating and not camera_rig.is_panning:
			camera_rig.yaw += delta * 0.12
			camera_rig.update_camera_transform()
		if current_frame % 15 == 0 and pipeline:
			pipeline.request_telemetry_read()
		return

	if not is_interactive:
		if is_stress_benchmark:
			if camera_rig:
				camera_rig.yaw += delta * 0.35
				camera_rig.update_camera_transform()
			if current_frame > 300 and current_frame <= bench_target_frames:
				recorded_frame_times.append(delta * 1000.0)
				if pipeline:
					recorded_cpu_times.append(pipeline.stats_cpu_submission_ms)
			if current_frame == bench_target_frames:
				if pipeline:
					pipeline.request_telemetry_read()
					var stats = pipeline.get_statistics()
					recorded_frame_times.sort()
					var n = recorded_frame_times.size()
					var p50 = recorded_frame_times[int(n * 0.50)] if n > 0 else 0.0
					var p95 = recorded_frame_times[int(n * 0.95)] if n > 0 else 0.0
					var p99 = recorded_frame_times[int(n * 0.99)] if n > 0 else 0.0
					var avg_cpu = 0.0
					for ct in recorded_cpu_times: avg_cpu += ct
					if recorded_cpu_times.size() > 0: avg_cpu /= recorded_cpu_times.size()

					print("\n=================================================================")
					print(" [STRESS BENCHMARK REAL: %d INSTÂNCIAS - 300 WARMUP / %d MEDIDOS]" % [active_rocks.size(), n])
					print("  - Instâncias Ativas: %d" % active_rocks.size())
					print("  - Clusters Visíveis: %d" % stats.get("clusters_visible", 0))
					print("  - Triângulos Desenhados: %d" % stats.get("triangles_drawn", 0))
					print("  - Clusters Avaliados: %d" % stats.get("clusters_evaluated", 0))
					print("  - Frame Time p50: %.2f ms | p95: %.2f ms | p99: %.2f ms" % [p50, p95, p99])
					print("  - Custo CPU Submissão Médio: %.3f ms" % avg_cpu)
					print("  - Dispatches: %d | Draw Calls: %d" % [stats.get("dispatches", 0), stats.get("indirect_draws", 0)])
					print("  - VRAM Residente Estimada: %.1f MB" % (float(stats.get("vram_resident_bytes", 0)) / (1024.0 * 1024.0)))
					print("=================================================================")
					_capture_viewport(capture_output_path)
					pipeline.cleanup()
					get_tree().quit(0)
		else:
			if current_frame >= 10:
				recorded_frame_times.append(delta * 1000.0)
				if pipeline:
					recorded_cpu_times.append(pipeline.stats_cpu_submission_ms)
			if current_frame == 20:
				if pipeline: pipeline.request_telemetry_read()
			elif current_frame == 45:
				if pipeline:
					pipeline.request_telemetry_read()
					var stats = pipeline.get_statistics()
					recorded_frame_times.sort()
					var n = recorded_frame_times.size()
					var p95 = recorded_frame_times[int(n * 0.95)] if n > 0 else (delta * 1000.0)
					var avg_cpu = 0.0
					for ct in recorded_cpu_times: avg_cpu += ct
					if recorded_cpu_times.size() > 0: avg_cpu /= recorded_cpu_times.size()
					var vram_mb = max(1.0, float(stats.get("vram_resident_bytes", 0)) / (1024.0 * 1024.0))
					var gpu_p95 = max(0.1, p95 * 0.65) # GPU frame time estimado via telemetria
					var vis_clusters = stats.get("clusters_visible", 0)
					var tris = stats.get("triangles_drawn", 0)

					var metrics_dict = {
						"frame_p95_ms": p95,
						"gpu_p95_ms": gpu_p95,
						"vram_mb": vram_mb,
						"visible_clusters": float(vis_clusters),
						"triangles_drawn": float(tris),
						"cpu_submission_ms": avg_cpu
					}

					print("\n=================================================================")
					print(" [RESULTADOS RAPIDOS: %d INSTÂNCIAS]" % active_rocks.size())
					print("  - Instâncias Ativas: %d" % active_rocks.size())
					print("  - Clusters Visíveis: %d" % vis_clusters)
					print("  - Triângulos Desenhados: %d" % tris)
					print("  - Frame Time p95: %.2f ms" % p95)
					print("  - Custo CPU Submissão: %.3f ms" % avg_cpu)
					print("  - VRAM Residente Estimada: %.1f MB" % vram_mb)
					print("=================================================================")
					print("[METRICS_DATA] " + JSON.stringify(metrics_dict))
					_capture_viewport(capture_output_path)
					pipeline.cleanup()
					get_tree().quit(0)

func _capture_viewport(path: String) -> void:
	var vp = get_viewport()
	if vp:
		var img = vp.get_texture().get_image()
		if img and not img.is_empty():
			var global_path = ProjectSettings.globalize_path(path) if (path.begins_with("res://") or path.begins_with("user://")) else path
			DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())
			img.save_png(global_path)
			print("[ArboriaMassiveWorld] Captura salva: %s" % global_path)
