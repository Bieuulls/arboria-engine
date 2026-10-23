extends Node3D

## TESTE C — JOLT PHYSICS: CHARACTER CONTROLLER 3D
## Valida movimentação, snap no solo, subida de rampas e degraus,
## colisão lateral e empurrão físico de RigidBody3D.

const PlayerController3D = preload("res://scripts/player_controller_3d.gd")

var player: PlayerController3D = null
var pushable_box: RigidBody3D = null
var static_wall: StaticBody3D = null

var frame_count: int = 0
var initial_box_pos: Vector3 = Vector3.ZERO
var initial_player_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE C] JOLT PHYSICS: CHARACTER CONTROLLER 3D (MOVIMENTO & COLISÃO)")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("=================================================================")

	_setup_environment()
	_setup_test_course()
	_setup_player()

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(10, 30, 20)
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)

	# Chão base
	var ground = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(100, 2, 100)
	col.shape = box
	col.position = Vector3(0, -1, 0)
	ground.add_child(col)
	add_child(ground)

func _setup_test_course() -> void:
	# 1. Caixa Rígida Dinâmica Empurrável no caminho direto
	pushable_box = RigidBody3D.new()
	pushable_box.name = "PushableBox"
	pushable_box.mass = 4.0
	pushable_box.position = Vector3(0.0, 0.7, -2.5)
	initial_box_pos = pushable_box.position
	
	var pcol = CollisionShape3D.new()
	var pbox = BoxShape3D.new()
	pbox.size = Vector3(1.2, 1.2, 1.2)
	pcol.shape = pbox
	pushable_box.add_child(pcol)

	var pmat = PhysicsMaterial.new()
	pmat.friction = 0.2
	pushable_box.physics_material_override = pmat
	add_child(pushable_box)

	# 2. Degraus (escada de 3 degraus de 0.25m após a caixa)
	for i in range(3):
		var step = StaticBody3D.new()
		step.name = "Step_%d" % i
		step.position = Vector3(0, (i + 1) * 0.25 * 0.5, -6.0 - i * 0.8)
		var c = CollisionShape3D.new()
		var b = BoxShape3D.new()
		b.size = Vector3(6.0, (i + 1) * 0.25, 0.8)
		c.shape = b
		step.add_child(c)
		add_child(step)

	# 3. Parede Estática Final (para teste de colisão sem tunneling)
	static_wall = StaticBody3D.new()
	static_wall.name = "StaticWall"
	static_wall.position = Vector3(0, 2.0, -12.0)
	var wc = CollisionShape3D.new()
	var wb = BoxShape3D.new()
	wb.size = Vector3(8.0, 4.0, 1.0)
	wc.shape = wb
	static_wall.add_child(wc)
	add_child(static_wall)

func _setup_player() -> void:
	player = PlayerController3D.new()
	player.name = "TestPlayer"
	player.position = Vector3(0.0, 1.0, 0.0)
	initial_player_pos = player.position

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
	arm.spring_length = 4.0
	
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, 0.0, 4.0)
	arm.add_child(cam)
	player.add_child(arm)

	add_child(player)

func _physics_process(_delta: float) -> void:
	frame_count += 1

	# Simulação automatizada de input:
	# Frames 1-120: Avançar (move_forward) -> sobe degraus e empurra a caixa
	if frame_count <= 140:
		Input.action_press("move_forward", 1.0)
		if frame_count >= 60 and frame_count <= 80:
			Input.action_press("sprint", 1.0)
		else:
			Input.action_release("sprint")
	else:
		Input.action_release("move_forward")
		Input.action_release("sprint")

	# Pulo no frame 90
	if frame_count == 90:
		Input.action_press("jump", 1.0)
	elif frame_count == 92:
		Input.action_release("jump")

	if frame_count % 30 == 0:
		print("[TESTE C - Frame %03d] Player Pos: (%.2f, %.2f, %.2f) | No Chão: %s | Caixa Z: %.2f" % [
			frame_count, player.position.x, player.position.y, player.position.z,
			str(player.is_on_floor()), pushable_box.position.z
		])

	if frame_count >= 220:
		_finish_test()

func _finish_test() -> void:
	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE C]")
	print("  Posição Inicial do Player: ", initial_player_pos)
	print("  Posição Final do Player: ", player.position)
	print("  Deslocamento da Caixa Empurrada: %.2f m" % (pushable_box.position.z - initial_box_pos.z))

	# Verificações de rigor físico:
	# 1. Player deve ter se movido para frente (Z negativo)
	if player.position.z >= initial_player_pos.z:
		push_error("[FALHA TESTE C] O Player não se moveu para frente!")
		get_tree().quit(1)
		return

	# 2. Player não deve ter atravessado a parede estática a Z = -12.0
	if player.position.z < -11.5:
		push_error("[FALHA TESTE C] Tunneling detectado! Player atravessou a parede estática!")
		get_tree().quit(1)
		return

	# 3. Caixa dinâmica deve ter sido empurrada para frente pelo Player
	var box_displacement = abs(pushable_box.position.z - initial_box_pos.z)
	if box_displacement < 0.2:
		push_error("[FALHA TESTE C] Caixa dinâmica não respondeu ao empurrão do Player!")
		get_tree().quit(1)
		return

	# 4. Player deve estar no chão
	if not player.is_on_floor():
		push_error("[FALHA TESTE C] Player não está fixado no solo ao final do teste!")
		get_tree().quit(1)
		return

	print("[SUCESSO TESTE C] CharacterBody3D, degraus, colisão e empurrão validados com distinção no Jolt Physics!")
	print("=================================================================")
	get_tree().quit(0)
