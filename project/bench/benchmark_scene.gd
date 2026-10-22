extends Node3D

## ARBORIA ENGINE — OFFICIAL BENCHMARK RUNNER
## Medição padronizada, determinística e rigorosa de desempenho de geometria.

const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")
const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var camera: Camera3D = $Camera3D
@onready var container: Node3D = $Container

var scenario_id: String = "dense_rock"
var variant_id: String = "mesh_instance"
var instance_count: int = 1
var mesh_path_vg: String = "res://assets/dense_rock_test.vgmesh"
var mesh_path_obj: String = "res://assets/dense_rock_test.obj"
var capture_path: String = ""
var output_json_path: String = ""
var raw_csv_path: String = ""

var warmup_frames: int = 300
var measured_frames: int = 1000
var current_frame: int = 0
var capture_frame: int = 290

var orbit_radius: float = 35.0
var orbit_height: float = 14.0
var orbit_speed: float = 0.004

var vp_rid: RID
var sample_records: Array[Dictionary] = []
var vg_data: Dictionary = {}
var base_array_mesh: ArrayMesh = null
var default_material: StandardMaterial3D = null

func _ready() -> void:
	_parse_command_line_args()

	# 1. Configurações rígidas de tela e renderização
	DisplayServer.window_set_vsync_mode(0) # 0 = VSYNC_MODE_DISABLED
	Engine.max_fps = 0
	get_viewport().size = Vector2i(1920, 1080)
	vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	print("================================================================")
	print(" [BENCHMARK RUNNER] INICIANDO EXECUCAO DETERMINISTICA")
	print("   Cenario   : ", scenario_id)
	print("   Variante  : ", variant_id)
	print("   Instancias: ", instance_count)
	print("   Malha VG  : ", mesh_path_vg)
	print("   Resolucao : 1920x1080 (VSync OFF, FPS Ilimitado)")
	print("================================================================")

	# 2. Carrega dados da malha
	vg_data = ArboriaMeshLoader.load_from_file(mesh_path_vg)
	if vg_data.is_empty():
		push_error("[FALHA] Nao foi possivel carregar: " + mesh_path_vg)
		get_tree().quit(2)
		return

	# Material de referência PBR
	default_material = StandardMaterial3D.new()
	default_material.albedo_color = Color(0.75, 0.76, 0.78)
	default_material.roughness = 0.6
	default_material.metallic = 0.05
	default_material.metallic_specular = 0.5

	# Ajusta raio da órbita conforme o tamanho da cena
	if instance_count >= 500:
		orbit_radius = 85.0
		orbit_height = 25.0
	elif instance_count >= 80:
		orbit_radius = 45.0
		orbit_height = 16.0
	else:
		orbit_radius = 25.0
		orbit_height = 10.0

	# 3. Gera transforms determinísticas
	var transforms = _generate_deterministic_transforms(instance_count)

	# 4. Constrói a variante correspondente
	match variant_id:
		"mesh_instance":
			_setup_variant_mesh_instance(transforms)
		"multimesh":
			_setup_variant_multimesh(transforms)
		"arboria":
			_setup_variant_arboria(transforms, false)
		"arboria_lod0":
			_setup_variant_arboria(transforms, true)
		_:
			push_error("[FALHA] Variante desconhecida: " + variant_id)
			get_tree().quit(3)

func _parse_command_line_args() -> void:
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--scenario" and i + 1 < args.size():
			scenario_id = args[i + 1]
		elif arg == "--variant" and i + 1 < args.size():
			variant_id = args[i + 1]
		elif arg == "--instances" and i + 1 < args.size():
			instance_count = int(args[i + 1])
		elif arg == "--mesh-vg" and i + 1 < args.size():
			mesh_path_vg = args[i + 1]
		elif arg == "--mesh-obj" and i + 1 < args.size():
			mesh_path_obj = args[i + 1]
		elif arg == "--capture-path" and i + 1 < args.size():
			capture_path = args[i + 1]
		elif arg == "--output-json" and i + 1 < args.size():
			output_json_path = args[i + 1]
		elif arg == "--raw-csv" and i + 1 < args.size():
			raw_csv_path = args[i + 1]
		elif arg == "--warmup" and i + 1 < args.size():
			warmup_frames = int(args[i + 1])
		elif arg == "--measured" and i + 1 < args.size():
			measured_frames = int(args[i + 1])

