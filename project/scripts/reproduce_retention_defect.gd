extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

func _init():
	var rd = RenderingServer.get_rendering_device()
	if not rd:
		print("FAIL: No RD")
		quit(1)
		return
		
	var vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)
	
	# Criando um SubViewport com UPDATE_DISABLED para simular framebuffer reutilizado sem Godot limpando
	var sv = SubViewport.new()
	sv.size = Vector2i(512, 512)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(sv)
	
	var cam = Camera3D.new()
	cam.position = Vector3(0, 0, 7)
	cam.current = true
	sv.add_child(cam)
	
	# Passo 1: Desenho ARBORIA habilitado
	pipeline.set_indirect_draw_enabled(true)
	pipeline.render_to_viewport(sv, cam, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
	var img1 = sv.get_texture().get_image()
	var cnt1 = count_non_black(img1)
	print("Passo 1 (ARBORIA Ativo): Pixels nao-pretos = ", cnt1)
	
	# Passo 2: Desligando ARBORIA (enable_indirect_draw = false)
	pipeline.set_indirect_draw_enabled(false)
	pipeline.render_to_viewport(sv, cam, Transform3D.IDENTITY, 1.5, 1, 0, true, false, false, 0)
	var img2 = sv.get_texture().get_image()
	var cnt2 = count_non_black(img2)
	print("Passo 2 (ARBORIA Desativado): Pixels nao-pretos = ", cnt2)
	
	if cnt2 > 0:
		print("DEFEITO REPRODUZIDO: Pixels anteriores vazaram/permaneceram retidos quando ARBORIA foi desativado (cnt2 = %d)!" % cnt2)
	else:
		print("Buffer estava limpo.")
	quit(0)

func count_non_black(img: Image) -> int:
	if not img: return 0
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if c.r > 0.05 or c.g > 0.05 or c.b > 0.05:
				cnt += 1
	return cnt
