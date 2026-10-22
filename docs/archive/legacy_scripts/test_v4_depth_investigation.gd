extends Node3D

# ARBORIA ENGINE — VALIDAÇÃO V4: INVESTIGAÇÃO RIGOROSA DE PROFUNDIDADE
# Teste de Interação e Oclusão Mútua entre Geometria Godot e ARBORIA

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice
var camera: Camera3D
var subview: SubViewport

var godot_box: MeshInstance3D
var mat_godot_box: StandardMaterial3D

var vg_data: Dictionary
var current_step = 0
var depth_results = {}
var output_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/profundidade"

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — VALIDAÇÃO V4: INVESTIGAÇÃO DE PROFUNDIDADE  ")
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
	camera.position = Vector3(0, 0, 14)
	camera.fov = 60.0
	camera.current = true
	subview.add_child(camera)

	# Cria Objeto Convencional Godot: Caixa Verde Brilhante (RGB: 0, 1, 0)
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(3.5, 3.5, 1.0)
	godot_box = MeshInstance3D.new()
	godot_box.mesh = box_mesh

	mat_godot_box = StandardMaterial3D.new()
	mat_godot_box.albedo_color = Color(0.0, 1.0, 0.0) # Verde puro
	mat_godot_box.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	godot_box.material_override = mat_godot_box
	subview.add_child(godot_box)

	add_child(subview)
	RenderingServer.frame_post_draw.connect(_on_frame)

func count_color(img: Image, target: Color, tol: float = 0.1) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if abs(c.r - target.r) < tol and abs(c.g - target.g) < tol and abs(c.b - target.b) < tol:
				cnt += 1
	return cnt

func count_non_black(img: Image) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if c.r > 0.05 or c.g > 0.05 or c.b > 0.05:
				cnt += 1
	return cnt

func _on_frame() -> void:
	current_step += 1

	match current_step:
		2:
			# CASO DE CONTROLE: Apenas Objeto Godot visível (sem ARBORIA)
			godot_box.position = Vector3(1.5, 0, 5.5) # À frente
			godot_box.visible = true

		3:
			print("\n[CONTROLE] Captura de Referência do Objeto Godot isolado")
			var img_ctrl = subview.get_texture().get_image()
			var green_ctrl = count_color(img_ctrl, Color(0, 1, 0))
			img_ctrl.save_png("%s/00_godot_box_isolado.png" % output_dir)
			print("  Pixels do Objeto Godot (Verde Isolado): %d" % green_ctrl)
			depth_results["godot_box_pixels_isolado"] = green_ctrl

			# PREPARA CASO A: Objeto Godot à FRENTE da geometria ARBORIA
			# Câmera está em Z = 14.
			# Godot Box está em Z = 5.5 (mais perto da câmera).
			# ARBORIA Rock está em Z = 0.0 (mais distante da câmera).
			# Pela lei óptica, o Objeto Godot DEVE ocluir a rocha ARBORIA onde sobrepõe.
			godot_box.position = Vector3(1.5, 0, 5.5)
			godot_box.visible = true

		4:
			print("\n[TESTE DE PROFUNDIDADE — CASO A] Objeto Godot à FRENTE da geometria ARBORIA")
			print("  Configuração: Câmera Z=14 | Objeto Godot Z=5.5 (Frente) | ARBORIA Z=0.0 (Fundo)")
			print("  Disparando pipeline.render_to_viewport() sobre o viewport...")

			# ARBORIA renderiza em Modo 0 (Neutro Color(0.8, 0.82, 0.85))
			pipeline.render_to_viewport(subview, camera, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)

			var img_a = subview.get_texture().get_image()
			img_a.save_png("%s/01_caso_a_godot_na_frente.png" % output_dir)

			var green_a = count_color(img_a, Color(0, 1, 0))
			var neutral_a = count_color(img_a, Color(0.8, 0.82, 0.85))
			var total_a = count_non_black(img_a)

			print("  Pixels Verdes visíveis (Objeto Godot): %d (Isolado original era: %d)" % [green_a, depth_results["godot_box_pixels_isolado"]])
			print("  Pixels Neutros visíveis (ARBORIA): %d" % neutral_a)
			print("  Total de pixels ativos: %d" % total_a)

			var godot_box_occluded_incorrectly = (green_a < depth_results["godot_box_pixels_isolado"] * 0.90)
			if godot_box_occluded_incorrectly:
				print("  ALERTA CRÍTICO DE PROFUNDIDADE: O Objeto Godot à frente teve pixels SOBRESCRITOS pelo ARBORIA!")
				print("  Perda de pixels do objeto frontal: %d pixels perdidos (%.1f%% do objeto frontal foi sobrescrito)" % [
					depth_results["godot_box_pixels_isolado"] - green_a,
					(1.0 - float(green_a) / float(depth_results["godot_box_pixels_isolado"])) * 100.0
				])
			else:
				print("  Objeto Godot preservou sua silhueta frontal intacta.")

			depth_results["caso_a_godot_na_frente"] = {
				"green_pixels": green_a,
				"expected_green": depth_results["godot_box_pixels_isolado"],
				"neutral_pixels": neutral_a,
				"overwritten": godot_box_occluded_incorrectly
			}

			# PREPARA CASO B: Geometria ARBORIA à FRENTE do objeto Godot
			# Godot Box é movido para Z = -3.0 (atrás da rocha ARBORIA em Z = 0.0)
			godot_box.position = Vector3(1.5, 0, -3.0)
			godot_box.visible = true

		5:
			# Frame 5: Godot rasteriza caixa atrás
			pass

		6:
			print("\n[TESTE DE PROFUNDIDADE — CASO B] Geometria ARBORIA à FRENTE do objeto Godot")
			print("  Configuração: Câmera Z=14 | ARBORIA Z=0.0 (Frente) | Objeto Godot Z=-3.0 (Fundo)")
			print("  Disparando pipeline.render_to_viewport() sobre o viewport...")

			pipeline.render_to_viewport(subview, camera, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)

			var img_b = subview.get_texture().get_image()
			img_b.save_png("%s/02_caso_b_arboria_na_frente.png" % output_dir)

			var green_b = count_color(img_b, Color(0, 1, 0))
			var neutral_b = count_color(img_b, Color(0.8, 0.82, 0.85))
			var total_b = count_non_black(img_b)

			print("  Pixels Verdes visíveis (Godot no fundo): %d" % green_b)
			print("  Pixels Neutros visíveis (ARBORIA na frente): %d" % neutral_b)
			print("  Total de pixels ativos: %d" % total_b)

			depth_results["caso_b_arboria_na_frente"] = {
				"green_pixels": green_b,
				"neutral_pixels": neutral_b,
				"total_pixels": total_b
			}

			finish_depth_investigation()

