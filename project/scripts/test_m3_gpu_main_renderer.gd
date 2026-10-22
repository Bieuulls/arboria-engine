extends Node3D

# ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 3/6
# Substituicao do MultiMesh como Caminho Principal pelo Renderizador GPU Indireto

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var camera: Camera3D
var rd: RenderingDevice
var step: int = 0
var test_results: Dictionary = {}
var output_dir: String = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao3"

# Dados medidos de hardware
var stats_near: Dictionary = {}
var stats_far: Dictionary = {}

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — EXECUCAO DA SUITE DE TESTES: MISSAO 3/6     ")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	print("[Hardware GPU] %s" % rd.get_device_name())

	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 5)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)

	# Assegura que o diretorio de evidencias da missao 3 existe
	var da = DirAccess.open("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL")
	if da:
		da.make_dir_recursive("AUDITORIA_FASE3_FINAL/evidencias/missao3")

	pipeline = VGGPUPipeline.new(rd)
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)

func _on_frame_post_draw() -> void:
	step += 1
	var vp = get_viewport()
	var vp_size = Vector2i(vp.get_visible_rect().size)
	if vp_size.x <= 0 or vp_size.y <= 0:
		return

	match step:
		1:
			print("\n--- INICIALIZANDO CARREGAMENTO NO CAMINHO PRINCIPAL (GPU PURO) ---")
			var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
			pipeline.load_vgmesh(vg)

		3:
			print("\n[PROVA 1] Verificacao de ausencia do MultiMesh no Caminho Principal")
			var mm_is_null = (pipeline.multimesh == null)
			var mmi_is_null = (pipeline.multimesh_instance == null)
			print("MultiMesh alocado no caminho principal? ", not mm_is_null)
			print("MultiMeshInstance3D alocado no caminho principal? ", not mmi_is_null)
			test_results["prova_1_multimesh_desacoplado"] = (mm_is_null and mmi_is_null)
			print("STATUS PROVA 1: ", "APROVADO" if test_results["prova_1_multimesh_desacoplado"] else "REPROVADO")

		5:
			print("\n[PROVA 2] Renderizacao com Camera Proxima (5m) exclusivamente via GPU Indirect")
			camera.position = Vector3(0, 0, 5)
			pipeline.render_to_viewport(vp, camera)

			# Leitura direta do buffer de argumentos indiretos gerado pela GPU (VkDrawIndirectCommand)
			var raw_cmd = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			stats_near["vertex_count"] = raw_cmd.decode_u32(0)
			stats_near["instance_count"] = raw_cmd.decode_u32(4)
			stats_near["first_vertex"] = raw_cmd.decode_u32(8)
			stats_near["first_instance"] = raw_cmd.decode_u32(12)
			stats_near["total_triangles"] = raw_cmd.decode_u32(16)
			stats_near["total_evaluated"] = raw_cmd.decode_u32(20)

			pipeline.poll_timestamps()
			stats_near["gpu_time_us"] = pipeline.stat_gpu_time_us

			print("VkDrawIndirectCommand da GPU (Camera 5m):")
			print("  - vertex_count:   %d (384 vertices por cluster)" % stats_near["vertex_count"])
			print("  - instance_count: %d (clusters visiveis compactados pela GPU)" % stats_near["instance_count"])
			print("  - first_vertex:   %d" % stats_near["first_vertex"])
			print("  - first_instance: %d" % stats_near["first_instance"])
			print("  - triangulos:     %d" % stats_near["total_triangles"])
			print("  - clusters total: %d" % stats_near["total_evaluated"])
			print("  - tempo GPU:      %.2f us" % stats_near["gpu_time_us"])

			var img_near = vp.get_texture().get_image()
			img_near.save_png(output_dir + "/01_camera_proxima_gpu_main.png")
			print("Captura salva: 01_camera_proxima_gpu_main.png (Bytes: %d)" % img_near.save_png_to_buffer().size())

		7:
			print("\n[PROVA 3] Renderizacao com Camera Distante (35m) exclusivamente via GPU Indirect")
			camera.position = Vector3(0, 0, 35)
			pipeline.render_to_viewport(vp, camera)

			# Leitura direta do buffer de argumentos indiretos gerado pela GPU para camera distante
			var raw_cmd_far = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			stats_far["vertex_count"] = raw_cmd_far.decode_u32(0)
			stats_far["instance_count"] = raw_cmd_far.decode_u32(4)
			stats_far["first_vertex"] = raw_cmd_far.decode_u32(8)
			stats_far["first_instance"] = raw_cmd_far.decode_u32(12)
			stats_far["total_triangles"] = raw_cmd_far.decode_u32(16)
			stats_far["total_evaluated"] = raw_cmd_far.decode_u32(20)

			pipeline.poll_timestamps()
			stats_far["gpu_time_us"] = pipeline.stat_gpu_time_us

			print("VkDrawIndirectCommand da GPU (Camera 35m):")
			print("  - vertex_count:   %d" % stats_far["vertex_count"])
			print("  - instance_count: %d (clusters visiveis compactados pela GPU)" % stats_far["instance_count"])
			print("  - first_vertex:   %d" % stats_far["first_vertex"])
			print("  - first_instance: %d" % stats_far["first_instance"])
			print("  - triangulos:     %d" % stats_far["total_triangles"])
			print("  - clusters total: %d" % stats_far["total_evaluated"])
			print("  - tempo GPU:      %.2f us" % stats_far["gpu_time_us"])

			var img_far = vp.get_texture().get_image()
			img_far.save_png(output_dir + "/02_camera_distante_gpu_main.png")
			print("Captura salva: 02_camera_distante_gpu_main.png (Bytes: %d)" % img_far.save_png_to_buffer().size())

			# Validacao da diferenca medida
			var selection_changed = (stats_near["instance_count"] != stats_far["instance_count"] and stats_far["instance_count"] < stats_near["instance_count"])
			test_results["prova_3_comparacao_distancia"] = selection_changed
			print("Selecao variou com distancia? ", selection_changed, " (%d -> %d clusters)" % [stats_near["instance_count"], stats_far["instance_count"]])
			print("STATUS PROVA 3: ", "APROVADO" if selection_changed else "REPROVADO")

		9:
			print("\n[PROVA 4] Teste Negativo: Desativar desenho indireto e verificar tela vazia")
			camera.position = Vector3(0, 0, 5)
			# Desativa o Indirect Draw
			pipeline.set_indirect_draw_enabled(false)
			# Limpa o framebuffer para verificar se algo alheio desenha
			var clear_colors = PackedColorArray([Color(0, 0, 0, 1)])
			var draw_list = rd.draw_list_begin(pipeline.vp_framebuffer, RenderingDevice.DRAW_CLEAR_COLOR_0 | RenderingDevice.DRAW_CLEAR_DEPTH, clear_colors, 1.0, 0)
			rd.draw_list_end()
			pipeline.render_to_viewport(vp, camera)

			var img_disabled = vp.get_texture().get_image()
			img_disabled.save_png(output_dir + "/03_teste_negativo_desativado.png")
			print("Captura salva: 03_teste_negativo_desativado.png")

			var diff_pixels = _count_differing_pixels(output_dir + "/01_camera_proxima_gpu_main.png", output_dir + "/03_teste_negativo_desativado.png")
			print("Pixels apagados ao desativar Indirect Draw: %d" % diff_pixels)
			test_results["prova_4_teste_negativo"] = (diff_pixels > 5000)
			print("STATUS PROVA 4: ", "APROVADO" if test_results["prova_4_teste_negativo"] else "REPROVADO")
			pipeline.set_indirect_draw_enabled(true)

		11:
			print("\n[PROVA 5] Verificacao do Fallback de Diagnostico MultiMesh sob demanda")
			var mm = pipeline.setup_multimesh_fallback()
			var fallback_ok = (mm != null and mm.multimesh != null and pipeline.multimesh_fallback_enabled)
			print("MultiMesh Fallback criado sob demanda com sucesso? ", fallback_ok)
			print("Total de instâncias alocadas no fallback: ", mm.multimesh.instance_count)
			test_results["prova_5_fallback_sob_demanda"] = fallback_ok
			print("STATUS PROVA 5: ", "APROVADO" if fallback_ok else "REPROVADO")
			pipeline.disable_multimesh_fallback()

		13:
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
				print("RESULTADO GLOBAL: TODOS OS TESTES DA MISSAO 3/6 FORAM APROVADOS!")
			else:
				print("RESULTADO GLOBAL: FALHA EM UM OU MAIS TESTES!")
			print("=================================================================\n")

			pipeline.destroy()
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
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca = img_a.get_pixel(x, y)
			var cb = img_b.get_pixel(x, y)
			if abs(ca.r - cb.r) > 0.05 or abs(ca.g - cb.g) > 0.05 or abs(ca.b - cb.b) > 0.05:
				diff += 1
	return diff
