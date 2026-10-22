extends Node3D

# ARBORIA ENGINE — VALIDAÇÃO V4: TESTES NEGATIVOS OBRIGATÓRIOS
# Comprovação Rigorosa de Independência dos Renderizadores e Verificação de Falhas

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice

var subview_ref: SubViewport
var subview_arb: SubViewport
var cam_ref: Camera3D
var cam_arb: Camera3D

var model_ref_instance: MeshInstance3D
var mat_unshaded_neutral: StandardMaterial3D
var mat_unshaded_red: StandardMaterial3D

var vg_data_rock: Dictionary
var vg_data_granite: Dictionary

var current_step = 0
var test_results = {}
var output_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/negativos"

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — VALIDAÇÃO V4: TESTES NEGATIVOS OBRIGATÓRIOS  ")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	print("[Hardware GPU] %s" % rd.get_device_name())

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
	var we_ref = WorldEnvironment.new()
	we_ref.environment = env_ref
	subview_ref.add_child(we_ref)

	cam_ref = Camera3D.new()
	cam_ref.position = Vector3(0, 0, 12)
	cam_ref.fov = 60.0
	cam_ref.current = true
	subview_ref.add_child(cam_ref)

	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data_rock, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh

	mat_unshaded_neutral = StandardMaterial3D.new()
	mat_unshaded_neutral.albedo_color = Color(0.8, 0.82, 0.85)
	mat_unshaded_neutral.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_unshaded_red = StandardMaterial3D.new()
	mat_unshaded_red.albedo_color = Color(1.0, 0.0, 0.0)
	mat_unshaded_red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	model_ref_instance.material_override = mat_unshaded_neutral
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
	cam_arb.position = Vector3(0, 0, 12)
	cam_arb.fov = 60.0
	cam_arb.current = true
	subview_arb.add_child(cam_arb)
	add_child(subview_arb)

	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data_rock)

	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func count_non_black(img: Image) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if c.r > 0.05 or c.g > 0.05 or c.b > 0.05:
				cnt += 1
	return cnt

func count_color(img: Image, target: Color, tol: float = 0.1) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if abs(c.r - target.r) < tol and abs(c.g - target.g) < tol and abs(c.b - target.b) < tol:
				cnt += 1
	return cnt

