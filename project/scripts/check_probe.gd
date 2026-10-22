extends SceneTree

func _init():
	var img2 = Image.load_from_file("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame2_ref_visible.png")
	var img3_before = Image.load_from_file("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame3_ref_hidden.png")
	var img3_after = Image.load_from_file("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame3_after_arboria.png")
	var img4 = Image.load_from_file("D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/diag_frame4.png")
	
	print("img2 non-black: ", count_nb(img2))
	print("img3_before non-black: ", count_nb(img3_before))
	print("img3_after non-black: ", count_nb(img3_after))
	print("img4 non-black: ", count_nb(img4))
	
	# Check sample colors of img3_after and img4
	print("img3_after sample center (640, 360): ", img3_after.get_pixel(640, 360))
	print("img4 sample center (640, 360): ", img4.get_pixel(640, 360))
	quit()

func count_nb(img: Image) -> int:
	var cnt = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if c.r > 0.05 or c.g > 0.05 or c.b > 0.05:
				cnt += 1
	return cnt
