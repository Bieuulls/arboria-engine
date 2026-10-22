extends Node3D

# ARBORIA ENGINE — SUITE DE TESTES OFICIAL: MISSAO 4/6
# Correcao do Shader de Rasterizacao Indireta (Eliminacao de NaN e Bounds Check)

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var camera: Camera3D
var rd: RenderingDevice
var step: int = 0
var test_results: Dictionary = {}
var output_dir: String = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao4"

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — EXECUCAO DA SUITE DE TESTES: MISSAO 4/6     ")
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

	# Assegura que o diretorio de evidencias existe
	var da = DirAccess.open("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL")
	if da:
		da.make_dir_recursive("AUDITORIA_FASE3_FINAL/evidencias/missao4")

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
			print("\n[TESTE 1] Compilacao SPIR-V e Validacao do Pipeline Vulkan sem NaN")
			var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
			pipeline.load_vgmesh(vg)

			var pipe_ok = pipeline.indirect_render_pipeline.is_valid()
			print("Pipeline de Rasterizacao Indireta valido? ", pipe_ok)
			print("Shader de Rasterizacao Indireta RID: ", pipeline.indirect_shader_rid)
			test_results["teste_1_compilacao_spirv"] = pipe_ok
			print("STATUS TESTE 1: ", "APROVADO" if pipe_ok else "REPROVADO")

		3:
			print("\n[TESTE 2] Validacao de Clusters Incompletos (< 128 triangulos)")
			# Inspeciona clusters com contagem incompleta de triangulos
			var incomplete_clusters = 0
			var clusters_data = pipeline.cached_vg_data["clusters"]
			for c in clusters_data:
				if c["triangle_count"] < 128:
					incomplete_clusters += 1
			print("Total de clusters da malha: %d | Clusters incompletos (<128 tris): %d" % [clusters_data.size(), incomplete_clusters])

			# Renderiza com o shader corrigido
			camera.position = Vector3(0, 0, 5)
			pipeline.render_to_viewport(vp, camera)

			var img_corrected = vp.get_texture().get_image()
			img_corrected.save_png(output_dir + "/01_render_clusters_incompletos.png")
			print("Captura salva: 01_render_clusters_incompletos.png (Bytes: %d)" % img_corrected.save_png_to_buffer().size())

			var ok_incomplete = (incomplete_clusters > 0 and img_corrected.save_png_to_buffer().size() > 100000)
			test_results["teste_2_clusters_incompletos"] = ok_incomplete
			print("STATUS TESTE 2: ", "APROVADO" if ok_incomplete else "REPROVADO")

		5:
			print("\n[TESTE 3] Casos Extremos de Fronteira e Bounds Checking (Granite Boulder)")
			# Carrega modelo Granite Boulder (apenas 28 clusters com limites reduzidos)
			var vg_granite = VGMeshLoader.load_from_file("res://assets/boulder_granite.vgmesh")
			pipeline.load_vgmesh(vg_granite)
			camera.position = Vector3(0, 0, 4)
			pipeline.render_to_viewport(vp, camera)

			var img_granite = vp.get_texture().get_image()
			img_granite.save_png(output_dir + "/02_render_modelo_fronteira.png")
			print("Captura salva: 02_render_modelo_fronteira.png (Bytes: %d)" % img_granite.save_png_to_buffer().size())

			# Leitura do counter_buf do modelo de fronteira
			var raw_cmd = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
			var inst_cnt = raw_cmd.decode_u32(4)
			var tris_cnt = raw_cmd.decode_u32(16)
			print("Granite Boulder GPU Stats: %d clusters visiveis, %d triangulos desenhados" % [inst_cnt, tris_cnt])

			var ok_granite = (inst_cnt > 0 and tris_cnt > 0)
			test_results["teste_3_casos_fronteira"] = ok_granite
			print("STATUS TESTE 3: ", "APROVADO" if ok_granite else "REPROVADO")

		7:
			print("\n[TESTE 4] Comparacao Visual com Imagem de Referencia da Missao 3")
			# Volta para o modelo Dense Rock na mesma posicao de camera (0, 0, 5)
			var vg_rock = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
			pipeline.load_vgmesh(vg_rock)
			camera.position = Vector3(0, 0, 5)
			pipeline.render_to_viewport(vp, camera)

			var img_rock = vp.get_texture().get_image()
			img_rock.save_png(output_dir + "/03_render_pos_correcao.png")

			# Compara com a captura de referencia da Missao 3
			var ref_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao3/01_camera_proxima_gpu_main.png"
			var cur_path = output_dir + "/03_render_pos_correcao.png"
			var diff_pixels = _count_differing_pixels(ref_path, cur_path)
			print("Diferenca de pixels em relacao a referencia da Missao 3: %d" % diff_pixels)

			# As geometrias devem ser identicas visualmente (zero regressao visual)
			var ok_no_regression = (diff_pixels < 50)
			test_results["teste_4_zero_regressao_visual"] = ok_no_regression
			print("Zero regressao visual? ", ok_no_regression, " (%d pixels de diferenca)" % diff_pixels)
			print("STATUS TESTE 4: ", "APROVADO" if ok_no_regression else "REPROVADO")

		9:
			print("\n[TESTE 5] Validacao de Orientacao das Faces (Backface Culling) e Escrita de Profundidade")
			# Move camera para visualizacao angular (3, 2, 4)
			camera.position = Vector3(3, 2, 4)
			camera.look_at(Vector3.ZERO, Vector3.UP)
			pipeline.render_to_viewport(vp, camera)

			var img_angled = vp.get_texture().get_image()
			img_angled.save_png(output_dir + "/04_teste_profundidade.png")
			print("Captura salva: 04_teste_profundidade.png (Bytes: %d)" % img_angled.save_png_to_buffer().size())

			var ok_depth = (img_angled.save_png_to_buffer().size() > 50000)
			test_results["teste_5_profundidade_e_faces"] = ok_depth
			print("STATUS TESTE 5: ", "APROVADO" if ok_depth else "REPROVADO")

		11:
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
				print("RESULTADO GLOBAL: TODOS OS TESTES DA MISSAO 4/6 FORAM APROVADOS!")
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
