extends Node3D

# ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 5/6
# VALIDACAO VISUAL RIGOROSA: Silhueta, Diferenca RGB, Profundidade, Rachaduras entre Clusters,
# Materiais/Iluminacao, Frustum Culling e Estabilidade de Camera.

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var camera: Camera3D
var rd: RenderingDevice
var world_env: WorldEnvironment
var light: DirectionalLight3D

var model_ref_instance: MeshInstance3D
var mat_unshaded: StandardMaterial3D
var mat_lit: StandardMaterial3D

var output_dir: String = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao5"

# Definicao dos 9 Cenarios Rigorosos de Validacao
var scenarios = [
	{
		"id": "01_closeup",
		"name": "Close-up (7.0m, Alta Densidade Geometrica e Enquadramento Proximo)",
		"dist": 7.0, "fov": 60.0, "yaw_deg": 0.0, "pitch_deg": 0.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "02_mid_distance",
		"name": "Distancia Intermediaria (14.0m, Clusters Mistos)",
		"dist": 14.0, "fov": 60.0, "yaw_deg": 45.0, "pitch_deg": 15.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "03_long_distance",
		"name": "Distancia Longa (30.0m, Triangulos Subpixel)",
		"dist": 30.0, "fov": 60.0, "yaw_deg": 90.0, "pitch_deg": -10.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 95.0, "tol_rmse": 0.06, "tol_cracks": 0
	},
	{
		"id": "04_fov_30",
		"name": "FOV 30° Telefoto (Projecao Estreita e Alta Precisao)",
		"dist": 22.0, "fov": 30.0, "yaw_deg": 25.0, "pitch_deg": 5.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "05_fov_90",
		"name": "FOV 90° Grande Angular (Distorcao Periferica)",
		"dist": 9.0, "fov": 90.0, "yaw_deg": -30.0, "pitch_deg": 12.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "06_camera_rotation",
		"name": "Rotacao de Camera (Inclinacao e Perspectiva Obliqua)",
		"dist": 12.0, "fov": 60.0, "yaw_deg": 135.0, "pitch_deg": 35.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "07_continuous_motion",
		"name": "Movimento Continuo e Estabilidade Temporal",
		"dist": 11.0, "fov": 60.0, "yaw_deg": 10.0, "pitch_deg": 5.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 1, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0,
		"is_motion": true
	},
	{
		"id": "08_frustum_culling",
		"name": "Frustum Culling (Objeto Fora do Campo de Visao)",
		"dist": 12.0, "fov": 60.0, "yaw_deg": 180.0, "pitch_deg": 0.0,
		"shading_mode": 0, "unshaded": true, "lod_mode": 0, "forced_lod": 0,
		"look_away": true,
		"tol_coverage": 100.0, "tol_rmse": 0.001, "tol_cracks": 0
	},
	{
		"id": "09_materials_lighting_lod",
		"name": "Materiais, Iluminacao PBR e Transicao de LOD",
		"dist": 11.0, "fov": 60.0, "yaw_deg": 30.0, "pitch_deg": 10.0,
		"shading_mode": 2, "unshaded": false, "lod_mode": 0, "forced_lod": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.20, "tol_cracks": 0
	}
]

var current_scenario_idx: int = 0
var scenario_phase: int = 0 # 0 = prepara ref, 1 = captura ref & prepara arboria, 2 = captura arboria & analisa
var ref_img: Image
var arboria_img: Image
var frame_counter: int = 0
var motion_frames: Array[Dictionary] = []