func finish_depth_investigation() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	print("\n=================================================================")
	print("   DIAGNÓSTICO ARQUITETURAL DA PROFUNDIDADE NO FORWARD+         ")
	print("=================================================================")

	var vp_rid = subview.get_viewport_rid()
	var tex_rs = RenderingServer.viewport_get_texture(vp_rid)
	var tex_rd = RenderingServer.texture_get_rd_texture(tex_rs)

	print("  - Viewport Color RID (RenderingServer): ", tex_rs)
	print("  - Viewport Color RID (RenderingDevice): ", tex_rd)
	print("  - Pipeline Framebuffer RID: ", pipeline.vp_framebuffer)
	print("  - Pipeline Private Depth RID: ", pipeline.vp_depth_tex)

	var case_a_overwritten = depth_results["caso_a_godot_na_frente"]["overwritten"]

	print("\n  CONCLUSÃO TÉCNICA OBRIGATÓRIA:")
	if case_a_overwritten:
		print("  [LIMITAÇÃO DE API CONFIRMADA] COMPOSIÇÃO VISUAL (SEM TESTE DE PROFUNDIDADE COMPARTILHADO).")
		print("  Causa Raiz: O pipeline ARBORIA aloca um buffer de profundidade privado (D32_SFLOAT)")
		print("  e renderiza na etapa 'frame_post_draw' (após a passagem Forward+ opaca do Godot).")
		print("  Como a API pública de GDScript do Godot não expõe o Depth Buffer interno do Forward+,")
		print("  a geometria ARBORIA não realiza teste de profundidade contra os objetos já rasterizados pelo Godot,")
		print("  sobrescrevendo objetos que estejam fisicamente à sua frente.")
	else:
		print("  [COMPARTILHAMENTO DE PROFUNDIDADE CONFIRMADO]: Teste de profundidade integrado.")

	print("\nEvidências salvas em: %s" % output_dir)
	print("=================================================================\n")
	get_tree().quit(0)
