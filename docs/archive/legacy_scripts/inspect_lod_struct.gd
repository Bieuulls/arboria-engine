extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

func _init():
	var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var clusters = vg["clusters"]
	var lods = vg["lods"]
	var groups = vg["groups"]
	print("LODs count: ", lods.size())
	for i in range(lods.size()):
		var l = lods[i]
		print("  LOD ", i, ": clusters=", l["cluster_count"], " tris=", l["triangle_count"], " max_error=", l["max_error"])
	
	var lod_hist = {}
	for c in clusters:
		var lvl = c["lod_level"]
		lod_hist[lvl] = lod_hist.get(lvl, 0) + 1
	print("Clusters per LOD level: ", lod_hist)
	print("Total groups in DAG: ", groups.size())
	quit()
