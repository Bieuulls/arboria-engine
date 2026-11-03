#ifndef VG_RUNTIME_H
#define VG_RUNTIME_H

#include "arboria_types.h"
#include "arboria_handle.h"
#include "arboria_mesh_resource.h"
#include "../scene/arboria_mesh_registry.h"
#include "../gpu/arboria_buffer_manager.h"
#include "../gpu/arboria_compute_dispatch.h"
#include "../gpu/arboria_indirect_renderer.h"

#include <memory>
#include <string>

namespace Arboria {

class ARBORIA_CLASS VGRuntime {
public:
    static VGRuntime& instance();

    bool initialize();
    void shutdown();
    bool is_initialized() const { return m_initialized; }

    // Gerenciamento com controle de geracao (Generational Handles) — delega ao ArboriaMeshRegistry
    Result<Handle> register_mesh_handle(const std::string& filepath);
    Status unregister_mesh_handle(Handle handle);
    std::shared_ptr<VGMeshResource> get_mesh_by_handle(Handle handle);

    // Gerenciamento compatível por ID — delega ao ArboriaMeshRegistry (mesh_id = pool slot index)
    int32_t register_mesh(const std::string& filepath);
    int32_t register_mesh_from_memory(const uint8_t* data, size_t size);
    bool unregister_mesh(int32_t mesh_id);
    std::shared_ptr<VGMeshResource> get_mesh(int32_t mesh_id);

    // Contagem de malhas ativas (fonte única: ArboriaMeshRegistry)
    size_t get_active_mesh_count() const { return ArboriaMeshRegistry::instance().get_mesh_count(); }

    const char* get_version_string() const {
        return "ARBORIA ENGINE NATIVE FORWARD+ V7.0 (VULKAN 1.4)";
    }

    // Estado da câmera (enviado via GDExtension update_camera / camera_ubo_buf)
    void set_camera(const float view_proj[16], const float cam_pos[3], const float viewport[2]);
    void get_camera(float view_proj[16], float cam_pos[3], float viewport[2]) const;

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

    // Estado da câmera (atualizado via GDExtension update_camera)
    float m_camera_view_proj[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    };
    float m_camera_pos[3] = {0.0f, 0.0f, 0.0f};
    float m_viewport_size[2] = {0.0f, 0.0f};
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
