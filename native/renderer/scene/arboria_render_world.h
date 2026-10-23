#ifndef ARBORIA_RENDER_WORLD_H
#define ARBORIA_RENDER_WORLD_H

#include "../core/arboria_types.h"
#include "arboria_gpu_scene_types.h"
#include "arboria_gpu_scene.h"
#include "arboria_mesh_registry.h"
#include "arboria_instance_registry.h"
#include "arboria_material_table.h"
#include <string>

namespace Arboria {

class ARBORIA_CLASS ArboriaRenderWorld {
public:
    static ArboriaRenderWorld& instance();

    void initialize();
    void shutdown();
    bool is_initialized() const { return m_initialized; }

    // Gerenciamento de Geometria Compartilhada
    Handle register_mesh(const std::string& path);
    bool unregister_mesh(Handle handle);

    // Gerenciamento de Instâncias Globais
    Handle register_instance(Handle mesh_handle, uint32_t material_id = 0);
    bool update_instance_transform(Handle instance_handle, const float transform[16]);
    bool update_instance_lod(Handle instance_handle, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod);
    bool update_instance_visibility(Handle instance_handle, bool visible);
    bool release_instance(Handle instance_handle);

    // Renderização Agrupada Global
    bool render_scene_global(
        const GPUDriverContext& ctx,
        const void* framebuffer,
        const void* compute_pipeline,
        const void* raster_pipeline,
        const void* compute_uniform_set,
        const void* raster_uniform_set,
        const void* indirect_args_buffer,
        uint32_t total_work_items,
        const void* initial_colors = nullptr
    );

    // Estatísticas da cena global
    size_t get_registered_mesh_count() const;
    size_t get_active_instance_count() const;

    // Gerenciamento de Memória VRAM e Streaming
    void memory_set_budget(size_t bytes);
    size_t memory_get_budget() const;
    size_t memory_get_resident_bytes() const;
    size_t memory_get_allocated_bytes() const;
    uint32_t memory_get_page_faults() const;
    uint32_t memory_get_evictions() const;
    void streaming_update(const float cam_pos[3], uint64_t current_frame);

private:
    ArboriaRenderWorld() = default;
    ~ArboriaRenderWorld() = default;

    bool m_initialized = false;
};

} // namespace Arboria

#endif // ARBORIA_RENDER_WORLD_H