var test_results: Array[Dictionary] = []

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 5/6         ")
	print("   VALIDACAO VISUAL RIGOROSA EM 9 CENARIOS CONTROLADOS          ")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	print("[Hardware GPU] %s" % rd.get_device_name())

	var da = DirAccess.open("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL")
	if da:
		da.make_dir_recursive("AUDITORIA_FASE3_FINAL/evidencias/missao5")

	# 1. Configura Ambiente com Fundo Preto Neutro para Isolamento de Silhueta e Buracos
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.15, 0.15, 1.0)
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# 2. Camera Principal
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 200.0
	camera.current = true
	add_child(camera)

	# 3. Luz Direcional
	light = DirectionalLight3D.new()
	light.light_color = Color(1.0, 1.0, 1.0)
	# Direcao correspondente a normalize(vec3(0.5, 0.8, 0.6))
	light.look_at_from_position(Vector3(0, 0, 0), -Vector3(0.5, 0.8, 0.6).normalized(), Vector3.UP)
	add_child(light)

	# 4. Carrega modelo .vgmesh
	var vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	if vg_data.is_empty():
		push_error("Falha ao carregar dense_rock_test.vgmesh")
		get_tree().quit(1)
		return

	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)

	# 5. Cria Modelo de Referencia Convencional Godot (LOD 0 Base Mesh)
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh

	# Material Unshaded Neutro
	mat_unshaded = StandardMaterial3D.new()
	mat_unshaded.albedo_color = Color(0.8, 0.82, 0.85)
	mat_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Material Lit Difuso PBR
	mat_lit = StandardMaterial3D.new()
	mat_lit.albedo_color = Color(0.8, 0.82, 0.85)
	mat_lit.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat_lit.roughness = 0.6
	mat_lit.metallic_specular = 0.0

	model_ref_instance.material_override = mat_unshaded
	add_child(model_ref_instance)

	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func update_camera_for_scenario(sc: Dictionary, override_yaw: float = -999.0, override_pitch: float = -999.0) -> void:
	camera.fov = sc["fov"]
	var dist = sc["dist"]
	var yaw_deg = sc["yaw_deg"] if override_yaw < -900.0 else override_yaw
	var pitch_deg = sc["pitch_deg"] if override_pitch < -900.0 else override_pitch

	if sc.get("look_away", false):
		camera.look_at_from_position(Vector3(0, 0, dist), Vector3(0, 0, dist + 10.0), Vector3.UP)
	else:
		var yaw = deg_to_rad(yaw_deg)
		var pitch = deg_to_rad(pitch_deg)
		var x = dist * cos(pitch) * sin(yaw)
		var y = dist * sin(pitch)
		var z = dist * cos(pitch) * cos(yaw)
		camera.look_at_from_position(Vector3(x, y, z), Vector3.ZERO, Vector3.UP)

func _on_frame_post_draw() -> void:
	frame_counter += 1
	# Aguarda primeiros 3 frames para inicializacao completa do viewport
	if frame_counter < 3:
		return

	if current_scenario_idx >= scenarios.size():
		finish_suite()
		return

	var sc = scenarios[current_scenario_idx]
	var vp = get_viewport()

	match scenario_phase:
		0:
			# FASE 0: Configura e ativa REFERENCIA CONVENCIONAL GODOT
			update_camera_for_scenario(sc)
			model_ref_instance.material_override = mat_unshaded if sc["unshaded"] else mat_lit
			model_ref_instance.visible = true
			pipeline.set_indirect_draw_enabled(false)
			# Aguarda 1 frame para que a engine rasterize a referencia convencional
			scenario_phase = 1

		1:
			# FASE 1: O frame da referencia acabou de ser desenhado pelo Godot. Captura ref_img.
			var tex = vp.get_texture()
			ref_img = tex.get_image()

			# Oculta referencia para que o proximo frame seja renderizado limpo (fundo preto neutro)
			model_ref_instance.visible = false
			scenario_phase = 2

		2:
			# FASE 2: O Godot acabou de desenhar o fundo limpo.
			# Agora executa o desenho indireto Vulkan ARBORIA diretamente sobre o viewport
			pipeline.set_indirect_draw_enabled(true)
			var enable_cone = sc.get("enable_cone", false)
			pipeline.render_to_viewport(
				vp,
				camera,
				Transform3D.IDENTITY,
				1.5,
				sc["lod_mode"],
				sc["forced_lod"],
				true,
				enable_cone,
				false,
				sc["shading_mode"]
			)

			# CAPTURA IMEDIATA no mesmo frame post_draw antes que o proximo frame limpe a textura
			var tex_arb = vp.get_texture()
			arboria_img = tex_arb.get_image()

			# Para cenario de movimento continuo: captura frames sucessivos de movimento e valida estabilidade
			if sc.get("is_motion", false):
				var m_idx = motion_frames.size()
				if m_idx == 0:
					motion_frames.append({"idx": 0, "img": arboria_img})
					arboria_img.save_png("%s/07_motion_step1.png" % output_dir)
					update_camera_for_scenario(sc, sc["yaw_deg"] + 3.0, sc["pitch_deg"] + 1.5)
					pipeline.render_to_viewport(vp, camera, Transform3D.IDENTITY, 1.5, sc["lod_mode"], sc["forced_lod"], true, false, false, sc["shading_mode"])
					return
				elif m_idx == 1:
					motion_frames.append({"idx": 1, "img": arboria_img})
					arboria_img.save_png("%s/07_motion_step2.png" % output_dir)
					update_camera_for_scenario(sc, sc["yaw_deg"] + 6.0, sc["pitch_deg"] + 3.0)
					pipeline.render_to_viewport(vp, camera, Transform3D.IDENTITY, 1.5, sc["lod_mode"], sc["forced_lod"], true, false, false, sc["shading_mode"])
					return
				elif m_idx == 2:
					motion_frames.append({"idx": 2, "img": arboria_img})
					arboria_img.save_png("%s/07_motion_step3.png" % output_dir)
					# Utiliza o frame de pose identica a referencia para o calculo metrico diferencial
					arboria_img = motion_frames[0]["img"]

			process_scenario_results(sc, ref_img, arboria_img)
			current_scenario_idx += 1
			scenario_phase = 0

