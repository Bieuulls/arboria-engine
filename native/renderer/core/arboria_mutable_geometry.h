#ifndef ARBORIA_MUTABLE_GEOMETRY_H
#define ARBORIA_MUTABLE_GEOMETRY_H

#include "arboria_types.h"
#include "arboria_handle.h"
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <cstdint>
#include <string>
#include <chrono>

namespace Arboria {

class VGMeshResource;

enum MutableDirtyFlags : uint32_t {
    MUTABLE_DIRTY_NONE      = 0,
    MUTABLE_DIRTY_GEOMETRY  = 1 << 0, // Vértices/índices foram alterados
    MUTABLE_DIRTY_DAG       = 1 << 1, // Relações DAG/LOD de clusters precisam de atualização
    MUTABLE_DIRTY_BOUNDS    = 1 << 2, // Volumes delimitadores (AABB/Esfera) alterados
    MUTABLE_DIRTY_GPU_SYNC  = 1 << 3, // Buffers GPU necessitam de re-upload parcial
    MUTABLE_DIRTY_PHYSICS   = 1 << 4  // Colisores precisam de sincronização
};

enum MutableResidencyState : uint32_t {
    MUTABLE_RESIDENCY_RESIDENT       = 0,
    MUTABLE_RESIDENCY_EVICTED        = 1,
    MUTABLE_RESIDENCY_PENDING_UPLOAD = 2
};

// Estatísticas de Reconstrução Incremental do DAG (ETAPA 3)
struct DAGReconstructionStats {
    uint32_t modified_lod0_clusters = 0;
    uint32_t affected_groups = 0;
    uint32_t rebuilt_parent_clusters = 0;
    uint32_t preserved_clusters = 0;
    float dag_update_time_ms = 0.0f;
    bool fallback_triggered = false;
};

// Patch de atualização parcial de geometria para o GPU Scene (ETAPA 4)
struct GPUMutableGeometryPatch {
    uint32_t instance_id = 0;
    uint32_t geometry_version = 0;
    uint32_t modified_cluster_count = 0;
    uint32_t dynamic_vertex_offset = 0;
    uint32_t dynamic_vertex_count = 0;
    uint32_t dynamic_triangle_offset = 0;
    uint32_t dynamic_triangle_count = 0;
    std::vector<GPUCluster> updated_gpu_clusters;
    std::vector<GPUPackedVertex> dynamic_vertices;
    std::vector<uint32_t> dynamic_triangles;
};

// Registro de uma região específica modificada na malha
struct MutableRegion {
    uint32_t region_id = 0;
    uint32_t mesh_id = 0;
    uint32_t instance_id = 0;
    uint32_t geometry_version = 1;
    uint32_t parent_cluster_id = 0;
    uint32_t dirty_flags = MUTABLE_DIRTY_NONE;

    // Intervalos de geometria
    uint32_t vertex_offset = 0;
    uint32_t vertex_count = 0;
    uint32_t index_offset = 0;
    uint32_t index_count = 0;
    uint32_t material_id = 0;
    uint32_t residency_state = MUTABLE_RESIDENCY_RESIDENT;

    // Volume delimitador local da região
    float center[3] = {0.0f, 0.0f, 0.0f};
    float radius = 0.0f;
    float aabb_min[3] = {0.0f, 0.0f, 0.0f};
    float aabb_max[3] = {0.0f, 0.0f, 0.0f};

    // Geometria modificada real da região (Copy-On-Write localizado)
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
    std::vector<Cluster> clusters;
    std::vector<GPUCluster> gpu_clusters;
    std::vector<GPUPackedVertex> packed_vertices;
    std::vector<uint32_t> packed_triangles;

    // Clusters originais substituídos por esta região
    std::vector<uint32_t> replaced_cluster_ids;
};

// Overlay de Geometria Mutável pertencente a uma instância específica.
// A geometria original continua 100% compartilhada e imutável.
// Apenas as regiões alteradas residem no overlay.
class ARBORIA_CLASS MutableGeometryOverlay {
public:
    MutableGeometryOverlay(uint32_t instance_id, uint32_t mesh_id);
    ~MutableGeometryOverlay() = default;

