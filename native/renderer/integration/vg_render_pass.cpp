#include "vg_render_pass.h"
#include <cmath>

namespace Arboria {

VGRenderPass::VGRenderPass() {}
VGRenderPass::~VGRenderPass() {}

LightParameters VGRenderPass::get_default_directional_light() {
    LightParameters lp{};
    // Direção descendente normalizada: vec3(0.5, 0.8, 0.6)
    float len = std::sqrt(0.5f * 0.5f + 0.8f * 0.8f + 0.6f * 0.6f);
    lp.light_direction[0] = 0.5f / len;
    lp.light_direction[1] = 0.8f / len;
    lp.light_direction[2] = 0.6f / len;

    lp.light_color[0] = 1.0f;
    lp.light_color[1] = 0.98f;
    lp.light_color[2] = 0.95f;
    lp.light_energy = 1.2f;
    lp.cast_shadows = true;
    return lp;
}

MaterialParameters VGRenderPass::get_default_material() {
    MaterialParameters mat{};
    mat.albedo[0] = 0.80f;
    mat.albedo[1] = 0.82f;
    mat.albedo[2] = 0.85f;
    mat.roughness = 0.65f;
    mat.metallic = 0.05f;
    mat.specular = 0.50f;
    return mat;
}

bool VGRenderPass::validate_framebuffer_attachments(uint64_t color_texture_rid, uint64_t depth_texture_rid) {
    // Ambos os attachments (cor HDR e profundidade nativa) devem ser RIDs validos e nao-nulos
    return (color_texture_rid != 0 && depth_texture_rid != 0);
}

} // namespace Arboria

ARBORIA_API int arboria_render_pass_validate_fb(uint64_t color_rid, uint64_t depth_rid) {
    return Arboria::VGRenderPass::validate_framebuffer_attachments(color_rid, depth_rid) ? 0 : -1;
}
