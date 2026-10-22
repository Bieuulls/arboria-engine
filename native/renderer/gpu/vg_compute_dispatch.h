#ifndef VG_COMPUTE_DISPATCH_H
#define VG_COMPUTE_DISPATCH_H

#include "../core/vg_types.h"
#include "../core/vg_mesh_resource.h"
#include "vg_gpu_driver.h"
#include <vector>
#include <array>

namespace Arboria {

struct CameraViewSettings {
    float view_proj_matrix[16];   // Col-major 4x4 matrix
    float camera_world_pos[3];    // World camera position
    float fov_radians = 1.0472f;  // ~60 degrees
    float viewport_width = 1920.0f;
    float viewport_height = 1080.0f;
    float max_screen_error = 1.5f; // Erro maximo em pixels no ecra
    uint32_t lod_mode = 0;         // 0 = Auto DAG, 1 = Forced LOD
    uint32_t forced_lod = 0;
    bool enable_frustum_culling = true;
    bool enable_cone_culling = true;
    uint32_t shading_mode = 0;     // 0 = neutral, 1 = normal, 2 = lit, 3 = cluster debug
};

struct ComputeDispatchResult {
    uint32_t visible_cluster_count = 0;
    uint32_t total_triangles_drawn = 0;
    uint32_t clusters_evaluated = 0;
    std::vector<uint32_t> visible_cluster_ids;
};

class ARBORIA_CLASS VGComputeDispatch {
public:
    VGComputeDispatch();
    ~VGComputeDispatch();

    // Extrai os 6 planos do frustum a partir da matriz MVP
    static void extract_frustum_planes(const float mvp[16], float planes_out[6][4]);

    // Constrói a estrutura CameraUniforms (224 bytes) para envio ao UBO da GPU
    static CameraUniforms build_camera_uniforms(
        const CameraViewSettings& settings,
        uint32_t total_clusters,
        const float model_matrix[16] = nullptr
    );

    // Calcula a quantidade de workgroups (local_size_x = 64)
    static uint32_t calculate_group_count(uint32_t total_clusters, uint32_t group_size = 64);

    // Avalia o culling e selecao DAG na CPU (espelho do cull_clusters.glsl para validacao e testes unitarios)
    static ComputeDispatchResult simulate_cull_offline(
        const VGMeshResource& mesh,
        const CameraUniforms& ubo
    );

    // Identificador de tipo para chamadas nativas de compute
    static bool is_compute_supported() { return true; }

    // Despacho real de Compute Culling na GPU via RenderingDevice
    static bool dispatch_cull_clusters_native(
        const struct GPUDriverContext& ctx,
        const void* compute_pipeline,
        const void* uniform_set,
        int64_t groups_x
    );

    // Despacho em lote de tarefas Compute Culling na GPU
    static bool dispatch_cull_clusters_batch(
        const struct GPUDriverContext& ctx,
        const void* compute_pipeline,
        const void* compute_sets_array,
        const void* groups_x_array,
        int64_t count
    );

private:
    static bool test_frustum(const float center[3], float radius, const float planes[6][4]);
    static bool test_backface(const float center[3], float radius, const float cone[4], const float cam_pos[3]);
    static float project_error_to_screen(float error, float dist, float fov_factor, float viewport_height);
};

} // namespace Arboria

#endif // VG_COMPUTE_DISPATCH_H