func _generate_deterministic_transforms(count: int) -> Array[Transform3D]:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	var transforms: Array[Transform3D] = []
	for i in range(count):
		var t = Transform3D()
		if count == 1:
			t.origin = Vector3(0, 0, 0)
		else:
			var radius = 2.0 + sqrt(float(i)) * 3.8
			var angle = float(i) * 2.39996323 # Golden angle
			var x = radius * cos(angle)
			var z = radius * sin(angle)
			var y = sin(x * 0.08) * cos(z * 0.08) * 1.5
			t.origin = Vector3(x, y, z)
			var rot_y = rng.randf_range(-PI, PI)
			var rot_x = rng.randf_range(-0.1, 0.1)
			var scale_factor = rng.randf_range(0.9, 1.1)
			var basis = Basis(Vector3.UP, rot_y) * Basis(Vector3.RIGHT, rot_x)
			basis = basis.scaled(Vector3.ONE * scale_factor)
			t.basis = basis
		transforms.append(t)
	return transforms

func _setup_variant_mesh_instance(transforms: Array[Transform3D]) -> void:
	print("[Variante A: MeshInstance3D] Construindo malha ArrayMesh LOD 0...")
	base_array_mesh = ArboriaMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	if not base_array_mesh:
		push_error("[FALHA] Falha ao construir ArrayMesh a partir do .vgmesh!")
		get_tree().quit(4)
		return

	for i in range(transforms.size()):
		var mi = MeshInstance3D.new()
		mi.mesh = base_array_mesh
		mi.material_override = default_material
		mi.transform = transforms[i]
		container.add_child(mi)

func _setup_variant_multimesh(transforms: Array[Transform3D]) -> void:
	print("[Variante B: MultiMeshInstance3D] Construindo buffer de instâncias MultiMesh...")
	base_array_mesh = ArboriaMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	if not base_array_mesh:
		push_error("[FALHA] Falha ao construir ArrayMesh a partir do .vgmesh!")
		get_tree().quit(4)
		return

	var mmi = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = base_array_mesh
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	mmi.multimesh = mm
	mmi.material_override = default_material
	container.add_child(mmi)

func _setup_variant_arboria(transforms: Array[Transform3D], force_lod0: bool = false) -> void:
	var mode_name = "ARBORIA (LOD0 Forçado)" if force_lod0 else "ARBORIA (DAG Dinâmico)"
	print("[Variante: %s] Inicializando pipeline nativo de geometria virtualizada..." % mode_name)
	var pipeline = ArboriaNativePipeline.get_or_create_shared()

	# Configura CompositorEffect
	if not world_env.compositor:
		world_env.compositor = Compositor.new()
	var comp = world_env.compositor
	var eff_cls = load("res://scripts/arboria_compositor_effect.gd")
	if eff_cls:
		var eff = eff_cls.new()
		eff.active = true
		comp.compositor_effects = [eff]
	camera.compositor = comp

	for i in range(transforms.size()):
		var vmi = ArboriaInstance3D.new()
		vmi.mesh_path = mesh_path_vg
		if force_lod0:
			vmi.lod_mode = 1 # Forced LOD
			vmi.forced_lod = 0 # LOD 0
		else:
			vmi.lod_mode = 0 # DAG dinâmico
			vmi.max_screen_error = 1.5
		vmi.transform = transforms[i]
		container.add_child(vmi)

