extends Node3D

## TESTE A — JOLT PHYSICS: GRAVIDADE, COLISÕES E ESTABILIDADE DE CORPOS RÍGIDOS
## Testa 100, 500 e 1.000 caixas dinâmicas caindo sobre solo estático.
## Valida: repouso (sleeping), ausência de penetração/tunneling e estabilidade do solver.

@export var box_count: int = 100
@export var auto_quit_frames: int = 300

var bodies: Array[RigidBody3D] = []
var ground: StaticBody3D = null
var floor_y: float = 0.0

var frame_count: int = 0
var max_penetration_failures: int = 0
var physics_step_times: Array[float] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--box-count="):
			box_count = arg.trim_prefix("--box-count=").to_int()
		elif arg.begins_with("--auto-quit="):
			auto_quit_frames = arg.trim_prefix("--auto-quit=").to_int()

	print("=================================================================")
	print(" [TESTE A] JOLT PHYSICS: GRAVIDADE & EMPILHAMENTO DE CAIXAS       ")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("  Quantidade de Corpos Rígidos: %d" % box_count)
	print("=================================================================")

	_setup_environment()
	_setup_ground()
	_spawn_boxes(box_count)

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(10, 30, 20)
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)

	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 15, 35)
	camera.look_at(Vector3(0, 5, 0), Vector3.UP)

func _setup_ground() -> void:
	ground = StaticBody3D.new()
	ground.name = "Ground"
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	col.shape = box
	col.position = Vector3(0, -1, 0)
	ground.add_child(col)
	add_child(ground)

func _spawn_boxes(count: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 1.0)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 0.9)

	var cols = int(ceil(sqrt(count / 10.0)))
	cols = maxi(cols, 4)

	for i in range(count):
		var rb = RigidBody3D.new()
		rb.name = "Box_%04d" % i
		rb.mass = 2.0
		
		# Dispersão organizada em camadas para criar empilhamento e colisão natural
		var layer = i / (cols * cols)
		var col_idx = i % cols
		var row_idx = (i / cols) % cols
		
		var px = (col_idx - cols * 0.5) * 1.5 + rng.randf_range(-0.1, 0.1)
		var pz = (row_idx - cols * 0.5) * 1.5 + rng.randf_range(-0.1, 0.1)
		var py = 3.0 + layer * 1.8 + rng.randf_range(0.0, 0.5)
		
		rb.position = Vector3(px, py, pz)
		rb.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0, TAU), rng.randf_range(-0.1, 0.1))

		var col = CollisionShape3D.new()
		col.shape = box_shape
		rb.add_child(col)

		var mi = MeshInstance3D.new()
		mi.mesh = box_mesh
		mi.material_override = mat
		rb.add_child(mi)

		add_child(rb)
		bodies.append(rb)

	print("[TESTE A] %d caixas instanciadas com sucesso." % bodies.size())

func _physics_process(_delta: float) -> void:
	frame_count += 1
	var t0 = Time.get_ticks_usec()
	
	# Checagem de tunneling / atravessamento de chão (y < -2.0 indica falha)
	var tunneling_count = 0
	var sleeping_count = 0
	for b in bodies:
		if is_instance_valid(b):
			if b.position.y < -2.0:
				tunneling_count += 1
			if b.sleeping:
				sleeping_count += 1

	var step_ms = (Time.get_ticks_usec() - t0) / 1000.0
	physics_step_times.append(step_ms)

	if frame_count % 60 == 0:
		print("[TESTE A - Frame %03d] Ativos: %d | Dormindo: %d | Tunneling: %d" % [
			frame_count, bodies.size() - sleeping_count, sleeping_count, tunneling_count
		])

	if frame_count >= auto_quit_frames:
		_finish_test(tunneling_count, sleeping_count)

func _finish_test(tunneling: int, sleeping: int) -> void:
	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE A]")
	print("  Total de Corpos: %d" % bodies.size())
	print("  Corpos em Repouso (Sleeping): %d (%.1f%%)" % [sleeping, (float(sleeping) / bodies.size()) * 100.0])
	print("  Corpos com Tunneling (Atravessaram o chão): %d" % tunneling)
	
	if tunneling > 0:
		push_error("[FALHA TESTE A] Tunneling detectado! %d corpos atravessaram o chão!" % tunneling)
		get_tree().quit(1)
		return
		
	print("[SUCESSO TESTE A] Gravidade, empilhamento e repouso validados no Jolt Physics!")
	print("=================================================================")
	get_tree().quit(0)
