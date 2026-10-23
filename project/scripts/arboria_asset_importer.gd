extends RefCounted
class_name ArboriaAssetImporter

## Converts real Godot-imported mesh resources through the existing C++ Baker.
const CACHE_VERSION := 1
const BAKER_CANDIDATES := ["res://../bin/vg_baker_cli.exe", "res://bin/vg_baker_cli.exe", "res://../bin/arboria_baker_cli.exe"]
const CACHE_DIR := "user://arboria_import_cache"
const REGISTRY_PATH := "user://arboria_asset_registry.json"

static func import_asset(source_path: String, output_path: String = "", _options: Dictionary = {}) -> Dictionary:
	return import_file(source_path, output_path)

static func import_file(source_path: String, output_path: String = "") -> Dictionary:
	var source_abs := ProjectSettings.globalize_path(source_path) if source_path.begins_with("res://") or source_path.begins_with("user://") else source_path
	if not FileAccess.file_exists(source_abs):
		return _failure("Source file does not exist: " + source_abs)
	var ext := source_path.get_extension().to_lower()
	if ext not in ["obj", "glb", "gltf"]:
		return _failure("Unsupported format: " + ext)
	var baker := _find_baker()
	if baker.is_empty():
		return _failure("Existing C++ Baker executable not found. Build tools/baker first.")
	var source_hash := _sha256(source_abs)
	if source_hash.is_empty():
		return _failure("Could not hash source file")
	var output_abs := ProjectSettings.globalize_path(output_path) if not output_path.is_empty() and (output_path.begins_with("res://") or output_path.begins_with("user://")) else output_path
	if output_abs.is_empty():
		output_abs = source_abs.get_basename() + ".vgmesh"
	var sidecar_abs := output_abs + ".arbmeta.json"
	var cache_key := source_hash + "_v" + str(CACHE_VERSION)
	var cache_file := ProjectSettings.globalize_path(CACHE_DIR) + "/" + cache_key + ".vgmesh"
	var cache_meta := cache_file + ".arbmeta.json"
	if FileAccess.file_exists(cache_file) and FileAccess.file_exists(cache_meta):
		if _verify(baker, cache_file):
			DirAccess.make_dir_recursive_absolute(output_abs.get_base_dir())
			if DirAccess.copy_absolute(cache_file, output_abs) == OK and DirAccess.copy_absolute(cache_meta, sidecar_abs) == OK:
				_register(source_abs, output_abs, source_hash, "cache")
				return {"success": true, "output_path": output_abs, "cached": true}

	var obj_path := ""
	var metadata := {"schema": 1, "source": source_abs, "source_sha256": source_hash, "surfaces": [], "nodes": [], "warnings": [], "unsupported": []}
	var counts := {"v": 0, "vt": 0, "vn": 0, "triangles": 0, "surfaces": 0}

	if ext == "obj":
		# Direct OBJ processing: eliminates dependency on Godot editor import database
		obj_path = source_abs
		var f := FileAccess.open(source_abs, FileAccess.READ)
		if f != null:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line.begins_with("v "):
					counts.v += 1
				elif line.begins_with("vt "):
					counts.vt += 1
				elif line.begins_with("vn "):
					counts.vn += 1
				elif line.begins_with("f "):
					counts.triangles += 1
			f.close()
			counts.surfaces = 1
			metadata.surfaces.append({"node": "root", "surface_index": 0, "vertex_count": counts.v, "triangle_count": counts.triangles})
	else:
		var root: Node = null
		if ext in ["gltf", "glb"]:
			var gltf_doc := GLTFDocument.new()
			var gltf_state := GLTFState.new()
			var err := gltf_doc.append_from_file(source_abs, gltf_state)
			if err == OK:
				root = gltf_doc.generate_scene(gltf_state)
		if root == null:
			var packed := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_REPLACE)
			if packed is PackedScene:
				root = (packed as PackedScene).instantiate()
			elif packed is Mesh:
				root = MeshInstance3D.new()
				(root as MeshInstance3D).mesh = packed
			else:
				return _failure("Godot could not import source as PackedScene or Mesh: " + source_path)

		obj_path = output_abs + ".source.obj"
		var obj_text := PackedStringArray(["# ARBORIA intermediate OBJ; generated from Godot-imported resources"])
		_collect_node(root, Transform3D.IDENTITY, obj_text, metadata, counts)
		if root != null:
			root.free()
		if counts.triangles == 0:
			return _failure("No triangle surfaces were found in the imported asset")
		var validation := ArboriaGeometryValidator.validate_obj_text(obj_text)
		if not validation.valid:
			return _failure("Geometry validation failed: " + "; ".join(validation.errors))
		var obj_file := FileAccess.open(obj_path, FileAccess.WRITE)
		if obj_file == null:
			return _failure("Cannot write temporary OBJ: " + obj_path)
		obj_file.store_string("\n".join(obj_text) + "\n")
		obj_file.close()

	var bake_output: Array = []
	var exit_code := OS.execute(baker, [obj_path, output_abs, "--verify"], bake_output, true)
	var log := "\n".join(PackedStringArray(bake_output))
	if exit_code != 0 or not _verify(baker, output_abs):
		return _failure("C++ Baker failed (exit %d): %s" % [exit_code, log])
	var meta_file := FileAccess.open(sidecar_abs, FileAccess.WRITE)
	if meta_file == null:
		return _failure("Baked geometry exists but metadata sidecar could not be written")
	meta_file.store_string(JSON.stringify(metadata, "\t"))
	meta_file.close()
	DirAccess.make_dir_recursive_absolute(cache_file.get_base_dir())
	DirAccess.copy_absolute(output_abs, cache_file)
	DirAccess.copy_absolute(sidecar_abs, cache_meta)
	_register(source_abs, output_abs, source_hash, "baked")
	return {"success": true, "output_path": output_abs, "metadata_path": sidecar_abs, "cached": false, "vertices": counts.v, "triangles": counts.triangles, "surfaces": counts.surfaces, "log": log, "warnings": metadata.warnings}