func _process(delta: float) -> void:
	current_frame += 1

	# Atualiza trajetória determinística da câmera
	var angle = float(current_frame) * orbit_speed
	var cam_x = orbit_radius * cos(angle)
	var cam_z = orbit_radius * sin(angle)
	camera.look_at_from_position(Vector3(cam_x, orbit_height, cam_z), Vector3(0, 1.5, 0), Vector3.UP)

	# Captura de tela FORA da janela de medição (no frame 290 de warmup)
	if current_frame == capture_frame:
		if capture_path != "":
			var img = get_viewport().get_texture().get_image()
			if img:
				img.save_png(capture_path)
				print("[BENCHMARK] Captura salva fora da janela de medicao em: ", capture_path)

	# Janela de medição rigorosa (frames 301 ate 300 + 1000)
	var start_measure = warmup_frames
	var end_measure = warmup_frames + measured_frames

	if current_frame > start_measure and current_frame <= end_measure:
		var frame_time_ms = delta * 1000.0
		var cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		var gpu_ms_raw = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)

		# Regra: GPU render time medido via Vulkan timestamp queries (latência inerente de 1-2 frames)
		var gpu_ms_val = null
		if gpu_ms_raw > 0.0001:
			gpu_ms_val = gpu_ms_raw

		var draws = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		var objs = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var vram_mb = float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / (1024.0 * 1024.0)

		# Instrumentação do pipeline customizado ARBORIA (não assumir 0 do Godot como zero trabalho de GPU)
		var arb_dispatches: int = 0
		var arb_indirect_draws: int = 0
		var arb_clusters_eval: int = 0
		var arb_clusters_vis: int = 0
		var arb_triangles: int = 0

		if variant_id.begins_with("arboria"):
			var pipe = ArboriaNativePipeline.get_active_instance()
			if pipe and pipe.has_method("get_statistics"):
				var stats = pipe.get_statistics()
				arb_dispatches = stats.get("dispatches", 0)
				arb_indirect_draws = stats.get("indirect_draws", 0)
				arb_clusters_eval = stats.get("clusters_evaluated", 0)
				arb_clusters_vis = stats.get("clusters_visible", 0)
				arb_triangles = stats.get("triangles_drawn", 0)

			# Trabalho real de renderização customizada
			draws += arb_indirect_draws
			if prims == 0:
				prims = arb_triangles

		sample_records.append({
			"frame": current_frame - start_measure,
			"frame_time_ms": frame_time_ms,
			"cpu_render_ms": cpu_ms,
			"gpu_render_ms": gpu_ms_val,
			"draw_calls": draws,
			"primitives": prims,
			"objects": objs,
			"vram_mb": vram_mb,
			"arb_dispatches": arb_dispatches,
			"arb_draws": arb_indirect_draws,
			"arb_clusters_eval": arb_clusters_eval,
			"arb_clusters_vis": arb_clusters_vis,
			"arb_triangles": arb_triangles
		})

	if current_frame >= end_measure:
		_finalize_benchmark()

