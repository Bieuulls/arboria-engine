#include "arboria_buffer_manager.h"
#include <iostream>
#include <limits>

namespace Arboria {

VGBufferManager::VGBufferManager() {
    cleanup();
}

VGBufferManager::~VGBufferManager() {
    cleanup();
}

void VGBufferManager::cleanup() {
    m_ready = false;
    m_cluster_count = 0;
    m_vertex_count = 0;
    m_triangle_count = 0;

    m_desc_in_clusters = BufferDescriptor{};
    m_desc_out_visible = BufferDescriptor{};
    m_desc_draw_args = BufferDescriptor{};
    m_desc_ubo = BufferDescriptor{};
    m_desc_in_vertices = BufferDescriptor{};
    m_desc_in_triangles = BufferDescriptor{};
}

bool VGBufferManager::setup_for_mesh(const VGMeshResource& mesh) {
    cleanup();

    if (!mesh.is_valid()) {
        std::cerr << "[VGBufferManager] Malha invalida fornecida para o Buffer Manager." << std::endl;
        return false;
    }

    m_cluster_count = mesh.get_cluster_count();
    m_vertex_count = mesh.get_vertex_count();
    m_triangle_count = mesh.get_triangle_count();

    // Reject layouts that cannot be represented safely in host address space.
    if (size_t(m_cluster_count) > std::numeric_limits<size_t>::max() / sizeof(uint32_t)) {
        cleanup();
        return false;
    }

    // 1. InClusters: binding 0, std430 (96 bytes per cluster)
    m_desc_in_clusters.name = "InClusters_SSBO";
    m_desc_in_clusters.size_bytes = mesh.get_gpu_clusters_byte_size();
    m_desc_in_clusters.alignment = 16;
    m_desc_in_clusters.binding = 0;
    m_desc_in_clusters.is_storage = true;

    // 2. OutVisibleClusters: binding 1, std430 (4 bytes per cluster ID)
    m_desc_out_visible.name = "OutVisibleClusters_SSBO";
    m_desc_out_visible.size_bytes = std::max(size_t(4), size_t(m_cluster_count) * sizeof(uint32_t));
    m_desc_out_visible.alignment = 16;
    m_desc_out_visible.binding = 1;
    m_desc_out_visible.is_storage = true;

    // 3. OutCounterAndDrawArgs: binding 2, std430 (24 bytes VkDrawIndirectCommand + counters)
    m_desc_draw_args.name = "OutCounterAndDrawArgs_SSBO";
    m_desc_draw_args.size_bytes = sizeof(OutCounterAndDrawArgs);
    m_desc_draw_args.alignment = 16;
    m_desc_draw_args.binding = 2;
    m_desc_draw_args.is_storage = true;
    m_desc_draw_args.is_indirect = true;

    // 4. CameraUniforms UBO: binding 3, std140 (224 bytes)
    m_desc_ubo.name = "CameraUniforms_UBO";
    m_desc_ubo.size_bytes = sizeof(CameraUniforms);
    m_desc_ubo.alignment = 256; // Standard Vulkan uniform buffer offset alignment
    m_desc_ubo.binding = 3;
    m_desc_ubo.is_uniform = true;

    // 5. InVertices: binding 5, std430 (32 bytes per vertex)
    m_desc_in_vertices.name = "InVertices_SSBO";
    m_desc_in_vertices.size_bytes = mesh.get_packed_vertices_byte_size();
    m_desc_in_vertices.alignment = 16;
    m_desc_in_vertices.binding = 5;
    m_desc_in_vertices.is_storage = true;

    // 6. InTriangles: binding 6, std430 (uint32 packed indices)
    m_desc_in_triangles.name = "InTriangles_SSBO";
    m_desc_in_triangles.size_bytes = mesh.get_packed_triangles_byte_size();
    m_desc_in_triangles.alignment = 16;
    m_desc_in_triangles.binding = 6;
    m_desc_in_triangles.is_storage = true;

    const size_t sizes[] = {m_desc_in_clusters.size_bytes, m_desc_out_visible.size_bytes,
        m_desc_draw_args.size_bytes, m_desc_ubo.size_bytes,
        m_desc_in_vertices.size_bytes, m_desc_in_triangles.size_bytes};
    size_t total = 0;
    for (size_t bytes : sizes) {
        if (bytes == 0 || bytes > std::numeric_limits<size_t>::max() - total) {
            cleanup();
            return false;
        }
        total += bytes;
    }
    m_ready = true;
    return true;
}

size_t VGBufferManager::get_total_vram_bytes() const {
    if (!m_ready) return 0;
    return m_desc_in_clusters.size_bytes +
           m_desc_out_visible.size_bytes +
           m_desc_draw_args.size_bytes +
           m_desc_ubo.size_bytes +
           m_desc_in_vertices.size_bytes +
           m_desc_in_triangles.size_bytes;
}

OutCounterAndDrawArgs VGBufferManager::get_initial_draw_args() const {
    OutCounterAndDrawArgs args{};
    args.draw_cmd.vertex_count = 384; // 128 triangulos maximos por cluster * 3 vertices
    args.draw_cmd.instance_count = 0; // Incrementado via atomicAdd na GPU
    args.draw_cmd.first_vertex = 0;
    args.draw_cmd.first_instance = 0;
    args.total_triangles_drawn = 0;
    args.total_clusters_evaluated = 0;
    return args;
}

} // namespace Arboria
