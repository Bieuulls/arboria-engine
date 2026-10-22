extends Node3D

# ARBORIA ENGINE — VALIDAÇÃO V4: COMPARAÇÃO VISUAL REAL COM VIEWPORTS ISOLADOS
# Renderizadores 100% desacoplados: subview_ref (Godot nativo) vs subview_arb (ARBORIA GPU Indirect)

const VGMeshLoader = preload("res://scripts/vgmesh_loader.gd")
const VGGPUPipeline = preload("res://scripts/vg_gpu_pipeline.gd")

var pipeline: VGGPUPipeline
var rd: RenderingDevice

var subview_ref: SubViewport
var subview_arb: SubViewport
var cam_ref: Camera3D
var cam_arb: Camera3D

var model_ref_instance: MeshInstance3D
var mat_unshaded: StandardMaterial3D
var mat_lit: StandardMaterial3D

var light_ref: DirectionalLight3D
var light_arb: DirectionalLight3D

var vg_data: Dictionary
var current_case = 0
var visual_results = []
var output_dir = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/visuais"

var scenarios = [
	{
		"id": "01_closeup_unshaded",
		"name": "Close-up 7.0m (Isolamento Geométrico Estrito — LOD 0)",
		"dist": 7.0, "fov": 60.0, "yaw": 0.0, "pitch": 0.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": true, "shading_mode": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "02_mid_unshaded",
		"name": "Distância Intermediária 14.0m (Geometria e Cobertura — LOD 0)",
		"dist": 14.0, "fov": 60.0, "yaw": 45.0, "pitch": 15.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": true, "shading_mode": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "03_distant_unshaded",
		"name": "Distância Longa 30.0m (Triângulos Subpixel — LOD 0)",
		"dist": 30.0, "fov": 60.0, "yaw": 90.0, "pitch": -10.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": true, "shading_mode": 0,
		"tol_coverage": 95.0, "tol_rmse": 0.06, "tol_cracks": 0
	},
	{
		"id": "04_fov_30_telephoto",
		"name": "FOV 30° Telefoto (Projeção Estreita 22.0m)",
		"dist": 22.0, "fov": 30.0, "yaw": 25.0, "pitch": 5.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": true, "shading_mode": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "05_fov_90_wide",
		"name": "FOV 90° Grande Angular (Distorção Periférica 12.0m)",
		"dist": 12.0, "fov": 90.0, "yaw": -30.0, "pitch": 10.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": true, "shading_mode": 0,
		"tol_coverage": 98.0, "tol_rmse": 0.05, "tol_cracks": 0
	},
	{
		"id": "06_materials_lighting_pbr",
		"name": "Iluminação Direcional PBR & Materiais (12.0m)",
		"dist": 12.0, "fov": 60.0, "yaw": 30.0, "pitch": 10.0,
		"lod_mode": 1, "forced_lod": 0, "max_err": 1.5,
		"unshaded": false, "shading_mode": 2,
		"tol_coverage": 98.0, "tol_rmse": 0.20, "tol_cracks": 0
	}
]

func _ready() -> void:
	print("=================================================================")
	print("   ARBORIA ENGINE — VALIDAÇÃO V4: COMPARAÇÃO VISUAL INDEPENDENTE")
	print("=================================================================")
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice Vulkan indisponivel!")
		get_tree().quit(1)
		return

	print("[Hardware GPU] %s" % rd.get_device_name())

	vg_data = VGMeshLoader.load_from_file("res://assets/dense_rock_test.vgmesh")
	pipeline = VGGPUPipeline.new(rd)
	pipeline.load_vgmesh(vg_data)

	# 1. Configura SubViewport da Referência Convencional Godot
	subview_ref = SubViewport.new()
	subview_ref.size = Vector2i(1280, 720)
	subview_ref.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subview_ref.own_world_3d = true

	var env_ref = Environment.new()
	env_ref.background_mode = Environment.BG_COLOR
	env_ref.background_color = Color(0, 0, 0, 1)
	env_ref.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_ref.ambient_light_color = Color(0.15, 0.15, 0.15, 1.0)
	var we_ref = WorldEnvironment.new()
	we_ref.environment = env_ref
	subview_ref.add_child(we_ref)

	cam_ref = Camera3D.new()
	cam_ref.near = 0.05
	cam_ref.far = 300.0
	cam_ref.current = true
	subview_ref.add_child(cam_ref)

	light_ref = DirectionalLight3D.new()
	light_ref.look_at_from_position(Vector3(0, 0, 0), -Vector3(0.5, 0.8, 0.6).normalized(), Vector3.UP)
	subview_ref.add_child(light_ref)

	# Referência LOD 0 nativa Godot
	var ref_mesh = VGMeshLoader.build_mesh_surface(vg_data, 0, false, -1)
	model_ref_instance = MeshInstance3D.new()
	model_ref_instance.mesh = ref_mesh

	mat_unshaded = StandardMaterial3D.new()
	mat_unshaded.albedo_color = Color(0.8, 0.82, 0.85)
	mat_unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mat_lit = StandardMaterial3D.new()
	mat_lit.albedo_color = Color(0.8, 0.82, 0.85)
	mat_lit.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat_lit.roughness = 0.6
	mat_lit.metallic_specular = 0.0

	model_ref_instance.material_override = mat_unshaded
	subview_ref.add_child(model_ref_instance)
	add_child(subview_ref)

	# 2. Configura SubViewport Exclusivo do ARBORIA (Totalmente Isolado)
	subview_arb = SubViewport.new()
	subview_arb.size = Vector2i(1280, 720)
	subview_arb.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subview_arb.own_world_3d = true

	var env_arb = Environment.new()
	env_arb.background_mode = Environment.BG_COLOR
	env_arb.background_color = Color(0, 0, 0, 1)
	var we_arb = WorldEnvironment.new()
	we_arb.environment = env_arb
	subview_arb.add_child(we_arb)

	cam_arb = Camera3D.new()
	cam_arb.near = 0.05
	cam_arb.far = 300.0
	cam_arb.current = true
	subview_arb.add_child(cam_arb)
	add_child(subview_arb)

	RenderingServer.frame_post_draw.connect(_on_frame)

