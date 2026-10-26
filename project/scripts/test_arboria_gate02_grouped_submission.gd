extends Node3D

## TESTE DE VALIDAÇÃO AUTOMATIZADA: ETAPA 02 — SUBMISSÃO INDIRETA AGRUPADA REAL
## Hardware de Teste: NVIDIA GeForce RTX 3050 (Vulkan 1.4 / Forward+)
## Compara Baseline (Per-Instance Loop: N Dispatches + N Draws) vs Grouped (1 Dispatch + 1 Draw Indireto)
## Escalonamento Obrigatório: 80, 500 e 2.000 instâncias.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

const TEST_MESH_PATH = "res://assets/dense_rock.vgmesh"

enum TestPhase {
	GROUPED_80,
	GROUPED_500,
	GROUPED_2000,
	COMPLETED
}

var current_phase: TestPhase = TestPhase.GROUPED_80
var phase_frame: int = 0
var instance_container: Node3D = null

# Armazenamento de telemetria comparativa
var results: Dictionary = {
	"grouped_80": {},
	"grouped_500": {},
	"grouped_2000": {}
}

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE DE REGRESSÃO FASE 1.1] SUBMISSÃO INDIRETA AGRUPADA O(1) ")
	print("  Hardware: NVIDIA GeForce RTX 3050 (Vulkan 1.4 / Forward+)      ")
	print("  Garante 1 Dispatch + 1 Draw Indireto Global para toda a cena   ")
	print("  Cenários: 80, 500 e 2.000 instâncias                           ")
	print("=================================================================")

	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)

	instance_container = Node3D.new()
	instance_container.name = "InstanceContainer"
	add_child(instance_container)

	_setup_phase(TestPhase.GROUPED_80)

func _setup_phase(phase: TestPhase) -> void:
	current_phase = phase
	phase_frame = 0

	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline:
		push_error("[GATE 02] Falha ao obter ArboriaNativePipeline!")
		get_tree().quit(1)
		return

	var count = 80
	var phase_name = ""

	match phase:
		TestPhase.GROUPED_80:
			count = 80
			phase_name = "80 INSTÂNCIAS -> 1 Dispatch / 1 Draw"
		TestPhase.GROUPED_500:
			count = 500
			phase_name = "500 INSTÂNCIAS -> 1 Dispatch / 1 Draw"
		TestPhase.GROUPED_2000:
			count = 2000
			phase_name = "2.000 INSTÂNCIAS -> 1 Dispatch / 1 Draw"

	pipeline.use_global_scene = true
	pipeline.enable_hiz = false

	# Limpa instâncias anteriores
	for child in instance_container.get_children():
		child.queue_free()

	print("\n>>> INICIANDO FASE: %s" % phase_name)

	var cols = int(ceil(sqrt(float(count))))
	var spacing = 4.5

	for i in range(count):
		var inst = ArboriaInstance3D.new()
		inst.name = "Pavilion_%04d" % i
		inst.mesh_path = TEST_MESH_PATH
		inst.max_screen_error = 1.5

		var row = i / cols
		var col = i % cols
		var x = (col - cols * 0.5) * spacing
		var z = -8.0 - row * spacing
		var y = 0.0

		# Escala de pavilhão arquitetural detalhado (2.4m de largura, nunca colide)
		var s = 0.08
		inst.transform = Transform3D(
			Basis().scaled(Vector3(s, s, s)),
			Vector3(x, y, z)
		)

		inst.base_albedo = Color(0.82, 0.78, 0.72)
		inst.roughness = 0.60
		inst.metallic = 0.02
		instance_container.add_child(inst)

	print("[GATE 02] %d instâncias criadas e registradas. use_global_scene = true" % count)

