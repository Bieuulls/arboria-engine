#ifndef ARBORIA_GPU_SCENE_TYPES_H
#define ARBORIA_GPU_SCENE_TYPES_H

#include "../core/arboria_types.h"
#include <cstdint>
#include <cstddef>

namespace Arboria {

#pragma pack(push, 1)

// Layout binário estrito alinhado com GLSL std430 (240 bytes)
struct alignas(16) GPUInstanceData {
    float model_matrix[16];         // offset 0..63
    float normal_matrix[16];        // offset 64..127: transposta da inversa da base 3x3 (expandida para 4x4)
    float bounding_sphere[4];       // offset 128..143: xyz = center mundo, w = radius mundo
    float aabb_min[4];              // offset 144..159: xyz = aabb_min mundo, w = max_screen_error
    float aabb_max[4];              // offset 160..175: xyz = aabb_max mundo, w = lod_mode (0 = auto DAG, 1 = forçado)
    float material_albedo_rough[4]; // offset 176..191: rgb = albedo, w = roughness
    float material_metal_spec[4];   // offset 192..207: x = metallic, y = specular, z = material_id, w = forced_lod
    uint32_t instance_id;           // offset 208
    uint32_t mesh_id;               // offset 212
    uint32_t visibility_flags;      // offset 216: bit 0 = visible, bit 1 = shadow_caster
    uint32_t resource_generation;   // offset 220: geracao de reciclagem do handle
    uint32_t cluster_offset;        // offset 224: offset no buffer global de clusters
    uint32_t cluster_count;         // offset 228: total de clusters da malha instanciada
    uint32_t pad[2];                // offset 232..239: alinhamento estrito a 16 bytes
};

// Item do buffer global de visibilidade compactado na GPU (8 bytes)
struct alignas(8) VisibleClusterItem {
    uint32_t instance_id = 0;
    uint32_t cluster_id = 0;
};

// Buffer de argumentos indiretos e contadores de telemetria GPU (32 bytes)
struct alignas(16) GPUIndirectArgsAndCounters {
    uint32_t vertex_count = 384;    // offset 0: 128 triangulos * 3 vertices
    uint32_t instance_count = 0;    // offset 4: clusters visiveis selecionados
    uint32_t first_vertex = 0;      // offset 8: 0
    uint32_t first_instance = 0;    // offset 12: 0
    uint32_t total_triangles_drawn = 0;    // offset 16
    uint32_t total_clusters_evaluated = 0; // offset 20
    uint32_t max_capacity = 0;             // offset 24: limite do buffer de saida
    uint32_t overflow_flag = 0;            // offset 28: 1 se max_capacity foi excedido
};

// Uniforms globais da cena para Culling e Rasterizacao (256 bytes)
struct alignas(16) GlobalSceneUniforms {
    float view_proj[16];            // offset 0..63
    float frustum_planes[6][4];     // offset 64..159 (6 planos x vec4)
    float camera_pos_fov[4];        // offset 160..175: xyz = cam pos, w = fov_factor
    float viewport_params[4];       // offset 176..191: x = width, y = height, z = max_err, w = lod_mode
    uint32_t total_instances;       // offset 192: total de instancias na cena
    uint32_t total_work_items;      // offset 196: total de clusters acumulados em todas as instancias
    uint32_t enable_frustum_culling;// offset 200: 0 ou 1
    uint32_t enable_cone_culling;   // offset 204: 0 ou 1
    uint32_t shading_mode;          // offset 208: 0 = neutral, 1 = normal, 2 = lit, 3 = cluster debug
    uint32_t enable_hiz;            // offset 212: 0 ou 1
    uint32_t max_visible_items;     // offset 216: capacidade máxima do buffer de visibilidade
    uint32_t wind_enabled;          // offset 220: 1 se animacao de vento GPU estiver ativa
    float wind_params[4];           // offset 224..239: x = time, y = strength, z = freq, w = gust
    float wind_direction[4];        // offset 240..255: xyz = dir_norm, w = unused
};

#pragma pack(pop)

static_assert(sizeof(GPUInstanceData) == 240, "GPUInstanceData deve ter exatamente 240 bytes");
static_assert(sizeof(VisibleClusterItem) == 8, "VisibleClusterItem deve ter exatamente 8 bytes");
static_assert(sizeof(GPUIndirectArgsAndCounters) == 32, "GPUIndirectArgsAndCounters deve ter exatamente 32 bytes");
static_assert(sizeof(GlobalSceneUniforms) == 256, "GlobalSceneUniforms deve ter exatamente 256 bytes");

} // namespace Arboria

#endif // ARBORIA_GPU_SCENE_TYPES_H
