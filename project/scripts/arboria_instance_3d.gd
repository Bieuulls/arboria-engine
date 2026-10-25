@tool
class_name ArboriaInstance3D
extends VisualInstance3D

## Instância de Geometria Virtualizada ARBORIA ENGINE
## Permite instanciar malhas virtuais (.vgmesh) na cena 3D do Godot com LOD Nanite DAG,
## GPU Culling e desenho indireto nativo no Forward+.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")
const ArboriaMeshLoader = preload("res://scripts/arboria_mesh_loader.gd")

signal mesh_loaded(path: String)
signal transform_updated()

@export_file("*.vgmesh") var mesh_path: String = "":
	set(value):
		if mesh_path != value:
			mesh_path = value
			_on_mesh_path_changed()

@export_group("LOD & Culling")
@export_range(0.1, 10.0, 0.1) var max_screen_error: float = 1.5:
	set(value):
		max_screen_error = value
		notify_pipeline_update()

@export_enum("Auto DAG Nanite", "Forced LOD") var lod_mode: int = 0:
	set(value):
		lod_mode = value
		notify_pipeline_update()

@export_range(0, 16, 1) var forced_lod: int = 0:
	set(value):
		forced_lod = value
		notify_pipeline_update()

@export_group("Material Override (StandardMaterial3D)")
@export var material_override: StandardMaterial3D = null:
	set(value):
		if material_override and material_override.changed.is_connected(_on_material_override_changed):
			material_override.changed.disconnect(_on_material_override_changed)
		material_override = value
		if material_override:
			material_override.changed.connect(_on_material_override_changed)
			_sync_from_material_override()
		if _shadow_proxy_node and is_instance_valid(_shadow_proxy_node):
			_shadow_proxy_node.material_override = material_override
		notify_pipeline_update()

func _on_material_override_changed() -> void:
	_sync_from_material_override()
	notify_pipeline_update()

func _sync_from_material_override() -> void:
	if not material_override:
		return
	base_albedo = material_override.albedo_color
	roughness = material_override.roughness
	metallic = material_override.metallic
	specular = material_override.metallic_specular
	if material_override.albedo_texture:
		albedo_texture = material_override.albedo_texture
	if material_override.normal_enabled and material_override.normal_texture:
		normal_texture = material_override.normal_texture
		normal_scale = material_override.normal_scale
	if material_override.roughness_texture:
		orm_texture = material_override.roughness_texture
	uv_scale = Vector2(material_override.uv1_scale.x, material_override.uv1_scale.y)
	if material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		alpha_scissor_threshold = material_override.alpha_scissor_threshold
	if material_override.emission_enabled:
		emission = material_override.emission
		emission_energy = material_override.emission_energy_multiplier

@export_group("Material PBR")
@export var base_albedo: Color = Color(0.80, 0.82, 0.85):
	set(value):
		base_albedo = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var roughness: float = 0.65:
	set(value):
		roughness = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var metallic: float = 0.05:
	set(value):
		metallic = value
		notify_pipeline_update()

@export_range(0.0, 1.0, 0.01) var specular: float = 0.50:
	set(value):
		specular = value
		notify_pipeline_update()

@export_group("Texturas PBR Externas")
@export var albedo_texture: Texture2D:
	set(value):
		albedo_texture = value
		notify_pipeline_update()

@export var normal_texture: Texture2D:
	set(value):
		normal_texture = value
		notify_pipeline_update()

@export var orm_texture: Texture2D:
	set(value):
		orm_texture = value
		notify_pipeline_update()

@export var uv_scale: Vector2 = Vector2.ONE:
	set(value):
		uv_scale = value
		notify_pipeline_update()

@export var normal_scale: float = 1.0:
	set(value):
		normal_scale = value
		notify_pipeline_update()

@export_group("Alpha Cutout & Emissao")
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.0:
	set(value):
		alpha_scissor_threshold = value
		notify_pipeline_update()

