#ifndef ARBORIA_GPU_SCENE_H
#define ARBORIA_GPU_SCENE_H

#include "../core/arboria_types.h"
#include "../gpu/arboria_gpu_driver.h"
#include "arboria_gpu_scene_types.h"
#include "arboria_mesh_registry.h"
#include "arboria_instance_registry.h"
#include "arboria_material_table.h"
#include "arboria_visibility_manager.h"
#include "arboria_indirect_command_manager.h"
#include <vector>

namespace Arboria {

struct SceneCullResult {
    uint32_t total_instances = 0;
    uint32_t total_work_items = 0;
    uint32_t visible_instances = 0;
    uint32_t visible_clusters = 0;
    uint32_t total_triangles_drawn = 0;
    std::vector<VisibleClusterItem> visible_items;
    bool has_overflow = false;
};

class ARBORIA_CLASS ArboriaGPUScene {
public:
    static ArboriaGPUScene& instance();

    // Constrói os uniforms globais da cena a partir da câmera
    GlobalSceneUniforms build_scene_uniforms(
        const float view_proj[16],
        const float cam_pos[3],
        float fov_factor,
        float vp_width,
        float vp_height,
        float max_screen_error = 1.5f,
        uint32_t lod_mode = 0,
        bool enable_frustum = true,
        bool enable_cone = true,
        uint32_t shading_mode = 0,
        bool enable_hiz = false
    );

    // Simulação do culling agrupado na CPU (espelho do compute shader para validação)
    SceneCullResult simulate_cull_scene(const GlobalSceneUniforms& uniforms) const;

    // Execução real do Culling Agrupado Global na GPU via RenderingDevice
    // Despacha um lote único de compute para toda a cena em vez de 1 por instância!
    bool dispatch_global_cull(
        const GPUDriverContext& ctx,
        const void* compute_pipeline,
        const void* global_uniform_set,
        uint32_t total_work_items
    );

    // Execução real do Desenho Indireto Agrupado Global na GPU via RenderingDevice
    // Emite comandos indiretos consolidados na GPU sem laço de CPU por objeto!
    bool draw_global_indirect(
        const GPUDriverContext& ctx,
        const void* framebuffer,
        const void* raster_pipeline,
        const void* raster_uniform_set,
        const void* indirect_args_buffer,
        const void* initial_colors = nullptr
    );

    // Barreiras e sincronização Vulkan Compute-to-Raster
    bool requires_pipeline_barrier() const { return true; }

private:
    ArboriaGPUScene() = default;
    ~ArboriaGPUScene() = default;

    static void extract_frustum_planes(const float vp[16], float planes[6][4]);
    static bool test_frustum(const float center[3], float radius, const float planes[6][4]);
    static bool test_cone(const float center[3], float radius, const float axis_cutoff[4], const float cam_pos[3]);
    static float project_screen_error(const float center[3], float radius, float mesh_error, const float cam_pos[3], float vp_h, float fov_factor);
};

} // namespace Arboria

#endif // ARBORIA_GPU_SCENE_H
