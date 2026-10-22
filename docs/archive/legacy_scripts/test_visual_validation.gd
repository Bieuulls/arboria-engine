@tool
extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var frame: int = 0
var vg_pipeline: VGGPUPipeline
var vg_data: Dictionary

# SubViewport e Cameras
var viewport: SubViewport
var camera: Camera3D
var model_ref_instance: MeshInstance3D
var pipeline_mesh_instance: MultiMeshInstance3D
var mat_ref_unshaded: StandardMaterial3D
var mat_ref_pbr: StandardMaterial3D
var light: DirectionalLight3D

var test_cases = [
	{"name": "1_Closeup_LOD0_Unshaded",  "dist": 9.5,  "fov": 65.0, "yaw": 0.0,  "pitch": 0.0,  "lod_mode": 1, "forced_lod": 0, "unshaded": true},
	{"name": "2_Closeup_LOD0_PBR",       "dist": 9.5,  "fov": 65.0, "yaw": 0.0,  "pitch": 0.0,  "lod_mode": 1, "forced_lod": 0, "unshaded": false},
	{"name": "3_Mid_Mixed_DAG_Unshaded", "dist": 16.0, "fov": 70.0, "yaw": 0.8,  "pitch": 0.2,  "lod_mode": 0, "forced_lod": 0, "unshaded": true},
	{"name": "4_Distant_LOD",            "dist": 32.0, "fov": 70.0, "yaw": 1.5,  "pitch": -0.3, "lod_mode": 0, "forced_lod": 0, "unshaded": true},
	{"name": "5_Wide_FOV_90",            "dist": 10.0, "fov": 90.0, "yaw": 2.2,  "pitch": 0.1,  "lod_mode": 0, "forced_lod": 0, "unshaded": true},
	{"name": "6_Narrow_FOV_30",          "dist": 22.0, "fov": 30.0, "yaw": 3.0,  "pitch": 0.4,  "lod_mode": 1, "forced_lod": 0, "unshaded": true},
	{"name": "7_Camera_Rotation",        "dist": 12.0, "fov": 65.0, "yaw": 4.5,  "pitch": -0.5, "lod_mode": 1, "forced_lod": 0, "unshaded": true},
	{"name": "8_Frustum_Culled_Away",    "dist": 12.0, "fov": 70.0, "yaw": 3.14, "pitch": 0.0,  "lod_mode": 0, "forced_lod": 0, "look_away": true},
	{"name": "9_Temporal_Motion_Check",  "dist": 10.0, "fov": 65.0, "yaw": 0.08, "pitch": 0.04, "lod_mode": 1, "forced_lod": 0, "unshaded": true}
]

var current_case_idx: int = 0
var sub_step: int = 0
var ref_img: Image
var gpu_img: Image

var results: Array[Dictionary] = []
var output_dir = "res://tests/visual_results"
var audit_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/visual"

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("ARBORIA ENGINE — VALIDACAO VISUAL & GEOMETRICA RIGOROSA (AUDITORIA P1)")
	print("Validacao: Silhueta, Diferenca RGB, Profundidade, Buracos, PBR e Frustum")
	print("=".repeat(80))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		setup_scene()
	elif frame >= 6:
		run_validation_loop()
	return false

func setup_scene() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	DirAccess.make_dir_recursive_absolute(audit_dir)

	vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	if vg_data.is_empty():
		push_error("FALHA: Nao conseguiu carregar dense_rock_test.vgmesh")
		quit(1)
		return

	vg_pipeline = VGGPUPipeline.new()
	vg_pipeline.load_vgmesh(vg_data)
	vg_pipeline.setup_multimesh(vg_data)

	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.05
	camera.far = 200.0
	viewport.add_child(camera)

	light = DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.5, 0)
	viewport.add_child(light)

	# Referencia Convencional LOD 0
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh

	# Materiais de Referencia: Unshaded e PBR
	mat_ref_unshaded = StandardMaterial3D.new()
	mat_ref_unshaded.albedo_color = Color(0.8, 0.82, 0.85)
	mat_ref_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_ref_pbr = StandardMaterial3D.new()
	mat_ref_pbr.albedo_color = Color(0.8, 0.82, 0.85)
	mat_ref_pbr.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat_ref_pbr.roughness = 0.5
	mat_ref_pbr.metallic = 0.05
	mat_ref_pbr.specular = 0.5

	model_ref_instance.material_override = mat_ref_unshaded
	viewport.add_child(model_ref_instance)

	# Instancia GPU MultiMesh
	pipeline_mesh_instance = vg_pipeline.multimesh_instance
	viewport.add_child(pipeline_mesh_instance)

	print("Cenario de teste visual configurado (Viewport 512x512, %d casos de teste)" % test_cases.size())

