class_name ArboriaStaticBody3D
extends StaticBody3D

## ARBORIA STATIC BODY 3D — JOLT PHYSICS COMPANION
## Corpo físico estático para terreno e obstáculos do Arboria Engine no Jolt.
## Utiliza colisor côncavo (trimesh perfeito do LOD 0), convexo ou caixa.

const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")
const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

@export_file("*.vgmesh") var mesh_path: String = "res://assets/dense_rock_test.vgmesh":
	set(val):
		mesh_path = val
		if is_inside_tree():
			_rebuild_mesh_and_shape()

@export_enum("Concave Trimesh", "Convex Hull", "Box") var shape_type: int = 0:
	set(val):
		shape_type = val
		if is_inside_tree():
			_rebuild_mesh_and_shape()

@export var max_screen_error: float = 1.5
@export var base_albedo: Color = Color(0.65, 0.68, 0.72)
@export var roughness: float = 0.70

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
			shape = ArboriaMeshLoader.get_cached_concave_shape(mesh_path, vg_data, 0)
		elif shape_type == 1:
			shape = ArboriaMeshLoader.get_cached_convex_shape(mesh_path, vg_data)
		else:
			shape = ArboriaMeshLoader.get_cached_box_shape(mesh_path, vg_data)
		collision_shape.shape = shape