static func _collect_node(node: Node, parent_transform: Transform3D, obj: PackedStringArray, metadata: Dictionary, counts: Dictionary) -> void:
	var local := Transform3D.IDENTITY
	if node is Node3D:
		local = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		metadata.nodes.append({"name": str(node.get_path()), "transform": _transform_json(local)})
		for si in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(si)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				metadata.warnings.append("Surface %s:%d has no vertex array" % [node.name, si])
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			if not tangents.is_empty():
				metadata.unsupported.append({"node": str(node.get_path()), "surface": si, "attribute": "tangents", "reason": "OBJ/Baker vertex format stores position, normal and UV only; original tangent data is retained in metadata as unavailable and source asset remains intact."})
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var material: Material = mi.mesh.surface_get_material(si)
			if mi.get_surface_override_material(si) != null:
				material = mi.get_surface_override_material(si)
			var material_data := _material_json(material)
			var vertex_base: int = int(counts.v)
			var uv_base: int = int(counts.v)
			var normal_base: int = int(counts.v)
			for vi in range(vertices.size()):
				var pos := local * vertices[vi]
				obj.append("v %.9g %.9g %.9g" % [pos.x, pos.y, pos.z]); counts.v += 1
				var uv := uvs[vi] if vi < uvs.size() else Vector2.ZERO
				obj.append("vt %.9g %.9g" % [uv.x, 1.0 - uv.y]); counts.vt += 1
				var normal := (local.basis.inverse().transposed() * normals[vi]).normalized() if vi < normals.size() and absf(local.basis.determinant()) > 0.000001 else (normals[vi].normalized() if vi < normals.size() else Vector3.UP)
				obj.append("vn %.9g %.9g %.9g" % [normal.x, normal.y, normal.z]); counts.vn += 1
			obj.append("o " + str(node.name).validate_node_name() + "_surface_" + str(si))
			obj.append("usemtl material_" + str(metadata.surfaces.size()))
			var tri_count := 0
			if not indices.is_empty():
				for ti in range(0, indices.size() - 2, 3):
					var a: int = indices[ti]
					var b: int = indices[ti + 1]
					var c: int = indices[ti + 2]
					if a < 0 or b < 0 or c < 0 or a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
						metadata.warnings.append("Invalid index encountered in %s surface %d" % [node.name, si])
						continue
					obj.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % [vertex_base+a+1,uv_base+a+1,normal_base+a+1,vertex_base+b+1,uv_base+b+1,normal_base+b+1,vertex_base+c+1,uv_base+c+1,normal_base+c+1])
					tri_count += 1
			else:
				for ti in range(0, vertices.size() - 2, 3):
					obj.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % [vertex_base+ti+1,uv_base+ti+1,normal_base+ti+1,vertex_base+ti+2,uv_base+ti+2,normal_base+ti+2,vertex_base+ti+3,uv_base+ti+3,normal_base+ti+3]); tri_count += 1
			metadata.surfaces.append({"node": str(node.get_path()), "surface_index": si, "vertex_count": vertices.size(), "triangle_count": tri_count, "material": material_data, "material_id": metadata.surfaces.size()})
			counts.triangles += tri_count; counts.surfaces += 1
		if mi.mesh is ArrayMesh:
			var blend_count := (mi.mesh as ArrayMesh).get_blend_shape_count()
			if blend_count > 0: metadata.unsupported.append({"node": str(node.get_path()), "attribute": "blend_shapes", "count": blend_count, "reason": "Baker format does not encode blend shapes; source is retained."})
	if node is Skeleton3D:
		metadata.unsupported.append({"node": str(node.get_path()), "attribute": "skeleton", "reason": "Skinned animation is not encoded in .vgmesh; source asset is retained."})
	for child in node.get_children():
		_collect_node(child, local, obj, metadata, counts)

