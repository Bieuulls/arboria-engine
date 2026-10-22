extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

func _init():
	var rd = RenderingServer.get_rendering_device()
	var vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)
	
	var cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 300.0
	cam.fov = 60.0
	var dist = 18.0
	var yaw = deg_to_rad(30.0)
	var pitch = deg_to_rad(10.0)
	var pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
	cam.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)
	
	var fov_rad = deg_to_rad(60.0)
	var aspect = 1280.0 / 720.0
	var proj_mat = Projection.create_perspective(60.0, aspect, 0.05, 300.0)
	var cam_xform = Transform3D.IDENTITY.looking_at(-pos, Vector3.UP)
	cam_xform.origin = pos
	var view_mat = cam_xform.affine_inverse()
	var vp_mat = proj_mat * Projection(view_mat)
	
	var clusters = vg_data["clusters"]
	var groups = vg_data["groups"]
	
	print("Análise analítica de projeção dos centros dos clusters:")
	var in_hole_zone = []
	for cid in range(172):
		var c = clusters[cid]
		var cp = c["center"]
		var v4 = vp_mat * Vector4(cp.x, cp.y, cp.z, 1.0)
		if v4.w > 0:
			var ndc = Vector3(v4.x / v4.w, v4.y / v4.w, v4.z / v4.w)
			var sx = (ndc.x * 0.5 + 0.5) * 1280.0
			var sy = (1.0 - (ndc.y * 0.5 + 0.5)) * 720.0
			if sx >= 600 and sx <= 650 and sy >= 260 and sy <= 300:
				in_hole_zone.append({"cid": cid, "gid": c["group_id"], "sx": sx, "sy": sy})
				
	print("Clusters do LOD 0 projetados no buraco [600..650, 260..300]:")
	for item in in_hole_zone:
		print("  Cluster %d (Group %d) at (%.1f, %.1f)" % [item.cid, item.gid, item.sx, item.sy])
		
	# Grupos únicos envolvidos:
	var g_set = {}
	for item in in_hole_zone:
		g_set[item.gid] = true
	print("Grupos envolvidos: ", g_set.keys())
	
	# Para cada um desses grupos, quais clusters foram selecionados pelo Compute Shader?
	# Dispara o culling
	var sv = SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = true
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 1)
	var we = WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	sv.add_child(cam)
	root.add_child(sv)
	
	pipeline.set_indirect_draw_enabled(true)
	pipeline.render_to_viewport(sv, cam, Transform3D.IDENTITY, 1.5, 0, 0, true, false, false, 0, true)
	
	var raw_cnt = rd.buffer_get_data(pipeline.counter_buf, 0, 24)
	var inst_cnt = raw_cnt.decode_u32(4)
	var raw_vis = rd.buffer_get_data(pipeline.out_visible_buf, 0, inst_cnt * 4)
	var sel_set = {}
	for i in range(inst_cnt):
		sel_set[raw_vis.decode_u32(i * 4)] = true
		
	print("\nStatus de seleção dos grupos envolvidos:")
	for gid in g_set.keys():
		print("\n--- GRUPO %d ---" % gid)
		# Clusters de LOD 0 do grupo
		var c0_sel = 0
		var c0_tot = 0
		for cid in range(172):
			if clusters[cid]["group_id"] == gid:
				c0_tot += 1
				if sel_set.has(cid): c0_sel += 1
		print("  LOD 0: %d de %d selecionados" % [c0_sel, c0_tot])
		
		# Clusters de LOD 1 do grupo
		var c1_sel = 0
		var c1_tot = 0
		for cid in range(172, 172 + 97):
			if clusters[cid]["refined_group"] == gid:
				c1_tot += 1
				if sel_set.has(cid): c1_sel += 1
		print("  LOD 1: %d de %d selecionados" % [c1_sel, c1_tot])
	quit()
