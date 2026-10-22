extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const VirtualMeshInstance3D = preload("res://scripts/virtual_mesh_instance_3d.gd")

var frame_count: int = 0
var demo_scene: Node = null

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE AUTOMACAO] ARBORIA NATIVE DEMO SUITE     ")
	print("====================================================")
	var scene_res = load("res://scenes/arboria_native_demo.tscn")
	if not scene_res:
		push_error("Falha ao carregar arboria_native_demo.tscn")
		get_tree().quit(1)
		return

	demo_scene = scene_res.instantiate()
	add_child(demo_scene)
	print("[TESTE] Cena de demonstracao instanciada com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 5:
		var rock1 = demo_scene.get_node_or_null("VirtualMesh_Rock1")
		var rock2 = demo_scene.get_node_or_null("VirtualMesh_Rock2")
		var cube = demo_scene.get_node_or_null("GodotStandardCube")

		assert(rock1 != null, "Rock1 nao encontrado")
		assert(rock2 != null, "Rock2 nao encontrado")
		assert(cube != null, "Cubo Godot convencional nao encontrado")
		print("[TESTE ETAPA 1] Instancias geometricas presentes na cena: OK")

	elif frame_count == 10:
		var pipeline = ArboriaNativePipeline.get_active_instance()
		assert(pipeline != null, "Pipeline nativo nao ativo")
		assert(pipeline.is_initialized, "Pipeline nao inicializado")
		print("[TESTE ETAPA 2] Pipeline nativo ativo e inicializado: OK")

	elif frame_count == 15:
		var pipeline = ArboriaNativePipeline.get_active_instance()
		pipeline.global_shading_mode = 0 # PBR Lit
		print("[TESTE ETAPA 3] Modo PBR Lit configurado: OK")

	elif frame_count == 20:
		var pipeline = ArboriaNativePipeline.get_active_instance()
		pipeline.global_shading_mode = 3 # Cluster Colors
		print("[TESTE ETAPA 4] Modo Cluster Debug Colors configurado: OK")

	elif frame_count == 25:
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://diag_arboria_native_demo_frame.png")
			print("[TESTE ETAPA 5] Captura salva: diag_arboria_native_demo_frame.png: OK")

	elif frame_count == 30:
		print("====================================================")
		print(" [TESTE CONCLUIDO COM SUCESSO ABSOLUTO]             ")
		print("====================================================")
		get_tree().quit(0)
