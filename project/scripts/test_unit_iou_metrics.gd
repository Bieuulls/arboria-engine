extends SceneTree

# ARBORIA ENGINE — ETAPA 3: TESTES UNITÁRIOS MATEMÁTICOS DE IoU VERDADEIRO
# Validação Formal com Resultados Conhecidos a Priori

const VGVisualMetrics = preload("res://scripts/vg_visual_metrics.gd")

func _init():
	print("=================================================================")
	print("   ARBORIA ENGINE — ETAPA 3: TESTE UNITÁRIO DE IoU MATEMÁTICO    ")
	print("=================================================================")

	var all_passed = true

	# -------------------------------------------------------------
	# CASO 1: Máscaras Iguais -> IoU 1.0 (100.0%)
	# -------------------------------------------------------------
	print("\n[Caso 1] Máscaras Iguais:")
	var img_a1 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var img_b1 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img_a1.fill_rect(Rect2i(20, 20, 40, 40), Color(0.8, 0.8, 0.8, 1.0)) # 1600 px
	img_b1.fill_rect(Rect2i(20, 20, 40, 40), Color(0.8, 0.8, 0.8, 1.0)) # 1600 px

	var res1 = VGVisualMetrics.evaluate(img_a1, img_b1)
	print("  Ref: %d | Arb: %d | Interseção: %d | União: %d" % [res1.ref_pixels, res1.arb_pixels, res1.intersection, res1.union])
	print("  IoU Calculado: %.6f | Esperado: 1.000000" % res1.iou)
	if abs(res1.iou - 1.0) > 0.00001 or res1.intersection != 1600 or res1.union != 1600:
		push_error("FALHA CASO 1: IoU de máscaras iguais deve ser 1.0!")
		all_passed = false
	else:
		print("  -> CASO 1 APROVADO")

	# -------------------------------------------------------------
	# CASO 2: Máscaras Sem Interseção -> IoU 0.0 (0.0%)
	# -------------------------------------------------------------
	print("\n[Caso 2] Máscaras Sem Interseção:")
	var img_a2 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var img_b2 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img_a2.fill_rect(Rect2i(10, 10, 20, 20), Color(0.8, 0.8, 0.8, 1.0)) # 400 px à esquerda
	img_b2.fill_rect(Rect2i(70, 70, 20, 20), Color(0.8, 0.8, 0.8, 1.0)) # 400 px à direita

	var res2 = VGVisualMetrics.evaluate(img_a2, img_b2)
	print("  Ref: %d | Arb: %d | Interseção: %d | União: %d" % [res2.ref_pixels, res2.arb_pixels, res2.intersection, res2.union])
	print("  IoU Calculado: %.6f | Esperado: 0.000000" % res2.iou)
	print("  Proporção Falsa Min/Max: %.2f%% (Mascara completamente a falha!)" % res2.false_ratio_pct)
	if abs(res2.iou - 0.0) > 0.00001 or res2.intersection != 0 or res2.union != 800:
		push_error("FALHA CASO 2: IoU de máscaras disjuntas deve ser 0.0!")
		all_passed = false
	else:
		print("  -> CASO 2 APROVADO (Comprovou que min/max informaria 100% erroneamente)")

	# -------------------------------------------------------------
	# CASO 3: Máscaras Parcialmente Sobrepostas -> Valor Exato Conhecido
	# A: [0..10, 0..10] = 100 px. B: [5..15, 0..10] = 100 px.
	# Interseção: [5..10, 0..10] = 5 * 10 = 50 px.
	# União: 100 + 100 - 50 = 150 px.
	# IoU Exato: 50 / 150 = 1/3 = 0.333333... (33.33%)
	# -------------------------------------------------------------
	print("\n[Caso 3] Máscaras Parcialmente Sobrepostas:")
	var img_a3 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var img_b3 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img_a3.fill_rect(Rect2i(0, 0, 10, 10), Color(0.8, 0.8, 0.8, 1.0))
	img_b3.fill_rect(Rect2i(5, 0, 10, 10), Color(0.8, 0.8, 0.8, 1.0))

	var res3 = VGVisualMetrics.evaluate(img_a3, img_b3)
	var expected_iou = 50.0 / 150.0
	print("  Ref: %d | Arb: %d | Interseção: %d | União: %d" % [res3.ref_pixels, res3.arb_pixels, res3.intersection, res3.union])
	print("  IoU Calculado: %.6f | Esperado: %.6f (33.33%%)" % [res3.iou, expected_iou])
	print("  Proporção Falsa Min/Max: %.2f%% (Mascara completamente o desalinhamento!)" % res3.false_ratio_pct)
	if abs(res3.iou - expected_iou) > 0.0001 or res3.intersection != 50 or res3.union != 150:
		push_error("FALHA CASO 3: IoU de sobreposição parcial divergente!")
		all_passed = false
	else:
		print("  -> CASO 3 APROVADO")

	# -------------------------------------------------------------
	# CASO 4: Máscara com Geometria Ausente (Buraco Interno) -> Redução de IoU
	# Ref: [10..50, 10..50] = 40x40 = 1600 px.
	# Arb: Igual, menos buraco interno [20..30, 20..30] = 10x10 = 100 px. Arb = 1500 px.
	# Interseção: 1500 px. União: 1600 px.
	# IoU Exato: 1500 / 1600 = 0.9375 (93.75%).
	# -------------------------------------------------------------
	print("\n[Caso 4] Máscara com Geometria Ausente (Buraco Interno):")
	var img_a4 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var img_b4 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img_a4.fill_rect(Rect2i(10, 10, 40, 40), Color(0.8, 0.8, 0.8, 1.0))
	img_b4.fill_rect(Rect2i(10, 10, 40, 40), Color(0.8, 0.8, 0.8, 1.0))
	img_b4.fill_rect(Rect2i(20, 20, 10, 10), Color(0, 0, 0, 1.0)) # Buraco interno de 100 px

	var res4 = VGVisualMetrics.evaluate(img_a4, img_b4)
	var expected_iou4 = 1500.0 / 1600.0
	print("  Ref: %d | Arb: %d | Interseção: %d | União: %d" % [res4.ref_pixels, res4.arb_pixels, res4.intersection, res4.union])
	print("  IoU Calculado: %.6f | Esperado: %.6f (93.75%%)" % [res4.iou, expected_iou4])
	print("  Rachaduras/Buracos Internos Detectados: %d pixels" % res4.internal_cracks)
	if abs(res4.iou - expected_iou4) > 0.0001 or res4.internal_cracks != 100:
		push_error("FALHA CASO 4: IoU ou detecção de buracos internos incorretos!")
		all_passed = false
	else:
		print("  -> CASO 4 APROVADO")

	# -------------------------------------------------------------
	# CASO 5: Cores Alteradas, Silhueta Idêntica -> IoU 1.0, mas Diferença RGB Detectada
	# Ref: Vermelho (1, 0, 0) em [10..30, 10..30] = 400 px.
	# Arb: Verde (0, 1, 0) em [10..30, 10..30] = 400 px.
	# IoU = 400 / 400 = 1.0 (100.0%).
	# RMSE RGB deve ser > 0 (diferença drástica de cor detectada).
	# -------------------------------------------------------------
	print("\n[Caso 5] Cores Alteradas, Silhueta Idêntica:")
	var img_a5 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var img_b5 = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img_a5.fill_rect(Rect2i(10, 10, 20, 20), Color(1.0, 0.0, 0.0, 1.0))
	img_b5.fill_rect(Rect2i(10, 10, 20, 20), Color(0.0, 1.0, 0.0, 1.0))

	var res5 = VGVisualMetrics.evaluate(img_a5, img_b5)
	print("  Ref: %d | Arb: %d | Interseção: %d | União: %d" % [res5.ref_pixels, res5.arb_pixels, res5.intersection, res5.union])
	print("  IoU Calculado: %.6f | Esperado: 1.000000" % res5.iou)
	print("  RMSE RGB: %.6f (Esperado > 0.5) | Max Delta: %.4f" % [res5.rmse, res5.max_diff])
	if abs(res5.iou - 1.0) > 0.00001 or res5.rmse < 0.5:
		push_error("FALHA CASO 5: IoU deve ser 1.0 e RMSE deve detectar divergência cromática!")
		all_passed = false
	else:
		print("  -> CASO 5 APROVADO")

	print("\n=================================================================")
	if all_passed:
		print("   TODOS OS 5 TESTES UNITÁRIOS MATEMÁTICOS FORAM APROVADOS!      ")
		print("=================================================================\n")
		quit(0)
	else:
		push_error("   FALHA EM TESTES UNITÁRIOS DE IoU!")
		print("=================================================================\n")
		quit(1)
