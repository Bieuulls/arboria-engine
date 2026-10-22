#ifndef ARBORIA_INSTANCE_REGISTRY_H
#define ARBORIA_INSTANCE_REGISTRY_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include "arboria_gpu_scene_types.h"
#include <vector>
#include <mutex>

namespace Arboria {

struct InstanceRecord {
    Handle handle;
    Handle mesh_handle;
    uint32_t material_id = 0;
    float model_matrix[16] = {
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        0,0,0,1
    };
    float max_screen_error = 1.5f;
    uint32_t lod_mode = 0; // 0 = Auto DAG, 1 = Forced
    uint32_t forced_lod = 0;
    bool visible = true;
    bool shadow_caster = true;
};

class ARBORIA_CLASS ArboriaInstanceRegistry {
public:
    static ArboriaInstanceRegistry& instance();

    Handle register_instance(Handle mesh_handle, uint32_t material_id = 0);
    bool unregister_instance(Handle instance_handle);
    bool is_valid_instance(Handle instance_handle) const;

    bool set_transform(Handle instance_handle, const float transform_matrix[16]);
    bool set_lod_parameters(Handle instance_handle, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod);
    bool set_visibility(Handle instance_handle, bool visible);
    bool set_material(Handle instance_handle, uint32_t material_id);

    const InstanceRecord* get_instance(Handle instance_handle) const;
    size_t get_instance_count() const;

    // Constrói o buffer GPU de instâncias empacotado para o SSBO global da GPU
    // Calcula volumes delimitadores (bounding sphere e AABB) no espaço de mundo com suporte
    // a escalas não uniformes e espelhadas (negativas), e matriz normal inversa transposta
    size_t build_gpu_instance_buffer(std::vector<GPUInstanceData>& out_buffer) const;

    // Utilitários matemáticos para transformações de bounding volumes e normais
    static void compute_world_bounds(
        const float local_center[3], float local_radius,
        const float local_min[3], const float local_max[3],
        const float m[16],
        float out_world_center[3], float& out_world_radius,
        float out_world_min[3], float out_world_max[3]
    );

    static void compute_normal_matrix(const float model[16], float normal_out[16]);

    void clear();

private:
    ArboriaInstanceRegistry() = default;
    ~ArboriaInstanceRegistry() = default;

    mutable std::mutex m_mutex;
    GenerationalPool<InstanceRecord> m_instance_pool;
};

} // namespace Arboria

#endif // ARBORIA_INSTANCE_REGISTRY_H