@export var emission: Color = Color.BLACK:
	set(value):
		emission = value
		notify_pipeline_update()

@export_range(0.0, 16.0, 0.1) var emission_energy: float = 0.0:
	set(value):
		emission_energy = value
		notify_pipeline_update()

@export_group("Physics & Collision (Jolt)")
@export_enum("None", "Static Concave", "Static Convex", "Static Box", "Rigid Convex", "Rigid Box") var collision_mode: int = 0:
	set(value):
		collision_mode = value
		if is_inside_tree():
			_update_physics_collision()

@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		if _physics_body:
			_physics_body.collision_layer = value

@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		if _physics_body:
			_physics_body.collision_mask = value

@export var mass: float = 1.0:
	set(value):
		mass = value
		if _physics_body and _physics_body is RigidBody3D:
			_physics_body.mass = value

var _pipeline: RefCounted = null
var _aabb: AABB = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
var _mesh_data: Dictionary = {}
var _is_registered: bool = false
var _shadow_proxy_mesh: Mesh = null
var _shadow_proxy_node: MeshInstance3D = null
var _physics_body: CollisionObject3D = null
var _collision_shape_node: CollisionShape3D = null

func _ready() -> void:
	set_notify_transform(true)
	if mesh_path != "":
		_load_mesh_if_needed()
	_register_to_pipeline()
	_update_physics_collision()

func _update_physics_collision() -> void:
	if collision_mode == 0:
		if _physics_body:
			_physics_body.queue_free()
			_physics_body = null
			_collision_shape_node = null
		return

	if _mesh_data.is_empty():
		return

	# Seleciona o shape apropriado do cache
	var shape: Shape3D = null
	if collision_mode == 1: # Static Concave
		shape = ArboriaMeshLoader.get_cached_concave_shape(mesh_path, _mesh_data, 0)
	elif collision_mode == 2 or collision_mode == 4: # Static Convex ou Rigid Convex
		shape = ArboriaMeshLoader.get_cached_convex_shape(mesh_path, _mesh_data)
	elif collision_mode == 3 or collision_mode == 5: # Static Box ou Rigid Box
		shape = ArboriaMeshLoader.get_cached_box_shape(mesh_path, _mesh_data)

	if not shape:
		return

	var is_rigid = (collision_mode == 4 or collision_mode == 5)
	
	# Se o pai ja for um CollisionObject3D (ex: o usuário colocou ArboriaInstance3D dentro de um RigidBody3D),
	# apenas garante que há um CollisionShape3D no pai com o shape correspondente.
	var parent = get_parent()
	if parent is CollisionObject3D:
		if not _collision_shape_node or _collision_shape_node.get_parent() != parent:
			_collision_shape_node = CollisionShape3D.new()
			_collision_shape_node.name = name + "_CollisionShape"
			parent.add_child(_collision_shape_node)
		_collision_shape_node.shape = shape
		return

	# Caso contrário, instancia o corpo como filho
	if is_rigid:
		if not (_physics_body is RigidBody3D):
			if _physics_body: _physics_body.queue_free()
			var rb = RigidBody3D.new()
			rb.name = name + "_RigidBody"
			_physics_body = rb
			add_child(_physics_body)
			_collision_shape_node = CollisionShape3D.new()
			_physics_body.add_child(_collision_shape_node)
		(_physics_body as RigidBody3D).mass = mass
	else:
		if not (_physics_body is StaticBody3D):
			if _physics_body: _physics_body.queue_free()
			var sb = StaticBody3D.new()
			sb.name = name + "_StaticBody"
			_physics_body = sb
			add_child(_physics_body)
			_collision_shape_node = CollisionShape3D.new()
			_physics_body.add_child(_collision_shape_node)

	_physics_body.collision_layer = collision_layer
	_physics_body.collision_mask = collision_mask
	if _collision_shape_node:
		_collision_shape_node.shape = shape

