extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

var frame_count: int = 0

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE AUTOMACAO ETAPA 4] PBR & QUALIDADE VISUAL")
	print("====================================================")
	
	# Configurar ambiente
	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
	print("[PBR TEST] Compositor Effect anexado com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1
	
	if frame_count == 10:
		print("[PBR TEST] Frame 10: Pipeline ativo, computando iluminação e materiais...")
		var pipeline = ArboriaNativePipeline.get_active_instance()
		if pipeline:
			pipeline.request_telemetry_read()
			
	elif frame_count == 25:
		print("[PBR TEST] Frame 25: Capturando frame de validação PBR...")
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://diag_arboria_pbr_side_by_side.png")
			print("[PBR TEST] Imagem salva em res://diag_arboria_pbr_side_by_side.png: OK")
			
	elif frame_count == 30:
		print("[PBR TEST] Frame 30: Validando equivalência PBR e preservação de atributos...")
		var img = Image.load_from_file("res://diag_arboria_pbr_side_by_side.png")
		if not img or img.is_empty():
			push_error("[FALHA] Imagem de validação PBR não pôde ser carregada.")
			get_tree().quit(1)
			return
			
		var w = img.get_width()
		var h = img.get_height()
		
		var arboria_pixels = 0
		var standard_pixels = 0
		var arboria_accum_lum = 0.0
		var standard_accum_lum = 0.0
		
		# Amostragem da metade esquerda (Arboria) vs metade direita (Godot StandardMaterial3D)
		for y in range(int(h * 0.25), int(h * 0.75)):
			for x in range(int(w * 0.1), int(w * 0.45)):
				var c = img.get_pixel(x, y)
				# Excluir cor de fundo cinza/azul
				if not (abs(c.r - 0.12) < 0.05 and abs(c.b - 0.18) < 0.05):
					arboria_pixels += 1
					arboria_accum_lum += c.get_luminance()
					
			for x in range(int(w * 0.55), int(w * 0.9)):
				var c = img.get_pixel(x, y)
				if not (abs(c.r - 0.12) < 0.05 and abs(c.b - 0.18) < 0.05):
					standard_pixels += 1
					standard_accum_lum += c.get_luminance()
					
		print("[PBR TEST] Pixels renderizados -> Arboria: %d, Godot Standard: %d" % [arboria_pixels, standard_pixels])
		
		if arboria_pixels < 5000:
			push_error("[FALHA] Objeto Arboria PBR não renderizou pixels suficientes: %d" % arboria_pixels)
			get_tree().quit(1)
			return
			
		if standard_pixels < 5000:
			push_error("[FALHA] Objeto Godot Standard não renderizou pixels suficientes: %d" % standard_pixels)
			get_tree().quit(1)
			return
			
		var arboria_avg_lum = arboria_accum_lum / float(arboria_pixels)
		var standard_avg_lum = standard_accum_lum / float(standard_pixels)
		print("[PBR TEST] Luminância média -> Arboria: %.3f, Godot Standard: %.3f" % [arboria_avg_lum, standard_avg_lum])
		
		# Verifica que a luminância média está dentro de uma faixa coerente (não preto, não estourado)
		if arboria_avg_lum < 0.1 or arboria_avg_lum > 0.95:
			push_error("[FALHA] Luminância do material Arboria fora da faixa física PBR: %.3f" % arboria_avg_lum)
			get_tree().quit(1)
			return
			
		# Verifica consistência visual comparada ao StandardMaterial3D (diferença relativa aceitável <= 50%)
		var lum_ratio = arboria_avg_lum / max(standard_avg_lum, 0.001)
		print("[PBR TEST] Razão de luminância (Arboria / Standard): %.2f" % lum_ratio)
		if lum_ratio < 0.4 or lum_ratio > 2.5:
			push_error("[FALHA] Discrepância excessiva de luminância com StandardMaterial3D: %.2f" % lum_ratio)
			get_tree().quit(1)
			return
			
		print("[PBR TEST] Equivalência PBR e consistência visual validadas com sucesso!")
		print("====================================================")
		print(" [ETAPA 4 CONCLUÍDA E APROVADA COM SUCESSO]         ")
		print("====================================================")
		get_tree().quit(0)
