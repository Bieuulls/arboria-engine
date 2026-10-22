extends Node3D

# ARBORIA ENGINE — ORDEM TÉCNICA V5.1
# SUÍTE DEFINITIVA DE ESTABILIZAÇÃO DOS TESTES ANTES DA INTEGRAÇÃO NATIVA

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")
const VGVisualMetrics = preload("res://scripts/vg_visual_metrics.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice

var subview_ref: SubViewport
var subview_arb: SubViewport
var cam_ref: Camera3D
var cam_arb: Camera3D

var model_ref_instance: MeshInstance3D
var mat_ref_neutral: StandardMaterial3D
var mat_ref_red: StandardMaterial3D
var mat_ref_lit: StandardMaterial3D

var light_ref: DirectionalLight3D
var light_arb: DirectionalLight3D

var vg_data_rock: Dictionary
var vg_data_granite: Dictionary

var step = 0
var test_log_lines: Array[String] = []
var all_assertions_passed = true

var base_output = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V5_1_FINAL/evidencias"
var log_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V5_1_FINAL/logs/execution.log"

func log_msg(msg: String) -> void:
	print(msg)
	test_log_lines.append(msg)

func _ready() -> void:
	log_msg("=================================================================")
	log_msg("   ARBORIA ENGINE — ORDEM TÉCNICA V5.1: VALIDAÇÃO FINAL ESTÁVEL  ")
	log_msg("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	log_msg("[Hardware GPU] %s" % rd.get_device_name())

	vg_data_rock = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	vg_data_granite = VGMeshLoader.load_from_file("res://assets/boulder_granite.vgmesh")

	# 1. SubViewport da Referência Convencional Godot (Totalmente Isolado)
	subview_ref = SubViewport.new()
	subview_ref.size = Vector2i(1280, 720)
	subview_ref.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subview_ref.own_world_3d = true

	var env_ref = Environment.new()
	env_ref.background_mode = Environment.BG_COLOR
	env_ref.background_color = Color(0, 0, 0, 1)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.ambient_light_color = Color(0.15, 0.15, 0.15, 1.0)
	var we_ref = WorldEnvironment.new()
	we_ref.environment = env_ref
	subview_ref.add_child(we_ref)

	cam_ref = Camera3D.new()
	cam_ref.near = 0.05
	cam_ref.far = 300.0
	cam_ref.current = true
	subview_ref.add_child(cam_ref)

	light_ref = DirectionalLight3D.new()
	light_ref.look_at_from_position(Vector3(0, 0, 0), -Vector3(0.5, 0.8, 0.6).normalized(), Vector3.UP)
	subview_ref.add_child(light_ref)

	var ref_mesh_rock = VGMeshLoader.build_mesh_surface(vg_data_rock, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh_rock

	mat_ref_neutral = StandardMaterial3D.new()
	mat_ref_neutral.albedo_color = Color(0.8, 0.82, 0.85)
	mat_ref_neutral.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_ref_red = StandardMaterial3D.new()
	mat_ref_red.albedo_color = Color(1.0, 0.0, 0.0)
	mat_ref_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_ref_lit = StandardMaterial3D.new()
	mat_ref_lit.albedo_color = Color(0.8, 0.82, 0.85)
	mat_ref_lit.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat_ref_lit.roughness = 0.6
	mat_ref_lit.metallic_specular = 0.0

	model_ref_instance.material_override = mat_ref_neutral
	subview_ref.add_child(model_ref_instance)
	add_child(subview_ref)

	# 2. SubViewport Exclusivo do ARBORIA GPU Indirect (Totalmente Isolado)
	subview_arb = SubViewport.new()
	subview_arb.size = Vector2i(1280, 720)
	subview_arb.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subview_arb.own_world_3d = true

	var env_arb = Environment.new()
	env_arb.background_mode = Environment.BG_COLOR
	env_arb.background_color = Color(0, 0, 0, 1)
	var we_arb = WorldEnvironment.new()
	we_arb.environment = env_arb
	subview_arb.add_child(we_arb)

	cam_arb = Camera3D.new()
	cam_arb.near = 0.05
	cam_arb.far = 300.0
	cam_arb.current = true
	subview_arb.add_child(cam_arb)

	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data_rock)

	add_child(subview_arb)
	RenderingServer.frame_post_draw.connect(_on_frame)

func set_cameras_pose(dist: float, yaw_deg: float, pitch_deg: float, fov: float) -> void:
	var yaw = deg_to_rad(yaw_deg)
	var pitch = deg_to_rad(pitch_deg)
	var pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
	cam_ref.fov = fov
	cam_ref.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	cam_arb.fov = fov
	cam_arb.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)

func _on_frame() -> void:
	step += 1

	match step:
		2:
			# =========================================================
			# TESTE A: Desenho indireto ARBORIA desativado
			# =========================================================
			set_cameras_pose(12.0, 0.0, 0.0, 60.0)
			model_ref_instance.visible = true
			model_ref_instance.material_override = mat_ref_neutral
			pipeline.set_indirect_draw_enabled(false)

		3:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE A] Desenho indireto ARBORIA desativado (Prova Negativa)")
			var img_ref = subview_ref.get_texture().get_image()

			# Chama render_to_viewport com p_clear_color = true
			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/negativos/teste_a_ref.png" % base_output)
			img_arb.save_png("%s/negativos/teste_a_arboria_disabled.png" % base_output)

			log_msg("  Pixels Referência: %d (esperado > 50000)" % m.ref_pixels)
			log_msg("  Pixels ARBORIA: %d (esperado == 0)" % m.arb_pixels)
			log_msg("  IoU: %.4f" % m.iou)

			var pass_a = (m.ref_pixels > 50000 and m.arb_pixels == 0 and m.iou == 0.0)
			if not pass_a: all_assertions_passed = false
			log_msg("  STATUS TESTE A: %s" % ("APROVADO" if pass_a else "FALHA"))

			# =========================================================
			# PREPARA TESTE B: Referência desativada, ARBORIA ativo
			# =========================================================
			model_ref_instance.visible = false
			pipeline.set_indirect_draw_enabled(true)

		4:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE B] Referência convencional desativada")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/negativos/teste_b_ref_disabled.png" % base_output)
			img_arb.save_png("%s/negativos/teste_b_arboria_active.png" % base_output)

			log_msg("  Pixels Referência: %d (esperado == 0)" % m.ref_pixels)
			log_msg("  Pixels ARBORIA: %d (esperado > 50000)" % m.arb_pixels)
			log_msg("  IoU: %.4f" % m.iou)

			var pass_b = (m.ref_pixels == 0 and m.arb_pixels > 50000 and m.iou == 0.0)
			if not pass_b: all_assertions_passed = false
			log_msg("  STATUS TESTE B: %s" % ("APROVADO" if pass_b else "FALHA"))

			# =========================================================
			# PREPARA TESTE C: Modelos geometricamente diferentes
			# Ref = Boulder Granite, Arb = Dense Rock
			# =========================================================
			var ref_granite = VGMeshLoader.build_mesh_surface(vg_data_granite, 0, false, -1)
			model_ref_instance.mesh = ref_granite
			model_ref_instance.material_override = mat_ref_neutral
			model_ref_instance.visible = true

			pipeline.load_vgmesh(vg_data_rock)
			pipeline.set_indirect_draw_enabled(true)

		5:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE C] Modelos geometricamente diferentes (Granite vs Dense Rock)")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/negativos/teste_c_ref_granite.png" % base_output)
			img_arb.save_png("%s/negativos/teste_c_arboria_dense_rock.png" % base_output)
			m.diff_image.save_png("%s/negativos/teste_c_diff.png" % base_output)

			log_msg("  Pixels Referência (Granite): %d" % m.ref_pixels)
			log_msg("  Pixels ARBORIA (Dense Rock): %d" % m.arb_pixels)
			log_msg("  Interseção: %d | União: %d" % [m.intersection, m.union])
			log_msg("  IoU Verdadeiro: %.4f (%.2f%%) (esperado < 0.25 para modelos distintos)" % [m.iou, m.iou_pct])

			var pass_c = (m.iou < 0.25 and abs(m.ref_pixels - m.arb_pixels) > 50000)
			if not pass_c: all_assertions_passed = false
			log_msg("  STATUS TESTE C: %s" % ("APROVADO (Divergência detectada)" if pass_c else "FALHA"))

			# =========================================================
			# PREPARA TESTE D: Cor alterada em somente um caminho
			# Ref = Vermelho puro, Arb = Cinza neutro
			# =========================================================
			var ref_rock = VGMeshLoader.build_mesh_surface(vg_data_rock, 0, false, -1)
			model_ref_instance.mesh = ref_rock
			model_ref_instance.material_override = mat_ref_red
			model_ref_instance.visible = true

		6:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE D] Cor alterada em somente um caminho (Ref Vermelho vs Arb Neutro)")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/negativos/teste_d_ref_red.png" % base_output)
			img_arb.save_png("%s/negativos/teste_d_arboria_neutral.png" % base_output)
			m.diff_image.save_png("%s/negativos/teste_d_diff.png" % base_output)

			log_msg("  IoU da Silhueta: %.4f (%.2f%%) (esperado >= 99.5%%)" % [m.iou, m.iou_pct])
			log_msg("  RMSE RGB: %.4f (esperado > 0.40 devido à divergência de cor)" % m.rmse)

			var pass_d = (m.iou >= 0.995 and m.rmse > 0.40)
			if not pass_d: all_assertions_passed = false
			log_msg("  STATUS TESTE D: %s" % ("APROVADO (Cores independentes comprovadas)" if pass_d else "FALHA"))

			# =========================================================
			# PREPARA TESTE E: LOD MISTO (Corte DAG Hierárquico Multi-Nível)
			# Pose 1: Dist: 18.0m, Yaw: 30°, Pitch: 10°, FOV: 60°
			# =========================================================
			set_cameras_pose(18.0, 30.0, 10.0, 60.0)
			model_ref_instance.material_override = mat_ref_neutral

		7:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE E — CASO 1] LOD Misto: Dist 18.0m, Yaw 30°, Pitch 10° (DAG Auto)")
			var img_ref = subview_ref.get_texture().get_image()

			# lod_mode = 0 (DAG Automática)
			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 0, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/lod_misto/01_lod_misto_ref.png" % base_output)
			img_arb.save_png("%s/lod_misto/01_lod_misto_arboria.png" % base_output)
			m.diff_image.save_png("%s/lod_misto/01_lod_misto_diff.png" % base_output)

			var raw_cnt = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			var inst_cnt = raw_cnt.decode_u32(4)
			var tris_cnt = raw_cnt.decode_u32(16)
			var raw_vis = rd.buffer_get_data(pipeline.out_visible_buf, 0, inst_cnt * 4)
			var dist_map = {}
			for i in range(inst_cnt):
				var cid = raw_vis.decode_u32(i * 4)
				var lvl = vg_data_rock["clusters"][cid]["lod_level"]
				dist_map[lvl] = dist_map.get(lvl, 0) + 1

			log_msg("  Clusters Ativos: %d | Triângulos: %d | Distribuição de LOD: %s" % [inst_cnt, tris_cnt, str(dist_map)])
			log_msg("  Ref Pixels: %d | Arb Pixels: %d | Interseção: %d | União: %d" % [m.ref_pixels, m.arb_pixels, m.intersection, m.union])
			log_msg("  IoU Verdadeiro: %.4f (%.2f%%) (esperado >= 98.0%%)" % [m.iou, m.iou_pct])
			log_msg("  Rachaduras Internas: %d pixels (esperado == 0)" % m.internal_cracks)

			# Exige que pelo menos 2 níveis de LOD estejam ativos simultaneamente!
			var has_multi_lod = dist_map.size() >= 2
			var pass_e1 = (m.iou >= 0.98 and m.internal_cracks == 0 and has_multi_lod)
			if not pass_e1: all_assertions_passed = false
			log_msg("  Múltiplos Níveis Simultâneos Presentes? %s" % str(has_multi_lod))
			log_msg("  STATUS CASO 1 LOD MISTO: %s" % ("APROVADO" if pass_e1 else "FALHA"))

			# =========================================================
			# PREPARA TESTE E — CASO 2: LOD Misto em Rotação Oblíqua
			# Dist: 15.0m, Yaw: 120°, Pitch: 40°, FOV: 60°
			# =========================================================
			set_cameras_pose(15.0, 120.0, 40.0, 60.0)

		8:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE E — CASO 2] LOD Misto: Dist 15.0m, Yaw 120°, Pitch 40° (DAG Auto)")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 0, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/lod_misto/02_lod_misto_rot_ref.png" % base_output)
			img_arb.save_png("%s/lod_misto/02_lod_misto_rot_arboria.png" % base_output)
			m.diff_image.save_png("%s/lod_misto/02_lod_misto_rot_diff.png" % base_output)

			var raw_cnt = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			var inst_cnt = raw_cnt.decode_u32(4)
			var tris_cnt = raw_cnt.decode_u32(16)
			var raw_vis = rd.buffer_get_data(pipeline.out_visible_buf, 0, inst_cnt * 4)
			var dist_map = {}
			for i in range(inst_cnt):
				var cid = raw_vis.decode_u32(i * 4)
				var lvl = vg_data_rock["clusters"][cid]["lod_level"]
				dist_map[lvl] = dist_map.get(lvl, 0) + 1

			log_msg("  Clusters Ativos: %d | Triângulos: %d | Distribuição de LOD: %s" % [inst_cnt, tris_cnt, str(dist_map)])
			log_msg("  Ref Pixels: %d | Arb Pixels: %d | Interseção: %d | União: %d" % [m.ref_pixels, m.arb_pixels, m.intersection, m.union])
			log_msg("  IoU Verdadeiro: %.4f (%.2f%%) (esperado >= 98.0%%)" % [m.iou, m.iou_pct])
			log_msg("  Rachaduras Internas: %d pixels (esperado == 0)" % m.internal_cracks)

			var has_multi_lod = dist_map.size() >= 2
			var pass_e2 = (m.iou >= 0.98 and m.internal_cracks == 0 and has_multi_lod)
			if not pass_e2: all_assertions_passed = false
			log_msg("  Múltiplos Níveis Simultâneos Presentes? %s" % str(has_multi_lod))
			log_msg("  STATUS CASO 2 LOD MISTO: %s" % ("APROVADO" if pass_e2 else "FALHA"))

			# =========================================================
			# PREPARA TESTE VISUAL: Close-up 7.0m LOD 0 Unshaded
			# =========================================================
			set_cameras_pose(7.0, 0.0, 0.0, 60.0)

		9:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE VISUAL 1] Close-up 7.0m (LOD 0 Puro Unshaded)")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/visuais/01_closeup_ref.png" % base_output)
			img_arb.save_png("%s/visuais/01_closeup_arboria.png" % base_output)
			m.diff_image.save_png("%s/visuais/01_closeup_diff.png" % base_output)

			log_msg("  Ref Pixels: %d | Arb Pixels: %d | Interseção: %d | União: %d" % [m.ref_pixels, m.arb_pixels, m.intersection, m.union])
			log_msg("  IoU Verdadeiro: %.6f (%.2f%%)" % [m.iou, m.iou_pct])
			log_msg("  RMSE RGB: %.4f | Max Delta: %.4f | Rachaduras: %d" % [m.rmse, m.max_diff, m.internal_cracks])

			var pass_v1 = (m.iou >= 0.999 and m.rmse == 0.0 and m.internal_cracks == 0)
			if not pass_v1: all_assertions_passed = false
			log_msg("  STATUS VISUAL 1: %s" % ("APROVADO" if pass_v1 else "FALHA"))

			# =========================================================
			# PREPARA TESTE VISUAL 2: Iluminação PBR Lit 12.0m
			# =========================================================
			set_cameras_pose(12.0, 30.0, 10.0, 60.0)
			model_ref_instance.material_override = mat_ref_lit

		10:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE VISUAL 2] Iluminação PBR Lit 12.0m")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 2, true)
			var img_arb = subview_arb.get_texture().get_image()

			var m = VGVisualMetrics.evaluate(img_ref, img_arb)
			img_ref.save_png("%s/visuais/02_pbr_lit_ref.png" % base_output)
			img_arb.save_png("%s/visuais/02_pbr_lit_arboria.png" % base_output)
			m.diff_image.save_png("%s/visuais/02_pbr_lit_diff.png" % base_output)

			log_msg("  IoU da Silhueta: %.6f (%.2f%%)" % [m.iou, m.iou_pct])
			log_msg("  RMSE RGB PBR: %.4f (tolerância <= 0.2000)" % m.rmse)
			log_msg("  Max Delta RGB: %.4f (tolerância <= 0.3500)" % m.max_diff)

			var pass_v2 = (m.iou >= 0.999 and m.rmse <= 0.20 and m.internal_cracks == 0)
			if not pass_v2: all_assertions_passed = false
			log_msg("  STATUS VISUAL 2: %s" % ("APROVADO" if pass_v2 else "FALHA"))

			# =========================================================
			# PREPARA TESTE DE PROFUNDIDADE: Caso A (Godot Box na frente)
			# =========================================================
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(3.5, 3.5, 1.0)
			var godot_box = MeshInstance3D.new()
			godot_box.name = "GodotBox"
			godot_box.mesh = box_mesh
			var mat_box = StandardMaterial3D.new()
			mat_box.albedo_color = Color(0.0, 1.0, 0.0) # Verde puro
			mat_box.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			godot_box.material_override = mat_box
			godot_box.position = Vector3(1.5, 0, 5.5) # À FRENTE do modelo em Z=0
			subview_arb.add_child(godot_box)

			set_cameras_pose(14.0, 0.0, 0.0, 60.0)

		11:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE DE PROFUNDIDADE — CASO A] Metodologia Controlada de Oclusão (Imagem A vs Imagem B)")
			log_msg("  Configuração: Câmera Z=14 | Caixa Verde Z=5.5 (Frente) | ARBORIA Z=0.0 (Fundo)")

			# 1. CAPTURA IMAGEM A: Cubo convencional Godot renderizado isoladamente
			var img_box_isolated = subview_arb.get_texture().get_image()
			img_box_isolated.save_png("%s/profundidade/00_godot_box_isolado.png" % base_output)

			# 2. CAPTURA IMAGEM B: Mesmo cubo com desenho indireto ARBORIA sobreposto (sem limpar cor)
			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, false)
			var img_box_overlaid = subview_arb.get_texture().get_image()
			img_box_overlaid.save_png("%s/profundidade/01_caso_a_godot_na_frente.png" % base_output)

			# 3. Análise controlada na máscara original do cubo
			var w = img_box_isolated.get_width()
			var h = img_box_isolated.get_height()
			var total_box_pixels = 0
			var preserved_box_pixels = 0
			var overwritten_box_pixels = 0
			var diff_depth_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

			for y in range(h):
				for x in range(w):
					var ca = img_box_isolated.get_pixel(x, y)
					var cb = img_box_overlaid.get_pixel(x, y)
					var is_box_orig = (ca.g > 0.8 and ca.r < 0.2 and ca.b < 0.2)
					var is_box_curr = (cb.g > 0.8 and cb.r < 0.2 and cb.b < 0.2)
					var is_arb_curr = (cb.r > 0.05 or cb.g > 0.05 or cb.b > 0.05) and not is_box_curr

					if is_box_orig:
						total_box_pixels += 1
						if is_box_curr:
							preserved_box_pixels += 1
							diff_depth_img.set_pixel(x, y, Color(0.0, 1.0, 0.0, 1.0)) # Verde = preservado
						else:
							overwritten_box_pixels += 1
							diff_depth_img.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0)) # Vermelho = sobrescrito pelo ARBORIA
					else:
						if is_arb_curr:
							diff_depth_img.set_pixel(x, y, Color(0.3, 0.3, 0.35, 1.0)) # Cinza = rocha fora da silhueta do cubo
						else:
							diff_depth_img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))

			diff_depth_img.save_png("%s/profundidade/01_caso_a_mascara_sobrescrita.png" % base_output)

			var pct_overwritten = (float(overwritten_box_pixels) / float(total_box_pixels)) * 100.0 if total_box_pixels > 0 else 0.0
			var pct_preserved = (float(preserved_box_pixels) / float(total_box_pixels)) * 100.0 if total_box_pixels > 0 else 0.0

			log_msg("  Total de Pixels na Máscara Original do Cubo (Imagem A): %d" % total_box_pixels)
			log_msg("  Pixels Originais do Cubo Preservados (Imagem B): %d (%.2f%%)" % [preserved_box_pixels, pct_preserved])
			log_msg("  Pixels Originais do Cubo Sobrescritos pelo ARBORIA: %d (%.2f%%)" % [overwritten_box_pixels, pct_overwritten])
			log_msg("  BLOQUEIO ARQUITETURAL CONFIRMADO: Devido ao buffer de profundidade isolado do ARBORIA,")
			log_msg("  %.2f%% dos pixels do cubo frontal foram indevidamente sobrescritos pela geometria de fundo." % pct_overwritten)
			log_msg("  STATUS PROFUNDIDADE: SOBREPOSIÇÃO VISUAL CONFIRMADA — BLOQUEIO FORWARD+ REGISTRADO")

			# PREPARA CASO B: Caixa Godot Atrás
			var box = subview_arb.get_node("GodotBox")
			box.position = Vector3(1.5, 0, -3.0)

		12:
			log_msg("\n-----------------------------------------------------------------")
			log_msg("[TESTE DE PROFUNDIDADE — CASO B] Geometria ARBORIA à FRENTE do objeto Godot")
			log_msg("  Configuração: Câmera Z=14 | ARBORIA Z=0.0 (Frente) | Caixa Verde Z=-3.0 (Fundo)")

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0, false)
			var img_depth_b = subview_arb.get_texture().get_image()
			img_depth_b.save_png("%s/profundidade/02_caso_b_arboria_na_frente.png" % base_output)

			log_msg("  STATUS CASO B: Evidência registrada com sucesso.")

			finish_suite()

func finish_suite() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	log_msg("\n=================================================================")
	log_msg("   CONSOLIDAÇÃO FINAL DA SUÍTE DE ESTABILIZAÇÃO V5.1            ")
	log_msg("=================================================================")
	log_msg("  Resultado Global dos Testes Funcionais: %s" % ("APROVADO" if all_assertions_passed else "REPROVADO"))
	log_msg("  Bloqueio de Profundidade Forward+: DOCUMENTADO COMO PENDÊNCIA NATIVA")
	log_msg("  Evidências salvas em: %s" % base_output)
	log_msg("=================================================================\n")

	# Salva o arquivo de log completo
	var f = FileAccess.open(log_path, FileAccess.WRITE)
	if f:
		for l in test_log_lines:
			f.store_line(l)
		f.close()

	get_tree().quit(0 if all_assertions_passed else 1)
