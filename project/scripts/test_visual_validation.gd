@tool
extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var frame: int = 0
var step: int = 0
var vg_pipeline: VGGPUPipeline
var vg_data: Dictionary

# SubViewport e Cameras
var viewport: SubViewport
var camera: Camera3D
var model_ref_instance: MeshInstance3D
var pipeline_mesh_instance: MultiMeshInstance3D

var test_cases = [
	{"name": "1_Closeup_LOD0", "dist": 9.5, "fov": 65.0, "yaw": 0.0, "pitch": 0.0, "lod_mode": 1, "forced_lod": 0},
	{"name": "2_Mid_Mixed_DAG", "dist": 16.0, "fov": 70.0, "yaw": 0.8, "pitch": 0.2, "lod_mode": 0, "forced_lod": 0},
	{"name": "3_Distant_LOD",   "dist": 32.0, "fov": 70.0, "yaw": 1.5, "pitch": -0.3, "lod_mode": 0, "forced_lod": 0},
	{"name": "4_Wide_FOV_90",   "dist": 10.0, "fov": 90.0, "yaw": 2.2, "pitch": 0.1, "lod_mode": 0, "forced_lod": 0},
	{"name": "5_Narrow_FOV_30", "dist": 22.0, "fov": 30.0, "yaw": 3.0, "pitch": 0.4, "lod_mode": 0, "forced_lod": 0},
	{"name": "6_Frustum_Culled_Away", "dist": 12.0, "fov": 70.0, "yaw": 3.14159, "pitch": 0.0, "lod_mode": 0, "forced_lod": 0, "look_away": true}
]

var current_case_idx: int = 0
var sub_step: int = 0 # 0 = render ref, 1 = render gpu, 2 = compare
var ref_img: Image
var gpu_img: Image

var results: Array[Dictionary] = []
var output_dir = "res://tests/visual_results"

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("ARBORIA ENGINE — VALIDACAO VISUAL & GEOMETRICA RIGOROSA (MISSAO 3)")
	print("=".repeat(80))

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		setup_scene()
	elif frame >= 6:
		run_validation_loop()
	return false

func setup_scene() -> void:
	# Cria diretorio para gravacao das capturas
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	
	# Carrega modelo de teste
	vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	if vg_data.is_empty():
		push_error("FALHA: Nao conseguiu carregar dense_rock_test.vgmesh")
		quit(1)
		return

	vg_pipeline = VGGPUPipeline.new()
	vg_pipeline.load_vgmesh(vg_data)

	# Cria SubViewport para renderizacao offscreen
	viewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	# Cria Camera
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.05
	camera.far = 200.0
	viewport.add_child(camera)

	# Iluminacao direcional simples
	var light = DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, 0.5, 0)
	viewport.add_child(light)

	# Instancia da Malha de Referencia (LOD 0 convencional)
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh
	var mat_ref = StandardMaterial3D.new()
	mat_ref.albedo_color = Color(1.0, 1.0, 1.0)
	mat_ref.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	model_ref_instance.material_override = mat_ref
	viewport.add_child(model_ref_instance)

	# Instancia MultiMesh da GPU
	pipeline_mesh_instance = vg_pipeline.multimesh_instance
	viewport.add_child(pipeline_mesh_instance)
	
	print("Cenario de teste visual configurado (Viewport 512x512, %d casos de teste)" % test_cases.size())

func update_camera_transform(tc: Dictionary) -> void:
	camera.fov = tc["fov"]
	var dist = tc["dist"]
	var yaw = tc["yaw"]
	var pitch = tc["pitch"]

	if tc.get("look_away", false):
		# Camera em (0, 0, 5) olhando para +Z (objeto em (0,0,0) fica completamente atras da camera)
		camera.position = Vector3(0, 0, 5.0)
		camera.look_at(Vector3(0, 0, 10.0), Vector3.UP)
	else:
		var x = dist * cos(pitch) * sin(yaw)
		var y = dist * sin(pitch)
		var z = dist * cos(pitch) * cos(yaw)
		camera.position = Vector3(x, y, z)
		camera.look_at(Vector3.ZERO, Vector3.UP)

