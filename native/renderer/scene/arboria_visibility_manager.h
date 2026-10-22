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

    // Inicializa estrutura inicial de contadores e argumentos indiretos
    GPUIndirectArgsAndCounters build_initial_draw_args() const {
        GPUIndirectArgsAndCounters args{};
        args.vertex_count = 384; // 128 triangulos * 3
        args.instance_count = 0;
        args.first_vertex = 0;
        args.first_instance = 0;
        args.total_triangles_drawn = 0;
        args.total_clusters_evaluated = 0;
        args.max_capacity = m_max_capacity;
        args.overflow_flag = 0;
        return args;
    }

private:
    ArboriaVisibilityManager() = default;
    ~ArboriaVisibilityManager() = default;

    uint32_t m_max_capacity = 262144; // 256k clusters visiveis maximos (~32M triangulos em tela)
};

} // namespace Arboria

#endif // ARBORIA_VISIBILITY_MANAGER_H