    uint32_t get_instance_id() const { return m_instance_id; }
    uint32_t get_mesh_id() const { return m_mesh_id; }
    uint32_t get_geometry_version() const { return m_geometry_version; }

    bool has_modifications() const { return !m_regions.empty(); }
    size_t get_region_count() const { return m_regions.size(); }

    // Cria ou obtém uma região mutável pelo ID
    MutableRegion& get_or_create_region(uint32_t region_id);
    const MutableRegion* get_region(uint32_t region_id) const;
    bool remove_region(uint32_t region_id);

    // Consulta se um cluster da malha original foi substituído nesta instância
    bool is_cluster_replaced(uint32_t original_cluster_id) const;
    const Cluster* get_replacement_cluster(uint32_t original_cluster_id) const;
    const GPUCluster* get_replacement_gpu_cluster(uint32_t original_cluster_id) const;

    // Mapeamento e vinculação de substituição de clusters
    void map_cluster_replacement(uint32_t original_cluster_id, uint32_t region_id, uint32_t local_cluster_idx);

    // Gestão de Dirty Flags e Versionamento
    void mark_dirty(uint32_t flags);
    void clear_dirty(uint32_t flags);
    uint32_t get_dirty_flags() const { return m_dirty_flags; }
    bool is_dirty(uint32_t flags) const { return (m_dirty_flags & flags) != 0; }
    void bump_version();

    // Recalcula o AABB e a Esfera Delimitadora combinada (compartilhado + overlay)
    void compute_combined_bounds(
        const float original_center[3], float original_radius,
        const float original_min[3], const float original_max[3],
        float out_center[3], float& out_radius,
        float out_min[3], float out_max[3]
    ) const;

    // Operação Geométrica: Esculpir depressão localizada (ETAPA 2)
    // Retorna a contagem de clusters modificados/substituídos nesta operação
    uint32_t apply_depression(
        const VGMeshResource& base_mesh,
        const float center[3],
        float radius,
        float depth,
        bool subdivide = true
    );

    // Exporta a geometria combinada final (base compartilhada + overlay modificado) para formato Wavefront OBJ
    bool export_to_obj(const VGMeshResource& base_mesh, const std::string& filepath) const;

    // Retorna contagens combinadas de vértices e triângulos no LOD 0
    void get_combined_lod0_stats(const VGMeshResource& base_mesh, size_t& out_vertices, size_t& out_triangles) const;

    // Reconstrução Incremental do DAG (ETAPA 3)
    // Propaga modificações locais para os grupos hierárquicos do DAG mantendo continuidade topológica
    DAGReconstructionStats rebuild_dag_incremental(const VGMeshResource& base_mesh);

    // Preparação de Patch de Atualização GPU (ETAPA 4)
    // Reloca offsets de vértices/triângulos no espaço dinâmico de SSBO e monta patch para upload
    GPUMutableGeometryPatch prepare_gpu_geometry_patch(uint32_t global_dynamic_vertex_base, uint32_t global_dynamic_triangle_base);

    const std::unordered_map<uint32_t, MutableRegion>& get_regions() const { return m_regions; }

    void clear();

private:
    uint32_t m_instance_id = 0;
    uint32_t m_mesh_id = 0;
    uint32_t m_geometry_version = 1;
    uint32_t m_dirty_flags = MUTABLE_DIRTY_NONE;

    // Regiões ativas do overlay
    std::unordered_map<uint32_t, MutableRegion> m_regions;

    // Mapeamento: original_cluster_id -> par (region_id, local_cluster_idx)
    struct ClusterRef {
        uint32_t region_id;
        uint32_t local_cluster_idx;
    };
    std::unordered_map<uint32_t, ClusterRef> m_cluster_replacements;
};

} // namespace Arboria

#endif // ARBORIA_MUTABLE_GEOMETRY_H
