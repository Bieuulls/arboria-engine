class_name VGVisualMetrics
extends RefCounted

# ARBORIA ENGINE — SISTEMA MATEMÁTICO DE VALIDAÇÃO VISUAL
# Implementação de IoU Verdadeiro (Interseção / União) e Métricas Fotométricas

static func is_geometry_pixel(c: Color, threshold: float = 0.05) -> bool:
	return c.r > threshold or c.g > threshold or c.b > threshold

static func compute_mask(img: Image, threshold: float = 0.05) -> Array[PackedByteArray]:
	var w = img.get_width()
	var h = img.get_height()
	var mask: Array[PackedByteArray] = []
	mask.resize(h)
	for y in range(h):
		var row = PackedByteArray()
		row.resize(w)
		for x in range(w):
			var c = img.get_pixel(x, y)
			row[x] = 1 if is_geometry_pixel(c, threshold) else 0
		mask[y] = row
	return mask

static func evaluate(img_ref: Image, img_arb: Image, threshold: float = 0.05) -> Dictionary:
	var w = img_ref.get_width()
	var h = img_ref.get_height()
	assert(w == img_arb.get_width() and h == img_arb.get_height(), "Dimensoes das imagens devem ser identicas!")

	var ref_mask = compute_mask(img_ref, threshold)
	var arb_mask = compute_mask(img_arb, threshold)

	var ref_pixels = 0
	var arb_pixels = 0
	var intersection_pixels = 0
	var union_pixels = 0
	var internal_cracks = 0
	var total_sq_diff = 0.0
	var max_diff = 0.0

	var diff_img = Image.create(w, h, false, Image.FORMAT_RGBA8)

	for y in range(h):
		for x in range(w):
			var is_r = (ref_mask[y][x] == 1)
			var is_a = (arb_mask[y][x] == 1)
			var c_ref = img_ref.get_pixel(x, y)
			var c_arb = img_arb.get_pixel(x, y)

			if is_r: ref_pixels += 1
			if is_a: arb_pixels += 1

			if is_r or is_a:
				union_pixels += 1

			if is_r and is_a:
				intersection_pixels += 1
				var dr = c_ref.r - c_arb.r
				var dg = c_ref.g - c_arb.g
				var db = c_ref.b - c_arb.b
				var sq_err = (dr * dr + dg * dg + db * db) / 3.0
				total_sq_diff += sq_err
				var abs_delta = (abs(dr) + abs(dg) + abs(db)) / 3.0
				if abs_delta > max_diff:
					max_diff = abs_delta

				if abs_delta < 0.02:
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 0.0, 1.0)) # Verde = match exato
				elif abs_delta < 0.10:
					diff_img.set_pixel(x, y, Color(1.0, 1.0, 0.0, 1.0)) # Amarelo = variacao sutil
				else:
					diff_img.set_pixel(x, y, Color(1.0, 0.4, 0.0, 1.0)) # Laranja = diferenca de cor
			elif is_r and not is_a:
				# Geometria ausente no ARBORIA
				# Rachadura interna (seam crack / buraco): pixel vazio no ARBORIA circundado por geometria ARBORIA
				var is_internal = false
				var arb_l = false
				var arb_r = false
				var arb_u = false
				var arb_d = false
				for step_x in range(1, 25):
					if x - step_x >= 0 and arb_mask[y][x - step_x] == 1: arb_l = true
					if x + step_x < w and arb_mask[y][x + step_x] == 1: arb_r = true
					if arb_l and arb_r: break
				for step_y in range(1, 25):
					if y - step_y >= 0 and arb_mask[y - step_y][x] == 1: arb_u = true
					if y + step_y < h and arb_mask[y + step_y][x] == 1: arb_d = true
					if arb_u and arb_d: break

				if arb_l and arb_r and arb_u and arb_d:
					is_internal = true

				if is_internal:
					internal_cracks += 1
					diff_img.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0)) # Magenta = rachadura interna
				else:
					diff_img.set_pixel(x, y, Color(0.0, 0.8, 1.0, 1.0)) # Ciano = silhueta/borda ausente (diferença de LOD)
			elif is_a and not is_r:
				# Geometria excedente no ARBORIA
				diff_img.set_pixel(x, y, Color(0.2, 0.2, 1.0, 1.0)) # Azul = excesso
			else:
				diff_img.set_pixel(x, y, Color(0.05, 0.05, 0.05, 1.0)) # Fundo preto

	var iou = 1.0
	if union_pixels > 0:
		iou = float(intersection_pixels) / float(union_pixels)
	elif ref_pixels == 0 and arb_pixels == 0:
		iou = 1.0
	else:
		iou = 0.0

	var false_ratio = 1.0
	if max(ref_pixels, arb_pixels) > 0:
		false_ratio = float(min(ref_pixels, arb_pixels)) / float(max(ref_pixels, arb_pixels))

	var rmse = 0.0
	if intersection_pixels > 0:
		rmse = sqrt(total_sq_diff / float(intersection_pixels))

	return {
		"ref_pixels": ref_pixels,
		"arb_pixels": arb_pixels,
		"intersection": intersection_pixels,
		"union": union_pixels,
		"iou": iou,
		"iou_pct": iou * 100.0,
		"false_ratio_pct": false_ratio * 100.0,
		"rmse": rmse,
		"max_diff": max_diff,
		"internal_cracks": internal_cracks,
		"diff_image": diff_img
	}
