#[compute]
#version 450

// ============================================================================
// ARBORIA VIRTUAL GEOMETRY — GATE D: RASTERIZAÇÃO AVANÇADA
//
// Shader de rasterização consolidada que consome a saída do culling Gate C
// (cull_clusters_v2.glsl) e emite draw indirect para todos os clusters visíveis.
//
// Camadas Gate D:
// 1. Draw Indirect Consolidado — um único draw indirect para todos clusters
// 2. LOD com Morphing — transição suave entre níveis
// 3. Variable Rate Shading (VRS) — taxa variável por importância do cluster
// 4. Early-Z + Conservative Raster — descarta clusters ocluídos no raster
// ============================================================================

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct GPUVisibleCluster {
    uint instance_id;         // ID da instância
    uint cluster_id;          // ID do cluster na malha
    uint lod_level;           // Nível LOD selecionado (0 = mais detalhado)
    uint morph_factor;        // Fator de morphing 0-255 (fixed point)
    uint vrs_rate;            // Taxa VRS (0=1:1, 1=2:1, 2=4:1, 3=8:1)
    uint vertex_offset;       // Offset no buffer de vértices dinâmicos
    uint vertex_count;        // Contagem de vértices
    uint triangle_offset;     // Offset no buffer de triângulos dinâmicos
    uint triangle_count;      // Contagem de triângulos
    float screen_error;       // Erro de tela projetado (pixels)
    float depth;              // Profundidade média do cluster
    uint pad[2];
};

struct DrawArgsConsolidated {
    uint draw_count;          // Número de clusters visíveis
    uint instance_count;      // Sempre 1
    uint first_index;         // Sempre 0
    uint base_vertex;         // Base do vértice
    uint base_instance;       // Base da instância
};

// Input: clusters visíveis da saída do culling Gate C
layout(set = 0, binding = 0, std430) readonly buffer InVisibleClusters {
    GPUVisibleCluster visible_clusters[];
};

// Output: argumentos de draw indirect consolidado
layout(set = 0, binding = 1, std430) writeonly buffer OutDrawArgs {
    DrawArgsConsolidated draw_args;
};

// Output: buffer de clusters processados para o raster
layout(set = 0, binding = 2, std430) writeonly buffer OutProcessedClusters {
    GPUVisibleCluster processed_clusters[];
};

// Uniforms de rasterização
layout(set = 0, binding = 3, std140) uniform RasterParams {
    uint max_visible_clusters;      // Limite máximo de clusters por frame
    uint enable_morphing;           // 1 = habilitar morphing LOD
    uint enable_vrs;                // 1 = habilitar Variable Rate Shading
    uint vrs_base_rate;             // Taxa VRS base (0=1:1, 1=2:1, ...)
    float morph_screen_error_min;   // Erro de tela onde morphing começa
    float morph_screen_error_max;   // Erro de tela onde morphing termina
    float vrs_distance_near;        // Distância para VRS alta qualidade
    float vrs_distance_far;         // Distância para VRS baixa qualidade
} raster;

// Contadores
layout(set = 0, binding = 4, std430) buffer RasterCounters {
    uint total_clusters_processed;
    uint total_clusters_culled_early_z;
    uint total_triangles_rasterized;
    uint total_morphing_clusters;
    uint total_vrs_clusters[4];  // Contagem por taxa VRS
} counters;

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= counters.total_clusters_processed) {
        return;
    }

    GPUVisibleCluster c = visible_clusters[idx];

    // --- Seleção de LOD com Morphing ---
    uint final_lod = c.lod_level;
    uint morph = 0;

    if (raster.enable_morphing != 0u) {
        if (c.screen_error > raster.morph_screen_error_min &&
            c.screen_error < raster.morph_screen_error_max) {
            // Interpola entre LOD atual e próximo
            float t = (c.screen_error - raster.morph_screen_error_min) /
                      (raster.morph_screen_error_max - raster.morph_screen_error_min);
            morph = uint(clamp(t * 255.0, 0.0, 255.0));
            if (c.lod_level < 0xFFFFFFFFu) {
                final_lod = c.lod_level;  // Mantém LOD atual com morph
            }
            atomicAdd(counters.total_morphing_clusters, 1u);
        }
    }

    // --- Variable Rate Shading (VRS) ---
    uint vrs_rate = raster.vrs_base_rate;
    if (raster.enable_vrs != 0u) {
        // Distância aproximada baseada na profundidade
        float dist_factor = clamp(c.depth / 1000.0, 0.0, 1.0);
        if (dist_factor < 0.3f) {
            vrs_rate = 0u;  // 1:1 — alta qualidade
        } else if (dist_factor < 0.6f) {
            vrs_rate = 1u;  // 2:1
        } else if (dist_factor < 0.85f) {
            vrs_rate = 2u;  // 4:1
        } else {
            vrs_rate = 3u;  // 8:1 — baixa qualidade
        }
        // Sobrescreve com taxa do cluster se for mais específica
        if (c.vrs_rate < vrs_rate) {
            vrs_rate = c.vrs_rate;
        }
        atomicAdd(counters.total_vrs_clusters[vrs_rate], 1u);
    }

    // --- Early-Z / Conservative Raster Culling ---
    // Clusters muito distantes com erro de tela mínimo podem ser descartados
    bool culled = false;
    if (c.depth > raster.vrs_distance_far && c.screen_error < 0.5f) {
        culled = true;
        atomicAdd(counters.total_clusters_culled_early_z, 1u);
    }

    if (!culled) {
        // Escreve cluster processado para o raster
        GPUVisibleCluster processed;
        processed.instance_id = c.instance_id;
        processed.cluster_id = c.cluster_id;
        processed.lod_level = final_lod;
        processed.morph_factor = morph;
        processed.vrs_rate = vrs_rate;
        processed.vertex_offset = c.vertex_offset;
        processed.vertex_count = c.vertex_count;
        processed.triangle_offset = c.triangle_offset;
        processed.triangle_count = c.triangle_count;
        processed.screen_error = c.screen_error;
        processed.depth = c.depth;
        processed.pad[0] = 0;
        processed.pad[1] = 0;

        uint out_slot = atomicAdd(counters.total_clusters_processed, 1u);
        if (out_slot < raster.max_visible_clusters) {
            processed_clusters[out_slot] = processed;
            atomicAdd(counters.total_triangles_rasterized, c.triangle_count);
        }
    }

    // Atualiza draw_args com contagem final
    if (idx == 0u) {
        draw_args.draw_count = counters.total_clusters_processed;
        draw_args.instance_count = 1u;
        draw_args.first_index = 0u;
        draw_args.base_vertex = 0u;
        draw_args.base_instance = 0u;
    }
}
