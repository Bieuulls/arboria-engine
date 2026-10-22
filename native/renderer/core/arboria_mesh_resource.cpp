#include "arboria_mesh_resource.h"
#include <fstream>
#include <cstring>
#include <cmath>
#include <iostream>

namespace Arboria {

VGMeshResource::VGMeshResource() {
    clear();
}

VGMeshResource::~VGMeshResource() {
    clear();
}

void VGMeshResource::clear() {
    m_valid = false;
    std::memset(&m_header, 0, sizeof(m_header));
    m_lods.clear();
    m_clusters.clear();
    m_groups.clear();
    m_vertices.clear();
    m_indices.clear();
    m_gpu_clusters.clear();
    m_packed_vertices.clear();
    m_packed_triangles.clear();
}

void VGMeshResource::get_bounding_box(float min_out[3], float max_out[3]) const {
    if (!m_valid) {
        min_out[0] = min_out[1] = min_out[2] = 0.0f;
        max_out[0] = max_out[1] = max_out[2] = 0.0f;
        return;
    }
    for (int i = 0; i < 3; ++i) {
        min_out[i] = m_header.bmin[i];
        max_out[i] = m_header.bmax[i];
    }
}

bool VGMeshResource::load_from_file(const std::string& filepath) {
    clear();

    std::ifstream file(filepath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        std::cerr << "[VGMeshResource] Falha ao abrir arquivo: " << filepath << std::endl;
        return false;
    }

    uint64_t file_size = static_cast<uint64_t>(file.tellg());
    file.seekg(0, std::ios::beg);

    if (file_size < sizeof(Header)) {
        std::cerr << "[VGMeshResource] Arquivo menor que tamanho do cabecalho." << std::endl;
        return false;
    }

    std::vector<uint8_t> buffer(file_size);
    if (!file.read(reinterpret_cast<char*>(buffer.data()), file_size)) {
        std::cerr << "[VGMeshResource] Falha na leitura dos bytes do arquivo." << std::endl;
        return false;
    }

    return load_from_memory(buffer.data(), file_size);
}

bool VGMeshResource::load_from_memory(const uint8_t* data, size_t size) {
    clear();

    if (!data || size < sizeof(Header)) {
        return false;
    }

    std::memcpy(&m_header, data, sizeof(Header));

    if (std::memcmp(m_header.magic, "ARBORIA2", 8) != 0 || m_header.version != 2) {
        std::cerr << "[VGMeshResource] Assinatura ARBORIA2 invalida ou versao != 2." << std::endl;
        return false;
    }

    uint64_t expected_size = sizeof(Header) +
        static_cast<uint64_t>(m_header.lods) * sizeof(LOD) +
        static_cast<uint64_t>(m_header.clusters) * sizeof(Cluster) +
        static_cast<uint64_t>(m_header.groups) * sizeof(Group) +
        static_cast<uint64_t>(m_header.vertices) * sizeof(Vertex) +
        m_header.indices;

    if (expected_size != size) {
        std::cerr << "[VGMeshResource] Inconsistencia no tamanho binario: esperado "
                  << expected_size << " bytes, recebido " << size << " bytes." << std::endl;
        return false;
    }

    size_t offset = sizeof(Header);

    // 1. LODs
    if (m_header.lods > 0) {
        m_lods.resize(m_header.lods);
        std::memcpy(m_lods.data(), data + offset, m_header.lods * sizeof(LOD));
        offset += m_header.lods * sizeof(LOD);
    }

    // 2. Clusters
    if (m_header.clusters > 0) {
        m_clusters.resize(m_header.clusters);
        std::memcpy(m_clusters.data(), data + offset, m_header.clusters * sizeof(Cluster));
        offset += m_header.clusters * sizeof(Cluster);
    }

    // 3. Grupos DAG
    if (m_header.groups > 0) {
        m_groups.resize(m_header.groups);
        std::memcpy(m_groups.data(), data + offset, m_header.groups * sizeof(Group));
        offset += m_header.groups * sizeof(Group);
    }

    // 4. Vertices
    if (m_header.vertices > 0) {
        m_vertices.resize(m_header.vertices);
        std::memcpy(m_vertices.data(), data + offset, m_header.vertices * sizeof(Vertex));
        offset += m_header.vertices * sizeof(Vertex);
    }

    // 5. Indices locais de triangulos
    if (m_header.indices > 0) {
        m_indices.resize(m_header.indices);
        std::memcpy(m_indices.data(), data + offset, m_header.indices);
        offset += m_header.indices;
    }

    return validate_and_prepare();
}

bool VGMeshResource::validate_and_prepare() {
    // Validacao dos LODs
    for (const auto& lod : m_lods) {
        if (static_cast<uint64_t>(lod.offset) + lod.clusters > m_header.clusters) {
            std::cerr << "[VGMeshResource] Intervalo de clusters invalido no LOD " << lod.level << std::endl;
            return false;
        }
    }

    // Validacao dos Clusters
    for (const auto& c : m_clusters) {
        if (c.lod >= m_header.lods) {
            std::cerr << "[VGMeshResource] Nivel de LOD fora dos limites no cluster " << c.id << std::endl;
            return false;
        }
        if (static_cast<uint64_t>(c.vertex_offset) + c.vertex_count > m_header.vertices) {
            std::cerr << "[VGMeshResource] Offset de vertices invalido no cluster " << c.id << std::endl;
            return false;
        }
        if (static_cast<uint64_t>(c.triangle_offset) + static_cast<uint64_t>(c.triangle_count) * 3 > m_header.indices) {
            std::cerr << "[VGMeshResource] Offset de triangulos invalido no cluster " << c.id << std::endl;
            return false;
        }
        if (c.group < -1 || (c.group >= 0 && static_cast<uint32_t>(c.group) >= m_header.groups)) {
            std::cerr << "[VGMeshResource] Grupo DAG pai invalido no cluster " << c.id << std::endl;
            return false;
        }
        if (c.refined < -1 || (c.refined >= 0 && static_cast<uint32_t>(c.refined) >= m_header.groups)) {
            std::cerr << "[VGMeshResource] Grupo DAG refinado invalido no cluster " << c.id << std::endl;
            return false;
        }

        // Validar integridade dos indices locais
        for (uint64_t i = c.triangle_offset; i < static_cast<uint64_t>(c.triangle_offset) + c.triangle_count * 3; ++i) {
            if (m_indices[i] >= c.vertex_count) {
                std::cerr << "[VGMeshResource] Indice de vertice local excede vertex_count no cluster " << c.id << std::endl;
                return false;
            }
        }
    }

    // Preparar GPU Clusters (layout identico ao cull_clusters.glsl)
    m_gpu_clusters.resize(m_clusters.size());
    for (size_t i = 0; i < m_clusters.size(); ++i) {
        const auto& c = m_clusters[i];
        auto& g = m_gpu_clusters[i];

        // center_radius
        g.center_radius[0] = c.center[0];
        g.center_radius[1] = c.center[1];
        g.center_radius[2] = c.center[2];
        g.center_radius[3] = c.radius;

        // cone_axis_cutoff
        g.cone_axis_cutoff[0] = c.cone[0];
        g.cone_axis_cutoff[1] = c.cone[1];
        g.cone_axis_cutoff[2] = c.cone[2];
        g.cone_axis_cutoff[3] = c.cone[3];

        // group_bounds_error (parent group)
        if (c.group >= 0 && static_cast<uint32_t>(c.group) < m_groups.size()) {
            const auto& grp = m_groups[c.group];
            g.group_bounds_error[0] = grp.center[0];
            g.group_bounds_error[1] = grp.center[1];
            g.group_bounds_error[2] = grp.center[2];
            g.group_bounds_error[3] = grp.error;
        } else {
            g.group_bounds_error[0] = 0.0f;
            g.group_bounds_error[1] = 0.0f;
            g.group_bounds_error[2] = 0.0f;
            g.group_bounds_error[3] = 999999.0f;
        }

        // refined_bounds_error (child/refined group)
        if (c.refined >= 0 && static_cast<uint32_t>(c.refined) < m_groups.size()) {
            const auto& rgrp = m_groups[c.refined];
            g.refined_bounds_error[0] = rgrp.center[0];
            g.refined_bounds_error[1] = rgrp.center[1];
            g.refined_bounds_error[2] = rgrp.center[2];
            g.refined_bounds_error[3] = rgrp.error;
        } else {
            g.refined_bounds_error[0] = 0.0f;
            g.refined_bounds_error[1] = 0.0f;
            g.refined_bounds_error[2] = 0.0f;
            g.refined_bounds_error[3] = -1.0f;
        }

        // data_offsets
        g.data_offsets[0] = c.vertex_offset;
        g.data_offsets[1] = c.vertex_count;
        g.data_offsets[2] = c.triangle_offset;
        g.data_offsets[3] = c.triangle_count;

        // cluster_info
        g.cluster_info[0] = c.id;
        g.cluster_info[1] = c.lod;
        g.cluster_info[2] = static_cast<uint32_t>(c.group);
        g.cluster_info[3] = static_cast<uint32_t>(c.refined);
    }

    // Preparar packed vertices para SSBO (32 bytes = 2 vec4)
    m_packed_vertices.resize(m_vertices.size());
    for (size_t i = 0; i < m_vertices.size(); ++i) {
        const auto& v = m_vertices[i];
        auto& pv = m_packed_vertices[i];
        pv.pos_x = v.position[0];
        pv.pos_y = v.position[1];
        pv.pos_z = v.position[2];
        pv.uv_x = v.uv[0];
        pv.norm_x = v.normal[0];
        pv.norm_y = v.normal[1];
        pv.norm_z = v.normal[2];
        pv.uv_y = v.uv[1];
    }

    // Preparar packed triangles para SSBO (agrupados em palavras uint32_t de 4 bytes)
    size_t word_count = (m_indices.size() + 3) / 4;
    m_packed_triangles.assign(word_count, 0u);
    for (size_t i = 0; i < m_indices.size(); ++i) {
        size_t word_idx = i / 4;
        size_t byte_in_word = i % 4;
        m_packed_triangles[word_idx] |= (static_cast<uint32_t>(m_indices[i]) << (byte_in_word * 8));
    }

    m_valid = true;
    return true;
}

} // namespace Arboria
