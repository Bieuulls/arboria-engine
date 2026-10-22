
@tool
extends SceneTree

var frame = 0
var probe_effect: ProbeEffect

class ProbeEffect extends CompositorEffect:
    func _init():
        effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
    
    func _render_callback(cb_type: int, rdata: RenderData) -> void:
        print('RENDER CALLBACK FIRED!')

func _process(_delta):
    frame += 1
    if frame == 1:
        var cam = Camera3D.new()
        cam.position = Vector3(0, 0, 5)
        root.add_child(cam)
        
        var mi = MeshInstance3D.new()
        mi.mesh = BoxMesh.new()
        root.add_child(mi)
        
        var comp = Compositor.new()
        probe_effect = ProbeEffect.new()
        comp.compositor_effects.append(probe_effect)
        cam.compositor = comp
    elif frame >= 10:
        quit(0)
    return false