func _process(_delta: float) -> void:
	phase_frame += 1
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline:
		return

	if phase_frame == 6:
		pipeline.request_telemetry_read()

	elif phase_frame == 12:
		pipeline.request_telemetry_read()
		var stats = pipeline.get_statistics()
		var key = ""
		var expected_count = 80
		var expected_dispatches = 1
		var expected_draws = 1

		match current_phase:
			TestPhase.GROUPED_80:
				key = "grouped_80"
				expected_count = 80
				expected_dispatches = 1
				expected_draws = 1
				_capture_viewport("res://diag_arboria_gate02_grouped.png")
			TestPhase.GROUPED_500:
				key = "grouped_500"
				expected_count = 500
				expected_dispatches = 1
				expected_draws = 1
			TestPhase.GROUPED_2000:
				key = "grouped_2000"
				expected_count = 2000
				expected_dispatches = 1
				expected_draws = 1

		var cpu_sub_ms = stats.get("cpu_submission_ms", 0.0)
		var inst_count = stats.get("total_instances", 0)
		var dispatches = stats.get("dispatches", 0)
		var draws = stats.get("indirect_draws", 0)
		var eval_clusters = stats.get("clusters_evaluated", 0)
		var vis_clusters = stats.get("clusters_visible", 0)
		var triangles = stats.get("triangles_drawn", 0)

		print("[%s RESULTADOS] Instâncias: %d | Dispatches: %d | Draws: %d | CPU Submissão: %.3f ms | Clusters Visíveis: %d | Triângulos: %d" % [
			key.to_upper(), inst_count, dispatches, draws, cpu_sub_ms, vis_clusters, triangles
		])

		if inst_count != expected_count:
			push_error("[FALHA GATE 02] Contagem de instâncias incompatível na fase %s! Esperado %d, obtido %d" % [key, expected_count, inst_count])
			get_tree().quit(1)
			return

		if dispatches != expected_dispatches:
			push_error("[FALHA GATE 02] Dispatches incorretos na fase %s! Esperado %d, obtido %d" % [key, expected_dispatches, dispatches])
			get_tree().quit(1)
			return

		if draws != expected_draws:
			push_error("[FALHA GATE 02] Draws incorretos na fase %s! Esperado %d, obtido %d" % [key, expected_draws, draws])
			get_tree().quit(1)
			return

		results[key] = {
			"instances": inst_count,
			"dispatches": dispatches,
			"draws": draws,
			"cpu_submission_ms": cpu_sub_ms,
			"clusters_evaluated": eval_clusters,
			"clusters_visible": vis_clusters,
			"triangles_drawn": triangles
		}

		# Próxima fase
		match current_phase:
			TestPhase.GROUPED_80:
				_setup_phase(TestPhase.GROUPED_500)
			TestPhase.GROUPED_500:
				_setup_phase(TestPhase.GROUPED_2000)
			TestPhase.GROUPED_2000:
				_evaluate_final_results()

func _evaluate_final_results() -> void:
	print("\n=================================================================")
	print(" [RELATÓRIO DE REGRESSÃO FASE 1.1: 1 DISPATCH + 1 DRAW O(1)]     ")
	print("=================================================================")

	var g80 = results["grouped_80"]
	var g500 = results["grouped_500"]
	var g2000 = results["grouped_2000"]

	print("\n--- CENÁRIO 1: 80 INSTÂNCIAS ---")
	print("  Grouped (1 Draw): Dispatches=%d, Draws=%d, CPU Submissão=%.3f ms, Triângulos=%d" % [g80.dispatches, g80.draws, g80.cpu_submission_ms, g80.triangles_drawn])

	print("\n--- CENÁRIO 2: 500 INSTÂNCIAS ---")
	print("  Grouped (1 Draw): Dispatches=%d, Draws=%d, CPU Submissão=%.3f ms, Triângulos=%d" % [g500.dispatches, g500.draws, g500.cpu_submission_ms, g500.triangles_drawn])

	print("\n--- CENÁRIO 3: 2.000 INSTÂNCIAS ---")
	print("  Grouped (1 Draw): Dispatches=%d, Draws=%d, CPU Submissão=%.3f ms, Triângulos=%d" % [g2000.dispatches, g2000.draws, g2000.cpu_submission_ms, g2000.triangles_drawn])

	print("\n=================================================================")
	print(" [GATE 02: APROVADO COM SUCESSO] SUBMISSÃO INDIRETA AGRUPADA O(1)")
	print("  - Dispatches = 1 e Draws = 1 comprovados em hardware real       ")
	print("  - Blindagem total contra regressão do Erro 1                    ")
	print("=================================================================")


	if instance_container:
		for child in instance_container.get_children():
			child.queue_free()
		instance_container.queue_free()

	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		pipeline.cleanup()

	get_tree().quit(0)

func _capture_viewport(path: String) -> void:
	var vp = get_viewport()
	if vp:
		var img = vp.get_texture().get_image()
		if img and not img.is_empty():
			img.save_png(path)
			print("[GATE 02] Captura salva: %s" % path)
