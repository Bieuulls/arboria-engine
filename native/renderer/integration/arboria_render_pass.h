#ifndef VG_RENDER_PASS_H
#define VG_RENDER_PASS_H

#include "../core/arboria_types.h"
#include <cstdint>

namespace Arboria {

enum class RenderPassType {
    DepthPrePass = 0,
    PostOpaque = 1,
    ShadowPass = 2
};

struct LightParameters {
    float light_direction[3];     // World light direction
    float light_color[3];         // RGB color
    float light_energy = 1.0f;    // Energy multiplier
    bool cast_shadows = true;
};

struct MaterialParameters {
    float albedo[3];              // Base color RGB
    float roughness = 0.5f;       // Surface roughness [0..1]
    float metallic = 0.05f;       // Metallic factor [0..1]
    float specular = 0.5f;        // Specular factor [0..1]
};

class ARBORIA_CLASS VGRenderPass {
public:
    VGRenderPass();
    ~VGRenderPass();

    static RenderPassType get_default_forward_pass() { return RenderPassType::PostOpaque; }

    static LightParameters get_default_directional_light();
    static MaterialParameters get_default_material();

    // Valida que o framebuffer de Forward+ possui profundidade valida
    static bool validate_framebuffer_attachments(uint64_t color_texture_rid, uint64_t depth_texture_rid);
};

} // namespace Arboria

// C Export API para Render Pass
ARBORIA_API int arboria_render_pass_validate_fb(uint64_t color_rid, uint64_t depth_rid);

#endif // VG_RENDER_PASS_H
