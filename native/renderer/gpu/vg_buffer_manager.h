#ifndef VG_BUFFER_MANAGER_H
#define VG_BUFFER_MANAGER_H

#include "../core/vg_types.h"
#include "../core/vg_mesh_resource.h"
#include <cstdint>
#include <vector>
#include <memory>
#include <string>

namespace Arboria {

// Descritor de layout de buffer GPU
struct BufferDescriptor {
    std::string name;
    size_t size_bytes = 0;
    size_t alignment = 16;
    uint32_t binding = 0;
    bool is_storage = true;
    bool is_uniform = false;
    bool is_indirect = false;
};

class ARBORIA_CLASS VGBufferManager {
public:
    VGBufferManager();
    ~VGBufferManager();

    // Inicializa o gerenciador com a malha fornecida
    bool setup_for_mesh(const VGMeshResource& mesh);

    // Reinicia e limpa recursos
    void cleanup();

    // Acessores de especificacao de buffers
    const BufferDescriptor& get_in_clusters_desc() const { return m_desc_in_clusters; }
    const BufferDescriptor& get_out_visible_desc() const { return m_desc_out_visible; }
    const BufferDescriptor& get_draw_args_desc() const { return m_desc_draw_args; }
    const BufferDescriptor& get_ubo_desc() const { return m_desc_ubo; }
    const BufferDescriptor& get_in_vertices_desc() const { return m_desc_in_vertices; }
    const BufferDescriptor& get_in_triangles_desc() const { return m_desc_in_triangles; }

    // Memoria total estimada em VRAM para a malha
    size_t get_total_vram_bytes() const;

    // Buffer de argumentos indiretos padrao inicial (vertex_count=384, instance_count=0)
    OutCounterAndDrawArgs get_initial_draw_args() const;

    bool is_ready() const { return m_ready; }

private:
    bool m_ready = false;
    uint32_t m_cluster_count = 0;
    uint32_t m_vertex_count = 0;
    uint32_t m_triangle_count = 0;

    BufferDescriptor m_desc_in_clusters;
    BufferDescriptor m_desc_out_visible;
    BufferDescriptor m_desc_draw_args;
    BufferDescriptor m_desc_ubo;
    BufferDescriptor m_desc_in_vertices;
    BufferDescriptor m_desc_in_triangles;
};

} // namespace Arboria

#endif // VG_BUFFER_MANAGER_H
