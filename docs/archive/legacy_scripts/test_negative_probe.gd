extends Node3D

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var camera: Camera3D
var rd: RenderingDevice
var model_ref_instance: MeshInstance3D

var frame = 0

func _ready():
	rd = RenderingServer.get_rendering_device()
	print("Hardware GPU: ", rd.get_device_name() if rd else "NULL")
	
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 7)
	camera.current = true
	add_child(camera)
	
	var vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 1) # Vermelho puro
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	model_ref_instance.material_override = mat
	add_child(model_ref_instance)
	
	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)
	
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame():
	frame += 1
	var vp = get_viewport()
	print("\n--- FRAME ", frame, " ---")
	
	if frame == 2:
		# Frame 2: Model ref esta visivel
		var img = vp.get_texture().get_image()
		var red_cnt = count_color(img, Color(1, 0, 0, 1))
		print("Frame 2 (Ref Visivel): Red pixels = ", red_cnt)
		img.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame2_ref_visible.png")
		
		# Oculta referencia para frame 3
		print("Ocultando model_ref_instance.visible = false")
		model_ref_instance.visible = false
		
	elif frame == 3:
		# Frame 3: Model ref esta OCULTO, sem pipeline.render_to_viewport
		var img = vp.get_texture().get_image()
		var red_cnt = count_color(img, Color(1, 0, 0, 1))
		print("Frame 3 (Ref Oculto, sem ARBORIA): Red pixels = ", red_cnt)
		img.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame3_ref_hidden.png")
		
		# Agora dispara ARBORIA com modo cluster debug (cores variadas)
		print("Chamando pipeline.render_to_viewport(shading_mode=3)...")
		pipeline.render_to_viewport(vp, camera, Transform3D.IDENTITY, 1.5, 1, 0, true, false, true, 3)
		var img_after_draw = vp.get_texture().get_image()
		var red_after = count_color(img_after_draw, Color(1, 0, 0, 1))
		print("Frame 3 (Imediatamente apos render_to_viewport): Red pixels = ", red_after)
		img_after_draw.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame3_after_arboria.png")
		
	elif frame == 4:
		# Frame 4: Frame seguinte apos render_to_viewport
		var img = vp.get_texture().get_image()
		print("Frame 4 (Proximo frame): Total non-black pixels = ", count_non_black(img))
		img.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame4.png")
		get_tree().quit()

func count_color(img: Image, target: Color) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if abs(c.r - target.r) < 0.1 and abs(c.g - target.g) < 0.1 and abs(c.b - target.b) < 0.1:
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
