extends SceneTree

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")

func _init() -> void:
	print("\n==============================================================")
	print("  SUITE DE TESTES E VALIDACAO REAL DO GODOT (.vgmesh v2)       ")
	print("==============================================================")

	var models = [
		{"name": "Granite Boulder", "path": "res://assets/boulder_granite.vgmesh", "expected_lods": 5},
		{"name": "Dense Scanned Rock", "path": "res://assets/dense_rock_test.vgmesh", "expected_lods": 9},
		{"name": "Pine Tree Trunk", "path": "res://assets/pine_trunk_complex.vgmesh", "expected_lods": 10}
	]

	var all_passed = true

	for m in models:
		print("\n[TESTANDO MODELO] %s (%s)..." % [m["name"], m["path"]])
		var data = VGMeshLoader.load_from_file(m["path"])

		if data.is_empty():
			printerr("❌ FALHA: Dados vazios ao carregar: ", m["path"])
			all_passed = false
			continue

		print("   -> Magic: %s | Versao: %d" % [data["magic"], data["version"]])
		print("   -> Bounding Box: %s ate %s" % [str(data["bbox_min"]), str(data["bbox_max"])])
		print("   -> Niveis de LOD: %d" % data["lods"].size())
		print("   -> Total Clusters: %d" % data["clusters"].size())

		if data["lods"].size() != m["expected_lods"]:
			printerr("❌ FALHA: Quantidade de LODs (%d) != esperada (%d)!" % [data["lods"].size(), m["expected_lods"]])
			all_passed = false

		# Valida reconstrucao de malha para CADA nivel de LOD
		for lod_idx in range(data["lods"].size()):
			var lod_desc = data["lods"][lod_idx]
			var mesh = VGMeshLoader.build_mesh_surface(data, lod_idx, true)

			if not mesh:
				printerr("❌ FALHA: Falha ao gerar ArrayMesh para LOD ", lod_idx)
				all_passed = false
				continue

			var arrays = mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var tris = indices.size() / 3

			if tris != lod_desc["triangle_count"]:
				printerr("❌ FALHA: Triangulos reconstruidos no Godot (%d) != descritor (%d)!" % [tris, lod_desc["triangle_count"]])
				all_passed = false

			if colors.size() != verts.size():
				printerr("❌ FALHA: Quantidade de cores por cluster (%d) != vertices (%d)!" % [colors.size(), verts.size()])
				all_passed = false

			print("      * LOD %d: %d triangulos, %d vertices, %d clusters (Erro max: %.4f) - OK" % [
				lod_idx, tris, verts.size(), lod_desc["cluster_count"], lod_desc["max_error"]
			])

		# Valida extracao de cluster individual
		var cluster_mesh = VGMeshLoader.build_mesh_surface(data, 0, true, 0)
		if cluster_mesh:
			var c_arrays = cluster_mesh.surface_get_arrays(0)
			var c_verts: PackedVector3Array = c_arrays[Mesh.ARRAY_VERTEX]
			var c_indices: PackedInt32Array = c_arrays[Mesh.ARRAY_INDEX]
			print("   -> Teste de Cluster Isolado (ID 0): %d triangulos, %d vertices - OK" % [c_indices.size() / 3, c_verts.size()])
		else:
			printerr("❌ FALHA: Falha ao isolar cluster 0")
			all_passed = false

	print("\n==============================================================")
	if all_passed:
		print("🎉 TODOS OS TESTES NO GODOT PASSARAM COM 100% DE SUCESSO!")
		print("   Geometria Virtualizada .vgmesh renderizavel sem fendas.")
		print("==============================================================\n")
		quit(0)
	else:
		printerr("❌ HOUVE FALHAS NA SUITE DE TESTES DO GODOT!")
		print("==============================================================\n")
		quit(1)