static func _material_json(material: Material) -> Dictionary:
	if material == null: return {"name": "default", "type": "none"}
	var result := {"name": material.resource_name, "type": material.get_class()}
	if material is StandardMaterial3D:
		var m := material as StandardMaterial3D
		result.merge({"albedo_color": m.albedo_color.to_html(true), "metallic": m.metallic, "roughness": m.roughness, "texture_albedo": m.albedo_texture.resource_path if m.albedo_texture else "", "texture_normal": m.normal_texture.resource_path if m.normal_texture else "", "texture_orm": m.orm_texture.resource_path if m.orm_texture else "", "transparency": m.transparency, "cull_mode": m.cull_mode}, true)
	elif material is ShaderMaterial:
		result["shader"] = (material as ShaderMaterial).shader.resource_path if (material as ShaderMaterial).shader else ""
	return result

static func _transform_json(t: Transform3D) -> Dictionary:
	return {"origin": [t.origin.x,t.origin.y,t.origin.z], "basis": [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z]}

static func _find_baker() -> String:
	for p in BAKER_CANDIDATES:
		var abs_path := ProjectSettings.globalize_path(p).simplify_path()
		if FileAccess.file_exists(abs_path): return abs_path
	var root := ProjectSettings.globalize_path("res://").simplify_path()
	for p in [root.path_join("../bin/vg_baker_cli.exe").simplify_path(), root.path_join("../bin/arboria_baker_cli.exe").simplify_path(), "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/bin/vg_baker_cli.exe"]:
		if FileAccess.file_exists(p): return p
	return ""

static func _sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return ""
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK: return ""
	while not f.eof_reached(): ctx.update(f.get_buffer(1024 * 1024))
	return ctx.finish().hex_encode()

static func _verify(baker: String, path: String) -> bool:
	if not FileAccess.file_exists(path): return false
	var output: Array = []
	return OS.execute(baker, ["--verify-only", path], output, true) == 0

static func _register(source: String, output: String, digest: String, mode: String) -> void:
	var entries: Dictionary = {}
	if FileAccess.file_exists(REGISTRY_PATH):
		var f := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary: entries = parsed
	entries[source] = {"output": output, "sha256": digest, "mode": mode, "updated_unix": int(Time.get_unix_time_from_system())}
	var f := FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(entries, "\t"))

static func _failure(message: String) -> Dictionary:
	push_error("[ArboriaAssetImporter] " + message)
	return {"success": false, "error": message}
