extends SceneTree

func _init():
	var diff_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V5_1_FINAL/evidencias/lod_misto/01_lod_misto_diff.png"
	var arb_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V5_1_FINAL/evidencias/lod_misto/01_lod_misto_arboria.png"
	var ref_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/VALIDACAO_V5_1_FINAL/evidencias/lod_misto/01_lod_misto_ref.png"
	
	var img_diff = Image.load_from_file(diff_path)
	var img_arb = Image.load_from_file(arb_path)
	var img_ref = Image.load_from_file(ref_path)
	
	var w = img_diff.get_width()
	var h = img_diff.get_height()
	
	var magenta_pixels = []
	for y in range(h):
		for x in range(w):
			var c = img_diff.get_pixel(x, y)
			# Magenta no diff: R > 0.8, G < 0.2, B > 0.8
			if c.r > 0.8 and c.g < 0.2 and c.b > 0.8:
				magenta_pixels.append(Vector2i(x, y))
				
	print("Total Magenta pixels: ", magenta_pixels.size())
	
	# Verifica se esses pixels magenta são REALMENTE um buraco interno no ARBORIA
	# Um buraco interno real no ARBORIA significa que no ARBORIA há pixels desenhados ao redor (cima, baixo, esq, dir)
	# mas aquele pixel está PRETO (vazio)!
	var real_holes_in_arb = 0
	var edge_recessions = 0
	for p in magenta_pixels:
		var x = p.x
		var y = p.y
		# Checa se o ARBORIA tem geometria ao redor em um raio um pouco maior (ex: 8 pixels)
		var arb_left = false
		var arb_right = false
		var arb_up = false
		var arb_down = false
		for d in range(1, 15):
			if x - d >= 0 and is_geom(img_arb.get_pixel(x - d, y)): arb_left = true
			if x + d < w and is_geom(img_arb.get_pixel(x + d, y)): arb_right = true
			if y - d >= 0 and is_geom(img_arb.get_pixel(x, y - d)): arb_up = true
			if y + d < h and is_geom(img_arb.get_pixel(x, y + d)): arb_down = true
		
		if arb_left and arb_right and arb_up and arb_down:
			real_holes_in_arb += 1
		else:
			edge_recessions += 1
			
	print("Buracos Reais Circundados por Geometria ARBORIA: ", real_holes_in_arb)
	print("Recuos de Silhueta / Borda (diferença de volume entre LODs): ", edge_recessions)
	quit()

func is_geom(c: Color) -> bool:
	return c.r > 0.05 or c.g > 0.05 or c.b > 0.05
