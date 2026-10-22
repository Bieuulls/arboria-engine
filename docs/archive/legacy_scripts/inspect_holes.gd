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
	
	var hole_pixels = []
	for y in range(h):
		for x in range(w):
			var cd = img_diff.get_pixel(x, y)
			if cd.r > 0.8 and cd.g < 0.2 and cd.b > 0.8:
				# Magenta
				# Checa se é circundado no Arb
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
					hole_pixels.append(Vector2i(x, y))
					
	print("Sample hole coordinates (first 20):")
	for i in range(mini(hole_pixels.size(), 20)):
		var p = hole_pixels[i]
		print("  (%d, %d)" % [p.x, p.y])
		
	# Bounding box dos buracos
	var min_x = w
	var min_y = h
	var max_x = 0
	var max_y = 0
	for p in hole_pixels:
		min_x = mini(min_x, p.x)
		min_y = mini(min_y, p.y)
		max_x = maxi(max_x, p.x)
		max_y = maxi(max_y, p.y)
	print("Hole bbox: [%d, %d] to [%d, %d] (width=%d, height=%d)" % [min_x, min_y, max_x, max_y, max_x - min_x, max_y - min_y])
	quit()

func is_geom(c: Color) -> bool:
	return c.r > 0.05 or c.g > 0.05 or c.b > 0.05
