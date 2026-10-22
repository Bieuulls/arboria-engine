extends Node3D

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice

var subview_ref: SubViewport
var subview_arb: SubViewport
var cam_ref: Camera3D
var cam_arb: Camera3D
var model_ref_instance: MeshInstance3D
var vg_data: Dictionary

var step = 0

func _ready():
	rd = RenderingServer.get_rendering_device()
	vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	
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
	cam_ref.near = 0.05
	cam_ref.far = 300.0
	cam_ref.fov = 60.0
	cam_ref.current = true
	subview_ref.add_child(cam_ref)
	
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.82, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	model_ref_instance.material_override = mat
	subview_ref.add_child(model_ref_instance)
	add_child(subview_ref)
	
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
	cam_arb.near = 0.05
	cam_arb.far = 300.0
	cam_arb.fov = 60.0
	cam_arb.current = true
	subview_arb.add_child(cam_arb)
	add_child(subview_arb)
	
	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)
	
	# Posição de câmera do caso 02_intermediaria: Dist: 18m, Yaw: 30°, Pitch: 10°
	var dist = 18.0
	var yaw = deg_to_rad(30.0)
	var pitch = deg_to_rad(10.0)
	var pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
	cam_ref.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	cam_arb.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame():
	step += 1
	if step == 2:
		# Captura Ref do Godot
		var img_ref = subview_ref.get_texture().get_image()
		
		# Renderiza ARBORIA com lod_mode = 0 (DAG automática)
		pipeline.set_indirect_draw_enabled(true)
		pipeline.render_to_viewport(subview_arb, cam_arb, Transform3D.IDENTITY, 1.5, 0, 0, true, false, false, 0)
		var img_arb = subview_arb.get_texture().get_image()
		
		# Compara Ref vs Arb
		var w = img_ref.get_width()
		var h = img_ref.get_height()
		var ref_cnt = 0
		var arb_cnt = 0
		var inter_cnt = 0
		var union_cnt = 0
		var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		
		for y in range(h):
			for x in range(w):
				var cr = img_ref.get_pixel(x, y)
				var ca = img_arb.get_pixel(x, y)
				var ir = (cr.r > 0.05 or cr.g > 0.05 or cr.b > 0.05)
				var ia = (ca.r > 0.05 or ca.g > 0.05 or ca.b > 0.05)
				if ir: ref_cnt += 1
				if ia: arb_cnt += 1
				if ir and ia:
					inter_cnt += 1
					diff_img.set_pixel(x, y, Color(0, 1, 0, 1)) # Verde = match
				elif ir and not ia:
					diff_img.set_pixel(x, y, Color(1, 0, 1, 1)) # Magenta = faltando no Arb
				elif ia and not ir:
					diff_img.set_pixel(x, y, Color(0, 0, 1, 1)) # Azul = excesso no Arb
				else:
					diff_img.set_pixel(x, y, Color(0, 0, 0, 1))
				if ir or ia: union_cnt += 1
				
		var iou = float(inter_cnt) / float(union_cnt) if union_cnt > 0 else 0.0
		var min_max = float(mini(ref_cnt, arb_cnt)) / float(maxi(ref_cnt, arb_cnt)) if maxi(ref_cnt, arb_cnt) > 0 else 0.0
		
		print("\n=== RESULTADO INVESTIGAÇÃO LOD MISTO (DAG AUTO) ===")
		print("Ref Pixels: %d | Arb Pixels: %d" % [ref_cnt, arb_cnt])
		print("Interseção: %d | União: %d" % [inter_cnt, union_cnt])
		print("IoU Verdadeiro: %.4f (%.2f%%)" % [iou, iou * 100.0])
		print("Proporção Min/Max: %.4f (%.2f%%)" % [min_max, min_max * 100.0])
		
		# Lê estatísticas de LOD
		var raw_cnt = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
		var inst_cnt = raw_cnt.decode_u32(4)
		var tris_cnt = raw_cnt.decode_u32(16)
		var raw_vis = rd.buffer_get_data(pipeline.out_visible_buf, 0, inst_cnt * 4)
		var dist_map = {}
		for i in range(inst_cnt):
			var cid = raw_vis.decode_u32(i * 4)
			var lvl = vg_data["clusters"][cid]["lod_level"]
			dist_map[lvl] = dist_map.get(lvl, 0) + 1
		print("Clusters Selecionados: %d | Triângulos: %d | Distribuição: %s" % [inst_cnt, tris_cnt, str(dist_map)])
		
		img_ref.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/investigacao_dag_ref.png")
		img_arb.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/investigacao_dag_arb.png")
		diff_img.save_png("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/investigacao_dag_diff.png")
		
		get_tree().quit(0)