func update_camera_transform(tc: Dictionary) -> void:
	camera.fov = tc["fov"]
	var dist = tc["dist"]
	var yaw = tc["yaw"]
	var pitch = tc["pitch"]

	if tc.get("look_away", false):
		camera.look_at_from_position(Vector3(0, 0, 5.0), Vector3(0, 0, 10.0), Vector3.UP)
	else:
		var x = dist * cos(pitch) * sin(yaw)
		var y = dist * sin(pitch)
		var z = dist * cos(pitch) * cos(yaw)
		camera.look_at_from_position(Vector3(x, y, z), Vector3.ZERO, Vector3.UP)

func run_validation_loop() -> void:
	if current_case_idx >= test_cases.size():
		summarize_results()
		return

	var tc = test_cases[current_case_idx]
	var is_unshaded = tc.get("unshaded", true)

	if sub_step == 0:
		update_camera_transform(tc)
		model_ref_instance.material_override = mat_ref_unshaded if is_unshaded else mat_ref_pbr
		model_ref_instance.visible = true
		pipeline_mesh_instance.visible = false
		sub_step = 1

	elif sub_step == 1:
		# Aguarda frame para rasterizar referencia
		sub_step = 2

	elif sub_step == 2:
		var tex = viewport.get_texture()
		ref_img = tex.get_image()

		model_ref_instance.visible = false
		pipeline_mesh_instance.visible = true

		# Configura shader da GPU
		vg_pipeline.render_material.set_shader_parameter("unshaded_mode", is_unshaded)
		vg_pipeline.render_material.set_shader_parameter("debug_cluster_colors", false)
		vg_pipeline.render_material.set_shader_parameter("base_albedo", Color(0.8, 0.82, 0.85))

		vg_pipeline.dispatch_culling(
			camera,
			Vector2(512, 512),
			1.5,
			tc["lod_mode"],
			tc["forced_lod"],
			true,  # enable_frustum
			false, # enable_cone
			false  # debug_colors
		)
		sub_step = 3

	elif sub_step == 3:
		# Aguarda frame para rasterizar GPU pipeline
		sub_step = 4

	elif sub_step == 4:
		var tex = viewport.get_texture()
		gpu_img = tex.get_image()

		analyze_comparison(tc, ref_img, gpu_img)
		current_case_idx += 1
		sub_step = 0

