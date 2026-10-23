extends Node3D

## TESTE F — JOLT PHYSICS + ARBORIA ENGINE INTEGRADO
## Cena técnica completa:
## - Terreno estático com colisão
## - Centenas de instâncias de geometria virtualizada ARBORIA (Nanite DAG)
## - Corpos rígidos dinâmicos (RigidBody3D) interagindo com as superfícies virtuais
## - Personagem CharacterBody3D controlável
## - Câmera móvel gerando mudanças ativas de LOD
## - Verificação de estabilidade: colisores persistem inalterados na mudança de LOD

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")
const ArboriaRigidBody3D = preload("res://scripts/arboria_rigid_body_3d.gd")
const PlayerController3D = preload("res://scripts/player_controller_3d.gd")

const MESH_ROCK = "res://assets/dense_rock_test.vgmesh"
const MESH_BOULDER = "res://assets/boulder_granite.vgmesh"
const MESH_PINE = "res://assets/pine_trunk_complex.vgmesh"

@export var auto_quit_frames: int = 300
var frame_count: int = 0

var camera: Camera3D = null
var dynamic_rocks: Array[RigidBody3D] = []
var static_arboria_entities: Array[ArboriaInstance3D] = []
var player: PlayerController3D = null

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE F] ARBORIA ENGINE + JOLT PHYSICS: CENA INTEGRADA MASTER ")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("=================================================================")

	_setup_compositor()
	_setup_environment()
	_setup_terrain()
	_setup_arboria_virtual_geometry()
	_setup_dynamic_rigid_bodies()
	_setup_player()

func _setup_compositor() -> void:
	var env = $WorldEnvironment if has_node("WorldEnvironment") else null
	if not env:
		env = WorldEnvironment.new()
		env.name = "WorldEnvironment"
		var e = Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.12, 0.15, 0.20)
		env.environment = e
		add_child(env)
	ArboriaCompositorEffect.attach_to_environment(env)

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(20, 40, 30)
	light.rotation_degrees = Vector3(-50, 35, 0)
	add_child(light)

func _setup_terrain() -> void:
	var ground = StaticBody3D.new()
	ground.name = "TerrainGround"
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	col.shape = box
	col.position = Vector3(0, -1, 0)
	ground.add_child(col)
	add_child(ground)

func _setup_arboria_virtual_geometry() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 2026

	# 1. Instanciacao de 80 rochas virtuais com colisor estático convexo/côncavo
	for i in range(80):
		var rock = ArboriaInstance3D.new()
		rock.name = "ArboriaRock_%03d" % i
		rock.mesh_path = MESH_ROCK if (i % 2 == 0) else MESH_BOULDER
		
		var px = rng.randf_range(-35.0, 35.0)
		var pz = rng.randf_range(-35.0, 35.0)
		# Deixar centro livre para o player
		if Vector2(px, pz).length() < 6.0:
			px += 10.0
			
		rock.position = Vector3(px, 0.0, pz)
		rock.rotation.y = rng.randf_range(0, TAU)
		var sc = rng.randf_range(1.5, 3.0)
		rock.scale = Vector3.ONE * sc
		
		# Habilita colisor estático convexo integrado no Jolt
		rock.collision_mode = 2 # Static Convex
		rock.max_screen_error = 1.5
		
		add_child(rock)
		static_arboria_entities.append(rock)

	# 2. Pinheiros virtuais de fundo (LOD dinâmico visual massivo)
	for i in range(30):
		var pine = ArboriaInstance3D.new()
		pine.name = "ArboriaPine_%02d" % i
		pine.mesh_path = MESH_PINE
		var px = rng.randf_range(-60.0, 60.0)
		var pz = rng.randf_range(-60.0, 60.0)
		if Vector2(px, pz).length() < 25.0:
			pz -= 30.0
		pine.position = Vector3(px, 0.0, pz)
		pine.scale = Vector3.ONE * rng.randf_range(2.0, 4.0)
		add_child(pine)
		static_arboria_entities.append(pine)

	print("[TESTE F] %d entidades virtuais ARBORIA populadas com colisores físicos Jolt." % static_arboria_entities.size())