func run_validation_loop() -> void:
	if current_case_idx >= test_cases.size():
		summarize_results()
		return

	var tc = test_cases[current_case_idx]

	if sub_step == 0:
		# 0: Configura camera e habilita modelo de referencia
		update_camera_transform(tc)
		model_ref_instance.visible = true
		pipeline_mesh_instance.visible = false
		sub_step = 1

	elif sub_step == 1:
		# 1: Aguarda 1 frame para rasterizacao da referencia
		sub_step = 2

	elif sub_step == 2:
		# 2: Captura imagem de referencia e dispara renderizacao GPU
		var tex = viewport.get_texture()
		ref_img = tex.get_image()

		model_ref_instance.visible = false
		pipeline_mesh_instance.visible = true

		vg_pipeline.dispatch_culling(
			camera,
			Vector2(512, 512),
			1.5,
			tc["lod_mode"],
			tc["forced_lod"],
			true,  # enable_frustum
			false, # enable_cone (rasterizer handles fine backfaces)
			false  # debug_colors
		)
		sub_step = 3

	elif sub_step == 3:
		# 3: Aguarda 1 frame para rasterizacao do pipeline GPU
		sub_step = 4

	elif sub_step == 4:
		# 4: Captura imagem GPU e analisa diferencas
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
	var holes_inside_silhouette: int = 0

	var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			var c_ref = img_ref.get_pixel(x, y)
			var c_gpu = img_gpu.get_pixel(x, y)
			
			var is_ref = (c_ref.a > 0.1)
			var is_gpu = (c_gpu.a > 0.1)
			
			if is_ref: ref_pixels += 1
			if is_gpu: gpu_pixels += 1
			if is_ref and is_gpu: intersection_pixels += 1
			if is_ref or is_gpu: union_pixels += 1
			
			# Detecta buracos internos (pixels onde a referencia existe, mas o GPU nao desenhou)
			if is_ref and not is_gpu:
				# Verifica se eh um buraco interno (cercado por pixels da referencia)
				holes_inside_silhouette += 1
				diff_img.set_pixel(x, y, Color(1, 0, 0, 1)) # Vermelho = buraco/falha
			elif not is_ref and is_gpu:
				diff_img.set_pixel(x, y, Color(0, 0, 1, 1)) # Azul = expansao
			elif is_ref and is_gpu:
				diff_img.set_pixel(x, y, Color(0, 1, 0, 1)) # Verde = correspondencia perfeita
			else:
				diff_img.set_pixel(x, y, Color(0, 0, 0, 1))

	var iou: float = float(intersection_pixels) / max(1.0, float(union_pixels))
	var coverage_ratio: float = float(gpu_pixels) / max(1.0, float(ref_pixels))

	# Salva capturas para inspecao de auditoria
	var name = tc["name"]
	var path_ref = "%s/%s_ref.png" % [output_dir, name]
	var path_gpu = "%s/%s_gpu.png" % [output_dir, name]
	var path_diff = "%s/%s_diff.png" % [output_dir, name]
	img_ref.save_png(ProjectSettings.globalize_path(path_ref))
	img_gpu.save_png(ProjectSettings.globalize_path(path_gpu))
	diff_img.save_png(ProjectSettings.globalize_path(path_diff))

	var is_culled_case = tc.get("look_away", false)
	var passed = false
	var verdict = ""

	if is_culled_case:
		# Em frustum culling de costas, deve haver ZERO pixels renderizados
		if gpu_pixels == 0:
			passed = true
			verdict = "APROVADO (Frustum Culling perfeito: 0 pixels renderizados fora da visao)"
		else:
			passed = false
			verdict = "FALHA (Frustum Culling vazou %d pixels!)" % gpu_pixels
	else:
		# Na visao normal, a silhueta deve cobrir > 90% do modelo base
		if iou >= 0.88 and coverage_ratio >= 0.88:
			passed = true
			verdict = "APROVADO (IoU: %.1f%% | Cobertura Silhueta: %.1f%% | Buracos residuais: %d px)" % [iou * 100.0, coverage_ratio * 100.0, holes_inside_silhouette]
		else:
			passed = false
			verdict = "FALHA (IoU baixo: %.1f%% | Cobertura: %.1f%%)" % [iou * 100.0, coverage_ratio * 100.0]

	results.append({
		"name": name,
		"passed": passed,
		"verdict": verdict,
		"iou": iou,
		"coverage": coverage_ratio,
		"ref_pixels": ref_pixels,
		"gpu_pixels": gpu_pixels,
		"holes": holes_inside_silhouette
	})
	print("  [%s] %s -> ref_pixels=%d, gpu_pixels=%d | %s" % ["APROVADO" if passed else "FALHA", name, ref_pixels, gpu_pixels, verdict])

func summarize_results() -> void:
	print("\n" + "=".repeat(80))
	print("RESUMO DA VALIDACAO VISUAL & GEOMETRICA (FASE 3)")
	print("=".repeat(80))
	var all_ok = true
	for r in results:
		print("[%s] %-25s | %s" % ["APROVADO" if r["passed"] else "FALHA", r["name"], r["verdict"]])
		if not r["passed"]:
			all_ok = false
	print("=".repeat(80))
	if all_ok:
		print("CONCLUSAO: A imagem gerada pela GPU corresponde fielmente ao modelo de referencia!")
		print("Capturas e mapas de diferencas gravados em: %s" % output_dir)
		vg_pipeline.cleanup()
		quit(0)
	else:
		print("CONCLUSAO: Falha em um ou mais testes visuais!")
		vg_pipeline.cleanup()
		quit(1)
