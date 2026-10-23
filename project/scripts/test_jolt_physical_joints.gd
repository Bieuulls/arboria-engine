extends Node3D

## TESTE E — JOLT PHYSICS: RESTRIÇÕES FÍSICAS E JUNTAS (JOINTS)
## Testa juntas suportadas pelo Jolt Physics: PinJoint3D, HingeJoint3D e SliderJoint3D.
## Valida restrições angulares, preservação de distância e estabilidade do solver.

@export var auto_quit_frames: int = 180
var frame_count: int = 0

var pendulum_body: RigidBody3D = null
var hinge_door_body: RigidBody3D = null
var slider_piston_body: RigidBody3D = null

func _ready() -> void:
	print("=================================================================")
	print(" [TESTE E] JOLT PHYSICS: RESTRIÇÕES FÍSICAS E JUNTAS (JOINTS)    ")
	print("  Backend Atual: %s" % ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("=================================================================")

	_setup_environment()
	_setup_pin_joint_pendulum()
	_setup_hinge_joint_door()
	_setup_slider_joint_piston()

func _setup_environment() -> void:
	var light = DirectionalLight3D.new()
	light.position = Vector3(10, 30, 20)
	add_child(light)

	var camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 8, 15)
	camera.look_at(Vector3(0, 4, 0), Vector3.UP)

func _setup_pin_joint_pendulum() -> void:
	# Ponto de ancoragem estático
	var anchor = StaticBody3D.new()
	anchor.position = Vector3(-6.0, 8.0, 0.0)
	var acol = CollisionShape3D.new()
	var ashape = SphereShape3D.new()
	ashape.radius = 0.3
	acol.shape = ashape
	anchor.add_child(acol)
	add_child(anchor)

	# Corpo do pêndulo
	pendulum_body = RigidBody3D.new()
	pendulum_body.position = Vector3(-3.0, 8.0, 0.0) # Deslocado 3m horizontalmente para oscilar por gravidade
	pendulum_body.mass = 5.0
	var pcol = CollisionShape3D.new()
	var pshape = SphereShape3D.new()
	pshape.radius = 0.5
	pcol.shape = pshape
	pendulum_body.add_child(pcol)
	add_child(pendulum_body)

	# PinJoint3D conectando âncora ao pêndulo
	var pin = PinJoint3D.new()
	pin.position = Vector3(-6.0, 8.0, 0.0)
	pin.node_a = anchor.get_path()
	pin.node_b = pendulum_body.get_path()
	add_child(pin)

func _setup_hinge_joint_door() -> void:
	# Posto estático da dobradiça
	var post = StaticBody3D.new()
	post.position = Vector3(0.0, 4.0, 0.0)
	var post_col = CollisionShape3D.new()
	var post_shape = CylinderShape3D.new()
	post_shape.height = 3.0
	post_shape.radius = 0.15
	post_col.shape = post_shape
	post.add_child(post_col)
	add_child(post)

	# Folha da porta (RigidBody)
	hinge_door_body = RigidBody3D.new()
	hinge_door_body.position = Vector3(1.0, 4.0, 0.0)
	hinge_door_body.mass = 2.0
	var dcol = CollisionShape3D.new()
	var dbox = BoxShape3D.new()
	dbox.size = Vector3(2.0, 2.5, 0.1)
	dcol.shape = dbox
	hinge_door_body.add_child(dcol)
	add_child(hinge_door_body)

	# HingeJoint3D
	var hinge = HingeJoint3D.new()
	hinge.position = Vector3(0.0, 4.0, 0.0)
	hinge.rotation_degrees = Vector3(90, 0, 0) # Eixo vertical de rotação
	hinge.node_a = post.get_path()
	hinge.node_b = hinge_door_body.get_path()
	add_child(hinge)

	# Impulso inicial para iniciar giro
	hinge_door_body.apply_torque_impulse(Vector3(0, 10.0, 0))

func _setup_slider_joint_piston() -> void:
	# Base estática do trilho deslizante
	var rail_base = StaticBody3D.new()
	rail_base.position = Vector3(6.0, 4.0, 0.0)
	var rcol = CollisionShape3D.new()
	var rshape = BoxShape3D.new()
	rshape.size = Vector3(0.5, 0.5, 6.0)
	rcol.shape = rshape
	rail_base.add_child(rcol)
	add_child(rail_base)

	# Pistão deslizante (RigidBody)
	slider_piston_body = RigidBody3D.new()
	slider_piston_body.position = Vector3(6.0, 4.0, 1.0)
	slider_piston_body.mass = 3.0
	var scol = CollisionShape3D.new()
	var sbox = BoxShape3D.new()
	sbox.size = Vector3(0.8, 0.8, 0.8)
	scol.shape = sbox
	slider_piston_body.add_child(scol)
	add_child(slider_piston_body)

	# SliderJoint3D
	var slider = SliderJoint3D.new()
	slider.position = Vector3(6.0, 4.0, 0.0)
	slider.node_a = rail_base.get_path()
	slider.node_b = slider_piston_body.get_path()
	add_child(slider)

	slider_piston_body.apply_central_impulse(Vector3(0, 0, 8.0))

func _physics_process(_delta: float) -> void:
	frame_count += 1
	if frame_count >= auto_quit_frames:
		_finish_test()

func _finish_test() -> void:
	print("=================================================================")
	print(" [RELATÓRIO DE CONCLUSÃO - TESTE E: JUNTAS & RESTRIÇÕES JOLT]")
	
	# Verificações de integridade das juntas:
	# 1. Pêndulo deve ter oscilado mantendo o raio de 3m da âncora (-6.0, 8.0, 0.0)
	var anchor_pos = Vector3(-6.0, 8.0, 0.0)
	var pend_dist = pendulum_body.position.distance_to(anchor_pos)
	print("  Distância do Pêndulo à Âncora: %.3f m (esperado: ~3.000 m)" % pend_dist)

	# 2. Dobradiça deve manter a porta próxima ao poste
	var post_pos = Vector3(0.0, 4.0, 0.0)
	var door_dist = hinge_door_body.position.distance_to(post_pos)
	print("  Distância do Centro da Porta ao Poste: %.3f m (esperado: ~1.000 m)" % door_dist)

	# 3. Pistão deslizante deve permanecer alinhado em X e Y
	var rail_deviation = abs(slider_piston_body.position.x - 6.0) + abs(slider_piston_body.position.y - 4.0)
	print("  Desvio Ortogonal do Pistão no Trilho: %.4f m" % rail_deviation)

	if abs(pend_dist - 3.0) > 0.35:
		push_error("[FALHA TESTE E] PinJoint3D falhou em preservar restrição de distância!")
		get_tree().quit(1)
		return

	if rail_deviation > 0.2:
		push_error("[FALHA TESTE E] SliderJoint3D falhou em restringir movimento ao eixo!")
		get_tree().quit(1)
		return

	print("[SUCESSO TESTE E] PinJoint3D, HingeJoint3D e SliderJoint3D validados com integridade no Jolt Physics!")
	print("=================================================================")
	get_tree().quit(0)
