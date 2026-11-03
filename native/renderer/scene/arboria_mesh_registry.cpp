#include "arboria_mesh_registry.h"
#include "../core/arboria_logger.h"

namespace Arboria {

ArboriaMeshRegistry& ArboriaMeshRegistry::instance() {
    static ArboriaMeshRegistry s_inst;
    return s_inst;
}

Result<Handle> ArboriaMeshRegistry::register_mesh(const std::string& path) {
    std::lock_guard<std::mutex> lock(m_mutex);

    // Se já foi registrada, reutiliza o handle existente (Geometria Compartilhada Garantida!)
    auto it = m_path_to_handle.find(path);
    if (it != m_path_to_handle.end() && m_mesh_pool.is_valid(it->second)) {
        return Result<Handle>::success(it->second);
    }

    auto mesh_res = std::make_shared<VGMeshResource>();
    if (!mesh_res->load_from_file(path)) {
        ARBORIA_LOG_ERROR("[ArboriaMeshRegistry] Falha ao carregar malha: " + path);
        return Result<Handle>::failure(ArboriaError::FileNotFound, "Não foi possível carregar .vgmesh: " + path);
    }

    // Já seguramos m_mutex — chamar a versão _locked para evitar aquisição recursiva de std::mutex.
    return register_mesh_resource_locked(path, mesh_res);
}

Result<Handle> ArboriaMeshRegistry::register_mesh_resource_locked(const std::string& path, std::shared_ptr<VGMeshResource> resource) {
    if (!resource || !resource->is_valid()) {
        return Result<Handle>::failure(ArboriaError::InvalidData, "Recurso de malha inválido ou nulo");
    }

    RegisteredMeshInfo info;
    info.path = path;
    info.cluster_count = resource->get_cluster_count();
    info.vertex_count = resource->get_vertex_count();
    info.triangle_count = resource->get_triangle_count();
    info.resource = resource;

    // Atribuição de offsets globais acumulados
    info.cluster_offset = m_total_clusters;
    info.vertex_offset = m_total_vertices;
    info.triangle_offset = m_total_triangles;

    m_total_clusters += info.cluster_count;
    m_total_vertices += info.vertex_count;
    m_total_triangles += info.triangle_count;

    Handle h = m_mesh_pool.allocate(std::move(info));
    if (m_mesh_pool.is_valid(h)) {
        m_mesh_pool.get(h)->handle = h;
        if (!path.empty()) {
            m_path_to_handle[path] = h;
        }
        std::string reg_msg = "[ArboriaMeshRegistry] Malha registrada: " + path
                  + " (Handle: " + std::to_string(h.to_u64())
                  + ", Clusters: " + std::to_string(info.cluster_count)
                  + ", Vertices: " + std::to_string(info.vertex_count)
                  + ", Triangulos: " + std::to_string(info.triangle_count)
                  + ", Cluster Offset Global: " + std::to_string(info.cluster_offset) + ")";
        ARBORIA_LOG_INFO(reg_msg);
        return Result<Handle>::success(h);
    }
    return Result<Handle>::failure(ArboriaError::RegistryFull, "Pool geracional atingiu capacidade");
}

Result<Handle> ArboriaMeshRegistry::register_mesh_resource(const std::string& path, std::shared_ptr<VGMeshResource> resource) {
    std::lock_guard<std::mutex> lock(m_mutex);
    return register_mesh_resource_locked(path, resource);
}

Status ArboriaMeshRegistry::unregister_mesh(Handle handle) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_mesh_pool.is_valid(handle)) {
        return Status::failure(ArboriaError::InvalidHandle, "Handle inválido ou já liberado");
    }

    RegisteredMeshInfo* info = m_mesh_pool.get(handle);
    if (info) {
        if (!info->path.empty()) {
            m_path_to_handle.erase(info->path);
        }
    }
    if (!m_mesh_pool.release(handle)) {
        return Status::failure(ArboriaError::InternalError, "Falha ao liberar slot do pool geracional");
    }
    return Status::success();
}

bool ArboriaMeshRegistry::is_valid_mesh(Handle handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_mesh_pool.is_valid(handle);
}

RegisteredMeshInfo ArboriaMeshRegistry::get_mesh_info(Handle handle) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    const RegisteredMeshInfo* info = m_mesh_pool.get(handle);
    return info ? *info : RegisteredMeshInfo{};
}

RegisteredMeshInfo ArboriaMeshRegistry::get_mesh_info_by_index(uint32_t index) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    const RegisteredMeshInfo* info = m_mesh_pool.get_by_index(index);
    return info ? *info : RegisteredMeshInfo{};
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
