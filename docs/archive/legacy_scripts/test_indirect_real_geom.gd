@tool
extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

func _init() -> void:
	print("--- TESTANDO RENDERIZACAO INDIRETA REAL DE GEOMETRIA .VGMESH ---")
	var vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var pipeline = VGGPUPipeline.new()
	var ok = pipeline.load_vgmesh(vg_data)
	print("Pipeline carregado:", ok)

	# Setup camera
	var cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 500.0
	cam.position = Vector3(0, 0, 12.0)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	# Dispatch culling
	pipeline.dispatch_culling(cam, Vector2(512, 512), 1.5, 0, 0, true, false, false)

	# Read counter_buf to inspect instance_count
	var rd = pipeline.rd
	var cnt_data = rd.buffer_get_data(pipeline.counter_buf)
	var v_count = cnt_data.decode_u32(0)
	var inst_count = cnt_data.decode_u32(4)
	print("VkDrawIndirectCommand: vertex_count=%d, instance_count=%d" % [v_count, inst_count])

	# Test setup of real raster pipeline
	pipeline.setup_indirect_raster_pipeline(512, 512)
	pipeline.execute_indirect_draw()
	print("execute_indirect_draw() executado com sucesso!")

	# Readback target texture to verify rendered pixels
	var rendered_bytes = rd.texture_get_data(pipeline.indirect_color_tex, 0)
	var non_zero = 0
	for i in range(0, rendered_bytes.size(), 4):
		if rendered_bytes[i] > 10 or rendered_bytes[i+1] > 10 or rendered_bytes[i+2] > 10:
			non_zero += 1
	print("Pixels reais renderizados no target via draw_list_draw_indirect:", non_zero)

	# Salva imagem de evidencia
	var img = Image.create_from_data(512, 512, false, Image.FORMAT_RGBA8, rendered_bytes)
	DirAccess.make_dir_recursive_absolute("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias")
	img.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/indirect_draw_real_geom.png")
	print("Evidencia salva em: AUDITORIA_FASE3_FINAL/evidencias/indirect_draw_real_geom.png")

	pipeline.cleanup()
	quit(0 if non_zero > 1000 else 1)
