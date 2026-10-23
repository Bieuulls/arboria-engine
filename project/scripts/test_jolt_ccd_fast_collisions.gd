extends Node3D

## TESTE D — JOLT PHYSICS: COLISÕES RÁPIDAS & CONTINUOUS COLLISION DETECTION (CCD)
## Testa projéteis pequenos a velocidades ultra-altas (50 m/s a 150 m/s) disparados
## contra paredes finas (espessura 0.1m) para comprovar a eficácia do CCD no Jolt.

@export var projectile_count: int = 40
@export var auto_quit_frames: int = 180

var projectiles: Array[RigidBody3D] = []
var thin_wall: StaticBody3D = null
var wall_z: float = -15.0
var wall_thickness: float = 0.15

var frame_count: int = 0
var tunneled_count: int = 0
var stopped_count: int = 0

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE D] JOLT PHYSICS: COLISÕES RÁPIDAS & CCD EM PAREDES FINAS ")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("  Espessura da Parede: %.2f m | Velocidade: 60 m/s - 120 m/s" % wall_thickness)
	print("=================================================================")

	_setup_environment()
	_setup_thin_wall()
	_spawn_fast_projectiles()

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(10, 30, 20)
	add_child(light)

	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(15, 8, -5)
	camera.look_at(Vector3(0, 3, wall_z), Vector3.UP)

func _setup_thin_wall() -> void:
	thin_wall = StaticBody3D.new()
	thin_wall.name = "ThinWall"
	thin_wall.position = Vector3(0, 4.0, wall_z)

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(25.0, 10.0, wall_thickness)
	col.shape = box
	thin_wall.add_child(col)

	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = box.size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.2, 0.7)
	mi.mesh = bm
	mi.material_override = mat
	thin_wall.add_child(mi)

	add_child(thin_wall)

func _spawn_fast_projectiles() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 777

	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.2 # Projétil pequeno

	for i in range(projectile_count):
		var rb = RigidBody3D.new()
		rb.name = "Bullet_%02d" % i
		rb.mass = 1.0
		# Habilita CCD estrito no Jolt Physics
		rb.continuous_cd = true

		var col = CollisionShape3D.new()
		col.shape = sphere_shape
		rb.add_child(col)

		var px = rng.randf_range(-10.0, 10.0)
		var py = rng.randf_range(1.0, 7.0)
		var pz = rng.randf_range(2.0, 8.0) # Distância de 17m a 23m da parede
		rb.position = Vector3(px, py, pz)

		var speed = rng.randf_range(60.0, 120.0) # 60 a 120 m/s
		rb.linear_velocity = Vector3(0, 0, -speed)

		add_child(rb)
		projectiles.append(rb)

	print("[TESTE D] %d projéteis com CCD ativo e velocidades entre 60m/s e 120m/s disparados." % projectiles.size())

func _physics_process(_delta: float) -> void:
	frame_count += 1

	if frame_count >= auto_quit_frames:
		_finish_test()

func _finish_test() -> void:
	tunneled_count = 0
	stopped_count = 0

	for p in projectiles:
		if is_instance_valid(p):
			# Se o projétil passou para além da parede (Z < wall_z - wall_thickness), houve tunneling!
			if p.position.z < (wall_z - wall_thickness * 1.5):
				tunneled_count += 1
			else:
				stopped_count += 1

	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE D: CCD & VELOCIDADE ALTA]")
	print("  Total de Projéteis Disparados: %d" % projectiles.size())
	print("  Projéteis Barrados pela Parede Fina: %d (%.1f%%)" % [stopped_count, (float(stopped_count)/projectiles.size())*100.0])
	print("  Projéteis com Tunneling (Atravessaram): %d" % tunneled_count)

	if tunneled_count > 0:
		push_error("[FALHA TESTE D] CCD falhou no Jolt! %d projéteis atravessaram a parede fina!" % tunneled_count)
		get_tree().quit(1)
		return

	print("[SUCESSO TESTE D] Continuous Collision Detection (CCD) comprovado com ZERO tunneling no Jolt Physics!")
	print("=================================================================")
	get_tree().quit(0)
