@tool
extends SceneTree

func _init() -> void:
	var rd := RenderingServer.get_rendering_device()
	if not rd:
		print("RD not available in headless mode without rendering device, trying to create local RD")
		rd = RenderingServer.create_local_rendering_device()
	
	print("RD:", rd)
	# Check methods on RD
	for m in rd.get_method_list():
		if "indirect" in m.name.to_lower():
			print("Method:", m.name, "args:", m.args)
			
	# Check draw_list methods
	for m in rd.get_method_list():
		if "draw_list" in m.name:
			print("DrawList Method:", m.name)
			
	quit(0)
