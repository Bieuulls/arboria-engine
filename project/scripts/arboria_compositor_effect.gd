@tool
extends CompositorEffect

## Compositor do projeto vinculado ao pipeline compartilhado usado pelas instâncias.
## O addon standalone mantém seu próprio compositor; dentro do projeto, ambos os
## lados precisam resolver para res://scripts/arboria_native_pipeline.gd.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")

@export_enum("PreOpaque_DepthPrepass", "PostOpaque_MainRaster") var stage: int = 1:
	set(value):
		stage = value
		effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE if stage == 0 else CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE

var pipeline: RefCounted
var active: bool = true

func _init(callback_type: int = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE) -> void:
	effect_callback_type = callback_type
	stage = 0 if callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE else 1
	enabled = true
	set_needs_normal_roughness(true)
	set_needs_motion_vectors(true)
	pipeline = ArboriaNativePipeline.get_or_create_shared()

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if not active:
		return
	if not pipeline:
		pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline or not pipeline.is_initialized:
		return
	if callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE:
		pipeline.render_depth_prepass(render_data)
	elif callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE:
		pipeline.render_scene_instances(render_data)

static func attach_to_environment(target: Variant) -> void:
	if not target:
		return
	var compositor: Compositor
	if target is WorldEnvironment or target is Camera3D:
		if not target.compositor:
			target.compositor = Compositor.new()
		compositor = target.compositor
	elif target is Compositor:
		compositor = target
	if compositor:
		compositor.compositor_effects = [
			new(CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE),
			new(CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE)
		]
		print("[ArboriaCompositorEffect] Pipeline compartilhado do projeto conectado ao Forward+.")

static func detach_from_environment(target: Variant) -> void:
	if not target:
		return
	var compositor: Compositor
	if target is WorldEnvironment or target is Camera3D:
		compositor = target.compositor
	elif target is Compositor:
		compositor = target
	if compositor:
		for effect in compositor.compositor_effects:
			if effect is CompositorEffect and effect.get_script() and effect.get_script().resource_path == "res://scripts/arboria_compositor_effect.gd":
				effect.enabled = false
		compositor.compositor_effects = []
	if target is WorldEnvironment or target is Camera3D:
		target.compositor = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		active = false
		pipeline = null
