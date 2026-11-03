#include "arboria_visibility_manager.h"
#include <algorithm>
#include <cmath>

namespace Arboria {

ArboriaVisibilityManager& ArboriaVisibilityManager::instance() {
    static ArboriaVisibilityManager s_inst;
    return s_inst;
}

void ArboriaVisibilityManager::set_capacity(uint32_t max_visible_items) {
    m_max_capacity = std::max(1024u, max_visible_items);
}

float ArboriaVisibilityManager::compute_screen_error(
    float distance, float mesh_error, float vp_height, float fov_factor
) {
    float d_eff = std::max(distance, 0.05f);
    return (mesh_error * vp_height) / (2.0f * d_eff * fov_factor);
}

uint32_t ArboriaVisibilityManager::select_lod_level(
    float screen_error_px, float max_screen_error_px, uint32_t lod_count
) const {
    if (lod_count == 0) return 0;
    // screen_error_px = erro geometrico projetado na tela à distância atual
    // Erro pequeno (objeto distante): pode usar LOD grosseiro (nível alto)
    // Erro grande (objeto próximo): precisa de LOD fino (nível baixo)
    if (screen_error_px <= max_screen_error_px) {
        return lod_count - 1u; // qualquer LOD é aceitável
    }
    // Erro excede o threshold: encontrar o nível mais fino cujo erro ainda excede.
    // Cada nível LOD do compilador reduz aproximadamente pela metade o erro.
    uint32_t lod = 0;
    float err = screen_error_px;
    while (lod + 1 < lod_count && err > max_screen_error_px) {
        err /= 2.0f;
        ++lod;
    }
    return std::min(lod, lod_count - 1u);
}

bool ArboriaVisibilityManager::should_refine_lod(
    int refined_group, float refined_error_px, float max_screen_error_px
) const {
    // Sem grupo refinado: ja estamos no LOD mais fino disponível para este cluster.
    if (refined_group < 0) return false;
    // O erro do grupo refinado ja e aceitavel na tela: nao precisa refinar mais.
    return refined_error_px > max_screen_error_px;
}

} // namespace Arboria
