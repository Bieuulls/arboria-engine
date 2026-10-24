@tool
class_name ArboriaCompositorEffect
extends CompositorEffect

## ARBORIA ENGINE — FORWARD+ COMPOSITOR INTEGRATION (PRE_OPAQUE & POST_OPAQUE)
## Conecta a renderização nativa de geometria virtualizada às passagens Forward+ do Godot,
## suportando Depth Prepass com Reversed-Z, Motion Vectors, Normais/Roughness e Renderização Opaca Principal.

const ArboriaNativePipeline = preload("arboria_native_pipeline.gd")

@export_enum("PreOpaque_DepthPrepass", "PostOpaque_MainRaster") var stage: int = 1:
	set(val):
		stage = val
		if stage == 0:
			effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE
		else:
			effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE

var pipeline: ArboriaNativePipeline
var active: bool = true

func _init(p_type: int = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE):
	effect_callback_type = p_type
	if p_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE:
		stage = 0
	else:
		stage = 1
	enabled = true
	set_needs_normal_roughness(true)
	set_needs_motion_vectors(true)
	pipeline = ArboriaNativePipeline.get_or_create_shared()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if not active:
		return
	if not pipeline:
		pipeline = ArboriaNativePipeline.get_or_create_shared()
	if not pipeline or not pipeline.is_initialized:
		return

	if p_effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE:
		pipeline.render_depth_prepass(p_render_data)
	elif p_effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE:
		pipeline.render_scene_instances(p_render_data)

## Vincula ambos os passos (Depth Prepass e Main Opaque) ao Compositor do ambiente ou câmera
static func attach_to_environment(target: Variant) -> void:
	if not target:
		return
	var comp: Compositor = null
	if target is WorldEnvironment or target is Camera3D:
		if not target.compositor:
			target.compositor = Compositor.new()
		comp = target.compositor
	elif target is Compositor:
		comp = target

	if comp:
		var pre_eff = ArboriaCompositorEffect.new(CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_OPAQUE)
		var post_eff = ArboriaCompositorEffect.new(CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE)
		comp.compositor_effects = [pre_eff, post_eff]
		print("[ArboriaCompositorEffect] Integracao Forward+ completa ativada (Depth Prepass + Main Opaque).")

static func detach_from_environment(target: Variant) -> void:
	if not target:
		return
	var comp: Compositor = null
	if target is WorldEnvironment or target is Camera3D:
		comp = target.compositor
	elif target is Compositor:
		comp = target
	if comp:
		comp.compositor_effects = []

