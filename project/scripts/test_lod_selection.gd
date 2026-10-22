extends Node3D

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice
var camera: Camera3D
var subview: SubViewport
var vg_data: Dictionary

var current_case = 0
var lod_results = []
var output_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/lod"

var cases = [
	{"name": "01_proxima", "dist": 7.0, "fov": 60.0, "yaw": 0.0, "pitch": 0.0, "max_err": 1.5, "desc": "Câmera próxima (alta resolução espacial)"},
	{"name": "02_intermediaria", "dist": 18.0, "fov": 60.0, "yaw": 30.0, "pitch": 10.0, "max_err": 1.5, "desc": "Distância intermediária (simplificação mista)"},
	{"name": "03_distante", "dist": 40.0, "fov": 60.0, "yaw": 60.0, "pitch": 15.0, "max_err": 1.5, "desc": "Câmera distante (níveis simplificados de LOD)"},
	{"name": "04_muito_distante", "dist": 80.0, "fov": 60.0, "yaw": 0.0, "pitch": 0.0, "max_err": 1.5, "desc": "Câmera muito distante (LODs mais grosseiros)"},
	{"name": "05_fov_30", "dist": 25.0, "fov": 30.0, "yaw": 15.0, "pitch": 5.0, "max_err": 1.5, "desc": "FOV 30° Telefoto (menor FOV amplia objeto)"},
	{"name": "06_fov_90", "dist": 15.0, "fov": 90.0, "yaw": -30.0, "pitch": 10.0, "max_err": 1.5, "desc": "FOV 90° Grande Angular (reduz objeto na tela)"},
	{"name": "07_orientacao", "dist": 15.0, "fov": 60.0, "yaw": 120.0, "pitch": 40.0, "max_err": 1.5, "desc": "Mudança de orientação e ângulo oblíquo"},
	{"name": "08_dag_transicao_fina", "dist": 15.0, "fov": 60.0, "yaw": 0.0, "pitch": 0.0, "max_err": 0.5, "desc": "Tolerância rigorosa (0.5 px - exige maior detalhe)"},
	{"name": "09_dag_transicao_grossa", "dist": 15.0, "fov": 60.0, "yaw": 0.0, "pitch": 0.0, "max_err": 6.0, "desc": "Tolerância permissiva (6.0 px - acelera simplificação)"}
]

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — VALIDAÇÃO V4: COMPROVAÇÃO DE SELEÇÃO DE LOD ")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)

	subview = SubViewport.new()
	subview.size = Vector2i(1280, 720)
	subview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subview.own_world_3d = true
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 1)
	var we = WorldEnvironment.new()
	we.environment = env
	subview.add_child(we)

	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 300.0
	camera.current = true
	subview.add_child(camera)
	add_child(subview)

	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame() -> void:
	if current_case >= cases.size():
		finish_lod_tests()
		return

	var c = cases[current_case]
	
	camera.fov = c["fov"]
	var yaw = deg_to_rad(c["yaw"])
	var pitch = deg_to_rad(c["pitch"])
	var dist = c["dist"]
	var pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
	camera.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)

	# Executa seleção automática via DAG (lod_mode = 0)
	# shading_mode = 3 (Cluster Debug Colors para visualizar distribuição de clusters e LODs)
	pipeline.render_to_viewport(subview, camera, Transform3D.IDENTITY, c["max_err"], 0, 0, true, false, true, 3)

	# Lê dados dos contadores GPU diretamente do counter_buf
	var raw_cnt = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
	var inst_cnt = raw_cnt.decode_u32(4)
	var tris_cnt = raw_cnt.decode_u32(16)
	var eval_cnt = raw_cnt.decode_u32(20)

	# Lê os IDs dos clusters visíveis selecionados na GPU via out_visible_buf
	var visible_ids: Array[int] = []
	if inst_cnt > 0:
		var raw_vis = rd.buffer_get_data(pipeline.out_visible_buf, 0, inst_cnt * 4)
		for i in range(inst_cnt):
			visible_ids.append(raw_vis.decode_u32(i * 4))

	# Analisa a distribuição de níveis de LOD utilizados
	var lod_distribution = {}
	var clusters_meta = vg_data["clusters"]
	for cid in visible_ids:
		if cid < clusters_meta.size():
			var lvl = clusters_meta[cid]["lod_level"]
			lod_distribution[lvl] = lod_distribution.get(lvl, 0) + 1

	var img = subview.get_texture().get_image()
	var img_path = "%s/%s_render.png" % [output_dir, c["name"]]
	img.save_png(img_path)

	# Deteccao de buracos/rachaduras internas na imagem
	var non_black = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var px = img.get_pixel(x, y)
			if px.r > 0.02 or px.g > 0.02 or px.b > 0.02:
				non_black += 1

	var res = {
		"name": c["name"],
		"desc": c["desc"],
		"dist": c["dist"],
		"fov": c["fov"],
		"max_err": c["max_err"],
		"visible_clusters": inst_cnt,
		"visible_triangles": tris_cnt,
		"evaluated_clusters": eval_cnt,
		"lod_distribution": lod_distribution,
		"active_pixels": non_black,
		"img_path": img_path
	}
	lod_results.append(res)

	print("\n[%s] %s" % [c["name"].to_upper(), c["desc"]])
	print("  Dist: %.1fm | FOV: %.1f° | Erro Máx: %.1f px" % [c["dist"], c["fov"], c["max_err"]])
	print("  Clusters Selecionados: %d | Triângulos: %d | Avaliados: %d" % [inst_cnt, tris_cnt, eval_cnt])
	print("  Distribuição de LODs: %s" % str(lod_distribution))
	print("  Pixels Renderizados na Tela: %d | Imagem: %s" % [non_black, img_path])

	current_case += 1

func finish_lod_tests() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	print("\n=================================================================")
	print("   CONSOLIDAÇÃO DA SELEÇÃO HIERÁRQUICA DE LOD (DAG)             ")
	print("=================================================================")
	for r in lod_results:
		print("  - %-22s: %3d clusters | %5d tris | LODs: %s" % [
			r["name"], r["visible_clusters"], r["visible_triangles"], str(r["lod_distribution"])
		])
	print("\nEvidências salvas em: %s" % output_dir)
	print("=================================================================\n")
	get_tree().quit(0)
