#ifndef VG_TYPES_H
#define VG_TYPES_H

#include <cstdint>
#include <cstddef>
#include <array>

#if defined(_WIN32)
#define ARBORIA_API extern "C" __declspec(dllexport)
#define ARBORIA_CLASS __declspec(dllexport)
#else
#define ARBORIA_API extern "C" __attribute__((visibility("default")))
#define ARBORIA_CLASS __attribute__((visibility("default")))
#endif

namespace Arboria {

#pragma pack(push, 1)

// ARBORIA2 File Header (72 bytes)
struct Header {
    char magic[8];             // "ARBORIA2"
    uint32_t version;          // 2
    uint32_t vertices;         // Total vertices count
    uint32_t indices;          // Total indices bytes count (local triangle indices)
    uint32_t triangles;        // Total triangles count
    uint32_t clusters;         // Total clusters count
    uint32_t lods;             // Total LOD levels count
    float bmin[3];             // AABB min (x, y, z)
    float bmax[3];             // AABB max (x, y, z)
    uint32_t groups;           // Total DAG groups count
    uint32_t base_triangles;   // LOD 0 base triangles count
    uint32_t reserved[2];      // Future expansion padding
};

// LOD Metadata (24 bytes)
struct LOD {
    uint32_t level;            // LOD level (0 = maximum detail)
    uint32_t offset;           // Cluster offset in the global cluster array
    uint32_t clusters;         // Number of clusters in this LOD
    uint32_t triangles;        // Number of triangles in this LOD
    float error;               // Geometric error threshold (object space)
    float ratio;               // Simplification ratio compared to base
};

// Cluster Metadata (68 bytes)
struct Cluster {
    uint32_t id;               // Global cluster ID
    uint32_t lod;              // LOD level
    int32_t group;             // Parent DAG group ID (-1 if root)
    int32_t refined;           // Child/Refined DAG group ID (-1 if leaf)
    float center[3];           // Bounding sphere center (x, y, z)
    float radius;              // Bounding sphere radius
    float cone[4];             // Normal cone (nx, ny, nz, cutoff)
    float error;               // Cluster geometric error
    uint32_t vertex_offset;    // Offset in vertices array
    uint32_t vertex_count;     // Vertices in this cluster (<= 256)
    uint32_t triangle_offset;  // Byte offset in triangle indices array
    uint32_t triangle_count;   // Triangles in this cluster (<= 128)
};

// DAG Group Metadata (28 bytes)
struct Group {
    uint32_t id;               // Group ID
    int32_t depth;             // Hierarchical DAG depth
    float center[3];           // Group bounding sphere center
    float radius;              // Group bounding sphere radius
    float error;               // Group max geometric error
};

// Vertex Structure (32 bytes)
struct Vertex {
    float position[3];         // Position (x, y, z)
    float normal[3];           // Normal vector (nx, ny, nz)
    float uv[2];               // Texture coordinates (u, v)
};

#pragma pack(pop)

// GPU Cluster Layout (96 bytes) - Matching cull_clusters.glsl binding 0
struct GPUCluster {
    float center_radius[4];        // xyz = center, w = radius
    float cone_axis_cutoff[4];     // xyz = cone axis, w = cone cutoff
    float group_bounds_error[4];   // xyz = parent group center, w = parent group error
    float refined_bounds_error[4]; // xyz = refined group center, w = refined group error (-1.0 if base)
    uint32_t data_offsets[4];      // x = v_offset, y = v_count, z = t_offset, w = t_count
    uint32_t cluster_info[4];      // x = cluster_id, y = lod_level, z = group_id, w = refined_group
};

// Camera Uniforms Buffer Layout (224 bytes) - Matching cull_clusters.glsl binding 3
struct CameraUniforms {
    float view_proj[16];           // 64 bytes: 4x4 MVP Matrix
    float frustum_planes[6][4];    // 96 bytes: 6 planes (nx, ny, nz, d)
    float camera_pos_fov[4];       // 16 bytes: xyz = pos, w = fov_factor
    float viewport_params[4];      // 16 bytes: x = width, y = height, z = max_screen_error, w = lod_mode
    uint32_t count_params[4];      // 16 bytes: x = total_clusters, y = forced_lod, z = enable_frustum, w = enable_cone
    uint32_t render_params[4];     // 16 bytes: x = shading_mode, y, z, w reserved
};

// Vulkan Draw Indirect Command Structure (16 bytes)
struct VkDrawIndirectCommand {
    uint32_t vertex_count;         // Usually 384 (128 triangles * 3 vertices)
    uint32_t instance_count;       // Dynamically incremented by GPU atomicAdd
    uint32_t first_vertex;         // 0
    uint32_t first_instance;       // 0
};

// GPU Counter and Indirect Args (24 bytes) - Matching cull_clusters.glsl binding 2
struct OutCounterAndDrawArgs {
    VkDrawIndirectCommand draw_cmd; // 16 bytes
    uint32_t total_triangles_drawn; // 4 bytes (offset 16)
    uint32_t total_clusters_evaluated; // 4 bytes (offset 20)
};

// Packed Vertex for GPU SSBO (32 bytes = 2x vec4)
struct GPUPackedVertex {
    float pos_x, pos_y, pos_z, uv_x;
    float norm_x, norm_y, norm_z, uv_y;
};

// Static assertions ensuring exact binary layout
static_assert(sizeof(Header) == 72, "Header size mismatch");
static_assert(sizeof(LOD) == 24, "LOD size mismatch");
static_assert(sizeof(Cluster) == 68, "Cluster size mismatch");
static_assert(sizeof(Group) == 28, "Group size mismatch");
static_assert(sizeof(Vertex) == 32, "Vertex size mismatch");
static_assert(sizeof(GPUCluster) == 96, "GPUCluster size mismatch");
static_assert(sizeof(CameraUniforms) == 224, "CameraUniforms size mismatch");
static_assert(sizeof(VkDrawIndirectCommand) == 16, "VkDrawIndirectCommand size mismatch");
static_assert(sizeof(OutCounterAndDrawArgs) == 24, "OutCounterAndDrawArgs size mismatch");
static_assert(sizeof(GPUPackedVertex) == 32, "GPUPackedVertex size mismatch");

} // namespace Arboria

#endif // VG_TYPES_H
