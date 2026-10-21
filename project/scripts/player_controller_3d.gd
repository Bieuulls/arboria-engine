extends CharacterBody3D
class_name PlayerController3D

## ====================================================================
## ARBORIA 3D - CHARACTER CONTROLLER 3D (GODOT 4)
## Controle de 3ª pessoa suave com fixação firme no chão (Zero Flutuação)
## ====================================================================

@export_group("Movement")
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 11.5
@export var jump_velocity: float = 7.5
@export var rotation_speed: float = 12.0

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.003
@export var min_pitch: float = -75.0
@export var max_pitch: float = 45.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var visual_mesh: Node3D = $VisualMesh

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.4 # Fixação precisa no solo para não flutuar
	floor_stop_on_slope = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if spring_arm:
			spring_arm.rotation.y -= event.relative.x * mouse_sensitivity
			spring_arm.rotation.x -= event.relative.y * mouse_sensitivity
			spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(min_pitch), deg_to_rad(max_pitch))

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# 1. Gravidade natural
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Pulo com verificação de solo
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 3. Vetor de Movimento relativo à Câmera
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := spring_arm.global_transform.basis if spring_arm else global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()

	var direction := (right * input_dir.x + forward * -input_dir.y).normalized()

	var is_sprinting := Input.is_action_pressed("sprint")
	var current_speed := sprint_speed if is_sprinting else walk_speed

	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed

		# Rotaciona o modelo na direção do movimento
		if visual_mesh:
			var target_rot := atan2(-direction.x, -direction.z)
			visual_mesh.rotation.y = lerp_angle(visual_mesh.rotation.y, target_rot, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# 4. Move e desliza com snap ao solo
	move_and_slide()