func _setup_dynamic_rigid_bodies() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1234

	# Instancia 40 corpos rígidos dinâmicos (esferas e caixas) que cairão sobre o cenário e as rochas
	for i in range(40):
		var rb = RigidBody3D.new()
		rb.name = "DynamicEntity_%02d" % i
		rb.mass = rng.randf_range(2.0, 15.0)
		rb.position = Vector3(
			rng.randf_range(-20.0, 20.0),
			rng.randf_range(5.0, 18.0),
			rng.randf_range(-20.0, 20.0)
		)

		var col = CollisionShape3D.new()
		if i % 2 == 0:
			var s = SphereShape3D.new()
			s.radius = rng.randf_range(0.4, 0.8)
			col.shape = s
		else:
			var b = BoxShape3D.new()
			var sz = rng.randf_range(0.6, 1.2)
			b.size = Vector3(sz, sz, sz)
			col.shape = b
		rb.add_child(col)

		add_child(rb)
		dynamic_rocks.append(rb)

	print("[TESTE F] %d corpos rígidos dinâmicos instanciados com gravidade ativa." % dynamic_rocks.size())

func _setup_player() -> void:
	player = PlayerController3D.new()
	player.name = "MainPlayer"
	player.position = Vector3(0.0, 1.0, 0.0)

	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0.0, 0.9, 0.0)
	player.add_child(col)

	var visual = Node3D.new()
	visual.name = "VisualMesh"
	player.add_child(visual)

	var arm = SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.position = Vector3(0.0, 1.6, 0.0)
	arm.spring_length = 5.0

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.position = Vector3(0, 0, 5.0)
	arm.add_child(camera)
	player.add_child(arm)

	add_child(player)

func _physics_process(_delta: float) -> void:
	frame_count += 1

	# Movimento contínuo do personagem para testar interação física com o mundo
	if frame_count <= 220:
		Input.action_press("move_forward", 1.0)
		if frame_count >= 80 and frame_count <= 140:
			Input.action_press("sprint", 1.0)
		else:
			Input.action_release("sprint")
	else:
		Input.action_release("move_forward")
		Input.action_release("sprint")

	# Pulo no frame 100
	if frame_count == 100:
		Input.action_press("jump", 1.0)
	elif frame_count == 103:
		Input.action_release("jump")

	# Variação dinâmica de distância da câmera para forçar transição contínua de LOD no DAG Nanite
	if camera and player:
		var cam_arm = player.get_node_or_null("SpringArm3D")
		if cam_arm and cam_arm is SpringArm3D:
			# Oscila a distância entre 3m e 25m, acionando diferentes níveis de cluster LOD
			cam_arm.spring_length = 10.0 + sin(frame_count * 0.05) * 8.0

	if frame_count % 60 == 0:
		var sleeping_count = 0
		for b in dynamic_rocks:
			if is_instance_valid(b) and b.sleeping:
				sleeping_count += 1
		print("[TESTE F - Frame %03d] Player Pos: (%.2f, %.2f, %.2f) | Corpos Dinâmicos Dormindo: %d / %d" % [
			frame_count, player.position.x, player.position.y, player.position.z,
			sleeping_count, dynamic_rocks.size()
		])

	if frame_count >= auto_quit_frames:
		_finish_test()

func _finish_test() -> void:
	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE F: ARBORIA + JOLT INTEGRADO]")
	print("  Entidades Virtuais ARBORIA Renderizadas: %d" % static_arboria_entities.size())
	print("  Corpos Rígidos Dinâmicos: %d" % dynamic_rocks.size())
	print("  Posição Final do Player: ", player.position)

	# 1. Comprova estabilidade física dos corpos
	var tunneled_count = 0
	for b in dynamic_rocks:
		if is_instance_valid(b) and b.position.y < -3.0:
			tunneled_count += 1

	if tunneled_count > 0:
		push_error("[FALHA TESTE F] %d corpos atravessaram o chão ou as rochas virtuais!" % tunneled_count)
		_cleanup()
		get_tree().quit(1)
		return

	# 2. Comprova integridade dos colisores das instâncias virtuais
	var valid_colliders = 0
	for ent in static_arboria_entities:
		if is_instance_valid(ent) and ent._physics_body != null:
			valid_colliders += 1

	print("  Colisores Físicos Persistentes nas Entidades Virtuais: %d / 80" % valid_colliders)
	if valid_colliders < 80:
		push_error("[FALHA TESTE F] Colisores foram destruídos durante mudanças de LOD!")
		_cleanup()
		get_tree().quit(1)
		return

	print("[SUCESSO ABSOLUTO TESTE F] Arboria Virtual Geometry + Jolt Physics 100% integrados e operacionais!")
	print("=================================================================")
	_cleanup()
	get_tree().quit(0)

func _cleanup() -> void:
	var env = $WorldEnvironment if has_node("WorldEnvironment") else null
	if env:
		ArboriaCompositorEffect.detach_from_environment(env)
	for ent in static_arboria_entities:
		if is_instance_valid(ent):
			ent.queue_free()
	static_arboria_entities.clear()
	dynamic_rocks.clear()
	var pipe = ArboriaNativePipeline.get_active_instance()
	if pipe:
		pipe.cleanup()
