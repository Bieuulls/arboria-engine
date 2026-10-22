#ifndef VG_INDIRECT_RENDERER_H
#define VG_INDIRECT_RENDERER_H

#include "../core/vg_types.h"
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
};

} // namespace Arboria

#endif // VG_INDIRECT_RENDERER_H
