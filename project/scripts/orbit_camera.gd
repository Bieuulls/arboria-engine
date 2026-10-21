extends Node3D
class_name OrbitCamera

@export var target_distance: float = 6.0
@export var min_distance: float = 0.5
@export var max_distance: float = 50.0
@export var rotate_speed: float = 0.005
@export var zoom_speed: float = 0.8
@export var pan_speed: float = 0.003

var yaw: float = 0.0
var pitch: float = -0.3
var is_rotating: bool = false
var is_panning: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var target_offset: Vector3 = Vector3(0, 1.0, 0)

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	update_camera_transform()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			is_rotating = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_distance = max(min_distance, target_distance - zoom_speed)
			update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_distance = min(max_distance, target_distance + zoom_speed)
			update_camera_transform()

	elif event is InputEventMouseMotion:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position

		if is_rotating:
			yaw -= delta.x * rotate_speed
			pitch = clamp(pitch - delta.y * rotate_speed, -1.5, 1.5)
			update_camera_transform()
		elif is_panning:
			var right = global_transform.basis.x
			var up = global_transform.basis.y
			target_offset -= (right * delta.x - up * delta.y) * pan_speed * (target_distance * 0.25)
			update_camera_transform()

func update_camera_transform() -> void:
	global_position = target_offset
	rotation = Vector3(pitch, yaw, 0.0)
	if camera:
		camera.position = Vector3(0, 0, target_distance)