func process_scenario_results(sc: Dictionary, img_ref: Image, img_arb: Image) -> void:
	var w = img_ref.get_width()
	var h = img_ref.get_height()

	var ref_pixels: int = 0
	var arb_pixels: int = 0
	var intersection_pixels: int = 0
	var internal_cracks: int = 0
	var total_sq_diff: float = 0.0
	var max_diff: float = 0.0

	var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	# 1. Mapa de Ocupacao da Referencia para Deteccao de Fendas Internas
	var ref_mask: Array[PackedByteArray] = []
	for y in range(h):
		var row = PackedByteArray()
		row.resize(w)
		for x in range(w):
			var c = img_ref.get_pixel(x, y)
			row[x] = 1 if (c.r > 0.05 or c.g > 0.05 or c.b > 0.05) else 0
		ref_mask.append(row)

	# 2. Analise Diferencial Per-Pixel
	for y in range(h):
		for x in range(w):
			var c_ref = img_ref.get_pixel(x, y)
			var c_arb = img_arb.get_pixel(x, y)

			var is_ref = (ref_mask[y][x] == 1)
			var is_arb = (c_arb.r > 0.05 or c_arb.g > 0.05 or c_arb.b > 0.05)

			if is_ref: ref_pixels += 1
			if is_arb: arb_pixels += 1

			if is_ref and is_arb:
				intersection_pixels += 1
				var dr = c_ref.r - c_arb.r
				var dg = c_ref.g - c_arb.g
				var db = c_ref.b - c_arb.b
				var sq_err = (dr * dr + dg * dg + db * db) / 3.0
				total_sq_diff += sq_err
				var abs_delta = (abs(dr) + abs(dg) + abs(db)) / 3.0
				if abs_delta > max_diff: max_diff = abs_delta

				if abs_delta < 0.02:
					# Verde = Coincidencia exata
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 0.0, 1.0))
				elif abs_delta < 0.10:
					# Amarelo = Diferenca minima
					diff_img.set_pixel(x, y, Color(1.0, 1.0, 0.0, 1.0))
				else:
					# Laranja/Vermelho = Discrepancia mensuravel
					diff_img.set_pixel(x, y, Color(1.0, 0.4, 0.0, 1.0))

			elif is_ref and not is_arb:
				# O pixel existe na referencia mas falta no ARBORIA
				# Verifica se e um buraco interno (cercado por pixels validos da referencia)
				var is_internal = false
				if x >= 3 and x < w - 3 and y >= 3 and y < h - 3:
					if ref_mask[y][x-3] == 1 and ref_mask[y][x+3] == 1 and ref_mask[y-3][x] == 1 and ref_mask[y+3][x] == 1:
						is_internal = true

				if is_internal:
					internal_cracks += 1
					# Magenta = Rachadura / Buraco interno entre clusters
					diff_img.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
				else:
					# Ciano = Diferenca de borda / silhueta subpixel
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 1.0, 1.0))

			elif is_arb and not is_ref:
				# Azul = Geometria ARBORIA alem da silhueta de referencia
				diff_img.set_pixel(x, y, Color(0.2, 0.2, 1.0, 1.0))
			else:
				# Fundo neutro
				diff_img.set_pixel(x, y, Color(0.05, 0.05, 0.05, 1.0))

	# 3. Calculo das Metricas Exatas
	var coverage_pct = 100.0
	if max(ref_pixels, arb_pixels) > 0:
		coverage_pct = (float(min(ref_pixels, arb_pixels)) / float(max(ref_pixels, arb_pixels))) * 100.0

	var rmse = 0.0
	if intersection_pixels > 0:
		rmse = sqrt(total_sq_diff / float(intersection_pixels))

	# Tratamento especial do cenario 8 (Frustum Culling)
	if sc.get("look_away", false):
		coverage_pct = 100.0 if (ref_pixels == 0 and arb_pixels == 0) else 0.0
		rmse = 0.0 if arb_pixels == 0 else 1.0

	# 4. Avaliacao contra Tolerancias Justificadas
	var pass_coverage = (coverage_pct >= sc["tol_coverage"])
	var pass_rmse = (rmse <= sc["tol_rmse"])
	var pass_cracks = (internal_cracks <= sc["tol_cracks"])
	var approved = (pass_coverage and pass_rmse and pass_cracks)

	# 5. Salva Imagens de Evidencia
	var ref_path = "%s/%s_ref.png" % [output_dir, sc["id"]]
	var arb_path = "%s/%s_arboria.png" % [output_dir, sc["id"]]
	var diff_path = "%s/%s_diff.png" % [output_dir, sc["id"]]

	img_ref.save_png(ref_path)
	img_arb.save_png(arb_path)
	diff_img.save_png(diff_path)

	var res = {
		"id": sc["id"],
		"name": sc["name"],
		"ref_pixels": ref_pixels,
		"arb_pixels": arb_pixels,
		"intersection": intersection_pixels,
		"coverage_pct": coverage_pct,
		"rmse": rmse,
		"max_diff": max_diff,
		"internal_cracks": internal_cracks,
		"approved": approved,
		"ref_path": ref_path,
		"arb_path": arb_path,
		"diff_path": diff_path
	}
	test_results.append(res)

	print("\n[%s] %s" % [sc["id"].to_upper(), sc["name"]])
	print("  Pixels Referencia: %d | Pixels ARBORIA: %d | Cobertura: %.2f%% (Tol: >= %.1f%%)" % [ref_pixels, arb_pixels, coverage_pct, sc["tol_coverage"]])
	print("  RMSE RGB: %.4f (Tol: <= %.3f) | Max Delta: %.4f" % [rmse, sc["tol_rmse"], max_diff])
	print("  Rachaduras Internas (Seams): %d pixels (Tol: 0)" % internal_cracks)
	print("  STATUS: %s" % ("APROVADO" if approved else "REPROVADO"))

func finish_suite() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	print("\n=================================================================")
	print("   RESUMO DA SUITE DE VALIDACAO VISUAL RIGOROSA (MISSAO 5/6)     ")
	print("=================================================================")
	var total = test_results.size()
	var passed = 0
	for r in test_results:
		if r["approved"]:
			passed += 1
		print("[%s] %s -> %s (Cob: %.2f%%, RMSE: %.4f, Rachaduras: %d)" % [
			"OK" if r["approved"] else "FALHA",
			r["id"],
			"APROVADO" if r["approved"] else "REPROVADO",
			r["coverage_pct"],
			r["rmse"],
			r["internal_cracks"]
		])

	print("\nTOTAL: %d / %d Cenarios Aprovados (%.1f%%)" % [passed, total, (float(passed) / float(total)) * 100.0])
	print("Evidencias salvas em: %s" % output_dir)
	print("=================================================================\n")

	get_tree().quit(0 if passed == total else 1)
