extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

func _init():
	var vg = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	var groups = vg["groups"]
	var clusters = vg["clusters"]
	
	# Mapeia quais clusters do LOD 0 pertencem a cada grupo
	var g_to_c0 = {}
	for i in range(172):
		var gid = clusters[i]["group_id"]
		if not g_to_c0.has(gid): g_to_c0[gid] = []
		g_to_c0[gid].append(i)
		
	# Mapeia quais clusters do LOD 1 refinam cada grupo
	var g_to_c1 = {}
	for i in range(172, 172 + 97):
		var rgid = clusters[i]["refined_group"]
		if not g_to_c1.has(rgid): g_to_c1[rgid] = []
		g_to_c1[rgid].append(i)
		
	print("Mapeamento Grupo -> Clusters LOD 0 vs Clusters LOD 1:")
	for gid in g_to_c0:
		var c0_list = g_to_c0[gid]
		var c1_list = g_to_c1.get(gid, [])
		print("Group %d: %d clusters no LOD 0 | %d clusters no LOD 1 que refinam ele" % [gid, c0_list.size(), c1_list.size()])
	quit()
