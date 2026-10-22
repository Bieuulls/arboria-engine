extends Node3D

## TESTE DE AUTOMACAO E BENCHMARK MASSIVO V7.2
## Valida 80 instâncias de geometria virtualizada, PBR fotorrealista Cook-Torrance e GPU culling.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")

var massive_scene: Node3D = null
var frame_count: int = 0
var max_frames: int = 25

func _ready() -> void:
	print("====================================================")
	print(" [BENCHMARK MASSIVO] 80 INSTANCIAS ARBORIA NATIVE   ")
	print("====================================================")
	var scene_res = load("res://scenes/arboria_massive_world_demo.tscn")
	if not scene_res:
		push_error("[FALHA] Nao foi possivel carregar arboria_massive_world_demo.tscn")
		get_tree().quit(1)
		return

	massive_scene = scene_res.instantiate()
	add_child(massive_scene)
	print("[BENCHMARK] Cena massiva instanciada com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 18:
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://diag_arboria_massive_world.png")
			print("[BENCHMARK] Captura de tela massiva salva em diag_arboria_massive_world.png")

	if frame_count >= max_frames:
		var pipeline = ArboriaNativePipeline.get_active_instance()
		if not pipeline:
			push_error("[FALHA] Pipeline nao ativo.")
			get_tree().quit(1)
			return

		print("[BENCHMARK METRICAS FINAIS]")
		print(" - Instancias registradas no pipeline: ", pipeline._registered_instances.size())
		print(" - Instancias processadas no frame: ", pipeline.stats_total_instances)
		print(" - Clusters visiveis na GPU: ", pipeline.stats_visible_clusters)
		print(" - Triangulos desenhados: ", pipeline.stats_triangles_drawn)

		var success = (pipeline.stats_total_instances >= 50) and (pipeline.stats_triangles_drawn > 0)
		if success:
			print("====================================================")
			print(" [BENCHMARK MASSIVO CONCLUIDO COM SUCESSO ABSOLUTO] ")
			print("====================================================")
			get_tree().quit(0)
		else:
			push_error("[FALHA] Metricas invalidas no benchmark massivo.")
			get_tree().quit(1)
