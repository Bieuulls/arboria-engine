extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

func _init():
	print("=================================================================")
	print("TESTE UNITARIO DO PIPELINE DE GPU REAL (VULKAN COMPUTE & GODOT)")
	print("=================================================================")
	
	var data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	if data.is_empty():
		push_error("ERRO: Falha ao carregar .vgmesh!")
		quit(1)
		return
		
	var pipeline = VGGPUPipeline.new()
	var ok = pipeline.load_vgmesh(data)
	print("1. Carga de buffers de GPU e texturas: ", "SUCESSO" if ok else "FALHOU")
	if not ok:
		push_error("ERRO: Falha ao inicializar pipeline!")
		quit(1)
		return
		
	var all_passed = true

	# Simula Camera3D
	var cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 500.0
	
	# Teste A: Camera olhando para o objeto a 8 metros
	cam.transform = Transform3D.IDENTITY.translated(Vector3(0, 0, 8.0))
	pipeline.dispatch_culling(cam, Vector2(1280, 720), 1.5, 0, 0, true, false, true)
	pipeline.poll_stats_async()
	var stats_a = pipeline.get_stats()
	print("\n2. Teste Culling A (Camera a 8m de frente):")
	print("   -> Clusters Visiveis: ", stats_a["visible_clusters"], " / ", stats_a["total_clusters"])
	print("   -> Triangulos Selecionados: ", stats_a["triangles_drawn"])
	print("   -> Tempo GPU: ", stats_a["gpu_time_us"], " us")
	print("   -> VRAM Alocada: ", stats_a["vram_kb"], " KB")
	if stats_a["visible_clusters"] == 0:
		all_passed = false
		push_error("FALHA: Teste A retornou 0 clusters visiveis")
	
	# Teste B: Camera dando zoom out (a 60 metros) -> erro de tela diminui e seleciona niveis mais grossos
	cam.transform = Transform3D.IDENTITY.translated(Vector3(0, 0, 60.0))
	pipeline.dispatch_culling(cam, Vector2(1280, 720), 1.5, 0, 0, true, false, true)
	pipeline.poll_stats_async()
	var stats_b = pipeline.get_stats()
	var lod_reduced = stats_b["triangles_drawn"] < stats_a["triangles_drawn"]
	print("\n3. Teste LOD B (Camera distante a 60m):")
	print("   -> Clusters Visiveis: ", stats_b["visible_clusters"], " / ", stats_b["total_clusters"])
	print("   -> Triangulos Selecionados: ", stats_b["triangles_drawn"])
	print("   -> Reducao de geometria confirmada: ", lod_reduced)
	if not lod_reduced:
		all_passed = false
		push_error("FALHA: Teste B esperava reducao de triangulos")
	
	# Teste C: Camera virada para tras (Frustum Culling 100%)
	cam.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 8.0))
	pipeline.dispatch_culling(cam, Vector2(1280, 720), 1.5, 0, 0, true, false, true)
	pipeline.poll_stats_async()
	var stats_c = pipeline.get_stats()
	var culled_ok = (stats_c["visible_clusters"] == 0)
	print("\n4. Teste Frustum Culling C (Camera virada de costas):")
	print("   -> Clusters Visiveis: ", stats_c["visible_clusters"], " / ", stats_c["total_clusters"])
	print("   -> Culling 100% eficaz confirmado: ", culled_ok)
	if not culled_ok:
		all_passed = false
		push_error("FALHA: Teste C esperava 0 clusters visiveis")
	
	pipeline.cleanup()
	print("\n=================================================================")
	if all_passed:
		print("✅ TODOS OS TESTES UNITARIOS DO PIPELINE GPU FORAM APROVADOS!")
		print("=================================================================")
		quit(0)
	else:
		print("❌ TESTES FALHARAM!")
		print("=================================================================")
		quit(1)