func _finalize_benchmark() -> void:
	print("[BENCHMARK] Medicao concluida (%d amostras coletadas). Gravando resultados..." % sample_records.size())

	if sample_records.is_empty():
		push_error("[FALHA] Nenhuma amostra coletada!")
		get_tree().quit(5)
		return

	# Calcula estatísticas descritivas
	var frame_times: Array[float] = []
	var cpu_times: Array[float] = []
	var gpu_times: Array[float] = []
	var vrams: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var arb_disp_list: Array[float] = []
	var arb_draw_list: Array[float] = []
	var arb_eval_list: Array[float] = []
	var arb_vis_list: Array[float] = []
	var arb_tri_list: Array[float] = []

	for s in sample_records:
		frame_times.append(s["frame_time_ms"])
		cpu_times.append(s["cpu_render_ms"])
		if s["gpu_render_ms"] != null:
			gpu_times.append(s["gpu_render_ms"])
		vrams.append(s["vram_mb"])
		draws.append(float(s["draw_calls"]))
		prims.append(float(s["primitives"]))
		arb_disp_list.append(float(s["arb_dispatches"]))
		arb_draw_list.append(float(s["arb_draws"]))
		arb_eval_list.append(float(s["arb_clusters_eval"]))
		arb_vis_list.append(float(s["arb_clusters_vis"]))
		arb_tri_list.append(float(s["arb_triangles"]))

	frame_times.sort()
	cpu_times.sort()
	vrams.sort()

	var p50_ft = _percentile(frame_times, 50.0)
	var p95_ft = _percentile(frame_times, 95.0)
	var p99_ft = _percentile(frame_times, 99.0)

	var p50_cpu = _percentile(cpu_times, 50.0)
	var p95_cpu = _percentile(cpu_times, 95.0)
	var p99_cpu = _percentile(cpu_times, 99.0)

	var p50_gpu = null
	var p95_gpu = null
	var p99_gpu = null
	if not gpu_times.is_empty():
		gpu_times.sort()
		p50_gpu = _percentile(gpu_times, 50.0)
		p95_gpu = _percentile(gpu_times, 95.0)
		p99_gpu = _percentile(gpu_times, 99.0)

	var avg_vram = _average(vrams)
	var max_vram = vrams[vrams.size() - 1]
	var avg_draws = _average(draws)
	var avg_prims = _average(prims)
	var avg_dispatches = _average(arb_disp_list)
	var avg_indirect_draws = _average(arb_draw_list)
	var avg_clusters_eval = _average(arb_eval_list)
	var avg_clusters_vis = _average(arb_vis_list)
	var avg_triangles = _average(arb_tri_list)

	var summary = {
		"scenario": scenario_id,
		"variant": variant_id,
		"instances": instance_count,
		"samples": sample_records.size(),
		"frame_time_p50": p50_ft,
		"frame_time_p95": p95_ft,
		"frame_time_p99": p99_ft,
		"cpu_time_p50": p50_cpu,
		"cpu_time_p95": p95_cpu,
		"cpu_time_p99": p99_cpu,
		"gpu_time_p50": p50_gpu,
		"gpu_time_p95": p95_gpu,
		"gpu_time_p99": p99_gpu,
		"vram_avg_mb": avg_vram,
		"vram_max_mb": max_vram,
		"draw_calls_avg": avg_draws,
		"primitives_avg": avg_prims,
		"arb_dispatches_avg": avg_dispatches,
		"arb_indirect_draws_avg": avg_indirect_draws,
		"arb_clusters_eval_avg": avg_clusters_eval,
		"arb_clusters_vis_avg": avg_clusters_vis,
		"arb_triangles_avg": avg_triangles,
		"status": "OK"
	}

	# Grava JSON resumido
	if output_json_path != "":
		var f = FileAccess.open(output_json_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(summary, "\t"))
			f.close()

	# Grava amostras brutas em CSV se especificado
	if raw_csv_path != "":
		var file_exists = FileAccess.file_exists(raw_csv_path)
		var f = FileAccess.open(raw_csv_path, FileAccess.READ_WRITE if file_exists else FileAccess.WRITE)
		if f:
			if file_exists:
				f.seek_end()
			else:
				f.store_line("scenario,variant,instances,frame,frame_time_ms,cpu_render_ms,gpu_render_ms,draw_calls,primitives,vram_mb,arb_dispatches,arb_draws,arb_clusters_eval,arb_clusters_vis,arb_tris")
			for s in sample_records:
				var gpu_str = "N/A" if s["gpu_render_ms"] == null else str(s["gpu_render_ms"])
				f.store_line("%s,%s,%d,%d,%.4f,%.4f,%s,%d,%d,%.2f,%d,%d,%d,%d,%d" % [
					scenario_id, variant_id, instance_count, s["frame"],
					s["frame_time_ms"], s["cpu_render_ms"], gpu_str,
					s["draw_calls"], s["primitives"], s["vram_mb"],
					s["arb_dispatches"], s["arb_draws"], s["arb_clusters_eval"],
					s["arb_clusters_vis"], s["arb_triangles"]
				])
			f.close()

	print("================================================================")
	print(" [BENCHMARK RESULTADO] %s | %s | %d inst" % [scenario_id, variant_id, instance_count])
	print("   Frame Time (p50/p95/p99) : %.2f / %.2f / %.2f ms" % [p50_ft, p95_ft, p99_ft])
	print("   CPU Render (p50/p95/p99) : %.2f / %.2f / %.2f ms" % [p50_cpu, p95_cpu, p99_cpu])
	var gpu_display = "N/A" if p95_gpu == null else ("%.2f / %.2f / %.2f ms" % [p50_gpu, p95_gpu, p99_gpu])
	print("   GPU Render (p50/p95/p99) : ", gpu_display)
	print("   VRAM Media / Max         : %.1f / %.1f MB" % [avg_vram, max_vram])
	print("   Draw Calls / Primitives  : %.0f / %.0f" % [avg_draws, avg_prims])
	if variant_id.begins_with("arboria"):
		print("   ARBORIA Dispatches/Draws : %.0f / %.0f" % [avg_dispatches, avg_indirect_draws])
		print("   ARBORIA Clusters Vis/Tot : %.0f / %.0f" % [avg_clusters_vis, avg_clusters_eval])
		print("   ARBORIA Triangulos Reais : %.0f" % avg_triangles)
	print("================================================================")

	var pipe = ArboriaNativePipeline.get_active_instance()
	if pipe and pipe.has_method("cleanup"):
		pipe.cleanup()

	get_tree().quit(0)

func _percentile(arr: Array[float], p: float) -> float:
	if arr.is_empty():
		return 0.0
	var idx = int(clamp(round((p / 100.0) * float(arr.size() - 1)), 0, arr.size() - 1))
	return arr[idx]

func _average(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var sum = 0.0
	for v in arr:
		sum += v
	return sum / float(arr.size())
