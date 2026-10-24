class_name ArboriaRigidBody3D
extends RigidBody3D

## ARBORIA RIGID BODY 3D — JOLT PHYSICS COMPANION
## Corpo rígido dinâmico com simulação física no Jolt e renderização virtualizada no Arboria Engine.
## As transformações físicas sincronizam automaticamente com a GPU Scene a cada physics tick.

const ArboriaInstance3D = preload("arboria_instance_3d.gd")
const ArboriaMeshLoader = preload("../core/arboria_mesh_loader.gd")

@export_file("*.vgmesh") var mesh_path: String = "res://assets/dense_rock_test.vgmesh":
	set(val):
		mesh_path = val
		if is_inside_tree():
			_rebuild_mesh_and_shape()

@export_enum("Convex Hull", "Box") var shape_type: int = 0:
	set(val):
		shape_type = val
		if is_inside_tree():
			_rebuild_mesh_and_shape()

@export var max_screen_error: float = 1.5
@export var base_albedo: Color = Color(0.7, 0.72, 0.75)
@export var roughness: float = 0.65

var visual_instance: ArboriaInstance3D = null
var collision_shape: CollisionShape3D = null

func _ready() -> void:
	_setup_nodes()

func _setup_nodes() -> void:
	if not visual_instance:
		visual_instance = ArboriaInstance3D.new()
		visual_instance.name = "ArboriaVisual"
		add_child(visual_instance)
	
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
		
	_rebuild_mesh_and_shape()

func _rebuild_mesh_and_shape() -> void:
	if not is_inside_tree() or mesh_path.is_empty():
		return
		
	if visual_instance:
		visual_instance.mesh_path = mesh_path
		visual_instance.max_screen_error = max_screen_error
		visual_instance.base_albedo = base_albedo
		visual_instance.roughness = roughness
		
	var pipeline = visual_instance.get_pipeline() if visual_instance else null
	if pipeline and collision_shape:
		var vg_data = pipeline.get_or_load_mesh(mesh_path)
		var shape: Shape3D = null
		if shape_type == 0:
			shape = ArboriaMeshLoader.get_cached_convex_shape(mesh_path, vg_data)
		else:
			shape = ArboriaMeshLoader.get_cached_box_shape(mesh_path, vg_data)
		collision_shape.shape = shape
