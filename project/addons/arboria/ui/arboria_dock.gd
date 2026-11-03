@tool
extends Control

## ARBORIA VIRTUAL GEOMETRY — EDITOR IMPORT & BAKE DOCK
## Permite importar e assar malhas 3D (.obj, .glb, .gltf) em .vgmesh diretamente no editor.

const ArboriaAssetImporter = preload("../core/arboria_asset_importer.gd")

@onready var source_edit: LineEdit = $VBox/SourceBox/LineEdit
@onready var source_browse_btn: Button = $VBox/SourceBox/BrowseBtn
@onready var output_edit: LineEdit = $VBox/OutputBox/LineEdit
@onready var bake_btn: Button = $VBox/BakeBtn
@onready var log_label: RichTextLabel = $VBox/LogBox/LogLabel
@onready var file_dialog: FileDialog = $FileDialog

func _ready() -> void:
	if source_browse_btn:
		source_browse_btn.pressed.connect(_on_browse_pressed)
	if bake_btn:
		bake_btn.pressed.connect(_on_bake_pressed)
	if file_dialog:
		file_dialog.file_selected.connect(_on_file_selected)

func _on_browse_pressed() -> void:
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_dialog.filters = PackedStringArray(["*.obj ; OBJ Models", "*.glb, *.gltf ; glTF Models"])
		file_dialog.popup_centered_ratio(0.7)

func _on_file_selected(path: String) -> void:
	if source_edit:
		source_edit.text = path
	if output_edit:
		var base = path.get_basename()
		output_edit.text = base + ".vgmesh"

func _on_bake_pressed() -> void:
	var src = source_edit.text.strip_edges()
	var out = output_edit.text.strip_edges()

	if src.is_empty():
		_log("[color=red][ERRO] Selecione um arquivo de origem (.obj/.glb) primeiro.[/color]\n")
		return

	if out.is_empty():
		out = src.get_basename() + ".vgmesh"
		output_edit.text = out

	_log("[color=cyan][ARBORIA BAKER] Iniciando importação e cozimento de malha...[/color]\n")
	_log("  Origem: " + src + "\n")
	_log("  Destino: " + out + "\n")

	bake_btn.disabled = true
	var res = ArboriaAssetImporter.import_file(src, out)
	bake_btn.disabled = false

	if res.get("success", false):
		_log("[color=green][SUCESSO] Malha virtual gerada com sucesso![/color]\n")
		_log("  Arquivo .vgmesh: " + res.get("output_path", out) + "\n")
		if res.get("cached", false):
			_log("  [Cache] Malha recuperada do cache determinístico local.\n")
	else:
		_log("[color=red][FALHA] Erro no cozimento: " + res.get("error", "Desconhecido") + "[/color]\n")

func _log(text: String) -> void:
	if log_label:
		log_label.append_text(text)
