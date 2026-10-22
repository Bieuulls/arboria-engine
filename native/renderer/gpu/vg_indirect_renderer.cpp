#include "vg_indirect_renderer.h"

namespace Arboria {

VGIndirectRenderer::VGIndirectRenderer() {}
VGIndirectRenderer::~VGIndirectRenderer() {}

RasterizerPipelineConfig VGIndirectRenderer::get_forward_plus_raster_config() {
    RasterizerPipelineConfig cfg{};
    cfg.enable_cull_back = true;
    cfg.clockwise_front_face = true;
    cfg.enable_depth_test = true;
    cfg.enable_depth_write = true;
    // Godot Reversed-Z convention: Near is 1.0, Far is 0.0 -> GREATER_OR_EQUAL
    cfg.depth_compare_op = 6; // RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
    cfg.primitive_type = 3;   // RenderingDevice.RENDER_PRIMITIVE_TRIANGLES
    cfg.wireframe = false;
    return cfg;
}

bool VGIndirectRenderer::validate_draw_command(const VkDrawIndirectCommand& cmd, uint32_t max_clusters) {
    if (cmd.vertex_count != 384) {
        return false;
    }
    if (cmd.instance_count > max_clusters) {
        return false;
    }
    if (cmd.first_vertex != 0 || cmd.first_instance != 0) {
        return false;
    }
    return true;
}

VkDrawIndirectCommand VGIndirectRenderer::build_initial_draw_command() {
    VkDrawIndirectCommand cmd{};
    cmd.vertex_count = 384; // 128 triangulos maximos * 3 vertices
    cmd.instance_count = 0; // GPU computa dinamicamente via atomicAdd
    cmd.first_vertex = 0;
    cmd.first_instance = 0;
    return cmd;
}

} // namespace Arboria
