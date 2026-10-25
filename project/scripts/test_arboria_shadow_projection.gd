extends Node3D

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

var frame_count: int = 0
var capture_path: String = "res://diag_arboria_shadow_projection.png"

func _ready() -> void:
	print("====================================================")
	print(" [TESTE DE VALIDACAO 3.1] PROJECAO DE SOMBRAS DO SOL")
	print("====================================================")
	
	ArboriaCompositorEffect.attach_to_environment($WorldEnvironment)
	print("[SHADOW TEST] Compositor Effect anexado com sucesso.")

func _process(_delta: float) -> void:
	frame_count += 1
	
	if frame_count == 10:
		print("[SHADOW TEST] Frame 10: Sol ativo com shadow_enabled = true, renderizando cena e Shadow Atlas...")
		var pipe = ArboriaNativePipeline.get_active_instance()
		if pipe:
			pipe.request_telemetry_read()
			
	elif frame_count == 25:
		print("[SHADOW TEST] Frame 25: Capturando frame com sombra projetada...")
		var img = get_viewport().get_texture().get_image()
		if img:
			img.save_png(capture_path)
			print("[SHADOW TEST] Imagem salva em: ", capture_path)
			
	elif frame_count == 30:
		print("[SHADOW TEST] Frame 30: Auditando pixels de sombra projetada no chao...")
		var img = Image.load_from_file(capture_path)
		if not img or img.is_empty():
			push_error("[FALHA] Imagem de validacao de sombra nao pode ser carregada.")
			get_tree().quit(1)
			return
			
		var w = img.get_width()
		var h = img.get_height()
		
		# A regiao do chao onde a sombra do objeto elevado incide
		var ground_lit_pixels = 0
		var ground_shadow_pixels = 0
		var lit_lum_sum = 0.0
		var shadow_lum_sum = 0.0
		
		# Amostra o chao na tela para detectar sombra projetada e regiao iluminada
		for y in range(int(h * 0.25), int(h * 0.95)):
			for x in range(int(w * 0.1), int(w * 0.9)):
				var c = img.get_pixel(x, y)
				var lum = c.get_luminance()
				# O chao e cinza/branco neutro (diferente da rocha marrom)
				var is_neutral = abs(c.r - c.g) < 0.08 and abs(c.g - c.b) < 0.08
				if is_neutral:
					if lum < 0.35 and lum > 0.02:
						ground_shadow_pixels += 1
						shadow_lum_sum += lum
					elif lum > 0.70:
						ground_lit_pixels += 1
						lit_lum_sum += lum
					
		print("[SHADOW TEST] Pixels analisados no chao:")
		print("  - Pixels de sombra projetada detectados : %d" % ground_shadow_pixels)
		print("  - Pixels de chao iluminado diretamente  : %d" % ground_lit_pixels)
		
		if ground_shadow_pixels < 500:
			push_error("[FALHA] Poucos ou nenhum pixel de sombra projetada detectado no chao: %d" % ground_shadow_pixels)
			get_tree().quit(1)
			return
			
		var avg_shadow_lum = shadow_lum_sum / float(ground_shadow_pixels)
		var avg_lit_lum = lit_lum_sum / max(1.0, float(ground_lit_pixels))
		var contrast_ratio = avg_lit_lum / max(0.001, avg_shadow_lum)
		
		print("[SHADOW TEST] Luminancia media: Sombra = %.3f | Chao Iluminado = %.3f (Contraste = %.2fx)" % [
			avg_shadow_lum, avg_lit_lum, contrast_ratio
		])
		
		if contrast_ratio < 1.4:
			push_error("[FALHA] Contraste de sombra insuficiente: %.2fx (esperado >= 1.4x)" % contrast_ratio)
			get_tree().quit(1)
			return
			
		print("[SHADOW TEST] Projecao de sombras validada com sucesso! Contraste claro/escuro nitido.")
		print("====================================================")
		print(" [FASE 3.1 CONCLUIDA E COMPROVADA COM SUCESSO]       ")
		print("====================================================")
		get_tree().quit(0)
