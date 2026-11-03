#ifndef VG_MESH_RESOURCE_H
#define VG_MESH_RESOURCE_H

#include "arboria_types.h"
#include <string>
#include <vector>
#include <memory>

namespace Arboria {

class ARBORIA_CLASS VGMeshResource {
public:
    VGMeshResource();
    ~VGMeshResource();

    // Carrega e valida arquivo .vgmesh
    bool load_from_file(const std::string& filepath);

    // Carrega e valida a partir de buffer na memória
    bool load_from_memory(const uint8_t* data, size_t size);

    // Limpa todos os dados da memória
    void clear();

    // Acessores de metadados
    bool is_valid() const { return m_valid; }
    const Header& get_header() const { return m_header; }
    uint32_t get_cluster_count() const { return m_header.clusters; }
    uint32_t get_vertex_count() const { return m_header.vertices; }
    uint32_t get_triangle_count() const { return m_header.triangles; }
    uint32_t get_lod_count() const { return m_header.lods; }
    uint32_t get_group_count() const { return m_header.groups; }

    void get_bounding_box(float min_out[3], float max_out[3]) const;

    // Acessores de colecoes brutas
    const std::vector<LOD>& get_lods() const { return m_lods; }
    const std::vector<Cluster>& get_clusters() const { return m_clusters; }
    const std::vector<Group>& get_groups() const { return m_groups; }
    const std::vector<Vertex>& get_vertices() const { return m_vertices; }
    const std::vector<uint8_t>& get_indices() const { return m_indices; }

    // Acessores dos dados otimizados para GPU
    const std::vector<GPUCluster>& get_gpu_clusters() const { return m_gpu_clusters; }
    const std::vector<GPUPackedVertex>& get_packed_vertices() const { return m_packed_vertices; }
    const std::vector<uint32_t>& get_packed_triangles() const { return m_packed_triangles; }

    // Tamanhos em bytes para alocacao de buffers GPU
    size_t get_gpu_clusters_byte_size() const { return m_gpu_clusters.size() * sizeof(GPUCluster); }
    size_t get_packed_vertices_byte_size() const { return m_packed_vertices.size() * sizeof(GPUPackedVertex); }
    size_t get_packed_triangles_byte_size() const { return m_packed_triangles.size() * sizeof(uint32_t); }

private:
    bool validate_and_prepare();

    bool m_valid = false;
    Header m_header{};
    std::vector<LOD> m_lods;
    std::vector<Cluster> m_clusters;
    std::vector<Group> m_groups;
    std::vector<Vertex> m_vertices;
    std::vector<uint8_t> m_indices;

    // Estruturas preparadas para upload direto em SSBOs Vulkan
    std::vector<GPUCluster> m_gpu_clusters;
    std::vector<GPUPackedVertex> m_packed_vertices;
    std::vector<uint32_t> m_packed_triangles;
};

} // namespace Arboria

#endif // VG_MESH_RESOURCE_H
