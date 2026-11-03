@tool
class_name ArboriaImportCache
extends RefCounted

static func fingerprint(source_abs: String, options: Dictionary) -> String:
	var file := FileAccess.open(source_abs, FileAccess.READ)
	if file == null: return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not file.eof_reached(): ctx.update(file.get_buffer(1024 * 1024))
	file.close()
	ctx.update(JSON.stringify(options).to_utf8_buffer())
	return ctx.finish().hex_encode()

static func is_valid_hit(output_abs: String, metadata_abs: String, expected: String) -> bool:
	if expected.is_empty() or not FileAccess.file_exists(output_abs) or not FileAccess.file_exists(metadata_abs): return false
	var f := FileAccess.open(metadata_abs, FileAccess.READ)
	if f == null: return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data is Dictionary and data.get("source_fingerprint", "") == expected

static func write_record(source_abs: String, output_abs: String, metadata_abs: String, fingerprint_value: String) -> void:
	var path := ProjectSettings.globalize_path("res://.arboria_import_cache.json")
	var records: Dictionary = {}
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		if old != null:
			var parsed: Variant = JSON.parse_string(old.get_as_text())
			if parsed is Dictionary: records = parsed
	records[source_abs] = {"output": output_abs, "metadata": metadata_abs, "fingerprint": fingerprint_value}
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out != null: out.store_string(JSON.stringify(records, "\t"))
