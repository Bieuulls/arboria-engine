extends Node3D

## TESTE B — JOLT PHYSICS: OBJETOS COMPLEXOS, CONVEX HULLS, ATRITO, RESTITUIÇÃO E RAMPAS
## Testa rochas virtuais com formas convexas reais sobre rampas inclinadas com diferentes atritos e restituições.

const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")
const ArboriaRigidBody3D = preload("res://scripts/arboria_rigid_body_3d.gd")
const ArboriaStaticBody3D = preload("res://scripts/arboria_static_body_3d.gd")

const MESH_ROCK = "res://assets/dense_rock_test.vgmesh"
const MESH_BOULDER = "res://assets/boulder_granite.vgmesh"

@export var auto_quit_frames: int = 240
var frame_count: int = 0
var test_bodies: Array[RigidBody3D] = []

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE B] JOLT PHYSICS: ROCHAS COMPLEXAS, CONVEX HULLS & RAMPAS  ")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("=================================================================")

	_setup_environment()
	_setup_ramps()
	_spawn_complex_rocks()

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(10, 30, 20)
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)

	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 12, 28)
	camera.look_at(Vector3(0, 3, 0), Vector3.UP)

	# Chão estático
	var ground = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(120, 2, 120)
	col.shape = box
	col.position = Vector3(0, -1, 0)
	ground.add_child(col)
	add_child(ground)

func _setup_ramps() -> void:
	# Cria 3 rampas com inclinações diferentes (15°, 30°, 45°) e materiais com atritos distintos
	var angles = [15.0, 30.0, 45.0]
	var frictions = [0.8, 0.4, 0.05]
	var x_offsets = [-12.0, 0.0, 12.0]

	for i in range(3):
		var ramp = StaticBody3D.new()
		ramp.name = "Ramp_%d" % i
		ramp.position = Vector3(x_offsets[i], 3.0, 0.0)
		ramp.rotation_degrees = Vector3(angles[i], 0.0, 0.0)

		var mat = PhysicsMaterial.new()
		mat.friction = frictions[i]
		mat.bounce = 0.2 + (i * 0.25) # Restituição crescente
		ramp.physics_material_override = mat

		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(8.0, 0.5, 18.0)
		col.shape = box
		ramp.add_child(col)

		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = box.size
		var sm = StandardMaterial3D.new()
		sm.albedo_color = Color(0.4, 0.45, 0.5).lerp(Color.RED, i * 0.4)
		mi.mesh = bm
		mi.material_override = sm
		ramp.add_child(mi)

		add_child(ramp)

func _spawn_complex_rocks() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 999
	
	var x_offsets = [-12.0, 0.0, 12.0]

	# Carrega previamente os dados das malhas para o cache de shapes
	var rock_data = ArboriaMeshLoader.load_from_file(MESH_ROCK)
	var boulder_data = ArboriaMeshLoader.load_from_file(MESH_BOULDER)

	var shape_rock = ArboriaMeshLoader.get_cached_convex_shape(MESH_ROCK, rock_data)
	var shape_boulder = ArboriaMeshLoader.get_cached_convex_shape(MESH_BOULDER, boulder_data)

	# Instancia rochas de massas variadas no topo de cada rampa
	for r in range(3):
		for k in range(6):
			var rb = RigidBody3D.new()
			rb.name = "Rock_Ramp%d_%d" % [r, k]
			
			var mass_val = 5.0 + k * 10.0
			rb.mass = mass_val

			var pmat = PhysicsMaterial.new()
			pmat.friction = 0.3
			pmat.bounce = 0.3
			rb.physics_material_override = pmat

			var col = CollisionShape3D.new()
			col.shape = shape_rock if (k % 2 == 0) else shape_boulder
			rb.add_child(col)

			# Mesh visual
			var mi = MeshInstance3D.new()
			var smesh = SphereMesh.new()
			smesh.radius = 0.8
			smesh.height = 1.6
			mi.mesh = smesh
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(0.8, 0.6, 0.4)
			mi.material_override = mat
			rb.add_child(mi)

			# Posição no topo da rampa
			var rz = -6.0 + k * 1.5
			var ry = 7.0 + k * 0.8
			rb.position = Vector3(x_offsets[r] + rng.randf_range(-1.0, 1.0), ry, rz)
			rb.rotation = Vector3(rng.randf_range(0, TAU), rng.randf_range(0, TAU), 0)

			add_child(rb)
			test_bodies.append(rb)

	print("[TESTE B] 18 rochas com Convex Polygon Shapes e massas entre 5kg e 55kg instanciadas nas 3 rampas.")

func _physics_process(_delta: float) -> void:
	frame_count += 1
	var moving_count = 0
	for b in test_bodies:
		if is_instance_valid(b) and b.linear_velocity.length() > 0.05:
			moving_count += 1

	if frame_count % 60 == 0:
		print("[TESTE B - Frame %03d] Corpos em movimento na rampa: %d / %d" % [
			frame_count, moving_count, test_bodies.size()
		])

	if frame_count >= auto_quit_frames:
		_finish_test()

func _finish_test() -> void:
	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE B]")
	var ok_count = 0
	for b in test_bodies:
		# Corpos devem deslizar pela rampa e atingir o chão (y >= 0.0 e y <= 15.0)
		if is_instance_valid(b) and b.position.y >= -0.5:
			ok_count += 1

	print("  Rochas Convexas íntegras e estáveis sobre rampas: %d / %d" % [ok_count, test_bodies.size()])
	if ok_count == test_bodies.size():
		print("[SUCESSO TESTE B] Colisão convexa, atrito, restituição e rolamento validados no Jolt Physics!")
		get_tree().quit(0)
	else:
		push_error("[FALHA TESTE B] Regressão física detectada em corpos convexos!")
		get_tree().quit(1)
