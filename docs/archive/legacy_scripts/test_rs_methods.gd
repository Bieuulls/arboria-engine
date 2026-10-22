
@tool
extends SceneTree

func _init():
    var vp = SubViewport.new()
    vp.size = Vector2i(512, 512)
    root.add_child(vp)
    var vp_rid = vp.get_viewport_rid()
    var tex_rs = RenderingServer.viewport_get_texture(vp_rid)
    var rd = RenderingServer.get_rendering_device()
    var tex_rd = RenderingServer.texture_get_rd_texture(tex_rs)
    var fmt = rd.texture_get_format(tex_rd)
    print('Usage bits:', fmt.usage_bits)
    # Check if COLOR_ATTACHMENT_BIT is set
    var is_color_att = (fmt.usage_bits & RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT) != 0
    print('Can be color attachment:', is_color_att)
    quit(0)
