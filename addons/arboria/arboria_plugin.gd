@tool
extends EditorPlugin

## Arboria Virtual Geometry Editor Plugin
## Registers Arboria custom nodes and handles lifecycle for virtual geometry scenes.

const AUTOLOAD_NAME = "ArboriaPipeline"

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
	print("[Arboria] Plugin ativado com sucesso. Nós de Geometria Virtualizada registrados.")

func _exit_tree() -> void:
	remove_custom_type("VirtualMeshInstance3D")
	remove_custom_type("ArboriaInstance3D")
	remove_custom_type("ArboriaRigidBody3D")
	remove_custom_type("ArboriaStaticBody3D")
	print("[Arboria] Plugin desativado.")
