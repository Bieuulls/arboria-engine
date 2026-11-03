@tool
extends EditorImportPlugin

## ArboriaMeshImportPlugin
## Automatiza a conversão de modelos 3D (.obj, .gltf, .glb) arrastados para o Godot
## em geometria virtualizada (.vgmesh) usando o Arboria Baker C++.

const ArboriaAssetImporter = preload("../core/arboria_asset_importer.gd")

func _get_importer_name() -> String:
	return "arboria.virtual_geometry"

func _get_visible_name() -> String:
	return "Arboria Virtual Geometry (.vgmesh)"

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["obj", "gltf", "glb"])

func _get_save_extension() -> String:
	return "vgmesh"

func _get_resource_type() -> String:
	return "Resource"

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Padrão Nanite DAG"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return [
		{
			"name": "max_cluster_triangles",
			"default_value": 128,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "32,128,1"
		},
		{
			"name": "target_error",
			"default_value": 1.5,
			"property_hint": PROPERTY_HINT_RANGE,
			"hint_string": "0.1,10.0,0.1"
		},
		{
			"name": "generate_physics_collision",
			"default_value": true
		}
	]

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true

func _get_priority() -> float:
	return 1.0

func _get_import_order() -> int:
	return 0

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array[String], gen_files: Array[String]) -> Error:
	var output_vgmesh = source_file.get_basename() + ".vgmesh"
	var res = ArboriaAssetImporter.import_file(source_file, output_vgmesh)
	if res.get("success", false):
		print("[Arboria Import] Modelo %s assado com sucesso -> %s" % [source_file, output_vgmesh])
		return OK
	else:
		printerr("[Arboria Import] Falha ao assar modelo %s: %s" % [source_file, res.get("error", "Erro desconhecido")])
		return FAILED
