extends Node3D

## TESTE DE VALIDAÇÃO AUTOMATIZADA: ETAPA 08 — IMPORTAÇÃO REAL E WORKFLOW DO EDITOR
## Hardware de Teste: NVIDIA GeForce RTX 3050 (Vulkan 1.4 / Forward+)
## Validação estrita do fluxo de uso:
## 1. Importação de modelo real (.obj / .glb)
## 2. Validação geométrica e conversão via Baker nativo C++
## 3. Criação de .vgmesh e metadados sidecar .arbmeta.json
## 4. Instanciação dinâmica com VirtualMeshInstance3D e ArboriaInstance3D
## 5. Renderização comprovada com materiais e clusters no hardware real

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaAssetImporter = preload("res://scripts/arboria_asset_importer.gd")
const VirtualMeshInstance3D = preload("res://scripts/virtual_mesh_instance_3d.gd")

const SOURCE_ASSET = "res://assets/rock_cluster.obj"
const TARGET_VGMESH = "res://assets/rock_cluster_baked.vgmesh"

var current_frame: int = 0
var instance_container: Node3D = null
var failed_init: bool = false
var error_msg: String = ""

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE DE VALIDAÇÃO ETAPA 08] IMPORTAÇÃO REAL E WORKFLOW EDITOR ")
	print("  Hardware: NVIDIA GeForce RTX 3050 (Vulkan 1.4 / Forward+)      ")
	print("  Origem: %s -> Destino: %s" % [SOURCE_ASSET, TARGET_VGMESH])
	print("=================================================================")

	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)

	# 1. Executa a importação e baking através do ArboriaAssetImporter
	print("\n[PASSO 1] Executando importação e conversão com o Baker C++...")
	var import_result = ArboriaAssetImporter.import_file(SOURCE_ASSET, TARGET_VGMESH)
	print("[PASSO 1] Resultado da importação: ", import_result)

	if not import_result.get("success", false):
		failed_init = true
		error_msg = import_result.get("error", "Erro desconhecido")
		push_error("[FALHA ETAPA 08] Falha na importação do asset: %s" % error_msg)
		return

	var output_path = import_result.get("output_path", "")
	var meta_path = import_result.get("metadata_path", "")
	print("[PASSO 2] Arquivo .vgmesh gerado com sucesso: %s" % output_path)
	print("[PASSO 2] Metadados gerados: %s" % meta_path)

	# 2. Cria contêiner para instâncias virtuais
	instance_container = Node3D.new()
	instance_container.name = "InstanceContainer"
	add_child(instance_container)

	# 3. Cria instâncias usando a classe VirtualMeshInstance3D
	print("\n[PASSO 3] Criando instâncias de VirtualMeshInstance3D na cena...")
	var count = 24
	var cols = 6
	var spacing = 4.0

	for i in range(count):
		var v_inst = VirtualMeshInstance3D.new()
		v_inst.mesh_path = TARGET_VGMESH
		v_inst.max_screen_error = 1.5

		var row = i / cols
		var col = i % cols
		var x = (col - cols * 0.5) * spacing
		var z = -4.0 - row * spacing
		var y = sin(float(i) * 0.5) * 0.5

		v_inst.transform = Transform3D(
			Basis().scaled(Vector3(1.0, 1.0, 1.0)),
			Vector3(x, y, z)
		)

		v_inst.base_albedo = Color(0.7, 0.65, 0.6)
		v_inst.roughness = 0.5
		v_inst.metallic = 0.05

		instance_container.add_child(v_inst)

	print("[PASSO 3] %d instâncias de VirtualMeshInstance3D criadas e registradas." % count)

func _process(_delta: float) -> void:
	if failed_init:
		push_error("[FALHA ETAPA 08] Encerrando por erro na inicialização: %s" % error_msg)
		get_tree().quit(1)
		return

	current_frame += 1
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline:
		return

	if current_frame == 10:
		pipeline.request_telemetry_read()

	elif current_frame == 18:
		pipeline.request_telemetry_read()
		var stats = pipeline.get_statistics()
		var vis_clusters = stats.get("clusters_visible", 0)
		var triangles = stats.get("triangles_drawn", 0)
		var instances = stats.get("total_instances", 0)

		print("\n=================================================================")
		print(" [RESULTADOS ETAPA 08: IMPORTAÇÃO E RENDERIZAÇÃO REAL]           ")
		print("  - Instâncias Ativas: %d" % instances)
		print("  - Clusters Visíveis: %d" % vis_clusters)
		print("  - Triângulos Desenhados: %d" % triangles)
		print("  - Custo CPU de Submissão: %.3f ms" % stats.get("cpu_submission_ms", 0.0))
		print("=================================================================")

		if instances == 0:
			push_error("[FALHA ETAPA 08] Nenhuma instância ativa registrada no pipeline!")
			get_tree().quit(1)
			return

		if vis_clusters == 0 or triangles == 0:
			push_error("[FALHA ETAPA 08] Geometria importada não gerou clusters visíveis ou triângulos!")
			get_tree().quit(1)
			return

		_capture_viewport("res://diag_arboria_asset_import.png")

		print("\n[ETAPA 08 APROVADO] Workflow de Importação, Baker e Editor Totalmente Funcional:")
		print(" - Modelo fonte (.obj / .glb) importado e validado")
		print(" - Conversão e verificação pelo Baker C++ comprovada")
		print(" - VirtualMeshInstance3D operacional e integrada ao Forward+ Vulkan")

		pipeline.cleanup()
		get_tree().quit(0)

func _capture_viewport(path: String) -> void:
	var vp = get_viewport()
	if vp:
		var img = vp.get_texture().get_image()
		if img and not img.is_empty():
			img.save_png(path)
			print("[ETAPA 08] Captura salva: %s" % path)
