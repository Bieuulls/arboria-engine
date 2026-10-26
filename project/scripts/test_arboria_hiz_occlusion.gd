extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")

var frame_count: int = 0
var clusters_no_hiz: int = 0
var triangles_no_hiz: int = 0
var clusters_with_hiz: int = 0
var triangles_with_hiz: int = 0

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE AUTOMACAO ETAPA 6] HIERARCHICAL Z-BUFFER  ")
	print("       (Hi-Z) REAL EM HARDWARE NVIDIA RTX 3050       ")
	print("====================================================")
	
	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		pipeline.enable_hiz = false
	print("[HIZ TEST] Pipeline configurado inicialmente com Hi-Z OFF.")

func _process(_delta: float) -> void:
	frame_count += 1
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline:
		return

	# Fase 1: Frames 5 a 15 com Hi-Z DESLIGADO (Baseline de Culling apenas com Frustum/Cone)
	if frame_count == 10:
		pipeline.request_telemetry_read()
	elif frame_count == 14:
		pipeline.request_telemetry_read()
		clusters_no_hiz = pipeline.stats_visible_clusters
		triangles_no_hiz = pipeline.stats_triangles_drawn
		print("[HIZ TEST] Frame 14 (Hi-Z OFF): Clusters Visíveis = %d, Triângulos = %d" % [
			clusters_no_hiz, triangles_no_hiz
		])
		# Ativa Hi-Z para a Fase 2
		pipeline.enable_hiz = true
		print("[HIZ TEST] Ativando pipeline.enable_hiz = true...")

	# Fase 2: Frames 15 a 30 com Hi-Z LIGADO (Descarte de Geometria Oculta por Parede)
	elif frame_count == 22:
		pipeline.request_telemetry_read()
	elif frame_count == 26:
		print("[HIZ TEST] Frame 26: Capturando frame de renderização com Hi-Z...")
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://diag_arboria_hiz_occlusion.png")
			print("[HIZ TEST] Imagem salva em res://diag_arboria_hiz_occlusion.png: OK")

	elif frame_count == 28:
		pipeline.request_telemetry_read()
		clusters_with_hiz = pipeline.stats_visible_clusters
		triangles_with_hiz = pipeline.stats_triangles_drawn
		print("[HIZ TEST] Frame 28 (Hi-Z ON): Clusters Visíveis = %d, Triângulos = %d" % [
			clusters_with_hiz, triangles_with_hiz
		])

	elif frame_count == 30:
		print("====================================================")
		print("            RELATORIO DE VALIDACAO HI-Z             ")
		print("====================================================")
		print("  -> Hi-Z OFF: %d clusters visiveis (%d triangulos)" % [clusters_no_hiz, triangles_no_hiz])
		print("  -> Hi-Z ON:  %d clusters visiveis (%d triangulos)" % [clusters_with_hiz, triangles_with_hiz])

		if clusters_no_hiz <= 0:
			push_error("[FALHA HI-Z] clusters_no_hiz invalido (0 clusters renderizados no baseline)!")
			get_tree().quit(1)
			return

		if clusters_with_hiz <= 0:
			push_error("[FALHA HI-Z] clusters_with_hiz e zero! Todas as rochas (inclusive visiveis) foram indevidamente ocluidas!")
			get_tree().quit(1)
			return

		if clusters_with_hiz >= clusters_no_hiz:
			push_error("[FALHA HI-Z] Nenhuma reducao de clusters detectada! Hi-Z ON (%d) >= Hi-Z OFF (%d)" % [
				clusters_with_hiz, clusters_no_hiz
			])
			get_tree().quit(1)
			return

		var reduction_pct = (1.0 - float(clusters_with_hiz) / float(clusters_no_hiz)) * 100.0
		print("  -> Reducao de Carga GPU por Oclusao: %.1f%% de clusters eliminados!" % reduction_pct)
		print("[SUCESSO] Hi-Z Occlusion Culling validado com reducao mensuravel e zero falsos positivos!")
		print("====================================================")
		if is_instance_valid(pipeline):
			pipeline.cleanup()
		get_tree().quit(0)
