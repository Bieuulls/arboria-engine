@tool
extends Node3D
class_name DayNightCycle

## ====================================================================
## ARBORIA 3D - DYNAMIC CELESTIAL DAY/NIGHT & ATMOSPHERE CONTROLLER
## Controla o ciclo solar físico:
## - Rotação do Sol e da Lua em tempo real
## - Transição de temperatura de cor (Alvorada, Meio-dia, Crepúsculo, Noite)
## - Modulação dinâmica da energia do SDFGI e da luz ambiente
## ====================================================================

@export_range(0.0, 24.0, 0.1) var time_of_day: float = 8.5:
	set(val):
		time_of_day = val
		update_celestial_lighting()

@export var day_length_seconds: float = 600.0 # 10 minutos por dia completo
@export var is_running: bool = true

@export_group("Nodes References")
@export var sun_light: DirectionalLight3D
@export var world_env: WorldEnvironment

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and is_running:
		time_of_day += (delta / day_length_seconds) * 24.0
		if time_of_day >= 24.0:
			time_of_day -= 24.0
		update_celestial_lighting()

func update_celestial_lighting() -> void:
	if not sun_light:
		return

	# Ângulo do sol (0h = meia-noite embaixo, 6h = nascer do sol, 12h = meio-dia no zênite, 18h = poente)
	var sun_angle = ((time_of_day - 6.0) / 24.0) * TAU
	sun_light.rotation.x = -sun_angle
	sun_light.rotation.y = deg_to_rad(-35.0)

	var sun_elevation = sin(sun_angle)

	# 1. Dia Pleno (Elevação > 0.25)
	if sun_elevation > 0.25:
		sun_light.visible = true
		sun_light.light_energy = lerp(1.8, 2.5, sun_elevation)
		sun_light.light_color = Color(1.0, 0.96, 0.88)
	# 2. Crepúsculo / Alvorada Dourada (-0.05 a 0.25)
	elif sun_elevation > -0.05:
		sun_light.visible = true
		var t = (sun_elevation + 0.05) / 0.30
		sun_light.light_energy = lerp(0.3, 1.8, t)
		# Cor rubi/dourada dramática
		sun_light.light_color = Color(1.0, 0.65, 0.32).lerp(Color(1.0, 0.96, 0.88), t)
	# 3. Noite Estrelada com Luar Suave
	else:
		sun_light.visible = true
		sun_light.light_energy = 0.15 # Luz azulada suave da lua
		sun_light.light_color = Color(0.35, 0.52, 0.75)

	# Ajusta energia do SDFGI se disponível
	if world_env and world_env.environment:
		var env = world_env.environment
		if env.sdfgi_enabled:
			env.sdfgi_energy = clamp(sun_elevation * 1.2 + 0.2, 0.1, 1.3)
