extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

func _init():
	var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var groups = vg["groups"]
	var clusters = vg["clusters"]
	print("Total groups: ", groups.size())
	for i in range(mini(groups.size(), 10)):
		var g = groups[i]
		print("Group ", i, ": depth=", g["depth"], " center=", g["center"], " radius=", g["radius"], " error=", g["error"])
		
	print("\nSample clusters LOD 0 (first 5):")
	for i in range(5):
		var c = clusters[i]
		print("Cluster ", i, ": lod=", c["lod_level"], " group_id=", c["group_id"], " refined=", c["refined_group"], " lod_error=", c["lod_error"])
		if c["group_id"] < groups.size():
			print("   -> Group of cluster: error=", groups[c["group_id"]]["error"])
			
	print("\nSample clusters LOD 1 (first 3):")
	for i in range(172, 175):
		var c = clusters[i]
		print("Cluster ", i, ": lod=", c["lod_level"], " group_id=", c["group_id"], " refined=", c["refined_group"], " lod_error=", c["lod_error"])
		if c["group_id"] < groups.size():
			print("   -> Group of cluster: error=", groups[c["group_id"]]["error"])
	quit()