func _on_frame_post_draw() -> void:
	current_step += 1

	match current_step:
		2:
			# PREPARA TESTE A: Referência ligada, ARBORIA desligado
			model_ref_instance.visible = true
			model_ref_instance.material_override = mat_unshaded_neutral
			pipeline.set_indirect_draw_enabled(false)

		3:
			# EXECUTA E VALIDA TESTE A: Desativar desenho indireto ARBORIA
			print("\n[TESTE NEGATIVO A] Desativar o desenho indireto ARBORIA")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
			var img_arb = subview_arb.get_texture().get_image()

			var px_ref = count_non_black(img_ref)
			var px_arb = count_non_black(img_arb)

			img_ref.save_png("%s/teste_a_ref.png" % output_dir)
			img_arb.save_png("%s/teste_a_arboria_disabled.png" % output_dir)

			print("  Pixels Referência: %d (esperado > 50000)" % px_ref)
			print("  Pixels ARBORIA: %d (esperado == 0)" % px_arb)

			var pass_a = (px_ref > 50000 and px_arb == 0)
			test_results["teste_a_arboria_desativado"] = pass_a
			print("  RESULTADO TESTE A: %s" % ("APROVADO" if pass_a else "REPROVADO"))

			# PREPARA TESTE B: Referência desligada, ARBORIA ligado
			model_ref_instance.visible = false
			pipeline.set_indirect_draw_enabled(true)

		4:
			# EXECUTA E VALIDA TESTE B: Desativar geometria de referência convencional
			print("\n[TESTE NEGATIVO B] Desativar a geometria de referência convencional")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
			var img_arb = subview_arb.get_texture().get_image()

			var px_ref = count_non_black(img_ref)
			var px_arb = count_non_black(img_arb)

			img_ref.save_png("%s/teste_b_ref_disabled.png" % output_dir)
			img_arb.save_png("%s/teste_b_arboria_active.png" % output_dir)

			print("  Pixels Referência: %d (esperado == 0)" % px_ref)
			print("  Pixels ARBORIA: %d (esperado > 50000)" % px_arb)

			var pass_b = (px_ref == 0 and px_arb > 50000)
			test_results["teste_b_referencia_desativada"] = pass_b
			print("  RESULTADO TESTE B: %s" % ("APROVADO" if pass_b else "REPROVADO"))

			# PREPARA TESTE C: Referência ligada com cor VERMELHA, ARBORIA ligado com cor NEUTRA
			model_ref_instance.visible = true
			model_ref_instance.material_override = mat_unshaded_red
			pipeline.set_indirect_draw_enabled(true)

		5:
			# EXECUTA E VALIDA TESTE C: Alterar cor de diagnóstico apenas de um dos caminhos
			print("\n[TESTE NEGATIVO C] Alterar cor de diagnóstico apenas de um dos caminhos")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
			var img_arb = subview_arb.get_texture().get_image()

			var red_in_ref = count_color(img_ref, Color(1, 0, 0))
			var red_in_arb = count_color(img_arb, Color(1, 0, 0))
			var neutral_in_arb = count_color(img_arb, Color(0.8, 0.82, 0.85))

			img_ref.save_png("%s/teste_c_ref_red.png" % output_dir)
			img_arb.save_png("%s/teste_c_arboria_neutral.png" % output_dir)

			print("  Pixels Vermelhos na Referência: %d (esperado > 50000)" % red_in_ref)
			print("  Pixels Vermelhos no ARBORIA: %d (esperado == 0)" % red_in_arb)
			print("  Pixels Neutros no ARBORIA: %d (esperado > 50000)" % neutral_in_arb)

			var pass_c = (red_in_ref > 50000 and red_in_arb == 0 and neutral_in_arb > 50000)
			test_results["teste_c_cor_independente"] = pass_c
			print("  RESULTADO TESTE C: %s" % ("APROVADO" if pass_c else "REPROVADO"))

			# PREPARA TESTE D: Referência usa modelo 'Boulder Granite', ARBORIA usa 'Dense Rock'
			var ref_mesh_granite = VGMeshLoader.build_mesh_surface(vg_data_granite, 0, false, -1)
			model_ref_instance.mesh = ref_mesh_granite
			model_ref_instance.material_override = mat_unshaded_neutral
			model_ref_instance.visible = true

			pipeline.load_vgmesh(vg_data_rock)
			pipeline.set_indirect_draw_enabled(true)

		6:
			# EXECUTA E VALIDA TESTE D: Modelos geometricamente diferentes nos dois caminhos
			print("\n[TESTE NEGATIVO D] Modelos geometricamente diferentes nos dois caminhos")
			var img_ref = subview_ref.get_texture().get_image()

			pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
			var img_arb = subview_arb.get_texture().get_image()

			var px_ref = count_non_black(img_ref)
			var px_arb = count_non_black(img_arb)

			img_ref.save_png("%s/teste_d_ref_granite.png" % output_dir)
			img_arb.save_png("%s/teste_d_arboria_dense_rock.png" % output_dir)

			print("  Pixels Referência (Granite): %d" % px_ref)
			print("  Pixels ARBORIA (Dense Rock): %d" % px_arb)
			var ratio = float(min(px_ref, px_arb)) / float(max(px_ref, px_arb))
			print("  Taxa de sobreposição: %.2f%% (esperada divergência flagrante < 70%%)" % (ratio * 100.0))

			var pass_d = (abs(px_ref - px_arb) > 20000 and ratio < 0.70)
			test_results["teste_d_modelos_divergentes"] = pass_d
			print("  RESULTADO TESTE D: %s" % ("APROVADO" if pass_d else "REPROVADO"))

			finish_negative_tests()

func finish_negative_tests() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	print("\n=================================================================")
	print("   CONSOLIDAÇÃO DOS 4 TESTES NEGATIVOS OBRIGATÓRIOS             ")
	print("=================================================================")
	var all_pass = true
	for k in test_results:
		var ok = test_results[k]
		if not ok: all_pass = false
		print("  - %s: %s" % [k, "APROVADO (Divergência detectada com sucesso)" if ok else "FALHA"])

	print("\nSTATUS GLOBAL DOS TESTES NEGATIVOS: %s" % ("APROVADO" if all_pass else "REPROVADO"))
	print("Evidências salvas em: %s" % output_dir)
	print("=================================================================\n")
	get_tree().quit(0 if all_pass else 1)
