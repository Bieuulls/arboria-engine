#ifndef VG_INDIRECT_RENDERER_H
#define VG_INDIRECT_RENDERER_H

#include "../core/vg_types.h"
#include "vg_gpu_driver.h"
#include <cstdint>

namespace Arboria {

struct RasterizerPipelineConfig {
    bool enable_cull_back = true;
    bool clockwise_front_face = true;
    bool enable_depth_test = true;
    bool enable_depth_write = true;
    // Vulkan COMPARE_OP_GREATER_OR_EQUAL (Godot Reversed-Z)
    uint32_t depth_compare_op = 6; // Godot RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
    uint32_t primitive_type = 3;   // TRIANGLES
    bool wireframe = false;
};

class ARBORIA_CLASS VGIndirectRenderer {
public:
    VGIndirectRenderer();
    ~VGIndirectRenderer();

    // Obtém configuração padrão para o pipeline de rasterização Forward+ (Reversed-Z)
    static RasterizerPipelineConfig get_forward_plus_raster_config();

    // Valida os argumentos indiretos recebidos da GPU
    static bool validate_draw_command(const VkDrawIndirectCommand& cmd, uint32_t max_clusters);

    // Constrói comando inicial de desenho indireto
    static VkDrawIndirectCommand build_initial_draw_command();

    // Sincronização e barreiras exigidas
    static bool requires_compute_to_raster_barrier() { return true; }

    // Execução real de draw_list_draw_indirect na GPU via RenderingDevice
    static bool draw_indirect_native(
        const struct GPUDriverContext& ctx,
        const void* framebuffer,
        const void* raster_pipeline,
        const void* uniform_set,
        const void* counter_buffer
    );

    // Execução em lote de draw_list_draw_indirect no framebuffer Forward+
    static bool draw_indirect_batch(
        const struct GPUDriverContext& ctx,
        const void* framebuffer,
        const void* raster_pipeline,
        const void* raster_sets_array,
        const void* counter_bufs_array,
        int64_t count,
        const void* initial_colors = nullptr
    );
};

} // namespace Arboria

#endif // VG_INDIRECT_RENDERER_H
