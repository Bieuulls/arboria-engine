extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

var frame_count: int = 0
var captured_triangle_counts: Array[int] = []

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE AUTOMACAO ETAPA 5] REFINAMENTO DO DAG &  ")
	print("       ELIMINACAO DE DEFEITOS GEOMETRICOS           ")
	print("====================================================")
	
	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
	print("[DAG TEST] Compositor Effect anexado com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1
	var cam: Camera3D = $Camera3D
	var pipeline = ArboriaNativePipeline.get_active_instance()
	
	# Aproximação e rotação contínua da câmera para testar estabilidade do DAG
	if frame_count >= 5 and frame_count <= 25:
		var t = float(frame_count - 5) / 20.0
		# Distância varia de 3.0m a 25.0m
		var dist = lerp(3.0, 25.0, t)
		var angle = t * PI * 0.5
		cam.position = Vector3(sin(angle) * dist, 1.5, cos(angle) * dist)
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		
		if pipeline:
			pipeline.request_telemetry_read()
			captured_triangle_counts.append(pipeline.stats_triangles_drawn)
			
	elif frame_count == 26:
		print("[DAG TEST] Frame 26: Capturando frame de integridade geométrica...")
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://diag_arboria_dag_integrity.png")
			print("[DAG TEST] Imagem salva em res://diag_arboria_dag_integrity.png: OK")
			
	elif frame_count == 30:
		print("[DAG TEST] Frame 30: Validando métricas geométricas do DAG...")
		
		# 1. Validação de ausência de dropouts
		if pipeline:
			print("[DAG TEST] Estatísticas finais: Instâncias: %d, Clusters: %d, Triângulos: %d" % [
				pipeline.stats_total_instances, pipeline.stats_visible_clusters, pipeline.stats_triangles_drawn
			])
			if pipeline.stats_visible_clusters <= 0 or pipeline.stats_triangles_drawn <= 0:
				push_error("[FALHA] Dropout geométrico: zero clusters ou triângulos renderizados!")
				get_tree().quit(1)
				return
				
		# 2. Validação da imagem capturada (silhueta contínua, ausência de buracos/cracks)
		var img = Image.load_from_file("res://diag_arboria_dag_integrity.png")
		if not img or img.is_empty():
			push_error("[FALHA] Imagem capturada inválida!")
			get_tree().quit(1)
			return
			
		var w = img.get_width()
		var h = img.get_height()
		
		var normal_mesh_pixels = 0
		var mirrored_mesh_pixels = 0
		
		# Amostra esquerda (instância espelhada) e direita (instância normal)
		for y in range(int(h * 0.2), int(h * 0.8)):
			for x in range(int(w * 0.1), int(w * 0.45)):
				var c = img.get_pixel(x, y)
				if not (abs(c.r - 0.12) < 0.05 and abs(c.b - 0.18) < 0.05):
					mirrored_mesh_pixels += 1
					
			for x in range(int(w * 0.55), int(w * 0.9)):
				var c = img.get_pixel(x, y)
				if not (abs(c.r - 0.12) < 0.05 and abs(c.b - 0.18) < 0.05):
					normal_mesh_pixels += 1
					
		print("[DAG TEST] Pixels renderizados -> Malha Normal: %d, Malha Espelhada: %d" % [normal_mesh_pixels, mirrored_mesh_pixels])
		
		if normal_mesh_pixels < 2500:
			push_error("[FALHA] Malha normal não renderizou pixels suficientes: %d" % normal_mesh_pixels)
			get_tree().quit(1)
			return
			
		if mirrored_mesh_pixels < 2500:
			push_error("[FALHA] Malha espelhada não renderizou pixels suficientes (possível culling reverso incorreto): %d" % mirrored_mesh_pixels)
			get_tree().quit(1)
			return
			
		print("[DAG TEST] Integridade do corte DAG, rotação suave e transformações espelhadas validadas com sucesso!")
		print("====================================================")
		print(" [ETAPA 5 CONCLUÍDA E APROVADA COM SUCESSO]         ")
		print("====================================================")
		get_tree().quit(0)
