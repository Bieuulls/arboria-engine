extends Node3D

const MainViewerScene = preload("res://scenes/main_viewer.tscn")

var frame_count = 0
var viewer_instance: Node3D

func _ready() -> void:
	print("Inicializando captura de cena do Godot...")
	viewer_instance = MainViewerScene.instantiate()
	add_child(viewer_instance)

func _process(_delta: float) -> void:
	frame_count += 1

	# Aguarda 5 frames para shaders compilarem e cena renderizar
	if frame_count == 10:
		var img = get_viewport().get_texture().get_image()
		var out_path = "res://screenshot_cluster_view.png"
		img.save_png(out_path)
		print("Screenshot capturado: ", out_path, " (", img.get_width(), "x", img.get_height(), ")")

		# Muda para wireframe
		viewer_instance.wireframe_check.button_pressed = true
		viewer_instance.refresh_mesh()

	elif frame_count == 20:
		var img = get_viewport().get_texture().get_image()
		var out_path = "res://screenshot_wireframe_view.png"
		img.save_png(out_path)
		print("Screenshot capturado: ", out_path)

		# Muda para LOD 3
		viewer_instance.wireframe_check.button_pressed = false
		viewer_instance.lod_slider.value = 3
		viewer_instance.current_lod = 3
		viewer_instance.refresh_mesh()

	elif frame_count == 30:
		var img = get_viewport().get_texture().get_image()
		var out_path = "res://screenshot_lod3_view.png"
		img.save_png(out_path)
		print("Screenshot capturado: ", out_path)
		get_tree().quit(0)
