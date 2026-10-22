extends SceneTree

func _init():
	var diff_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/investigacao_dag_diff.png"
	var arb_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/investigacao_dag_arb.png"
	
	var img_diff = Image.load_from_file(diff_path)
	var img_arb = Image.load_from_file(arb_path)
	
	var w = img_diff.get_width()
	var h = img_diff.get_height()
	
	var real_holes = 0
	for y in range(h):
		for x in range(w):
			var cd = img_diff.get_pixel(x, y)
			if cd.r > 0.8 and cd.g < 0.2 and cd.b > 0.8:
				# Magenta
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
					real_holes += 1
					
	print("Buracos Reais Circundados por Geometria ARBORIA: ", real_holes)
	quit()

func is_geom(c: Color) -> bool:
	return c.r > 0.05 or c.g > 0.05 or c.b > 0.05
