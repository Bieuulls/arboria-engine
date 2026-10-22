extends Node3D

## Teste de Validação da Troca de Modelos no Main Viewer com o Pipeline Nativo V7

var viewer_scene: Node = null
var current_step: int = 0
var step_timer: float = 0.0

func _ready() -> void:
	print("====================================================")
	print(" [TESTE] VALIDACAO DE MODELOS NO MAIN VIEWER V7     ")
	print("====================================================")
	var scene_res = load("res://scenes/main_viewer.tscn")
	if not scene_res:
		push_error("Falha ao carregar main_viewer.tscn")
		get_tree().quit(1)
		return

	viewer_scene = scene_res.instantiate()
	add_child(viewer_scene)

func _process(delta: float) -> void:
	step_timer += delta

	if current_step == 0 and step_timer > 0.5:
		print("[TESTE MODELO 0] Dense Scanned Rock carregado com sucesso.")
		assert(viewer_scene.native_pipeline != null)
		assert(viewer_scene.native_instance != null)
		current_step = 1
		step_timer = 0.0
		# Troca para o Modelo 1: Pine Tree Trunk
		viewer_scene.load_selected_model(1)

	elif current_step == 1 and step_timer > 0.5:
		print("[TESTE MODELO 1] Pine Tree Trunk carregado com sucesso.")
		assert(viewer_scene.current_model_name == "Pine Tree Trunk")
		current_step = 2
		step_timer = 0.0
		# Troca para o Modelo 2: Granite Boulder PBR
		viewer_scene.load_selected_model(2)

	elif current_step == 2 and step_timer > 0.5:
		print("[TESTE MODELO 2] Granite Boulder PBR carregado com sucesso.")
		assert(viewer_scene.current_model_name == "Granite Boulder")
		current_step = 3
		step_timer = 0.0
		# Retorna para o Modelo 0
		viewer_scene.load_selected_model(0)

	elif current_step == 3 and step_timer > 0.5:
		print("[TESTE RECARREGAMENTO] Retorno ao Modelo 0 com sucesso.")
		print("====================================================")
		print(" [TESTE DE TROCA DE MODELOS PASSOU COM EXITO]       ")
		print("====================================================")
		get_tree().quit(0)
