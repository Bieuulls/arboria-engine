@tool
class_name ArboriaMeshConverter
extends RefCounted

## Uses Godot's real importers and scene resources, then serializes every triangle
## surface into one temporary OBJ for the existing native Baker. Metadata is kept
## beside the .vgmesh because the current Baker format has no material table.
static func convert_to_obj(source_path: String, _options: Dictionary = {}) -> Dictionary:
	var resource := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if resource == null:
		return {"success": false, "error": "Godot não conseguiu importar/carregar o arquivo: %s" % source_path}
	var root: Node
	if resource is PackedScene:
		root = (resource as PackedScene).instantiate()
	elif resource is Mesh:
		root = MeshInstance3D.new()
		(root as MeshInstance3D).mesh = resource
	else:
		return {"success": false, "error": "Tipo de recurso não suportado (%s). Use GLB, glTF ou OBJ." % resource.get_class()}
	var text := "# ARBORIA intermediate OBJ; source=%s\n" % source_path
	var surfaces: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var nodes: Array[Dictionary] = []
	var warnings: Array[String] = []
	var counts := {"v": 0, "vt": 0, "vn": 0}
	var mesh_count := _walk(root, Transform3D.IDENTITY, "", surfaces, materials, nodes, warnings, counts, text)
	if root != null:
		root.free()
	if mesh_count == 0 or counts.v == 0:
		return {"success": false, "error": "O arquivo foi carregado, mas não contém superfícies triangulares utilizáveis."}
	# Reconstruct the text after traversal, since GDScript strings are value types.
	text = _serialize(source_path, surfaces)
	return {"success": true, "obj_text": text, "surfaces": surfaces, "materials": materials, "nodes": nodes, "warnings": warnings}

static func _walk(node: Node, parent_xform: Transform3D, parent_path: String, surfaces: Array[Dictionary], materials: Array[Dictionary], nodes: Array[Dictionary], warnings: Array[String], _counts: Dictionary, _unused_text: String) -> int:
	var count := 0
	var path := node.name if parent_path.is_empty() else parent_path + "/" + str(node.name)
	var world := parent_xform
	if node is Node3D:
		world = parent_xform * (node as Node3D).transform
		nodes.append({"path": path, "class": node.get_class(), "transform": _transform_to_array(world)})
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			if mi.skin != null or mi.skeleton != NodePath():
				warnings.append("%s: skeleton/skin não é baked; geometria estática usada e original preservado." % path)
			if mi.mesh.get_blend_shape_count() > 0:
				warnings.append("%s: blend shapes não são baked; malha base usada e original preservado." % path)
			for si in range(mi.mesh.get_surface_count()):
				if mi.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
					warnings.append("%s superfície %d ignorada: não é uma superfície de triângulos." % [path, si])
					continue
				var arrays := mi.mesh.surface_get_arrays(si)
				if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
					continue
				var mat := mi.get_active_material(si)
				var mat_id := _material_id(mat, materials)
				surfaces.append({"node_path": path, "surface": si, "transform": _transform_to_array(world), "arrays": arrays, "material_id": mat_id, "material_name": mat.resource_name if mat != null else ""})
				count += 1
	for child in node.get_children():
		count += _walk(child, world, path, surfaces, materials, nodes, warnings, _counts, _unused_text)
	return count

static func _material_id(mat: Material, materials: Array[Dictionary]) -> int:
	if mat == null:
		return -1
	for i in range(materials.size()):
		if materials[i].get("resource_path", "") == mat.resource_path and materials[i].get("resource_name", "") == mat.resource_name:
			return i
	var entry: Dictionary = {"resource_path": mat.resource_path, "resource_name": mat.resource_name, "type": mat.get_class()}
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		entry["albedo_color"] = [sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, sm.albedo_color.a]
		entry["metallic"] = sm.metallic
		entry["roughness"] = sm.roughness
		entry["albedo_texture"] = sm.albedo_texture.resource_path if sm.albedo_texture != null else ""
		entry["normal_texture"] = sm.normal_texture.resource_path if sm.normal_texture != null else ""
	materials.append(entry)
	return materials.size() - 1

static func _serialize(source_path: String, surfaces: Array[Dictionary]) -> String:
	var out := "# ARBORIA converted geometry\n# source=%s\n" % source_path
	var v_offset := 1
	var uv_offset := 1
	var n_offset := 1
	for surface in surfaces:
		var arrays: Array = surface.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(verts.size())
			for i in range(verts.size()): indices[i] = i
		var xform: Transform3D = _array_to_transform(surface.transform)
		var normal_xform := xform.basis.inverse().transposed()
		out += "\no %s_surface_%d\n" % [str(surface.node_path).replace(" ", "_"), int(surface.surface)]
		out += "usemtl arboria_material_%d\n" % int(surface.material_id)
		for p in verts:
			var q := xform * p
			out += "v %.9g %.9g %.9g\n" % [q.x, q.y, q.z]
		for uv in uvs:
			out += "vt %.9g %.9g\n" % [uv.x, 1.0 - uv.y]
		for n in norms:
			var qn := (normal_xform * n).normalized()
			out += "vn %.9g %.9g %.9g\n" % [qn.x, qn.y, qn.z]
		for i in range(0, indices.size() - 2, 3):
			var face := "f"
			for j in range(3):
				var idx := int(indices[i + j])
				face += " %d" % (v_offset + idx)
				if not uvs.is_empty() and not norms.is_empty(): face += "/%d/%d" % [uv_offset + idx, n_offset + idx]
				elif not uvs.is_empty(): face += "/%d" % (uv_offset + idx)
				elif not norms.is_empty(): face += "//%d" % (n_offset + idx)
			out += face + "\n"
		v_offset += verts.size()
		uv_offset += uvs.size()
		n_offset += norms.size()
	return out

static func _transform_to_array(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

static func _array_to_transform(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