func _enter_tree() -> void:
	set_notify_transform(true)
	_register_to_pipeline()
	if _aabb.size.length_squared() > 0.001:
		_setup_shadow_proxy()

func _exit_tree() -> void:
	_unregister_from_pipeline()
	set_base(RID())
	_shadow_proxy_mesh = null
	if _shadow_proxy_node and is_instance_valid(_shadow_proxy_node):
		_shadow_proxy_node.queue_free()
		_shadow_proxy_node = null
	_pipeline = null
	if _physics_body:
		_physics_body.queue_free()
		_physics_body = null
	if _collision_shape_node and _collision_shape_node.get_parent() != self:
		_collision_shape_node.queue_free()
		_collision_shape_node = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		var parent = get_parent()
		if parent is RigidBody3D and parent.sleeping:
			return # Otimizacao: Nao suja a GPU Scene se o corpo fisico estiver dormindo
		notify_pipeline_update()
		emit_signal("transform_updated")
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		notify_pipeline_update()

func _on_mesh_path_changed() -> void:
	if is_inside_tree():
		_load_mesh_if_needed()
		_update_physics_collision()
		notify_pipeline_update()

func _load_mesh_if_needed() -> void:
	if mesh_path == "":
		return

	var pipeline = get_pipeline()
	if pipeline:
		_mesh_data = pipeline.get_or_load_mesh(mesh_path)
		if _mesh_data.has("bbox_min") and _mesh_data.has("bbox_max"):
			var bmin = _mesh_data["bbox_min"]
			var bmax = _mesh_data["bbox_max"]
			_aabb = AABB(bmin, bmax - bmin)
			_setup_shadow_proxy()
		emit_signal("mesh_loaded", mesh_path)

func _setup_shadow_proxy() -> void:
	if mesh_path != "" and not _mesh_data.is_empty():
		var am = ArboriaMeshLoader.get_cached_array_mesh(mesh_path, _mesh_data, 0)
		if am:
			_shadow_proxy_mesh = am
			if not _shadow_proxy_node or not is_instance_valid(_shadow_proxy_node):
				_shadow_proxy_node = MeshInstance3D.new()
				_shadow_proxy_node.name = "_ArboriaShadowProxy"
				add_child(_shadow_proxy_node)
			_shadow_proxy_node.mesh = am
			_shadow_proxy_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			print("[ArboriaInstance3D] Shadow proxy MeshInstance3D configurado com sucesso: ", mesh_path)
			return

	if _aabb.size.length_squared() < 0.001:
		set_base(RID())
		return
	if not _shadow_proxy_mesh:
		_shadow_proxy_mesh = BoxMesh.new()
	_shadow_proxy_mesh.size = _aabb.size
	set_base(_shadow_proxy_mesh.get_rid())
	var inst_rid = get_instance()
	if inst_rid.is_valid():
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst_rid, RenderingServer.SHADOW_CASTING_SETTING_SHADOWS_ONLY)

func _get_aabb() -> AABB:
	return _aabb

func get_custom_aabb() -> AABB:
	return _aabb

func _register_to_pipeline() -> void:
	if _is_registered:
		return
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("register_instance"):
		pipeline.register_instance(self)
		_is_registered = true

func _unregister_from_pipeline() -> void:
	if not _is_registered:
		return
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("unregister_instance"):
		pipeline.unregister_instance(self)
	_is_registered = false

func notify_pipeline_update() -> void:
	var pipeline = get_pipeline()
	if pipeline and pipeline.has_method("mark_instance_dirty"):
		pipeline.mark_instance_dirty(self)

func get_pipeline() -> RefCounted:
	if _pipeline:
		return _pipeline
	if ArboriaNativePipeline.get_active_instance():
		_pipeline = ArboriaNativePipeline.get_active_instance()
	else:
		_pipeline = ArboriaNativePipeline.get_or_create_shared()
	return _pipeline
