#include "arboria_mesh_registry.h"
#include <iostream>

namespace Arboria {

ArboriaMeshRegistry& ArboriaMeshRegistry::instance() {
    static ArboriaMeshRegistry s_inst;
    return s_inst;
}

Handle ArboriaMeshRegistry::register_mesh(const std::string& path) {
    std::lock_guard<std::mutex> lock(m_mutex);

    // Se já foi registrada, reutiliza o handle existente (Geometria Compartilhada Garantida!)
    auto it = m_path_to_handle.find(path);
    if (it != m_path_to_handle.end() && m_mesh_pool.is_valid(it->second)) {
        return it->second;
    }

    auto mesh_res = std::make_shared<VGMeshResource>();
    if (!mesh_res->load_from_file(path)) {
        std::cerr << "[ArboriaMeshRegistry] Falha ao carregar malha: " << path << std::endl;
        return Handle{};
    }

    return register_mesh_resource(path, mesh_res);
}

Handle ArboriaMeshRegistry::register_mesh_resource(const std::string& path, std::shared_ptr<VGMeshResource> resource) {
    if (!resource || !resource->is_valid()) return Handle{};

    RegisteredMeshInfo info;
    info.path = path;
    info.resource = resource;
    info.cluster_count = resource->get_cluster_count();
    info.vertex_count = resource->get_vertex_count();
    info.triangle_count = resource->get_triangle_count();

    // Atribuição de offsets globais acumulados
    info.cluster_offset = m_total_clusters;
    info.vertex_offset = m_total_vertices;
    info.triangle_offset = m_total_triangles;

    m_total_clusters += info.cluster_count;
    m_total_vertices += info.vertex_count;
    m_total_triangles += info.triangle_count;

    Handle h = m_mesh_pool.allocate(info);
    if (m_mesh_pool.is_valid(h)) {
        m_mesh_pool.get(h)->handle = h;
        if (!path.empty()) {
            m_path_to_handle[path] = h;
        }
        std::cout << "[ArboriaMeshRegistry] Malha registrada: " << path 
                  << " (Handle: " << h.to_u64() 
                  << ", Clusters: " << info.cluster_count 
                  << ", Vertices: " << info.vertex_count 
                  << ", Triangulos: " << info.triangle_count 
                  << ", Cluster Offset Global: " << info.cluster_offset << ")" << std::endl;
    }
    return h;
}

bool ArboriaMeshRegistry::unregister_mesh(Handle handle) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_mesh_pool.is_valid(handle)) return false;

    RegisteredMeshInfo* info = m_mesh_pool.get(handle);
    if (info) {
        if (!info->path.empty()) {
            m_path_to_handle.erase(info->path);
        }
        info->resource.reset();
    }
    return m_mesh_pool.release(handle);
}

bool ArboriaMeshRegistry::is_valid_mesh(Handle handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_mesh_pool.is_valid(handle);
}

const RegisteredMeshInfo* ArboriaMeshRegistry::get_mesh_info(Handle handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_mesh_pool.get(handle);
}

const RegisteredMeshInfo* ArboriaMeshRegistry::get_mesh_info_by_index(uint32_t index) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_mesh_pool.get_by_index(index);
}

std::shared_ptr<VGMeshResource> ArboriaMeshRegistry::get_mesh_resource(Handle handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    const RegisteredMeshInfo* info = m_mesh_pool.get(handle);
    return info ? info->resource : nullptr;
}

size_t ArboriaMeshRegistry::get_mesh_count() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_mesh_pool.active_count();
}

void ArboriaMeshRegistry::clear() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_mesh_pool.clear();
    m_path_to_handle.clear();
    m_total_clusters = 0;
    m_total_vertices = 0;
    m_total_triangles = 0;
}

} // namespace Arboria
