class_name PVEEcosystemGrower
extends Node3D

## ARBORIA ENGINE — ECOSYSTEM GROWER & VIRTUAL GEOMETRY POPULATOR
## Popula o mundo com entidades de geometria virtualizada (Nanite DAG)
## e garante o registro do compositor Forward+ Vulkan 1.4 na cena.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaCompositorEffect = preload("res://scripts/arboria_compositor_effect.gd")
const ArboriaInstance3D = preload("res://scripts/arboria_instance_3d.gd")

@export var grass_count: int = 8000
@export var fern_count: int = 1500
@export var flower_count: int = 1200
@export var rock_count: int = 250
@export var area_size: Vector2 = Vector2(300, 300)

const ROCK_MESH = "res://assets/dense_rock_test.vgmesh"
const BOULDER_MESH = "res://assets/boulder_granite.vgmesh"
const PINE_MESH = "res://assets/pine_trunk_complex.vgmesh"

var spawned_entities: Array[Node3D] = []

func _ready() -> void:
	print("[PVEEcosystemGrower] Inicializando ecossistema vivo do Arboria Engine...")
	_setup_compositor_pipeline()
	_setup_terrain_collision()
	_populate_virtual_geometry()
	
	if "--auto-quit" in OS.get_cmdline_args() or "--auto-quit" in OS.get_cmdline_user_args():
		get_tree().create_timer(2.0).timeout.connect(func(): get_tree().quit(0))

func _setup_compositor_pipeline() -> void:
	var env = get_node_or_null("../WorldEnvironment")
	if env and env is WorldEnvironment:
		ArboriaCompositorEffect.attach_to_environment(env)
		print("[PVEEcosystemGrower] ArboriaCompositorEffect vinculado com sucesso ao WorldEnvironment.")
	
	var pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline:
		print("[PVEEcosystemGrower] Pipeline Nativo Forward+ Vulkan ativo e sincronizado.")

func _setup_terrain_collision() -> void:
	var terrain = get_node_or_null("../Terrain")
	if terrain and terrain is StaticBody3D:
		var col_shape = terrain.get_node_or_null("CollisionPolygon3D")
		if col_shape and col_shape is CollisionShape3D and col_shape.shape == null:
			var box = BoxShape3D.new()
			box.size = Vector3(500, 2, 500)
			col_shape.shape = box
			col_shape.position = Vector3(0, -1, 0)
			print("[PVEEcosystemGrower] Colisao solida de terreno configurada com sucesso.")

func _populate_virtual_geometry() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337
	
	var half_w = area_size.x * 0.5
	var half_h = area_size.y * 0.5
	
	# 1. Instanciacao de Pinheiros Ancestrais Monumentais
	var num_trees = 30
	for i in range(num_trees):
		var tree = ArboriaInstance3D.new()
		tree.name = "VirtualPine_%02d" % i
		tree.mesh_path = PINE_MESH
		
		var px = rng.randf_range(-half_w * 0.8, half_w * 0.8)
		var pz = rng.randf_range(-half_h * 0.8, half_h * 0.8)
		# Deixa uma clareira ao redor do Player (0, 0)
		if Vector2(px, pz).length() < 15.0:
			px += 25.0
			
		tree.position = Vector3(px, 0.0, pz)
		tree.rotation.y = rng.randf_range(0, TAU)
		var sc = rng.randf_range(2.0, 3.5)
		tree.scale = Vector3.ONE * sc
		tree.base_albedo = Color(0.42, 0.32, 0.24)
		tree.roughness = 0.88
		tree.max_screen_error = 1.5
		
		add_child(tree)
		spawned_entities.append(tree)
		
	# 2. Instanciacao de Rochedos e Granitos Virtuais
	var actual_rocks = mini(rock_count, 120)
	for i in range(actual_rocks):
		var rock = ArboriaInstance3D.new()
		rock.name = "VirtualRock_%03d" % i
		rock.mesh_path = ROCK_MESH if (i % 2 == 0) else BOULDER_MESH
		
		var px = rng.randf_range(-half_w, half_w)
		var pz = rng.randf_range(-half_h, half_h)
		if Vector2(px, pz).length() < 8.0:
			pz += 12.0
			
		rock.position = Vector3(px, rng.randf_range(-0.3, 0.2), pz)
		rock.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0, TAU), rng.randf_range(-0.1, 0.1))
		var sc = rng.randf_range(1.2, 2.8)
		rock.scale = Vector3.ONE * sc
		rock.base_albedo = Color(0.65, 0.68, 0.72) if (i % 2 == 0) else Color(0.55, 0.58, 0.60)
		rock.roughness = 0.65
		rock.max_screen_error = 1.5
		
		add_child(rock)
		spawned_entities.append(rock)
		
	print("[PVEEcosystemGrower] Ecossistema gerado com %d entidades virtuais Nanite DAG." % spawned_entities.size())
