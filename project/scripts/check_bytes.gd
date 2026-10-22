extends SceneTree

func _init():
	for i in range(1, 10):
		var id = ""
		match i:
			1: id = "01_closeup"
			2: id = "02_mid_distance"
			3: id = "03_long_distance"
			4: id = "04_fov_30"
			5: id = "05_fov_90"
			6: id = "06_camera_rotation"
			7: id = "07_continuous_motion"
			8: id = "08_frustum_culling"
			9: id = "09_materials_lighting_lod"
			
		var r_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao5/%s_ref.png" % id
		var a_path = "D:/ARBORIA_ENGINE/ARBORIA_ENGINE_OFFICIAL/AUDITORIA_FASE3_FINAL/evidencias/missao5/%s_arboria.png" % id
		
		var fa = FileAccess.get_file_as_bytes(a_path)
		var fr = FileAccess.get_file_as_bytes(r_path)
		
		var byte_identical = (fa == fr)
		print("[%s] Size Ref: %d | Size Arb: %d | Byte identical? %s" % [id, fr.size(), fa.size(), byte_identical])
	quit()
