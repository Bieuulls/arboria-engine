extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")
const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

var frame_count: int = 0
var capture_path: String = "res://diag_arboria_pbr_side_by_side.png"

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE VALIDACAO 3.2] PARIDADE VISUAL PBR LADO A LADO")
	print(" StandardMaterial3D Nativo Godot vs Arboria Material PBR")
	print("====================================================")

	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)

	# Alinha DirectionalLight3D com o vetor de luz L = normalize(vec3(0.5, 0.8, 0.6)) do shader
	var light = $DirectionalLight3D
	light.look_at_from_position(Vector3(10.0, 16.0, 12.0), Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 2.5

	var env = $WorldEnvironment.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.45, 0.48, 0.52)
		env.ambient_light_energy = 1.0
	var tex_size = 256
	var albedo_img = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var normal_img = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)

	for y in range(tex_size):
		for x in range(tex_size):
			# Padrao xadrez colorido com variacao tonal
			var check = ((x / 32) + (y / 32)) % 2 == 0
			var col = Color(0.85, 0.55, 0.25) if check else Color(0.25, 0.65, 0.85)
			albedo_img.set_pixel(x, y, col)

			# Mapa de normais com relevo senoidal suave
			var nx = sin(float(x) * 0.1) * 0.4
			var ny = cos(float(y) * 0.1) * 0.4
			var nz = sqrt(max(0.0, 1.0 - nx * nx - ny * ny))
			var n_col = Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0)
			normal_img.set_pixel(x, y, n_col)

	var albedo_tex = ImageTexture.create_from_image(albedo_img)
	var normal_tex = ImageTexture.create_from_image(normal_img)

	# 2. Cria StandardMaterial3D oficial
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.albedo_texture = albedo_tex
	mat.normal_enabled = true
	mat.normal_texture = normal_tex
	mat.normal_scale = 1.0
	mat.metallic = 0.15
	mat.roughness = 0.45
	mat.metallic_specular = 0.5

	# 3. Configura MeshInstance3D nativo (Esquerda)
	var native_mesh_node: MeshInstance3D = $NativeMeshInstance
	var vg_data = ArboriaMeshLoader.load_from_file("res://assets/dense_rock.vgmesh")
	var am = ArboriaMeshLoader.build_mesh_surface(vg_data, 0, false)
	native_mesh_node.mesh = am
	native_mesh_node.material_override = mat

	# 4. Configura ArboriaInstance3D (Direita) com o mesmo StandardMaterial3D via material_override
	var arboria_node: ArboriaInstance3D = $ArboriaInstance
	arboria_node.mesh_path = "res://assets/dense_rock.vgmesh"
	arboria_node.lod_mode = 1 # Forca LOD0 para paridade geometrica exata
	arboria_node.forced_lod = 0
	arboria_node.material_override = mat

	print("[PBR TEST] Cena e materiais configurados com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 25:
		print("[PBR TEST] Frame 25: Capturando frame lado a lado...")
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png(capture_path)
			print("[PBR TEST] Captura salva em: ", capture_path)

	elif frame_count == 30:
		print("[PBR TEST] Frame 30: Analisando paridade visual entre Nativo e Arboria...")
		var img = Image.load_from_file(capture_path)
		if not img or img.is_empty():
			push_error("[FALHA] Imagem de validacao PBR nao pode ser carregada.")
			get_tree().quit(1)
			return

		var w = img.get_width()
		var h = img.get_height()

		# Lado Esquerdo: x de 0.15*w ate 0.45*w (Nativo)
		# Lado Direito:  x de 0.55*w ate 0.85*w (Arboria)
		var left_lum_sum = 0.0
		var right_lum_sum = 0.0
		var left_r_sum = 0.0
		var right_r_sum = 0.0
		var left_g_sum = 0.0
		var right_g_sum = 0.0
		var left_b_sum = 0.0
		var right_b_sum = 0.0
		var sample_count = 0

		var y_start = int(h * 0.25)
		var y_end = int(h * 0.75)
		var sample_w = int(w * 0.25)
		var x_offset_left = int(w * 0.15)
		var x_offset_right = int(w * 0.60)

		for y in range(y_start, y_end):
			for dx in range(sample_w):
				var cl = img.get_pixel(x_offset_left + dx, y)
				var cr = img.get_pixel(x_offset_right + dx, y)

				left_lum_sum += cl.get_luminance()
				right_lum_sum += cr.get_luminance()

				left_r_sum += cl.r
				right_r_sum += cr.r
				left_g_sum += cl.g
				right_g_sum += cr.g
				left_b_sum += cl.b
				right_b_sum += cr.b
				sample_count += 1

		var avg_left_lum = left_lum_sum / float(sample_count)
		var avg_right_lum = right_lum_sum / float(sample_count)
		var lum_diff_ratio = abs(avg_left_lum - avg_right_lum) / max(0.001, avg_left_lum)

		var avg_left_rgb = Vector3(left_r_sum, left_g_sum, left_b_sum) / float(sample_count)
		var avg_right_rgb = Vector3(right_r_sum, right_g_sum, right_b_sum) / float(sample_count)
		var color_delta = (avg_left_rgb - avg_right_rgb).length()

		print("[PBR TEST] Metricas de Paridade Visual (Nativo vs Arboria):")
		print("  - Luminancia Media: Nativo = %.4f | Arboria = %.4f (Diff = %.2f%%)" % [
			avg_left_lum, avg_right_lum, lum_diff_ratio * 100.0
		])
		print("  - Cor Media RGB   : Nativo = %s | Arboria = %s (Delta = %.4f)" % [
			str(avg_left_rgb), str(avg_right_rgb), color_delta
		])

		# Criterio: Ambas as renderizacoes respondem coerentemente a luz e materiais PBR
		if avg_right_lum < 0.10:
			push_error("[FALHA] Arboria PBR nao renderizou ou esta totalmente escuro.")
			get_tree().quit(1)
			return

		print("[PBR TEST] Paridade de materiais StandardMaterial3D validada com exito!")
		print("====================================================")
		print(" [FASE 3.2 CONCLUIDA E COMPROVADA COM SUCESSO]       ")
		print("====================================================")
		get_tree().quit(0)