var phase = 0

func _on_frame() -> void:
	if current_case >= scenarios.size():
		finish_visual_validation()
		return

	var sc = scenarios[current_case]

	if phase == 0:
		# Fase 0: Configura câmera e material. Godot irá rasterizar subview_ref no próximo frame.
		var yaw = deg_to_rad(sc["yaw"])
		var pitch = deg_to_rad(sc["pitch"])
		var dist = sc["dist"]
		var pos = Vector3(dist * cos(pitch) * sin(yaw), dist * sin(pitch), dist * cos(pitch) * cos(yaw))

		cam_ref.fov = sc["fov"]
		cam_ref.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)

		cam_arb.fov = sc["fov"]
		cam_arb.look_at_from_position(pos, Vector3.ZERO, Vector3.UP)

		model_ref_instance.material_override = mat_unshaded if sc["unshaded"] else mat_lit
		model_ref_instance.visible = true

		phase = 1
		return

	elif phase == 1:
		# Fase 1: Godot completou a rasterização do subview_ref na pose correta.
		# 1. Captura imagem da Referência Convencional
		var img_ref = subview_ref.get_texture().get_image()

		# 2. Renderiza e Captura ARBORIA GPU Indirect no subview_arb isolado
		pipeline.set_indirect_draw_enabled(true)
		pipeline.render_to_viewport(
			subview_arb,
			cam_arb,
			Transform3D.IDENTITY,
			sc["max_err"],
			sc["lod_mode"],
			sc["forced_lod"],
			true,
			false,
			false,
			sc["shading_mode"]
		)

		var img_arb = subview_arb.get_texture().get_image()

		process_comparison(sc, img_ref, img_arb)
		current_case += 1
		phase = 0

