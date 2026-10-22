#ifndef VG_SCENE_BRIDGE_H
#define VG_SCENE_BRIDGE_H

#include "../core/vg_types.h"
#include <cstdint>
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>

namespace Arboria {

struct SceneInstanceData {
    uint32_t instance_id = 0;
    int32_t mesh_id = -1;
    float transform_matrix[16];   // Col-major 4x4 matrix
    float aabb_min[3];            // World-space AABB min
    float aabb_max[3];            // World-space AABB max
    float max_screen_error = 1.5f;
    uint32_t lod_mode = 0;        // 0 = Auto DAG, 1 = Forced LOD
    uint32_t forced_lod = 0;
    bool visible = true;
    uint32_t material_id = 0;
};

class ARBORIA_CLASS VGSceneBridge {
public:
    static VGSceneBridge& instance();

    uint32_t register_instance(int32_t mesh_id);
    bool unregister_instance(uint32_t instance_id);

    bool set_instance_transform(uint32_t instance_id, const float matrix[16]);
    bool set_instance_visible(uint32_t instance_id, bool visible);
    bool set_instance_lod_params(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod);

    const SceneInstanceData* get_instance(uint32_t instance_id) const;
    std::vector<SceneInstanceData> get_active_instances() const;

    size_t get_instance_count() const { return m_instances.size(); }
    void clear();

private:
    VGSceneBridge();
    ~VGSceneBridge();

    uint32_t m_next_instance_id = 1;
    std::unordered_map<uint32_t, SceneInstanceData> m_instances;
};

} // namespace Arboria

// C Export API para Scene Bridge
ARBORIA_API uint32_t arboria_scene_create_instance(int32_t mesh_id);
ARBORIA_API int arboria_scene_destroy_instance(uint32_t instance_id);
ARBORIA_API int arboria_scene_set_transform(uint32_t instance_id, const float matrix[16]);
ARBORIA_API int arboria_scene_set_visible(uint32_t instance_id, int visible);
ARBORIA_API int arboria_scene_set_lod(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod);
ARBORIA_API uint32_t arboria_scene_get_active_count();

#endif // VG_SCENE_BRIDGE_H
