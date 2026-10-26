@tool
extends EditorPlugin

## Arboria Virtual Geometry Editor Plugin
## Registers Arboria custom nodes and handles lifecycle for virtual geometry scenes.

const AUTOLOAD_NAME = "ArboriaPipeline"
const DOCK_SCENE = preload("ui/arboria_dock.tscn")
var dock_instance: Control = null

func _enter_tree() -> void:
	# Registra os nós customizados de geometria virtualizada e física
	add_custom_type(
		"ArboriaInstance3D",
		"VisualInstance3D",
		preload("nodes/arboria_instance_3d.gd"),
		preload("icons/arboria_instance_3d.svg") if ResourceLoader.exists("res://addons/arboria/icons/arboria_instance_3d.svg") else null
	)
	add_custom_type(
		"ArboriaRigidBody3D",
		"RigidBody3D",
		preload("nodes/arboria_rigid_body_3d.gd"),
		preload("icons/arboria_rigid_body_3d.svg") if ResourceLoader.exists("res://addons/arboria/icons/arboria_rigid_body_3d.svg") else null
	)
	add_custom_type(
		"ArboriaStaticBody3D",
		"StaticBody3D",
		preload("nodes/arboria_static_body_3d.gd"),
		preload("icons/arboria_static_body_3d.svg") if ResourceLoader.exists("res://addons/arboria/icons/arboria_static_body_3d.svg") else null
	)
	add_custom_type(
		"VirtualMeshInstance3D",
		"VisualInstance3D",
		preload("nodes/virtual_mesh_instance_3d.gd"),
		preload("icons/virtual_mesh_instance_3d.svg") if ResourceLoader.exists("res://addons/arboria/icons/virtual_mesh_instance_3d.svg") else null
	)

	# Registra o painel de importação e cozimento de malhas (Dock do Editor)
	dock_instance = DOCK_SCENE.instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, dock_instance)
	print("[Arboria] Plugin ativado com sucesso. Nós de Geometria Virtualizada e Dock de Importação registrados.")

func _exit_tree() -> void:
	if dock_instance:
		remove_control_from_docks(dock_instance)
		dock_instance.free()
		dock_instance = null

	remove_custom_type("VirtualMeshInstance3D")
	remove_custom_type("ArboriaInstance3D")
	remove_custom_type("ArboriaRigidBody3D")
	remove_custom_type("ArboriaStaticBody3D")
	print("[Arboria] Plugin desativado.")