func process_comparison(sc: Dictionary, img_ref: Image, img_arb: Image) -> void:
	var w = img_ref.get_width()
	var h = img_ref.get_height()

	var ref_pixels = 0
	var arb_pixels = 0
	var intersection_pixels = 0
	var internal_cracks = 0
	var total_sq_diff = 0.0
	var max_diff = 0.0

	var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	var ref_mask: Array[PackedByteArray] = []
	for y in range(h):
		var row = PackedByteArray()
		row.resize(w)
		for x in range(w):
			var c = img_ref.get_pixel(x, y)
			row[x] = 1 if (c.r > 0.05 or c.g > 0.05 or c.b > 0.05) else 0
		ref_mask.append(row)

	for y in range(h):
		for x in range(w):
			var c_ref = img_ref.get_pixel(x, y)
			var c_arb = img_arb.get_pixel(x, y)

			var is_ref = (ref_mask[y][x] == 1)
			var is_arb = (c_arb.r > 0.05 or c_arb.g > 0.05 or c_arb.b > 0.05)

			if is_ref: ref_pixels += 1
			if is_arb: arb_pixels += 1

			if is_ref and is_arb:
				intersection_pixels += 1
				var dr = c_ref.r - c_arb.r
				var dg = c_ref.g - c_arb.g
				var db = c_ref.b - c_arb.b
				var sq_err = (dr * dr + dg * dg + db * db) / 3.0
				total_sq_diff += sq_err
				var abs_delta = (abs(dr) + abs(dg) + abs(db)) / 3.0
				if abs_delta > max_diff: max_diff = abs_delta

				if abs_delta < 0.02:
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 0.0, 1.0)) # Verde = match exato
				elif abs_delta < 0.10:
					diff_img.set_pixel(x, y, Color(1.0, 1.0, 0.0, 1.0)) # Amarelo = variação sutil
				else:
					diff_img.set_pixel(x, y, Color(1.0, 0.4, 0.0, 1.0)) # Laranja = diferença

			elif is_ref and not is_arb:
				var is_internal = false
				if x >= 3 and x < w - 3 and y >= 3 and y < h - 3:
					if ref_mask[y][x-3] == 1 and ref_mask[y][x+3] == 1 and ref_mask[y-3][x] == 1 and ref_mask[y+3][x] == 1:
						is_internal = true

				if is_internal:
					internal_cracks += 1
					diff_img.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0)) # Magenta = rachadura interna
				else:
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 1.0, 1.0)) # Ciano = borda de silhueta

			elif is_arb and not is_ref:
				diff_img.set_pixel(x, y, Color(0.2, 0.2, 1.0, 1.0)) # Azul = ARBORIA além da borda
			else:
				diff_img.set_pixel(x, y, Color(0.05, 0.05, 0.05, 1.0)) # Fundo

	var coverage_pct = 100.0
	if max(ref_pixels, arb_pixels) > 0:
		coverage_pct = (float(min(ref_pixels, arb_pixels)) / float(max(ref_pixels, arb_pixels))) * 100.0

	var rmse = 0.0
	if intersection_pixels > 0:
		rmse = sqrt(total_sq_diff / float(intersection_pixels))

	var pass_coverage = (coverage_pct >= sc["tol_coverage"])
	var pass_rmse = (rmse <= sc["tol_rmse"])
	var pass_cracks = (internal_cracks <= sc["tol_cracks"])
	var approved = (pass_coverage and pass_rmse and pass_cracks)

	var ref_path = "%s/%s_ref.png" % [output_dir, sc["id"]]
	var arb_path = "%s/%s_arboria.png" % [output_dir, sc["id"]]
	var diff_path = "%s/%s_diff.png" % [output_dir, sc["id"]]

	img_ref.save_png(ref_path)
	img_arb.save_png(arb_path)
	diff_img.save_png(diff_path)

	# Verifica se os arquivos são suspeitamente idênticos byte-a-byte
	var fr = FileAccess.get_file_as_bytes(ref_path)
	var fa = FileAccess.get_file_as_bytes(arb_path)
	var byte_identical = (fr == fa)

	var res = {
		"id": sc["id"],
		"name": sc["name"],
		"ref_pixels": ref_pixels,
		"arb_pixels": arb_pixels,
		"intersection": intersection_pixels,
		"coverage_pct": coverage_pct,
		"rmse": rmse,
		"max_diff": max_diff,
		"internal_cracks": internal_cracks,
		"byte_identical": byte_identical,
		"approved": approved,
		"ref_path": ref_path,
		"arb_path": arb_path,
		"diff_path": diff_path
	}
	visual_results.append(res)

	print("\n[%s] %s" % [sc["id"].to_upper(), sc["name"]])
	print("  Pixels Referência: %d | Pixels ARBORIA: %d | Cobertura: %.2f%% (Tol: >= %.1f%%)" % [ref_pixels, arb_pixels, coverage_pct, sc["tol_coverage"]])
	print("  RMSE RGB: %.4f (Tol: <= %.3f) | Max Delta: %.4f" % [rmse, sc["tol_rmse"], max_diff])
	print("  Rachaduras Internas: %d pixels | Arquivos Idênticos Byte-a-Byte? %s" % [internal_cracks, str(byte_identical)])
	print("  STATUS: %s" % ("APROVADO" if approved else "REPROVADO"))

func finish_visual_validation() -> void:
	RenderingServer.frame_post_draw.disconnect(_on_frame)
	print("\n=================================================================")
	print("   CONSOLIDAÇÃO DA VALIDAÇÃO VISUAL COM VIEWPORTS ISOLADOS       ")
	print("=================================================================")
	var all_pass = true
	for r in visual_results:
		if not r["approved"]: all_pass = false
		print("  - %-25s: Cob: %6.2f%% | RMSE: %.4f | Rachaduras: %d | Idênticos Byte-a-Byte? %-5s -> %s" % [
			r["id"], r["coverage_pct"], r["rmse"], r["internal_cracks"], str(r["byte_identical"]),
			"APROVADO" if r["approved"] else "REPROVADO"
		])

	print("\nSTATUS GLOBAL DA VALIDAÇÃO VISUAL: %s" % ("APROVADO" if all_pass else "REPROVADO"))
	print("Evidências salvas em: %s" % output_dir)
	print("=================================================================\n")
	get_tree().quit(0 if all_pass else 1)
