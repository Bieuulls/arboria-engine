#include "arboria_scene_bridge.h"
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

Handle VGSceneBridge::register_instance_handle(Handle mesh_handle) {
    // Resolve o Handle correto da malha no ArboriaMeshRegistry (usando o indice para pegar a geracao correta)
    Handle resolved_mesh_h{};
    if (mesh_handle.index != 0) {
        const RegisteredMeshInfo minfo = ArboriaMeshRegistry::instance().get_mesh_info_by_index(mesh_handle.index);
        if (minfo.handle.is_valid()) resolved_mesh_h = minfo.handle;
    }
    if (!resolved_mesh_h.is_valid()) resolved_mesh_h = mesh_handle;

    // Registra no ArboriaInstanceRegistry (fonte unica de verdade para handles geracionais)
    Handle inst_h = ArboriaInstanceRegistry::instance().register_instance(resolved_mesh_h);
    if (!inst_h.is_valid()) {
        return Handle{};
    }

    // Armazena dados da instancia para compatibilidade com API por ID legado
    uint32_t id = m_next_instance_id++;
    SceneInstanceData inst;
    inst.instance_handle = inst_h;
    inst.mesh_handle = resolved_mesh_h;
    inst.instance_id = id;
    inst.mesh_id = static_cast<int32_t>(resolved_mesh_h.index);
    for (int i = 0; i < 16; ++i) inst.transform_matrix[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    inst.aabb_min[0] = -1.0f; inst.aabb_min[1] = -1.0f; inst.aabb_min[2] = -1.0f;
    inst.aabb_max[0] =  1.0f; inst.aabb_max[1] =  1.0f; inst.aabb_max[2] =  1.0f;
    inst.visible = true;
    m_instances[id] = inst;
    m_id_to_handle[id] = inst_h;

    return inst_h;
}

bool VGSceneBridge::unregister_instance_handle(Handle instance_handle) {
    bool ok = ArboriaInstanceRegistry::instance().unregister_instance(instance_handle);
    // Limpa mapas de compatibilidade com API por ID
    for (auto it = m_id_to_handle.begin(); it != m_id_to_handle.end(); ++it) {
        if (it->second == instance_handle) {
            m_instances.erase(it->first);
            m_id_to_handle.erase(it);
            break;
        }
    }
    return ok;
}

bool VGSceneBridge::set_instance_transform_handle(Handle instance_handle, const float matrix[16]) {
    return ArboriaInstanceRegistry::instance().set_transform(instance_handle, matrix);
}

bool VGSceneBridge::set_instance_visible_handle(Handle instance_handle, bool visible) {
    return ArboriaInstanceRegistry::instance().set_visibility(instance_handle, visible);
}

bool VGSceneBridge::set_instance_lod_handle(Handle instance_handle, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    return ArboriaInstanceRegistry::instance().set_lod_parameters(instance_handle, max_screen_error, lod_mode, forced_lod);
}

SceneInstanceData* VGSceneBridge::get_instance_by_handle(Handle instance_handle) {
    for (auto& pair : m_id_to_handle) {
        if (pair.second == instance_handle) {
            auto it = m_instances.find(pair.first);
            if (it != m_instances.end()) return &it->second;
            break;
        }
    }
    return nullptr;
}

const SceneInstanceData* VGSceneBridge::get_instance_by_handle(Handle instance_handle) const {
    for (auto& pair : m_id_to_handle) {
        if (pair.second == instance_handle) {
            auto it = m_instances.find(pair.first);
            if (it != m_instances.end()) return &it->second;
            break;
        }
    }
    return nullptr;
}

uint32_t VGSceneBridge::register_instance(int32_t mesh_id) {
    // Resolve o Handle da malha no ArboriaMeshRegistry (mesh_id eh o slot index do pool)
    Handle mesh_h{};
    if (mesh_id >= 0) {
        const RegisteredMeshInfo minfo = ArboriaMeshRegistry::instance().get_mesh_info_by_index(
            static_cast<uint32_t>(mesh_id));
        if (minfo.handle.is_valid()) mesh_h = minfo.handle;
    }
    if (!mesh_h.is_valid()) {
        return 0;
    }

    // Registra no ArboriaInstanceRegistry (fonte unica para o GPU scene)
    Handle inst_h = ArboriaInstanceRegistry::instance().register_instance(mesh_h);
    if (!inst_h.is_valid()) {
        return 0;
    }

    uint32_t id = m_next_instance_id++;
    SceneInstanceData inst;
    inst.instance_handle = inst_h;
    inst.mesh_handle = mesh_h;
    inst.instance_id = id;
    inst.mesh_id = mesh_id;
    for (int i = 0; i < 16; ++i) inst.transform_matrix[i] = (i % 5 == 0) ? 1.0f : 0.0f;
    inst.aabb_min[0] = -1.0f; inst.aabb_min[1] = -1.0f; inst.aabb_min[2] = -1.0f;
    inst.aabb_max[0] =  1.0f; inst.aabb_max[1] =  1.0f; inst.aabb_max[2] =  1.0f;
    inst.visible = true;
    m_instances[id] = inst;
    m_id_to_handle[id] = inst_h;
    return id;
}

bool VGSceneBridge::unregister_instance(uint32_t instance_id) {
    bool removed_from_instances = false;
    auto it2 = m_instances.find(instance_id);
    if (it2 != m_instances.end()) {
        m_instances.erase(it2);
        removed_from_instances = true;
    }
    auto it = m_id_to_handle.find(instance_id);
    if (it != m_id_to_handle.end()) {
        ArboriaInstanceRegistry::instance().unregister_instance(it->second);
        m_id_to_handle.erase(it);
    }
    return removed_from_instances;
}

bool VGSceneBridge::set_instance_transform(uint32_t instance_id, const float matrix[16]) {
    auto it = m_id_to_handle.find(instance_id);
    if (it != m_id_to_handle.end()) {
        ArboriaInstanceRegistry::instance().set_transform(it->second, matrix);
    }
    auto it2 = m_instances.find(instance_id);
    if (it2 != m_instances.end()) {
        std::memcpy(it2->second.transform_matrix, matrix, sizeof(float) * 16);
        return true;
    }
    return false;
}

bool VGSceneBridge::set_instance_visible(uint32_t instance_id, bool visible) {
    auto it = m_id_to_handle.find(instance_id);
    if (it != m_id_to_handle.end()) {
        ArboriaInstanceRegistry::instance().set_visibility(it->second, visible);
    }
    auto it2 = m_instances.find(instance_id);
    if (it2 != m_instances.end()) {
        it2->second.visible = visible;
        return true;
    }
    return false;
}

bool VGSceneBridge::set_instance_lod_params(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    auto it = m_id_to_handle.find(instance_id);
    if (it != m_id_to_handle.end()) {
        ArboriaInstanceRegistry::instance().set_lod_parameters(it->second, max_screen_error, lod_mode, forced_lod);
    }
    auto it2 = m_instances.find(instance_id);
    if (it2 != m_instances.end()) {
        it2->second.max_screen_error = max_screen_error;
        it2->second.lod_mode = lod_mode;
        it2->second.forced_lod = forced_lod;
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
    std::vector<SceneInstanceData> result;
    result.reserve(m_instances.size());
    for (const auto& pair : m_instances) {
        if (pair.second.visible) {
            result.push_back(pair.second);
        }
    }
    return result;
}

void VGSceneBridge::clear() {
    // Limpa o registro unificado
    ArboriaInstanceRegistry::instance().clear();
    m_instances.clear();
    m_id_to_handle.clear();
    m_next_instance_id = 1;
}

} // namespace Arboria

extern "C" {
ARBORIA_API uint32_t arboria_scene_create_instance(int32_t mesh_id) {
    return Arboria::VGSceneBridge::instance().register_instance(mesh_id);
}

ARBORIA_API int arboria_scene_destroy_instance(uint32_t instance_id) {
    return Arboria::VGSceneBridge::instance().unregister_instance(instance_id) ? 1 : 0;
}

ARBORIA_API int arboria_scene_set_transform(uint32_t instance_id, const float matrix[16]) {
    return Arboria::VGSceneBridge::instance().set_instance_transform(instance_id, matrix) ? 1 : 0;
}

ARBORIA_API int arboria_scene_set_visible(uint32_t instance_id, int visible) {
    return Arboria::VGSceneBridge::instance().set_instance_visible(instance_id, visible != 0) ? 1 : 0;
}

ARBORIA_API int arboria_scene_set_lod(uint32_t instance_id, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    return Arboria::VGSceneBridge::instance().set_instance_lod_params(instance_id, max_screen_error, lod_mode, forced_lod) ? 1 : 0;
}

ARBORIA_API uint32_t arboria_scene_get_active_count() {
    return static_cast<uint32_t>(Arboria::VGSceneBridge::instance().get_instance_count());
}
}
