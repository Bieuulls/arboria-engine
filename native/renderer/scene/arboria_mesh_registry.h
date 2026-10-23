#ifndef ARBORIA_MESH_REGISTRY_H
#define ARBORIA_MESH_REGISTRY_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include "../core/arboria_mesh_resource.h"
#include <unordered_map>
#include <memory>
#include <string>
#include <vector>
#include <mutex>

namespace Arboria {

struct RegisteredMeshInfo {
    Handle handle;
    std::string path;
    std::shared_ptr<VGMeshResource> resource;
    uint32_t cluster_offset = 0;   // Offset acumulado no buffer global de clusters
    uint32_t vertex_offset = 0;    // Offset acumulado no buffer global de vertices
    uint32_t triangle_offset = 0;  // Offset acumulado no buffer global de triangulos
    uint32_t cluster_count = 0;
    uint32_t vertex_count = 0;
    uint32_t triangle_count = 0;
};

class ARBORIA_CLASS ArboriaMeshRegistry {
public:
    static ArboriaMeshRegistry& instance();

    // Registra uma malha a partir de arquivo .vgmesh; se já carregada, reutiliza compartilhando VRAM
    Handle register_mesh(const std::string& path);

    // Registra um recurso de malha pré-carregado
    Handle register_mesh_resource(const std::string& path, std::shared_ptr<VGMeshResource> resource);

    // Desregistra a malha (decrementa referência; se 0, libera)
    bool unregister_mesh(Handle handle);

    // Consulta se handle é válido
    bool is_valid_mesh(Handle handle) const;

    // Obtém informações da malha
    const RegisteredMeshInfo* get_mesh_info(Handle handle) const;
    const RegisteredMeshInfo* get_mesh_info_by_index(uint32_t index) const;
    std::shared_ptr<VGMeshResource> get_mesh_resource(Handle handle) const;

    // Estatísticas globais acumuladas de geometria compartilhada
    size_t get_mesh_count() const;
    uint32_t get_total_clusters() const { return m_total_clusters; }
    uint32_t get_total_vertices() const { return m_total_vertices; }
    uint32_t get_total_triangles() const { return m_total_triangles; }

    // Limpa todas as malhas registradas
    void clear();

private:
    ArboriaMeshRegistry() = default;
    ~ArboriaMeshRegistry() = default;

    mutable std::mutex m_mutex;
    GenerationalPool<RegisteredMeshInfo> m_mesh_pool;
    std::unordered_map<std::string, Handle> m_path_to_handle;

    uint32_t m_total_clusters = 0;
    uint32_t m_total_vertices = 0;
    uint32_t m_total_triangles = 0;
};

} // namespace Arboria

#endif // ARBORIA_MESH_REGISTRY_H
