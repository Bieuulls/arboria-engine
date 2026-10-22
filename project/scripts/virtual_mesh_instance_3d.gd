@tool
class_name VirtualMeshInstance3D
extends VisualInstance3D

## Instância de Geometria Virtualizada ARBORIA ENGINE
## Permite instanciar malhas virtuais (.vgmesh) na cena 3D do Godot com LOD Nanite DAG,
## GPU Culling e desenho indireto nativo no Forward+.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")

signal mesh_loaded(path: String)
signal transform_updated()

@export_file("*.vgmesh") var mesh_path: String = "":
	set(value):
		if mesh_path != value:
			mesh_path = value
			_on_mesh_path_changed()

@export_group("LOD & Culling")
@export_range(0.1, 10.0, 0.1) var max_screen_error: float = 1.5:
	set(value):
		max_screen_error = value
		notify_pipeline_update()

@export_enum("Auto DAG Nanite", "Forced LOD") var lod_mode: int = 0:
	set(value):
		lod_mode = value
		notify_pipeline_update()

@export_range(0, 16, 1) var forced_lod: int = 0:
	set(value):
		forced_lod = value
		notify_pipeline_update()

@export_group("Material PBR")
@export var base_albedo: Color = Color(0.80, 0.82, 0.85):
	set(value):
		base_albedo = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var roughness: float = 0.65:
	set(value):
		roughness = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var metallic: float = 0.05:
	set(value):
		metallic = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var specular: float = 0.50:
	set(value):
		specular = value
		notify_pipeline_update()

var _pipeline: RefCounted = null
var _aabb: AABB = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
var _mesh_data: Dictionary = {}
var _is_registered: bool = false

func _ready() -> void:
	set_notify_transform(true)
	if mesh_path != "":
		_load_mesh_if_needed()
	_register_to_pipeline()

func _enter_tree() -> void:
	set_notify_transform(true)
	_register_to_pipeline()

func _exit_tree() -> void:
	_unregister_from_pipeline()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		notify_pipeline_update()
		emit_signal("transform_updated")
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		notify_pipeline_update()

func _on_mesh_path_changed() -> void:
	if is_inside_tree():
		_load_mesh_if_needed()
		notify_pipeline_update()

func _load_mesh_if_needed() -> void:
	if mesh_path == "":
		return

	var pipeline = get_pipeline()
	if pipeline:
		_mesh_data = pipeline.get_or_load_mesh(mesh_path)
		if _mesh_data.has("bbox_min") and _mesh_data.has("bbox_max"):
			var bmin = _mesh_data["bbox_min"]
			var bmax = _mesh_data["bbox_max"]
			_aabb = AABB(bmin, bmax - bmin)
			set_base(RID())
		emit_signal("mesh_loaded", mesh_path)

func _get_aabb() -> AABB:
	return _aabb

func get_custom_aabb() -> AABB:
	return _aabb

func _register_to_pipeline() -> void:
	if _is_registered:
		return
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("register_instance"):
		pipeline.register_instance(self)
		_is_registered = true

func _unregister_from_pipeline() -> void:
	if not _is_registered:
		return
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("unregister_instance"):
		pipeline.unregister_instance(self)
	_is_registered = false

func notify_pipeline_update() -> void:
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("mark_instance_dirty"):
		pipeline.mark_instance_dirty(self)

func get_pipeline() -> RefCounted:
	if _pipeline:
		return _pipeline
	if ArboriaNativePipeline.get_active_instance():
		_pipeline = ArboriaNativePipeline.get_active_instance()
	else:
		_pipeline = ArboriaNativePipeline.get_or_create_shared()
	return _pipeline
