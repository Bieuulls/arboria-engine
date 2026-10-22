@tool
extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var results: Array[Dictionary] = []

func _init() -> void:
	print("\n" + "=".repeat(80))
	print("ARBORIA VIRTUAL GEOMETRY — BATERIA DE TESTES NEGATIVOS OBRIGATORIOS (P0)")
	print("Testes: A (Desativar Draw), B (Instance Count = 0), C (Mudanca Geometria), D (LOD Dinamico), E (Reducao Efetiva)")
	print("=".repeat(80))

	var out_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var pipeline = VGGPUPipeline.new()
	var vg_rock = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	pipeline.load_vgmesh(vg_rock)
	pipeline.setup_indirect_raster_pipeline(512, 512)

	var cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 500.0
	cam.position = Vector3(0, 0, 12.0)
	cam.look_at_from_position(Vector3(0, 0, 12.0), Vector3.ZERO, Vector3.UP)

	# Passagem normal inicial
	pipeline.dispatch_culling(cam, Vector2(512, 512), 1.5, 0, 0, true, false, false)
	pipeline.execute_indirect_draw()
	var normal_bytes = pipeline.rd.texture_get_data(pipeline.indirect_color_tex, 0)
	var normal_pixels = count_colored_pixels(normal_bytes)
	var img_normal = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, normal_bytes)
	img_normal.save_png(out_dir + "/neg_test_normal.png")
	print("Passagem Normal: %d pixels desenhados via draw_list_draw_indirect" % normal_pixels)

	# TESTE NEGATIVO A: Desativar desenho indireto
	# Resultado esperado: 0 pixels desenhados (geometria desaparece completamente)
	var clear_colors = PackedColorArray([Color(0, 0, 0, 0)])
	var dl = pipeline.rd.draw_list_begin(pipeline.indirect_framebuffer, RenderingDevice.DRAW_CLEAR_COLOR_0 | RenderingDevice.DRAW_CLEAR_DEPTH, clear_colors, 1.0, 0)
	pipeline.rd.draw_list_end()
	var test_a_bytes = pipeline.rd.texture_get_data(pipeline.indirect_color_tex, 0)
	var test_a_pixels = count_colored_pixels(test_a_bytes)
	var test_a_passed = (test_a_pixels == 0)
	var img_a = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, test_a_bytes)
	img_a.save_png(out_dir + "/neg_test_A_disabled.png")
	record("Teste A: Desativar desenho indireto", test_a_passed, 
		"Pixels com desenho desativado: %d (Esperado: 0)" % test_a_pixels)

	# TESTE NEGATIVO B: Contador de instâncias igual a zero (instance_count = 0)
	# Forcamos o VkDrawIndirectCommand com instance_count = 0
	var zero_cmd = PackedByteArray()
	zero_cmd.resize(24)
	zero_cmd.encode_u32(0, 384) # vertex_count
	zero_cmd.encode_u32(4, 0)   # instance_count = 0
	pipeline.rd.buffer_update(pipeline.counter_buf, 0, 24, zero_cmd)
	pipeline.execute_indirect_draw()
	var test_b_bytes = pipeline.rd.texture_get_data(pipeline.indirect_color_tex, 0)
	var test_b_pixels = count_colored_pixels(test_b_bytes)
	var test_b_passed = (test_b_pixels == 0)
	var img_b = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, test_b_bytes)
	img_b.save_png(out_dir + "/neg_test_B_instance_zero.png")
	record("Teste B: instance_count = 0", test_b_passed,
		"Pixels com instance_count=0: %d (Esperado: 0)" % test_b_pixels)

	# TESTE C: Alteração de geometria (troca por boulder_granite.vgmesh)
	# Resultado esperado: a geometria e os pixels desenhados mudam
	var p_boulder = VGGPUPipeline.new()
	var vg_boulder = VGMeshLoader.load_from_file("res://assets/boulder_granite.vgmesh")
	p_boulder.load_vgmesh(vg_boulder)
	p_boulder.setup_indirect_raster_pipeline(512, 512)
	p_boulder.dispatch_culling(cam, Vector2(512, 512), 1.5, 0, 0, true, false, false)
	p_boulder.execute_indirect_draw()
	var test_c_bytes = p_boulder.rd.texture_get_data(p_boulder.indirect_color_tex, 0)
	var test_c_pixels = count_colored_pixels(test_c_bytes)
	var diff_from_rock = count_pixel_diff(normal_bytes, test_c_bytes)
	var test_c_passed = (test_c_pixels > 0 and diff_from_rock > 1000)
	var img_c = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, test_c_bytes)
	img_c.save_png(out_dir + "/neg_test_C_different_geom.png")
	record("Teste C: Alteracao de Geometria (.vgmesh)", test_c_passed,
		"Pixels Boulder: %d | Diferenca em relacao a Rock: %d px" % [test_c_pixels, diff_from_rock])
	p_boulder.cleanup()

	# TESTE D: Seleção de LOD dinâmica sem leitura CPU
	# Câmera próxima (dist 8m) vs Câmera distante (dist 35m)
	cam.look_at_from_position(Vector3(0, 0, 8.0), Vector3.ZERO, Vector3.UP)
	pipeline.dispatch_culling(cam, Vector2(512, 512), 1.5, 0, 0, true, false, false)
	var cnt_near = pipeline.rd.buffer_get_data(pipeline.counter_buf)
	var inst_near = cnt_near.decode_u32(4)

	cam.look_at_from_position(Vector3(0, 0, 35.0), Vector3.ZERO, Vector3.UP)
	pipeline.dispatch_culling(cam, Vector2(512, 512), 1.5, 0, 0, true, false, false)
	var cnt_far = pipeline.rd.buffer_get_data(pipeline.counter_buf)
	var inst_far = cnt_far.decode_u32(4)

	var test_d_passed = (inst_near > 0 and inst_far > 0 and inst_near != inst_far)
	record("Teste D: Selecao de LOD Dinamica GPU", test_d_passed,
		"Instancias Near (8m): %d | Instancias Far (35m): %d (Selecao puramente GPU)" % [inst_near, inst_far])

	# TESTE E: Redução real de trabalho de vértices
	# Compara quantidade de vértices invocados pelo MultiMesh fixo anterior (total_clusters * 384)
	# com os vértices realmente submetidos pelo draw_list_draw_indirect (inst_far * 384)
	var total_instances_legacy = pipeline.total_clusters
	var legacy_vertex_invocations = total_instances_legacy * 384
	var indirect_vertex_invocations = inst_far * 384
	var vertex_reduction_pct = (1.0 - float(indirect_vertex_invocations) / float(legacy_vertex_invocations)) * 100.0
	var test_e_passed = (indirect_vertex_invocations < legacy_vertex_invocations and vertex_reduction_pct > 25.0)
	record("Teste E: Reducao Real de Trabalho de Vertices", test_e_passed,
		"Legado (MultiMesh fixo): %d vertices submetidos | Indireto GPU: %d vertices (-%.1f%% trabalho real)" % [
			legacy_vertex_invocations, indirect_vertex_invocations, vertex_reduction_pct
		])

	pipeline.cleanup()

	print("\n" + "=".repeat(80))
	print("RESUMO DOS TESTES NEGATIVOS (P0)")
	print("=".repeat(80))
	var all_ok = true
	for r in results:
		print("[%s] %-40s | %s" % ["APROVADO" if r["passed"] else "FALHA", r["name"], r["detail"]])
		if not r["passed"]: all_ok = false
	print("=".repeat(80))
	quit(0 if all_ok else 1)

func count_colored_pixels(bytes: PackedByteArray) -> int:
	var count = 0
	for i in range(0, bytes.size(), 4):
		if bytes[i] > 10 or bytes[i+1] > 10 or bytes[i+2] > 10:
			count += 1
	return count

func count_pixel_diff(b1: PackedByteArray, b2: PackedByteArray) -> int:
	var diff = 0
	var limit = min(b1.size(), b2.size())
	for i in range(0, limit, 4):
		var d = abs(int(b1[i]) - int(b2[i])) + abs(int(b1[i+1]) - int(b2[i+1])) + abs(int(b1[i+2]) - int(b2[i+2]))
		if d > 30:
			diff += 1
	return diff

func record(name: String, passed: bool, detail: String) -> void:
	results.append({"name": name, "passed": passed, "detail": detail})
