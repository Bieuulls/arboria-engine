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

bool VGIndirectRenderer::draw_indirect_native(
    const GPUDriverContext& ctx,
    const void* framebuffer,
    const void* raster_pipeline,
    const void* uniform_set,
    const void* counter_buffer
) {
    if (!ctx.call_method || !ctx.rd || !framebuffer || !raster_pipeline || !uniform_set || !counter_buffer) {
        return false;
    }

    uint8_t clear_flags_var[32] = {0};
    int64_t clear_0 = 0;
    if (ctx.from_int) ctx.from_int(clear_flags_var, &clear_0);

    uint8_t empty_colors[32] = {0};
    const void* dl_begin_args[] = { framebuffer, clear_flags_var, empty_colors };
    uint8_t dl_var[32] = {0};
    if (!ctx.call_method(ctx.rd, "draw_list_begin", dl_begin_args, 3, dl_var)) {
        return false;
    }

    const void* bind_pipe_args[] = { dl_var, raster_pipeline };
    ctx.call_method(ctx.rd, "draw_list_bind_render_pipeline", bind_pipe_args, 2, nullptr);

    uint8_t set_idx_var[32] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    const void* bind_set_args[] = { dl_var, uniform_set, set_idx_var };
    ctx.call_method(ctx.rd, "draw_list_bind_uniform_set", bind_set_args, 3, nullptr);

    uint8_t false_var[32] = {0};
    uint8_t val_false = 0;
    if (ctx.from_bool) ctx.from_bool(false_var, &val_false);

    uint8_t offset_var[32] = {0};
    int64_t offset_0 = 0;
    if (ctx.from_int) ctx.from_int(offset_var, &offset_0);

    uint8_t count_var[32] = {0};
    int64_t count_1 = 1;
    if (ctx.from_int) ctx.from_int(count_var, &count_1);

    uint8_t stride_var[32] = {0};
    int64_t stride_16 = 16;
    if (ctx.from_int) ctx.from_int(stride_var, &stride_16);

    const void* draw_args[] = { dl_var, false_var, counter_buffer, offset_var, count_var, stride_var };
    ctx.call_method(ctx.rd, "draw_list_draw_indirect", draw_args, 6, nullptr);

    ctx.call_method(ctx.rd, "draw_list_end", nullptr, 0, nullptr);
    return true;
}

bool VGIndirectRenderer::draw_indirect_batch(
    const GPUDriverContext& ctx,
    const void* framebuffer,
    const void* raster_pipeline,
    const void* raster_sets_array,
    const void* counter_bufs_array,
    int64_t count,
    const void* initial_colors
) {
    if (!ctx.call_method || !ctx.rd || !framebuffer || !raster_pipeline || count <= 0) {
        return false;
    }

    uint8_t clear_flags_var[32] = {0};
    int64_t clear_0 = 0;
    if (ctx.from_int) ctx.from_int(clear_flags_var, &clear_0);

    const void* colors_arg = initial_colors;
    const void* dl_begin_args[] = { framebuffer, clear_flags_var, colors_arg };
    uint8_t dl_var[32] = {0};
    if (!ctx.call_method(ctx.rd, "draw_list_begin", dl_begin_args, 3, dl_var)) {
        return false;
    }

    const void* bind_pipe_args[] = { dl_var, raster_pipeline };
    ctx.call_method(ctx.rd, "draw_list_bind_render_pipeline", bind_pipe_args, 2, nullptr);

    uint8_t set_idx_var[32] = {0};
    int64_t set_0 = 0;
    if (ctx.from_int) ctx.from_int(set_idx_var, &set_0);

    uint8_t false_var[32] = {0};
    uint8_t val_false = 0;
    if (ctx.from_bool) ctx.from_bool(false_var, &val_false);

    uint8_t offset_var[32] = {0};
    int64_t offset_0 = 0;
    if (ctx.from_int) ctx.from_int(offset_var, &offset_0);

    uint8_t count_var[32] = {0};
    int64_t count_1 = 1;
    if (ctx.from_int) ctx.from_int(count_var, &count_1);

    uint8_t stride_var[32] = {0};
    int64_t stride_16 = 16;
    if (ctx.from_int) ctx.from_int(stride_var, &stride_16);

    for (int64_t i = 0; i < count; ++i) {
        uint8_t rset_var[32] = {0};
        uint8_t cnt_var[32] = {0};
        uint8_t valid = 0, oob = 0;

        if (ctx.get_indexed) {
            ctx.get_indexed(raster_sets_array, i, rset_var, &valid, &oob);
            ctx.get_indexed(counter_bufs_array, i, cnt_var, &valid, &oob);
        }

        const void* bind_set_args[] = { dl_var, rset_var, set_idx_var };
        ctx.call_method(ctx.rd, "draw_list_bind_uniform_set", bind_set_args, 3, nullptr);

        const void* draw_args[] = { dl_var, false_var, cnt_var, offset_var, count_var, stride_var };
        ctx.call_method(ctx.rd, "draw_list_draw_indirect", draw_args, 6, nullptr);
    }

    ctx.call_method(ctx.rd, "draw_list_end", nullptr, 0, nullptr);
    return true;
}

} // namespace Arboria
