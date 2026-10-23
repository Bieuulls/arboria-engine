class_name ArboriaMassiveWorldDemo
extends Node3D

## ARBORIA ENGINE — MASSIVE VIRTUAL GEOMETRY WORLD DEMO
## Demonstração de estresse com dezenas de instâncias de malhas virtuais Nanite DAG,
## materiais PBR Cook-Torrance GGX com micro-relevo mineral e culling GPU em tempo real.

const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")
const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")

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
var is_interactive: bool = false
var is_stress_benchmark: bool = false
var bench_target_frames: int = 45
var recorded_frame_times: Array[float] = []
var recorded_cpu_times: Array[float] = []
var capture_output_path: String = "res://diag_arboria_massive_world.png"

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
	for arg in OS.get_cmdline_args():
		if arg == "--interactive":
			is_interactive = true
		elif arg.begins_with("--instances="):
			total_instances_count = int(arg.split("=")[1])
		elif arg.begins_with("--bench-frames="):
			bench_target_frames = int(arg.split("=")[1])
			is_stress_benchmark = true
		elif arg.begins_with("--capture-path="):
			capture_output_path = arg.split("=")[1]
	pipeline = ArboriaNativePipeline.get_or_create_shared()

	# Registra CompositorEffect no WorldEnvironment
	_setup_compositor()

	# Gera o vale rochoso procedural com 80 instâncias
	_spawn_rock_valley()

	# Configura interface gráfica
	_setup_ui()

	if camera_rig:
		camera_rig.target_offset = Vector3(0, 3.0, 0)
		camera_rig.pitch = -0.14
		camera_rig.yaw = 0.45
		camera_rig.target_distance = 38.0
		camera_rig.update_camera_transform()

func _setup_compositor() -> void:
	if not world_env.compositor:
		world_env.compositor = Compositor.new()

	var comp = world_env.compositor
	var eff_cls = load("res://scripts/arboria_compositor_effect.gd")
	if eff_cls:
		var eff = eff_cls.new()
		eff.active = true
		var effects = comp.compositor_effects.duplicate()
		effects.append(eff)
		comp.compositor_effects = effects

	if camera:
		camera.compositor = comp
	print("[ArboriaMassiveWorld] ArboriaCompositorEffect registrado (Total: ", comp.compositor_effects.size(), ").")

func _spawn_rock_valley() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261022

	# Limpa instâncias anteriores se houver
	for c in rocks_container.get_children():
		c.queue_free()
	active_rocks.clear()

	# Lista de malhas virtuais disponíveis
	var available_meshes = [
		"res://assets/dense_rock_test.vgmesh",
		"res://assets/boulder_granite.vgmesh",
		"res://assets/pine_trunk_complex.vgmesh"
	]

	# Gera formação mista de floresta e cânion com 80 instâncias
	for i in range(total_instances_count):
		var rock = ArboriaInstance3D.new()
		var mesh_choice = available_meshes[i % available_meshes.size()]
		rock.name = "Entity_%03d" % i
		rock.mesh_path = mesh_choice
		rock.max_screen_error = 1.5
		rock.lod_mode = 0 # Auto DAG Nanite

		# Seleciona paleta e propriedades de material de acordo com o tipo
		var col = rock_palettes[i % rock_palettes.size()]
		var col_var = rng.randf_range(0.9, 1.1)

		if mesh_choice.contains("pine_trunk"):
			# Casca de pinheiro (marrom escuro/terra)
			col = Color(0.38, 0.28, 0.22)
			rock.roughness = rng.randf_range(0.85, 0.95)
			rock.metallic = 0.01
		elif mesh_choice.contains("boulder"):
			# Granito liso arredondado
			col = Color(0.65, 0.68, 0.72)
			rock.roughness = rng.randf_range(0.40, 0.65)
			rock.metallic = 0.04
		else:
			# Rocha escarpada
			rock.roughness = rng.randf_range(0.60, 0.85)
			rock.metallic = rng.randf_range(0.02, 0.06)

		# Posicionamento orgânico no terreno proporcional ao número de instâncias
		var side_count = int(ceil(sqrt(float(total_instances_count))))
		side_count = max(side_count, 1)
		var col_idx = i % side_count
		var row_idx = i / side_count
		var spacing = 4.8
		var grid_x = (float(col_idx) - side_count * 0.5) * spacing + rng.randf_range(-1.2, 1.2)
		var grid_z = (float(row_idx) - side_count * 0.5) * spacing + rng.randf_range(-1.2, 1.2)

		var dist_from_center = Vector2(grid_x, grid_z).length()
		var y = pow(dist_from_center / max(side_count * 2.8, 10.0), 1.5) * 4.5 + rng.randf_range(-0.3, 0.5)

		# Escala variada para compor rochedos gigantes e pedregulhos menores
		var scale_factor = 1.0
		if i < 10:
			scale_factor = rng.randf_range(2.6, 3.8) # Rochas monumentais
			y -= 0.3
		elif i < 35:
			scale_factor = rng.randf_range(1.5, 2.3) # Rochas médias
		else:
			scale_factor = rng.randf_range(0.8, 1.4) # Pedras menores

		rock.position = Vector3(grid_x, y, grid_z)
		rock.rotation = Vector3(
			rng.randf_range(-0.25, 0.25),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.25, 0.25)
		)
		rock.scale = Vector3.ONE * scale_factor

		rocks_container.add_child(rock)
		active_rocks.append(rock)

	print("[ArboriaMassiveWorld] Geradas com sucesso %d instancias virtuais." % active_rocks.size())

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
		error_slider.min_value = 0.2
		error_slider.max_value = 6.0
		error_slider.step = 0.1
		error_slider.value = 1.5
		error_slider.value_changed.connect(_on_error_slider_changed)
		_on_error_slider_changed(1.5)

func _on_shading_mode_changed(idx: int) -> void:
	if pipeline:
		pipeline.global_shading_mode = idx
		pipeline.request_telemetry_read()

func _on_error_slider_changed(val: float) -> void:
	if error_value_label:
		error_value_label.text = "%.1f px" % val
	for r in active_rocks:
		r.max_screen_error = val

func _process(delta: float) -> void:
	# Atualiza telemetria da HUD
	var fps = Engine.get_frames_per_second()
	if fps_label:
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
			if current_frame == 20:
				if pipeline: pipeline.request_telemetry_read()
			elif current_frame == 45:
				if pipeline:
					pipeline.request_telemetry_read()
					var stats = pipeline.get_statistics()
					print("\n=================================================================")
					print(" [RESULTADOS RAPIDOS: %d INSTÂNCIAS]" % active_rocks.size())
					print("  - Instâncias Ativas: %d" % active_rocks.size())
					print("  - Clusters Visíveis: %d" % stats.get("clusters_visible", 0))
					print("  - Triângulos Desenhados: %d" % stats.get("triangles_drawn", 0))
					print("  - Custo CPU Submissão: %.3f ms" % stats.get("cpu_submission_ms", 0.0))
					print("=================================================================")
					_capture_viewport(capture_output_path)
					pipeline.cleanup()
					get_tree().quit(0)

func _capture_viewport(path: String) -> void:
	var vp = get_viewport()
	if vp:
		var img = vp.get_texture().get_image()
		if img and not img.is_empty():
			img.save_png(path)
			print("[ArboriaMassiveWorld] Captura salva: %s" % path)
