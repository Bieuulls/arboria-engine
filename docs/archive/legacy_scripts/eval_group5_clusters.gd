extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

func _init():
	var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var clusters = vg["clusters"]
	var groups = vg["groups"]
	
	print("Clusters do LOD 1 com refined_group == 5:")
	var c_list = []
	for cid in range(172, 172 + 97):
		var c = clusters[cid]
		if c["refined_group"] == 5:
			c_list.append(c)
			print("Cluster %d: group_id=%d, refined=%d, center=%s, radius=%f, cone_axis=%s, cone_cutoff=%f" % [
				c["cluster_id"], c["group_id"], c["refined_group"],
				str(c["center"]), c["radius"], str(c["normal_cone"].slice(0, 3)), c["normal_cone"][3]
			])
			
	# Câmera do caso 02_intermediaria: Dist: 18m, Yaw: 30°, Pitch: 10°
	var dist = 18.0
	var yaw = deg_to_rad(30.0)
	var pitch = deg_to_rad(10.0)
	var cam_pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))
	var fov_rad = deg_to_rad(60.0)
	var fov_factor = tan(fov_rad * 0.5)
	var vp_h = 720.0
	var max_screen_err = 1.5
	
	print("\nAvaliação detalhada de cada um dos 5 clusters:")
	for c in c_list:
		var cid = c["cluster_id"]
		var center = c["center"]
		var radius = c["radius"]
		
		# A. Grupo Pai (group_id = c["group_id"])
		var gid = c["group_id"]
		var g = groups[gid]
		var p_center = g["center"]
		var p_error = g["error"]
		var p_dist = max(cam_pos.distance_to(p_center) - radius, 0.01)
		var p_err_pixels = (p_error * vp_h) / (2.0 * p_dist * fov_factor)
		var parent_needed = (p_err_pixels > max_screen_err) or (p_error > 10000.0)
		
		# B. Grupo Refinado (refined_group = c["refined_group"])
		var rgid = c["refined_group"]
		var rg = groups[rgid]
		var r_center = rg["center"]
		var r_error = rg["error"]
		var r_dist = max(cam_pos.distance_to(r_center) - radius, 0.01)
		var r_err_pixels = (r_error * vp_h) / (2.0 * r_dist * fov_factor)
		var child_satisfied = (r_err_pixels <= max_screen_err)
		
		var is_selected = parent_needed and child_satisfied
		
		print("Cluster %d:" % cid)
		print("  p_err_pixels = %.4f (parent_needed = %s)" % [p_err_pixels, parent_needed])
		print("  r_err_pixels = %.4f (child_satisfied = %s)" % [r_err_pixels, child_satisfied])
		print("  is_selected = %s" % is_selected)
		print("  p_dist = %.4f, r_dist = %.4f, radius = %.4f" % [p_dist, r_dist, radius])
	quit()
