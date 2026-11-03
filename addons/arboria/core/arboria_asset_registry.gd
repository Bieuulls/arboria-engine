@tool
class_name ArboriaAssetRegistry
extends RefCounted

static func register_asset(output_abs: String, metadata_abs: String, metadata: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("res://arboria_asset_registry.json")
	var registry: Dictionary = {"schema": "arboria.registry.v1", "assets": []}
	if FileAccess.file_exists(path):
		var existing := FileAccess.open(path, FileAccess.READ)
		if existing != null:
			var parsed: Variant = JSON.parse_string(existing.get_as_text())
			if parsed is Dictionary: registry = parsed
	var assets: Array = registry.get("assets", [])
	var found := false
	for i in range(assets.size()):
		if assets[i] is Dictionary and assets[i].get("output", "") == output_abs:
			assets[i] = {"output": output_abs, "metadata": metadata_abs, "source": metadata.get("source", ""), "fingerprint": metadata.get("source_fingerprint", "")}
			found = true
	if not found: assets.append({"output": output_abs, "metadata": metadata_abs, "source": metadata.get("source", ""), "fingerprint": metadata.get("source_fingerprint", "")})
	registry["assets"] = assets
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(registry, "\t"))
