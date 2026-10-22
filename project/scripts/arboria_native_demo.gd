extends Node3D

## ARBORIA ENGINE — CENA DE DEMONSTRAÇÃO DO RENDERIZADOR NATIVO FORWARD+
## Demonstração com múltiplas instâncias, oclusão bidirecional de profundidade com Godot nativo,
## iluminação PBR direcional e controles de LOD.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

@onready var rock_instance_1: ArboriaInstance3D = $VirtualMesh_Rock1
@onready var rock_instance_2: ArboriaInstance3D = $VirtualMesh_Rock2
@onready var standard_cube: MeshInstance3D = $GodotStandardCube
@onready var camera: Camera3D = $OrbitCamera
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D

# UI Nodes
@onready var ui_info_label: Label = $CanvasLayer/UI/VBox/InfoLabel
@onready var ui_shading_btn: OptionButton = $CanvasLayer/UI/VBox/ShadingOption
@onready var ui_lod_mode_btn: OptionButton = $CanvasLayer/UI/VBox/LODModeOption
@onready var ui_lod_slider: HSlider = $CanvasLayer/UI/VBox/ErrorSlider
@onready var ui_lod_label: Label = $CanvasLayer/UI/VBox/ErrorLabel

var compositor_effect: ArboriaCompositorEffect

# Controle de câmera orbital
var cam_distance: float = 12.0
var cam_pitch: float = 20.0
var cam_yaw: float = 45.0
var is_dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	print("[ArboriaNativeDemo] Inicializando cena de demonstracao nativa...")
	_setup_compositor()
	_setup_ui()
	_update_camera_transform()

func _exit_tree() -> void:
	var pipeline = ArboriaNativePipeline.get_active_instance()
	if pipeline:
		pipeline.cleanup()


func _setup_compositor() -> void:
	var env: WorldEnvironment = $WorldEnvironment
	if not env.compositor:
		env.compositor = Compositor.new()

	compositor_effect = ArboriaCompositorEffect.new()
	compositor_effect.active = true
	var effects = env.compositor.compositor_effects.duplicate()
	effects.append(compositor_effect)
	env.compositor.compositor_effects = effects

	if camera:
		camera.compositor = env.compositor
	print("[ArboriaNativeDemo] ArboriaCompositorEffect registrado no WorldEnvironment e Camera3D (Total: ", env.compositor.compositor_effects.size(), ").")

func _setup_ui() -> void:
	if ui_shading_btn:
		ui_shading_btn.clear()
		ui_shading_btn.add_item("PBR Lit Forward+", 0)
		ui_shading_btn.add_item("Superficie Normais", 1)
		ui_shading_btn.add_item("Unshaded Albedo", 2)
		ui_shading_btn.add_item("Cluster Colors (Nanite)", 3)
		ui_shading_btn.item_selected.connect(_on_shading_selected)

	if ui_lod_mode_btn:
		ui_lod_mode_btn.clear()
		ui_lod_mode_btn.add_item("Auto DAG Nanite", 0)
		ui_lod_mode_btn.add_item("LOD 0 (Maximo Detalhe)", 1)
		ui_lod_mode_btn.add_item("LOD 1 (Medio)", 2)
		ui_lod_mode_btn.add_item("LOD 2 (Baixo)", 3)
		ui_lod_mode_btn.item_selected.connect(_on_lod_mode_selected)

	if ui_lod_slider:
		ui_lod_slider.value_changed.connect(_on_error_slider_changed)

func _process(_delta: float) -> void:
	var pipeline = ArboriaNativePipeline.get_active_instance()
	if pipeline and ui_info_label:
		var fps = Engine.get_frames_per_second()
		var txt = "ARBORIA ENGINE V7 NATIVE FORWARD+\n"
		txt += "FPS: %d\n" % fps
		txt += "Instancias Virtuais: %d\n" % pipeline.stats_total_instances
		txt += "Clusters Visiveis: %d\n" % pipeline.stats_visible_clusters
		txt += "Triangulos Desenhados: %d\n" % pipeline.stats_triangles_drawn
		txt += "Modo de Shading: %s\n" % ["PBR", "Normais", "Unshaded", "Clusters"][pipeline.global_shading_mode]
		txt += "Max Screen Error: %.2f px" % rock_instance_1.max_screen_error
		ui_info_label.text = txt

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			last_mouse_pos = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = clamp(cam_distance - 0.8, 3.0, 50.0)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = clamp(cam_distance + 0.8, 3.0, 50.0)
			_update_camera_transform()

	elif event is InputEventMouseMotion and is_dragging:
		var delta = event.position - last_mouse_pos
		last_mouse_pos = event.position
		cam_yaw -= delta.x * 0.4
		cam_pitch = clamp(cam_pitch + delta.y * 0.4, -80.0, 80.0)
		_update_camera_transform()

func _update_camera_transform() -> void:
	if not camera:
		return
	var yaw_rad = deg_to_rad(cam_yaw)
	var pitch_rad = deg_to_rad(cam_pitch)

	var offset = Vector3(
		cam_distance * cos(pitch_rad) * sin(yaw_rad),
		cam_distance * sin(pitch_rad),
		cam_distance * cos(pitch_rad) * cos(yaw_rad)
	)

	var target = Vector3(0.0, 0.5, 0.0)
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)

func _on_shading_selected(idx: int) -> void:
	var pipeline = ArboriaNativePipeline.get_active_instance()
	if pipeline:
		pipeline.global_shading_mode = idx

func _on_lod_mode_selected(idx: int) -> void:
	if idx == 0:
		rock_instance_1.lod_mode = 0
		rock_instance_2.lod_mode = 0
	else:
		rock_instance_1.lod_mode = 1
		rock_instance_1.forced_lod = idx - 1
		rock_instance_2.lod_mode = 1
		rock_instance_2.forced_lod = idx - 1

func _on_error_slider_changed(val: float) -> void:
	rock_instance_1.max_screen_error = val
	rock_instance_2.max_screen_error = val
	if ui_lod_label:
		ui_lod_label.text = "Max Error: %.1f px" % val
