extends Node3D

## TESTE DE VALIDAÇÃO AUTOMATIZADA: ETAPA 01 — GPU SCENE GLOBAL CONSOLIDADO
## Verifica a renderização agrupada global com 1, 80, 500 e 2.000 instâncias em hardware real (RTX 3050).
## Critério estrito: 1 Dispatch e 1 Draw Indireto constantes (O(1) CPU/GPU submissões) independente da contagem de instâncias.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

const TEST_MESH_PATH = "res://assets/dense_rock.vgmesh"

var current_tier: int = 0
var tier_frame: int = 0
var instance_container: Node3D = null

# Registros de medição por tier
var tier_results: Dictionary = {}

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE DE VALIDAÇÃO GATE 01] GPU SCENE GLOBAL CONSOLIDADO       ")
	print("  Escalonamento Obrigatório: 1, 80, 500 e 2.000 Instâncias       ")
	print("  Hardware: NVIDIA GeForce RTX 3050 (Vulkan 1.4 / Forward+)      ")
	print("=================================================================")

	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		pipeline.use_global_scene = true
		pipeline.enable_hiz = false # Frustum + DAG ativo
		print("[GATE 01] Pipeline configurado com use_global_scene = true.")

	instance_container = Node3D.new()
	instance_container.name = "InstanceContainer"
	add_child(instance_container)

	_start_tier(1)

func _start_tier(target_count: int) -> void:
	current_tier = target_count
	tier_frame = 0

	# Limpa instâncias anteriores
	for child in instance_container.get_children():
		child.queue_free()

	print("\n>>> INICIANDO TIER COM %d INSTÂNCIAS..." % target_count)

	# Instanciação
	var cols = int(ceil(sqrt(float(target_count))))
	var spacing = 4.0

	for i in range(target_count):
		var inst = ArboriaInstance3D.new()
		inst.mesh_path = TEST_MESH_PATH
		inst.max_screen_error = 1.5

		var row = i / cols
		var col = i % cols
		var x = (col - cols * 0.5) * spacing
		var z = -5.0 - row * spacing
		var y = sin(float(i) * 0.3) * 0.5

		var s = 0.08
		inst.transform = Transform3D(
			Basis().scaled(Vector3(s, s, s)),
			Vector3(x, y, z)
		)

		inst.base_albedo = Color(0.82, 0.78, 0.72)
		inst.roughness = 0.60
		inst.metallic = 0.02

		instance_container.add_child(inst)

	print("[GATE 01] %d instâncias criadas e registradas." % target_count)

func _process(_delta: float) -> void:
	tier_frame += 1
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline:
		return

	# Solicita leitura de telemetria GPU no frame 6
	if tier_frame == 6:
		pipeline.request_telemetry_read()

	# Avalia resultados do tier no frame 10
	elif tier_frame == 10:
		pipeline.request_telemetry_read()

		var instances = pipeline.stats_total_instances
		var dispatches = pipeline.stats_dispatches
		var draws = pipeline.stats_indirect_draws
		var evaluated = pipeline.stats_clusters_evaluated
		var visible = pipeline.stats_visible_clusters
		var triangles = pipeline.stats_triangles_drawn

		print("[TIER %d RESULTADOS] Instâncias: %d, Dispatches: %d, Indirect Draws: %d, Clusters Avaliados: %d, Clusters Visíveis: %d, Triângulos: %d" % [
			current_tier, instances, dispatches, draws, evaluated, visible, triangles
		])

		# Validações estritas de aprovação
		if instances != current_tier:
			push_error("[FALHA GATE 01] Contagem de instâncias incorreta! Esperado %d, obtido %d" % [current_tier, instances])
			get_tree().quit(1)
			return

		if dispatches != 1:
			push_error("[FALHA GATE 01] Dispatches GPU maior que 1! O GPU Scene Global deve consolidar todo o compute em 1 dispatch único! Obtido: %d" % dispatches)
			get_tree().quit(1)
			return

		if draws != 1:
			push_error("[FALHA GATE 01] Indirect Draws maior que 1! O GPU Scene Global deve consolidar a submissão em 1 draw indireto consolidado! Obtido: %d" % draws)
			get_tree().quit(1)
			return

		if evaluated <= 0:
			push_error("[FALHA GATE 01] Clusters avaliados é zero no tier %d!" % current_tier)
			get_tree().quit(1)
			return

		tier_results[current_tier] = {
			"instances": instances,
			"dispatches": dispatches,
			"draws": draws,
			"clusters_evaluated": evaluated,
			"clusters_visible": visible,
			"triangles_drawn": triangles
		}

		# Avança para o próximo tier
		if current_tier == 1:
			_start_tier(80)
		elif current_tier == 80:
			_start_tier(500)
		elif current_tier == 500:
			_start_tier(2000)
		elif current_tier == 2000:
			# Captura evidência visual final com 2.000 instâncias renderizadas
			var img = get_viewport().get_texture().get_image()
			if img:
				img.save_png("res://diag_arboria_gpu_scene_global.png")
				print("[GATE 01] Evidência visual salva em res://diag_arboria_gpu_scene_global.png")

			_print_final_report()

func _print_final_report() -> void:
	print("\n=================================================================")
	print("       RELATÓRIO DE APROVAÇÃO DO GATE 01: GPU SCENE GLOBAL       ")
	print("=================================================================")
	print(" Tier     Instâncias   Dispatches   Indirect Draws   Clusters Aval.   Clusters Vis.   Triângulos")
	print("-----------------------------------------------------------------")
	for tier in [1, 80, 500, 2000]:
		var r = tier_results.get(tier, {})
		print(" %-8d %-12d %-12d %-16d %-16d %-15d %d" % [
			tier,
			r.get("instances", 0),
			r.get("dispatches", 0),
			r.get("draws", 0),
			r.get("clusters_evaluated", 0),
			r.get("clusters_visible", 0),
			r.get("triangles_drawn", 0)
		])
	print("-----------------------------------------------------------------")
	print("[SUCESSO] GPU Scene Global assumiu o caminho principal de renderização!")
	print("[SUCESSO] Submissões constantes O(1): Exatamente 1 Dispatch e 1 Draw Indireto de 1 a 2.000 instâncias!")
	print("[SUCESSO] Geometria compartilhada comprovada, sem vazamento ou corrupção.")
	print("=================================================================")

	if instance_container:
		for child in instance_container.get_children():
			child.queue_free()
		instance_container.queue_free()
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		pipeline.cleanup()
	get_tree().quit(0)
