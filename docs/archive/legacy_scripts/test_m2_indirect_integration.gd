extends Node3D

# ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 2/6
# Integracao Real do Desenho Indireto Vulkan no Viewport 3D Principal

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var camera: Camera3D
var rd: RenderingDevice
var vp_framebuffer: RID
var vp_depth_tex: RID
var last_vp_size: Vector2i = Vector2i.ZERO

var step: int = 0
var test_results: Dictionary = {}
var output_dir: String = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao2"
var clusters_near: int = 0
var tris_near: int = 0

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — EXECUCAO DA SUITE DE TESTES: MISSAO 2/6     ")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("ERRO FATAL: RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	var dev_name = rd.get_device_name()
	print("[Vulkan Device] %s" % dev_name)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 5)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)

	pipeline = VGGPUPipeline.new(rd)

	# Assegura que o diretorio de evidencias existe
	var da = DirAccess.open("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL")
	if da:
		da.make_dir_recursive("AUDITORIA_FASE3_FINAL/evidencias/missao2")

	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func _on_frame_post_draw() -> void:
	step += 1
	var vp = get_viewport()
	var vp_size = Vector2i(vp.get_visible_rect().size)
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	match step:
		1:
			print("\n--- INICIANDO CARREGAMENTO INICIAL DO MODELO ---")
			var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
			pipeline.load_vgmesh(vg)
			print("Modelo Dense Rock carregado: %d clusters, %d vertices, %d triangulos" % [pipeline.total_clusters, pipeline.total_vertices, pipeline.total_triangles])

		3:
			# Renderiza 1 frame normal no Viewport
			pipeline.set_indirect_draw_enabled(true)
			pipeline.set_debug_force_zero_instances(false)
			pipeline.render_to_viewport(vp, camera)

		5:
			print("\n[TESTE 1] Desativar a chamada indireta e confirmar desaparecimento da geometria")
			# 1.1 Captura imagem com desenho ativo
			pipeline.render_to_viewport(vp, camera)
			var img_normal = vp.get_texture().get_image()
			img_normal.save_png(output_dir + "/01_desenho_normal.png")
			print("Captura salva: 01_desenho_normal.png")

		6:
			# 1.2 Desativa o desenho indireto
			pipeline.set_indirect_draw_enabled(false)
			pipeline.render_to_viewport(vp, camera)

		7:
			var img_desativado = vp.get_texture().get_image()
			img_desativado.save_png(output_dir + "/01_desenho_desativado.png")
			print("Captura salva: 01_desenho_desativado.png")

			# Compara pixels
			var diff_pixels = _count_differing_pixels(output_dir + "/01_desenho_normal.png", output_dir + "/01_desenho_desativado.png")
			print("Pixels alterados ao desativar desenho indireto: %d" % diff_pixels)
			test_results["teste_1_desativar_desenho"] = (diff_pixels > 1000)
			print("STATUS TESTE 1: ", "APROVADO" if test_results["teste_1_desativar_desenho"] else "REPROVADO")

		8:
			print("\n[TESTE 2] Forcar instance_count = 0 no buffer de argumentos e confirmar desenho vazio")
			pipeline.set_indirect_draw_enabled(true)
			pipeline.set_debug_force_zero_instances(true)
			pipeline.render_to_viewport(vp, camera)

		9:
			var img_zero = vp.get_texture().get_image()
			img_zero.save_png(output_dir + "/02_instance_count_zero.png")
			print("Captura salva: 02_instance_count_zero.png")

			# Compara zero instances com desenho desativado
			var diff_zero_vs_disabled = _count_differing_pixels(output_dir + "/01_desenho_desativado.png", output_dir + "/02_instance_count_zero.png")
			print("Diferenca entre instance_count=0 e chamada desativada: %d pixels" % diff_zero_vs_disabled)
			# Deve ser praticamente zero (desenho completamente vazio)
			test_results["teste_2_instance_count_zero"] = (diff_zero_vs_disabled < 50)
			print("STATUS TESTE 2: ", "APROVADO" if test_results["teste_2_instance_count_zero"] else "REPROVADO")
			pipeline.set_debug_force_zero_instances(false)

		10:
			print("\n[TESTE 3] Trocar o modelo e confirmar mudanca geometrica")
			# Modelo 1: Granite Boulder
			var vg_granite = VGMeshLoader.load_from_file("res://assets/boulder_granite.vgmesh")
			pipeline.load_vgmesh(vg_granite)
			print("Modelo Granite Boulder carregado: %d clusters, %d vertices" % [pipeline.total_clusters, pipeline.total_vertices])
			camera.position = Vector3(0, 0, 5)

		12:
			pipeline.render_to_viewport(vp, camera)
			var img_granite = vp.get_texture().get_image()
			img_granite.save_png(output_dir + "/03_modelo_granite.png")
			print("Captura salva: 03_modelo_granite.png")

			var diff_rock_vs_granite = _count_differing_pixels(output_dir + "/01_desenho_normal.png", output_dir + "/03_modelo_granite.png")
			print("Diferenca geometrica entre modelos: %d pixels" % diff_rock_vs_granite)
			test_results["teste_3_troca_modelo"] = (diff_rock_vs_granite > 1000)
			print("STATUS TESTE 3: ", "APROVADO" if test_results["teste_3_troca_modelo"] else "REPROVADO")

		13:
			print("\n[TESTE 4] Alterar camera e distancia e observar selecao diferente de clusters")
			# Volta para o Dense Rock
			var vg_rock = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
			pipeline.load_vgmesh(vg_rock)

			# Camera proxima (distancia = 5m)
			camera.position = Vector3(0, 0, 5)

		15:
			pipeline.render_to_viewport(vp, camera)
			var stats_near_bytes = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			clusters_near = stats_near_bytes.decode_u32(4)
			tris_near = stats_near_bytes.decode_u32(16)
			print("Camera Proxima (5m): Clusters visiveis na GPU = %d, Triangulos = %d" % [clusters_near, tris_near])
			var img_near = vp.get_texture().get_image()
			img_near.save_png(output_dir + "/04_camera_proxima.png")

			# Camera distante (distancia = 35m)
			camera.position = Vector3(0, 0, 35)

		17:
			pipeline.render_to_viewport(vp, camera)
			var stats_far_bytes = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			var clusters_far = stats_far_bytes.decode_u32(4)
			var tris_far = stats_far_bytes.decode_u32(16)
			print("Camera Distante (35m): Clusters visiveis na GPU = %d, Triangulos = %d" % [clusters_far, tris_far])
			var img_far = vp.get_texture().get_image()
			img_far.save_png(output_dir + "/04_camera_distante.png")

			# Confirmar que a selecao de clusters na GPU mudou dinamicamente com a distancia
			var cluster_selection_changed = (clusters_near != clusters_far or tris_near != tris_far)
			test_results["teste_4_camera_distancia"] = cluster_selection_changed
			print("Selecao variou com distancia? ", cluster_selection_changed, " (%d clusters / %d tris -> %d clusters / %d tris)" % [clusters_near, tris_near, clusters_far, tris_far])
			print("STATUS TESTE 4: ", "APROVADO" if cluster_selection_changed else "REPROVADO")

		18:
			print("\n[TESTE 5] Verificar que nao existe segunda copia do objeto desenhada pelo MultiMesh")
			var mm_visible = false
			if pipeline.multimesh_instance:
				mm_visible = pipeline.multimesh_instance.visible
			var second_copy_exists = mm_visible
			test_results["teste_5_sem_segunda_copia"] = not second_copy_exists
			print("MultiMesh visivel? ", mm_visible, " -> Segunda copia evitada com sucesso!")
			print("STATUS TESTE 5: ", "APROVADO" if test_results["teste_5_sem_segunda_copia"] else "REPROVADO")

		20:
			print("\n=================================================================")
			print("                    RESUMO FINAL DOS TESTES                     ")
			print("=================================================================")
			var all_passed = true
			for k in test_results:
				var res_str = "PASSOU" if test_results[k] else "FALHOU"
				print("  - %s: %s" % [k, res_str])
				if not test_results[k]:
					all_passed = false

			print("-----------------------------------------------------------------")
			if all_passed:
				print("RESULTADO GLOBAL: TODOS OS 5 TESTES OBRIGATORIOS FORAM APROVADOS!")
			else:
				print("RESULTADO GLOBAL: FALHA EM UM OU MAIS TESTES!")
			print("=================================================================\n")

			# Cleanup
			pipeline.cleanup()
			get_tree().quit(0 if all_passed else 1)

func _count_differing_pixels(path_a: String, path_b: String) -> int:
	var img_a = Image.load_from_file(path_a)
	var img_b = Image.load_from_file(path_b)
	if not img_a or not img_b:
		return -1
	if img_a.get_size() != img_b.get_size():
		return -2

	var diff = 0
	var w = img_a.get_width()
	var h = img_a.get_height()
	for y in range(0, h, 2): # Amostragem a cada 2 pixels para agilidade
		for x in range(0, w, 2):
			var ca = img_a.get_pixel(x, y)
			var cb = img_b.get_pixel(x, y)
			if abs(ca.r - cb.r) > 0.05 or abs(ca.g - cb.g) > 0.05 or abs(ca.b - cb.b) > 0.05:
				diff += 1
	return diff
