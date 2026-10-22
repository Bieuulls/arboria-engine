#include "vg_scene_bridge.h"
#include <cstring>

namespace Arboria {

VGSceneBridge& VGSceneBridge::instance() {
    static VGSceneBridge s_bridge;
    return s_bridge;
}

VGSceneBridge::VGSceneBridge() {}
VGSceneBridge::~VGSceneBridge() {
    clear();
}

void VGSceneBridge::clear() {
    m_instances.clear();
}

uint32_t VGSceneBridge::register_instance(int32_t mesh_id) {
    uint32_t id = m_next_instance_id++;
    SceneInstanceData data{};
    data.instance_id = id;
    data.mesh_id = mesh_id;

    // Identidade padrão
    std::memset(data.transform_matrix, 0, sizeof(data.transform_matrix));
    data.transform_matrix[0] = 1.0f;
    data.transform_matrix[5] = 1.0f;
    data.transform_matrix[10] = 1.0f;
    data.transform_matrix[15] = 1.0f;

    data.max_screen_error = 1.5f;
    data.lod_mode = 0;
    data.forced_lod = 0;
    data.visible = true;

    m_instances[id] = data;
    return id;
}

bool VGSceneBridge::unregister_instance(uint32_t instance_id) {
    auto it = m_instances.find(instance_id);
    if (it != m_instances.end()) {
        m_instances.erase(it);
        return true;
    }
    return false;
}

bool VGSceneBridge::set_instance_transform(uint32_t instance_id, const float matrix[16]) {
    if (!matrix) return false;
    auto it = m_instances.find(instance_id);
    if (it != m_instances.end()) {
        std::memcpy(it->second.transform_matrix, matrix, sizeof(float) * 16);
        return true;
    }
    return false;
}

bool VGSceneBridge::set_instance_visible(uint32_t instance_id, bool visible) {
    auto it = m_instances.find(instance_id);
    if (it != m_instances.end()) {
        it->second.visible = visible;
        return true;
    }
    return false;
}

bool VGSceneBridge::set_instance_lod_params(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    auto it = m_instances.find(instance_id);
    if (it != m_instances.end()) {
        it->second.max_screen_error = max_screen_error;
        it->second.lod_mode = lod_mode;
        it->second.forced_lod = forced_lod;
        return true;
    }
    return false;
}

const SceneInstanceData* VGSceneBridge::get_instance(uint32_t instance_id) const {
    auto it = m_instances.find(instance_id);
    if (it != m_instances.end()) {
        return &it->second;
    }
    return nullptr;
}

std::vector<SceneInstanceData> VGSceneBridge::get_active_instances() const {
    std::vector<SceneInstanceData> active;
    active.reserve(m_instances.size());
    for (const auto& pair : m_instances) {
        if (pair.second.visible && pair.second.mesh_id >= 0) {
            active.push_back(pair.second);
        }
    }
    return active;
}

} // namespace Arboria

// ----------------------------------------------------------------------------
// C Export API Implementation
// ----------------------------------------------------------------------------

ARBORIA_API uint32_t arboria_scene_create_instance(int32_t mesh_id) {
    return Arboria::VGSceneBridge::instance().register_instance(mesh_id);
}

ARBORIA_API int arboria_scene_destroy_instance(uint32_t instance_id) {
    return Arboria::VGSceneBridge::instance().unregister_instance(instance_id) ? 0 : -1;
}

ARBORIA_API int arboria_scene_set_transform(uint32_t instance_id, const float matrix[16]) {
    return Arboria::VGSceneBridge::instance().set_instance_transform(instance_id, matrix) ? 0 : -1;
}

ARBORIA_API int arboria_scene_set_visible(uint32_t instance_id, int visible) {
    return Arboria::VGSceneBridge::instance().set_instance_visible(instance_id, visible != 0) ? 0 : -1;
}

ARBORIA_API int arboria_scene_set_lod(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    return Arboria::VGSceneBridge::instance().set_instance_lod_params(instance_id, max_screen_error, lod_mode, forced_lod) ? 0 : -1;
}

ARBORIA_API uint32_t arboria_scene_get_active_count() {
    return static_cast<uint32_t>(Arboria::VGSceneBridge::instance().get_active_instances().size());
}
