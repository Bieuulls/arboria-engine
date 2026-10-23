extends SceneTree

func _init() -> void:
	print("--- INSPEÇÃO DE SERVIDORES DE FÍSICA ---")
	print("physics/3d/physics_engine config: ", ProjectSettings.get_setting("physics/3d/physics_engine"))
	print("has jolt velocity_steps: ", ProjectSettings.has_setting("physics/jolt_physics_3d/simulation/velocity_steps"))
	print("jolt velocity_steps value: ", ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/velocity_steps"))
	
	# Checar métodos de PhysicsServer3DManager se existirem
	if ClassDB.class_exists("PhysicsServer3DManager"):
		print("PhysicsServer3DManager existe.")
		for m in ClassDB.class_get_method_list("PhysicsServer3DManager"):
			print("Metodo: ", m.name)
	
	# Checar classes registradas contendo Jolt
	var jolt_classes = []
	for c in ClassDB.get_class_list():
		if "Jolt" in c or "jolt" in c:
			jolt_classes.append(c)
	print("Classes Jolt encontradas no ClassDB: ", jolt_classes)
	
	# Checar PhysicsServer3D ativo
	var ps = PhysicsServer3D
	print("PhysicsServer3D singleton: ", ps)
	quit(0)