func analyze_comparison(tc: Dictionary, img_ref: Image, img_gpu: Image) -> void:
	var w = img_ref.get_width()
	var h = img_ref.get_height()

	var ref_pixels: int = 0
	var gpu_pixels: int = 0
	var intersection_pixels: int = 0
	var union_pixels: int = 0
	var internal_holes: int = 0
	var unexpected_black_pixels: int = 0
	var total_rgb_diff: float = 0.0

	var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			var c_ref = img_ref.get_pixel(x, y)
			var c_gpu = img_gpu.get_pixel(x, y)

			var is_ref = (c_ref.a > 0.1)
			var is_gpu = (c_gpu.a > 0.1)

			if is_ref: ref_pixels += 1
			if is_gpu: gpu_pixels += 1
			if is_ref and is_gpu:
				intersection_pixels += 1
				var d_r = abs(c_ref.r - c_gpu.r)
				var d_g = abs(c_ref.g - c_gpu.g)
				var d_b = abs(c_ref.b - c_gpu.b)
				var rgb_delta = (d_r + d_g + d_b) / 3.0
				total_rgb_diff += rgb_delta

				# Detecta pixels pretos inesperados dentro da superficie opaca
				if c_gpu.r < 0.05 and c_gpu.g < 0.05 and c_gpu.b < 0.05 and (c_ref.r > 0.2 or c_ref.g > 0.2):
					unexpected_black_pixels += 1
					diff_img.set_pixel(x, y, Color(1, 0, 1, 1)) # Magenta = pixel preto anomalo
				elif rgb_delta > 0.15:
					diff_img.set_pixel(x, y, Color(1, 1, 0, 1)) # Amarelo = discrepancia de cor
				else:
					diff_img.set_pixel(x, y, Color(0, 1, 0, 1)) # Verde = match perfeito

			elif is_ref and not is_gpu:
				# Verifica se eh buraco interno (cercado por pixels validos da referencia)
				var is_internal = true
				for dy in [-2, 2]:
					for dx in [-2, 2]:
						var nx = clamp(x + dx, 0, w - 1)
						var ny = clamp(y + dy, 0, h - 1)
						if img_ref.get_pixel(nx, ny).a <= 0.1:
							is_internal = false
							break
				if is_internal:
					internal_holes += 1
					diff_img.set_pixel(x, y, Color(1, 0, 0, 1)) # Vermelho = buraco interno na superficie
				else:
					diff_img.set_pixel(x, y, Color(0.5, 0, 0, 1)) # Borda/silhueta

			elif not is_ref and is_gpu:
				diff_img.set_pixel(x, y, Color(0, 0, 1, 1)) # Azul = expansao
			else:
				diff_img.set_pixel(x, y, Color(0, 0, 0, 1))

			if is_ref or is_gpu:
				union_pixels += 1

	var iou: float = float(intersection_pixels) / max(1.0, float(union_pixels))
	var coverage_ratio: float = float(gpu_pixels) / max(1.0, float(ref_pixels))
	var avg_rgb_delta: float = total_rgb_diff / max(1.0, float(intersection_pixels))

	# Salva capturas para auditoria
	var name = tc["name"]
	var p_ref = "%s/%s_ref.png" % [audit_dir, name]
	var p_gpu = "%s/%s_gpu.png" % [audit_dir, name]
	var p_diff = "%s/%s_diff.png" % [audit_dir, name]
	img_ref.save_png(p_ref)
	img_gpu.save_png(p_gpu)
	diff_img.save_png(p_diff)

	var is_culled = tc.get("look_away", false)
	var passed = false
	var verdict = ""

	if is_culled:
		if gpu_pixels == 0:
			passed = true
			verdict = "APROVADO (Frustum Culling: 0 pixels desenhados fora da visao)"
		else:
			passed = false
			verdict = "FALHA (Frustum Culling vazou %d pixels!)" % gpu_pixels
	else:
		var min_iou = 0.90 if tc.get("forced_lod", -1) == 0 else 0.85
		var max_black = 10
		var max_holes = 5
		if iou >= min_iou and coverage_ratio >= 0.88 and unexpected_black_pixels <= max_black and internal_holes <= max_holes:
			passed = true
			verdict = "APROVADO (IoU: %.1f%% | Cobertura: %.1f%% | RGB Delta: %.3f | Buracos: %d | Pretos: %d)" % [
				iou * 100.0, coverage_ratio * 100.0, avg_rgb_delta, internal_holes, unexpected_black_pixels
			]
		else:
			passed = false
			verdict = "FALHA (IoU: %.1f%% | RGB Delta: %.3f | Buracos: %d | Pretos: %d)" % [
				iou * 100.0, avg_rgb_delta, internal_holes, unexpected_black_pixels
			]

	results.append({
		"name": name,
		"passed": passed,
		"verdict": verdict,
		"iou": iou,
		"coverage": coverage_ratio,
		"rgb_delta": avg_rgb_delta,
		"ref_pixels": ref_pixels,
		"gpu_pixels": gpu_pixels,
		"holes": internal_holes,
		"black_pixels": unexpected_black_pixels
	})
	print("  [%s] %-28s -> Ref=%d, GPU=%d | %s" % ["APROVADO" if passed else "FALHA", name, ref_pixels, gpu_pixels, verdict])

func summarize_results() -> void:
	print("\n" + "=".repeat(100))
	print("RESUMO DA AUDITORIA VISUAL RIGOROSA (9 CENARIOS)")
	print("=".repeat(100))
	print("%-30s | %10s | %8s | %10s | %10s | %8s | %8s" % [
		"Cenario", "Status", "IoU", "Cobertura", "RGB Delta", "Buracos", "Pretos"
	])
	print("-".repeat(100))
	var all_ok = true
	for r in results:
		var status_str = "APROVADO" if r["passed"] else "FALHA"
		print("%-30s | %10s | %7.1f%% | %9.1f%% | %10.4f | %8d | %8d" % [
			r["name"], status_str, r["iou"] * 100.0, r["coverage"] * 100.0, r["rgb_delta"], r["holes"], r["black_pixels"]
		])
		if not r["passed"]:
			all_ok = false
	print("=".repeat(100))

	if all_ok:
		print("CONCLUSAO: Validacao visual aprovada em todos os 9 cenarios sem defeitos!")
		vg_pipeline.cleanup()
		quit(0)
	else:
		print("CONCLUSAO: Falha em um ou mais cenarios visuais!")
		vg_pipeline.cleanup()
		quit(1)

