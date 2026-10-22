#ifndef VG_RUNTIME_H
#define VG_RUNTIME_H

#include "vg_types.h"
#include "vg_mesh_resource.h"
#include "../gpu/vg_buffer_manager.h"
#include "../gpu/vg_compute_dispatch.h"
#include "../gpu/vg_indirect_renderer.h"

#include <unordered_map>
#include <memory>
#include <string>

namespace Arboria {

class ARBORIA_CLASS VGRuntime {
public:
    static VGRuntime& instance();

    bool initialize();
    void shutdown();
    bool is_initialized() const { return m_initialized; }

    // Gerenciamento de malhas carregadas
    int32_t register_mesh(const std::string& filepath);
    int32_t register_mesh_from_memory(const uint8_t* data, size_t size);
    bool unregister_mesh(int32_t mesh_id);

    std::shared_ptr<VGMeshResource> get_mesh(int32_t mesh_id);

    // Contagem de malhas ativas
    size_t get_active_mesh_count() const { return m_meshes.size(); }

    const char* get_version_string() const {
        return "ARBORIA ENGINE NATIVE FORWARD+ V7.0 (VULKAN 1.4)";
    }

    // Execução real do pipeline gráfico nativo (Compute Culling + Indirect Draw)
    bool render_scene_native(
        const GPUDriverContext& ctx,
        const void* framebuffer,
        const void* compute_pipeline,
        const void* raster_pipeline,
        const void* compute_sets_array,
        const void* groups_x_array,
        const void* raster_sets_array,
        const void* counter_bufs_array,
        int64_t count,
        const void* initial_colors = nullptr
    );

private:
    VGRuntime();
    ~VGRuntime();

    bool m_initialized = false;
    int32_t m_next_mesh_id = 1;
    std::unordered_map<int32_t, std::shared_ptr<VGMeshResource>> m_meshes;
};

} // namespace Arboria

// ----------------------------------------------------------------------------
// C Export API para consumo pelo Godot GDScript / GDExtension / Plugins
// ----------------------------------------------------------------------------
ARBORIA_API int arboria_init();
ARBORIA_API void arboria_shutdown();
ARBORIA_API const char* arboria_get_version();

ARBORIA_API int32_t arboria_load_mesh(const char* filepath);
ARBORIA_API int32_t arboria_load_mesh_from_memory(const uint8_t* data, size_t size);
ARBORIA_API int arboria_unload_mesh(int32_t mesh_id);

ARBORIA_API int arboria_get_mesh_header(int32_t mesh_id, Arboria::Header* out_header);
ARBORIA_API int arboria_get_mesh_bounds(int32_t mesh_id, float out_bmin[3], float out_bmax[3]);

ARBORIA_API const void* arboria_get_gpu_clusters_ptr(int32_t mesh_id, size_t* out_size_bytes);
ARBORIA_API const void* arboria_get_packed_vertices_ptr(int32_t mesh_id, size_t* out_size_bytes);
ARBORIA_API const void* arboria_get_packed_triangles_ptr(int32_t mesh_id, size_t* out_size_bytes);

ARBORIA_API int arboria_build_camera_ubo(
    const Arboria::CameraViewSettings* settings,
    uint32_t total_clusters,
    const float model_matrix[16],
    Arboria::CameraUniforms* out_ubo
);

ARBORIA_API int arboria_simulate_cull(
    int32_t mesh_id,
    const Arboria::CameraUniforms* ubo,
    uint32_t* out_visible_clusters,
    uint32_t* out_triangles_drawn
);

#endif // VG_RUNTIME_H
