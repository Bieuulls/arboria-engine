extends MainLoop

func _process(_delta: float) -> bool:
	var rd = RenderingServer.get_rendering_device()
	if not rd:
		print("RD null!")
		return true

	var pipeline_cls = load("res://scripts/arboria_native_pipeline.gd")
	var pipeline = pipeline_cls.new(rd)
	var mesh = pipeline.get_or_load_mesh("res://assets/dense_rock_test.vgmesh")
	var mesh_res = pipeline._mesh_cache["res://assets/dense_rock_test.vgmesh"]

	var node = Node3D.new()
	var inst_gpu = pipeline._get_or_create_instance_gpu_data(node, mesh_res)
	print("inst_gpu ready: ", inst_gpu.is_ready)
	print("raster_uniform_set valid: ", inst_gpu.raster_uniform_set.is_valid())
	return true
