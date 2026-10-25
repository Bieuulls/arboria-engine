extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

var frame_count: int = 0
var demo_scene: Node = null
var captured_img: Image = null

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE AUTOMACAO V7.2] ARBORIA NATIVE SUITE     ")
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

	elif frame_count >= 10 and frame_count <= 24:
		# Movimentacao dinamica da camera 3D para testar Reversed-Z depth em movimento
		var cam: Camera3D = demo_scene.get_node("OrbitCamera")
		var t = float(frame_count - 10) / 14.0
		# Oscilação suave na posição da câmera (testa oclusão contínua em movimento)
		var offset_x = sin(t * TAU) * 0.5
		var offset_y = cos(t * TAU) * 0.25
		cam.global_position = Vector3(8.0 + offset_x, 4.0 + offset_y, 8.0)
		cam.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)

	elif frame_count == 25:
		# Retorna à posição de enquadramento canônico
		var cam: Camera3D = demo_scene.get_node("OrbitCamera")
		cam.global_position = Vector3(8.0, 4.0, 8.0)
		cam.look_at(Vector3(0.0, 0.5, 0.0), Vector3.UP)

		var pipeline = ArboriaNativePipeline.get_active_instance()
		if pipeline:
			pipeline.request_telemetry_read()

	elif frame_count == 27:
		captured_img = get_viewport().get_texture().get_image()
		if captured_img:
			captured_img.save_png("res://diag_arboria_native_demo_frame.png")
			print("[TESTE ETAPA 5] Captura salva: diag_arboria_native_demo_frame.png: OK")

	elif frame_count == 28:
		print("[TESTE ETAPA 6] Executando validacao automatica rigorosa (Requisitos V7.2)...")
		var pipeline = ArboriaNativePipeline.get_active_instance()

		# 1. Validacao do Backend C++ GDExtension real
		if not pipeline or not pipeline.is_initialized:
			push_error("[FALHA] Pipeline nativo nao inicializado.")
			get_tree().quit(1)
			return

		if not pipeline.native_core:
			push_error("[FALHA] ArboriaNativeCore C++ nao instanciado no pipeline.")
			get_tree().quit(1)
			return

		if not pipeline.native_core.is_active():
			push_error("[FALHA] ArboriaNativeCore C++ is_active retornou falso.")
			get_tree().quit(1)
			return

		var c_active_instances = pipeline.native_core.scene_get_active_count()
		print("[TESTE] Backend C++ ativo: ", pipeline.native_core.get_version(), " (Instancias no VGSceneBridge: %d)" % c_active_instances)
		if c_active_instances != 2:
			push_error("[FALHA] VGSceneBridge C++ esperado 2 instancias ativas, obtido: %d" % c_active_instances)
			get_tree().quit(1)
			return
		print("[TESTE] 1. Backend C++ (VGRuntime/VGSceneBridge) executando ativamente: OK")

		# 2. Validacao de desenho indireto e telemetria da GPU
		if pipeline.stats_total_instances != 2:
			push_error("[FALHA] Esperadas 2 instancias virtuais ativas, obtido: %d" % pipeline.stats_total_instances)
			get_tree().quit(1)
			return

		if pipeline.stats_visible_clusters <= 0:
			push_error("[FALHA] Nenhum cluster visivel processado pelo compute shader (Clusters: %d)." % pipeline.stats_visible_clusters)
			get_tree().quit(1)
			return

		if pipeline.stats_triangles_drawn <= 0:
			push_error("[FALHA] Nenhum triangulo desenhado via draw indirect (Triangulos: %d)." % pipeline.stats_triangles_drawn)
			get_tree().quit(1)
			return
		print("[TESTE] 2. Desenho indireto e telemetria GPU validada (Clusters: %d, Triangulos: %d): OK" % [pipeline.stats_visible_clusters, pipeline.stats_triangles_drawn])

		# 3. Validacao de nao-dependencia de MultiMesh legado
		var rock1 = demo_scene.get_node("VirtualMesh_Rock1")
		var rock2 = demo_scene.get_node("VirtualMesh_Rock2")
		if rock1.has_node("MultiMeshInstance3D") or rock2.has_node("MultiMeshInstance3D"):
			push_error("[FALHA] Detectada dependencia residual de MultiMesh legado.")
			get_tree().quit(1)
			return
		print("[TESTE] 3. Sem dependencia de MultiMesh legado: OK")

		# 4. Validacao dos pixels na imagem capturada
		var img = captured_img
		if not img:
			img = Image.load_from_file("res://diag_arboria_native_demo_frame.png")
		if not img or img.is_empty():
			push_error("[FALHA] Imagem capturada invalida ou vazia.")
			get_tree().quit(1)
			return

		var width = img.get_width()
		var height = img.get_height()
		var cube_pixels = 0
		var rock_pixels = 0
		var floor_pixels = 0
		var sky_pixels = 0

		for y in range(height):
			for x in range(width):
				var c = img.get_pixel(x, y)
				# Cubo convencional (vermelho em sombra / iluminação Forward+)
				if c.r > 0.12 and c.r > c.g * 1.8 and c.r > c.b * 1.8:
					cube_pixels += 1
				# Céu / background
				elif abs(c.r - 0.12) < 0.04 and abs(c.g - 0.14) < 0.04 and abs(c.b - 0.18) < 0.04:
					sky_pixels += 1
				# Chão
				elif abs(c.r - 0.25) < 0.06 and abs(c.g - 0.27) < 0.06 and abs(c.b - 0.30) < 0.06:
					floor_pixels += 1
				# Geometria virtualizada ARBORIA (exclui área de UI no topo-esquerdo)
				elif (x > 350 or y > 400):
					rock_pixels += 1

		print("[TESTE] Pixels detectados -> Cubo: %d, Rochas ARBORIA: %d, Chao: %d, Ceu: %d" % [cube_pixels, rock_pixels, floor_pixels, sky_pixels])

		if cube_pixels < 5000:
			push_error("[FALHA] Cubo convencional ausente ou encoberto incorretamente (Pixels: %d < 5000)." % cube_pixels)
			get_tree().quit(1)
			return

		if rock_pixels < 50000:
			push_error("[FALHA] Geometria virtualizada ARBORIA ausente dos pixels capturados (Pixels: %d < 50000)." % rock_pixels)
			get_tree().quit(1)
			return
		print("[TESTE] 4. Pixels de geometria virtualizada e cubo convencional presentes: OK")

		# 5. Validacao de oclusao bidirecional de profundidade
		var cube_center_sample = img.get_pixel(495, 391)
		var rock_left_sample = img.get_pixel(370, 391)
		var rock_right_sample = img.get_pixel(650, 391)

		var is_cube_center_red = (cube_center_sample.r > 0.12 and cube_center_sample.r > cube_center_sample.g * 1.8)
		var is_rock_left_visible = not (abs(rock_left_sample.r - 0.12) < 0.04 and abs(rock_left_sample.b - 0.18) < 0.04)
		var is_rock_right_visible = not (abs(rock_right_sample.r - 0.12) < 0.04 and abs(rock_right_sample.b - 0.18) < 0.04)

		if not is_cube_center_red:
			push_error("[FALHA] Oclusao incorreta: Cubo convencional nao ocluiu a Rocha 1 a sua frente.")
			get_tree().quit(1)
			return

		if not (is_rock_left_visible and is_rock_right_visible):
			push_error("[FALHA] Oclusao incorreta: Rocha 1 nao esta visivel ao redor do Cubo.")
			get_tree().quit(1)
			return
		print("[TESTE] 5. Oclusao bidirecional de profundidade validada nos pixels mesmo apos camera em movimento: OK")

	elif frame_count == 32:
		print("====================================================")
		print(" [TESTE CONCLUIDO COM SUCESSO ABSOLUTO V7.2]        ")
		print("====================================================")
		get_tree().quit(0)
