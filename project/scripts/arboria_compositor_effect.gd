@tool
class_name ArboriaCompositorEffect
extends CompositorEffect

## ARBORIA ENGINE — COMPOSITOR EFFECT (POST_OPAQUE)
## Conecta a renderização nativa de geometria virtualizada à passagem Forward+ do Godot.

const ArboriaNativePipeline = preload("res://scripts/arboria_native_pipeline.gd")

var pipeline: ArboriaNativePipeline
var active: bool = true

func _init():
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
	enabled = true
	pipeline = ArboriaNativePipeline.get_or_create_shared()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if not active:
		return
	if p_effect_callback_type != CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE:
		return
	if not pipeline:
		pipeline = ArboriaNativePipeline.get_or_create_shared()
	if pipeline and pipeline.is_initialized:
		pipeline.render_scene_instances(p_render_data)
