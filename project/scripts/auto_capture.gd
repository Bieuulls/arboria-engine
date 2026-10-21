extends Node

var frame_count = 0
@onready var viewer = get_parent()

func _ready() -> void:
	print("Auto-capture pine trunk inicializado...")

func _process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 10:
		# Muda para o modelo Pine Tree Trunk
		viewer.load_selected_model(1)
		viewer.model_option.selected = 1

	elif frame_count == 30:
		var img = get_viewport().get_texture().get_image()
		var p = "res://screenshot_pine_trunk.png"
		img.save_png(p)
		print("Screenshot gravado: ", p)
		get_tree().quit(0)
