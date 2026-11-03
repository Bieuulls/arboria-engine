#ifndef ARBORIA_VISIBILITY_MANAGER_H
#define ARBORIA_VISIBILITY_MANAGER_H

#include "../core/arboria_types.h"
#include "arboria_gpu_scene_types.h"
#include <cstdint>

namespace Arboria {

class ARBORIA_CLASS ArboriaVisibilityManager {
public:
    static ArboriaVisibilityManager& instance();

    void set_capacity(uint32_t max_visible_items);
    uint32_t get_capacity() const { return m_max_capacity; }

    // Retorna o tamanho em bytes necessário para o buffer global de itens visíveis
    size_t get_visibility_buffer_bytes() const {
        return m_max_capacity * sizeof(VisibleClusterItem);
    }

    // --- Selecao de LOD baseada em distancia/erro de tela ---

    // Computa o erro na tela em pixels para uma distancia e erro geometrico dados.
    // Formula: (mesh_error * vp_height) / (2 * distance_effective * fov_factor)
    static float compute_screen_error(float distance, float mesh_error, float vp_height, float fov_factor);

    // Seleciona o nivel LOD apropriado com base no erro de tela vs threshold.
    // Retorna o nivel LOD (0 = maior detalhe) que deve ser usado para a instância.
    // Cada nível LOD dobrar aproximadamente o erro geometrico (config do compilador),
    // portanto buscamos o maior nível cujo erro projetado ainda cabe no threshold.
    uint32_t select_lod_level(float screen_error_px, float max_screen_error_px, uint32_t lod_count) const;

    // Verifica se a transicao para o LOD refinado (refined field dos grupos DAG)
    // e necessaria: retorna true se o erro do grupo refinado ja e aceitavel na tela,
    // ou se nao ha grupo refinado (refined_group < 0, ja esta no LOD mais fino).
    bool should_refine_lod(int refined_group, float refined_error_px, float max_screen_error_px) const;

    // Inicializa estrutura inicial de contadores e argumentos indiretos
    GPUIndirectArgsAndCounters build_initial_draw_args() const {
        GPUIndirectArgsAndCounters args{};
        args.vertex_count = 384; // 128 triangulos * 3
        args.instance_count = 0;
        args.first_vertex = 0;
        args.first_instance = 0;
        args.total_triangles_drawn = 0;
        args.total_clusters_visible = 0;
        args.total_clusters_submitted = 0;
        args.max_capacity = m_max_capacity;
        args.overflow_flag = 0;
        return args;
    }

private:
    ArboriaVisibilityManager() = default;
    ~ArboriaVisibilityManager() = default;

    uint32_t m_max_capacity = 1048576u; // 1M clusters visiveis maximos (~64M triangulos em tela)
};

} // namespace Arboria

#endif // ARBORIA_VISIBILITY_MANAGER_H
