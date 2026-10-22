extends SceneTree

func _init():
	var ref_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/visuais/02_mid_dag_unshaded_ref.png"
	var arb_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/visuais/02_mid_dag_unshaded_arboria.png"
	var diff_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V4_CORRIGIDA/evidencias/visuais/02_mid_dag_unshaded_diff.png"
	
	var img_ref = Image.load_from_file(ref_path)
	var img_arb = Image.load_from_file(arb_path)
	var img_diff = Image.load_from_file(diff_path)
	
	var w = img_ref.get_width()
	var h = img_ref.get_height()
	
	# Conta cores no diff
	var diff_color_hist = {}
	var ref_only_bbox = [w, h, 0, 0] # min_x, min_y, max_x, max_y
	var arb_only_bbox = [w, h, 0, 0]
	var both_bbox = [w, h, 0, 0]
	
	for y in range(h):
		for x in range(w):
			var cr = img_ref.get_pixel(x, y)
			var ca = img_arb.get_pixel(x, y)
			var cd = img_diff.get_pixel(x, y)
			
			var hex = cd.to_html(false)
			diff_color_hist[hex] = diff_color_hist.get(hex, 0) + 1
			
			var is_r = (cr.r > 0.05 or cr.g > 0.05 or cr.b > 0.05)
			var is_a = (ca.r > 0.05 or ca.g > 0.05 or ca.b > 0.05)
			
			if is_r and not is_a:
				ref_only_bbox[0] = mini(ref_only_bbox[0], x)
				ref_only_bbox[1] = mini(ref_only_bbox[1], y)
				ref_only_bbox[2] = maxi(ref_only_bbox[2], x)
				ref_only_bbox[3] = maxi(ref_only_bbox[3], y)
			if is_a and not is_r:
				arb_only_bbox[0] = mini(arb_only_bbox[0], x)
				arb_only_bbox[1] = mini(arb_only_bbox[1], y)
				arb_only_bbox[2] = maxi(arb_only_bbox[2], x)
				arb_only_bbox[3] = maxi(arb_only_bbox[3], y)
			if is_r and is_a:
				both_bbox[0] = mini(both_bbox[0], x)
				both_bbox[1] = mini(both_bbox[1], y)
				both_bbox[2] = maxi(both_bbox[2], x)
				both_bbox[3] = maxi(both_bbox[3], y)
				
	print("Diff Color Histogram:")
	for k in diff_color_hist:
		print("  Hex #%s: %d pixels" % [k, diff_color_hist[k]])
		
	print("Both bbox: ", both_bbox)
	print("Ref only bbox: ", ref_only_bbox)
	print("Arb only bbox: ", arb_only_bbox)
	
	# Verificando se a malha foi renderizada com transform diferente ou se é um pedaço inteiro faltando
	# Centroides
	var r_cx = 0.0
	var r_cy = 0.0
	var r_cnt = 0
	var a_cx = 0.0
	var a_cy = 0.0
	var a_cnt = 0
	for y in range(h):
		for x in range(w):
			var cr = img_ref.get_pixel(x, y)
			var ca = img_arb.get_pixel(x, y)
			if cr.r > 0.05 or cr.g > 0.05 or cr.b > 0.05:
				r_cx += x
				r_cy += y
				r_cnt += 1
			if ca.r > 0.05 or ca.g > 0.05 or ca.b > 0.05:
				a_cx += x
				a_cy += y
				a_cnt += 1
	if r_cnt > 0:
		print("Ref centroid: (%.2f, %.2f)" % [r_cx / r_cnt, r_cy / r_cnt])
	if a_cnt > 0:
		print("Arb centroid: (%.2f, %.2f)" % [a_cx / a_cnt, a_cy / a_cnt])
	quit()
