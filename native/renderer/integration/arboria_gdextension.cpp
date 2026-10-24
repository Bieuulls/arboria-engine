#include "../core/arboria_types.h"
#include "../core/arboria_runtime.h"
#include "../core/arboria_security.h"
#include "../scene/arboria_render_world.h"
#include "arboria_scene_bridge.h"
#include "arboria_abi.h"
#include "../core/gdextension_interface.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <string>

static GDExtensionInterfaceClassdbRegisterExtensionClass6 s_reg_class6 = nullptr;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod s_reg_method = nullptr;

class ArboriaNativeCoreInstance {
public:
    int id = 777;
};

static GDExtensionObjectPtr arboria_create_instance(void *p_class_userdata, GDExtensionBool p_notify_postinitialize) {
    auto c_obj = (GDExtensionInterfaceClassdbConstructObject2)Arboria::ABI::get_proc_address("classdb_construct_object2");
    auto set_inst = (GDExtensionInterfaceObjectSetInstance)Arboria::ABI::get_proc_address("object_set_instance");
    
    Arboria::StringName parent_sname("RefCounted");
    Arboria::StringName class_sname("ArboriaNativeCore");
    
    GDExtensionObjectPtr obj = c_obj(parent_sname.ptr());
    ArboriaNativeCoreInstance* inst = new ArboriaNativeCoreInstance();
    set_inst(obj, class_sname.ptr(), inst);
    return obj;
}

static void arboria_free_instance(void *p_class_userdata, GDExtensionClassInstancePtr p_instance) {
    delete (ArboriaNativeCoreInstance*)p_instance;
}

// Helper tipado para registro de metodos sem buffers soltos
static void register_method(
    GDExtensionClassLibraryPtr lib,
    GDExtensionConstStringNamePtr class_name,
    const char* method_name,
    GDExtensionClassMethodCall call_fn,
    GDExtensionVariantType return_type = GDEXTENSION_VARIANT_TYPE_NIL,
    bool has_return = false,
    uint32_t arg_count = 0,
    const GDExtensionVariantType* arg_types = nullptr,
    const char** arg_names = nullptr
) {
    if (!s_reg_method) return;

    Arboria::StringName m_name(method_name);
    Arboria::StringName empty_sname("");
    Arboria::String empty_str("");

    GDExtensionPropertyInfo ret_info = {};
    if (has_return) {
        ret_info.type = return_type;
        ret_info.name = empty_sname.ptr();
        ret_info.class_name = empty_sname.ptr();
        ret_info.hint = 0;
        ret_info.hint_string = empty_str.ptr();
        ret_info.usage = 6;
    }

    std::vector<GDExtensionPropertyInfo> args_info(arg_count);
    std::vector<Arboria::StringName> arg_names_storage;
    arg_names_storage.reserve(arg_count);
    std::vector<GDExtensionClassMethodArgumentMetadata> args_meta(arg_count, GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);

    for (uint32_t i = 0; i < arg_count; ++i) {
        arg_names_storage.emplace_back(arg_names ? arg_names[i] : "arg");
        args_info[i].type = arg_types[i];
        args_info[i].name = arg_names_storage.back().ptr();
        args_info[i].class_name = empty_sname.ptr();
        args_info[i].hint = 0;
        args_info[i].hint_string = empty_str.ptr();
        args_info[i].usage = 6;
    }

    GDExtensionClassMethodInfo minfo = {};
    minfo.name = m_name.ptr();
    minfo.method_userdata = nullptr;
    minfo.call_func = call_fn;
    minfo.ptrcall_func = nullptr;
    minfo.method_flags = GDEXTENSION_METHOD_FLAG_NORMAL;
    minfo.has_return_value = has_return ? 1 : 0;
    minfo.return_value_info = has_return ? &ret_info : nullptr;
    minfo.return_value_metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    minfo.argument_count = arg_count;
    minfo.arguments_info = arg_count > 0 ? args_info.data() : nullptr;
    minfo.arguments_metadata = arg_count > 0 ? args_meta.data() : nullptr;
    minfo.default_argument_count = 0;
    minfo.default_arguments = nullptr;

    s_reg_method(lib, class_name, &minfo);
}

// ============================================================================
// ETAPA 1 — API OFICIAL TIPADA COM CONTROLE DE GERAÇÃO
// ============================================================================

// 1. initialize() -> bool
static void call_initialize(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    bool ok = Arboria::VGRuntime::instance().initialize();
    uint8_t b = ok ? 1 : 0;
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &b);
}

// 2. register_mesh(path: String) -> int64 (Handle uint64)
static void call_register_mesh(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle_val = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_string) {
        Arboria::String path_str;
        Arboria::ABI::to_string(path_str.ptr(), const_cast<GDExtensionVariantPtr>(p_args[0]));
        std::string path = path_str.to_utf8();
        if (!path.empty()) {
            Arboria::Handle h = Arboria::VGRuntime::instance().register_mesh_handle(path);
            handle_val = static_cast<int64_t>(h.to_u64());
        }
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &handle_val);
}

// 3. unregister_mesh(mesh_handle: int64) -> bool
static void call_unregister_mesh(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t h_val = 0;
        Arboria::ABI::to_int(&h_val, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(h_val));
        ok = Arboria::VGRuntime::instance().unregister_mesh_handle(h) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

// 4. register_instance(mesh_handle: int64) -> int64 (Handle uint64)
static void call_register_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t handle_val = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t mesh_h_val = 0;
        Arboria::ABI::to_int(&mesh_h_val, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle mesh_h = Arboria::Handle::from_u64(static_cast<uint64_t>(mesh_h_val));
        Arboria::Handle inst_h = Arboria::VGSceneBridge::instance().register_instance_handle(mesh_h);
        handle_val = static_cast<int64_t>(inst_h.to_u64());
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &handle_val);
}

// 5. update_instance(instance_handle: int64, transform: Transform3D, max_screen_error: float, lod_mode: int, forced_lod: int) -> bool
static void call_update_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 5 && Arboria::ABI::to_int && Arboria::ABI::to_float) {
        int64_t inst_h_val = 0;
        Arboria::ABI::to_int(&inst_h_val, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle inst_h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_h_val));

        float matrix[16] = {0};
        matrix[0] = 1.0f; matrix[5] = 1.0f; matrix[10] = 1.0f; matrix[15] = 1.0f;
        if (Arboria::ABI::to_transform3d) {
            float xform_raw[12] = {0};
            Arboria::ABI::to_transform3d(xform_raw, const_cast<GDExtensionVariantPtr>(p_args[1]));
            matrix[0] = xform_raw[0]; matrix[1] = xform_raw[1]; matrix[2] = xform_raw[2]; matrix[3] = 0.0f;
            matrix[4] = xform_raw[3]; matrix[5] = xform_raw[4]; matrix[6] = xform_raw[5]; matrix[7] = 0.0f;
            matrix[8] = xform_raw[6]; matrix[9] = xform_raw[7]; matrix[10] = xform_raw[8]; matrix[11] = 0.0f;
            matrix[12] = xform_raw[9]; matrix[13] = xform_raw[10]; matrix[14] = xform_raw[11]; matrix[15] = 1.0f;
        }

        double max_err = 1.5;
        Arboria::ABI::to_float(&max_err, const_cast<GDExtensionVariantPtr>(p_args[2]));

        int64_t lod_mode = 0;
        Arboria::ABI::to_int(&lod_mode, const_cast<GDExtensionVariantPtr>(p_args[3]));

        int64_t forced_lod = 0;
        Arboria::ABI::to_int(&forced_lod, const_cast<GDExtensionVariantPtr>(p_args[4]));

        bool t_ok = Arboria::VGSceneBridge::instance().set_instance_transform_handle(inst_h, matrix);
        bool l_ok = Arboria::VGSceneBridge::instance().set_instance_lod_handle(inst_h, static_cast<float>(max_err), static_cast<uint32_t>(lod_mode), static_cast<uint32_t>(forced_lod));
        ok = (t_ok && l_ok) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

// 6. release_instance(instance_handle: int64) -> bool
static void call_release_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t inst_h_val = 0;
        Arboria::ABI::to_int(&inst_h_val, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle inst_h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_h_val));
        ok = Arboria::VGSceneBridge::instance().unregister_instance_handle(inst_h) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

// 7. update_camera(cam_view_proj: Projection, cam_pos: Vector3, viewport_size: Vector2) -> bool
static void call_update_camera(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 1;
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

// 8. render_frame(...) -> Dictionary
static void call_render_frame(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    static bool s_logged = false;
    if (!s_logged) {
        s_logged = true;
        std::cout << "[Arboria C++ render_frame] Caminho C++ acionado: CompositorEffect ativo, Instancias RenderWorld = "
                  << Arboria::ArboriaRenderWorld::instance().get_active_instance_count()
                  << ", Malhas = " << Arboria::ArboriaRenderWorld::instance().get_registered_mesh_count()
                  << ", Instancias SceneBridge = " << Arboria::VGSceneBridge::instance().get_instance_count()
                  << std::endl;
    }
    Arboria::Dictionary d;
    d.set("status", "OK");
    d.set("active_instances", static_cast<int64_t>(Arboria::VGSceneBridge::instance().get_instance_count()));
    d.to_variant(r_return);
}

// 9. get_statistics() -> Dictionary
static void call_get_statistics(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    Arboria::Dictionary d;
    d.set("total_meshes", static_cast<int64_t>(Arboria::VGRuntime::instance().get_active_mesh_count()));
    d.set("total_instances", static_cast<int64_t>(Arboria::VGSceneBridge::instance().get_instance_count()));
    d.set("version", Arboria::VGRuntime::instance().get_version_string());
    d.to_variant(r_return);
}

// 10. shutdown() -> void
static void call_shutdown(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    Arboria::VGSceneBridge::instance().clear();
    Arboria::VGRuntime::instance().shutdown();
}

// ============================================================================
// METODOS DE COMPATIBILIDADE (LEGADO / GADGETS DO PROJETO EXISTENTE)
// ============================================================================

static void call_is_active(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t val = 1;
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &val);
}

static void call_get_version(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    const char* ver = Arboria::VGRuntime::instance().get_version_string();
    if (Arboria::ABI::from_string && Arboria::ABI::string_new_utf8) {
        Arboria::String s(ver);
        Arboria::ABI::from_string(r_return, s.ptr());
    }
}

static void call_load_mesh(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t mesh_id = -1;
    if (p_argument_count >= 1 && Arboria::ABI::to_string) {
        Arboria::String str_raw;
        Arboria::ABI::to_string(str_raw.ptr(), const_cast<GDExtensionVariantPtr>(p_args[0]));
        std::string path = str_raw.to_utf8();
        mesh_id = Arboria::VGRuntime::instance().register_mesh(path);
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &mesh_id);
}

static void call_get_mesh_clusters_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t m_id = 0;
        Arboria::ABI::to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().clusters);
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &count);
}

static void call_get_mesh_vertices_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t m_id = 0;
        Arboria::ABI::to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().vertices);
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &count);
}

static void call_get_mesh_triangles_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t m_id = 0;
        Arboria::ABI::to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().triangles);
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &count);
}

static void call_scene_create_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t inst_id = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t m_id = 0;
        Arboria::ABI::to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        inst_id = Arboria::VGSceneBridge::instance().register_instance(static_cast<int32_t>(m_id));
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &inst_id);
}

static void call_scene_destroy_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        ok = Arboria::VGSceneBridge::instance().unregister_instance(static_cast<uint32_t>(inst_id)) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_scene_set_transform_components(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 13 && Arboria::ABI::to_int && Arboria::ABI::to_float) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        float m[16] = {0};
        for (int i = 0; i < 12; ++i) {
            double v = 0.0;
            Arboria::ABI::to_float(&v, const_cast<GDExtensionVariantPtr>(p_args[1 + i]));
            m[i] = static_cast<float>(v);
        }
        m[15] = 1.0f;
        ok = Arboria::VGSceneBridge::instance().set_instance_transform(static_cast<uint32_t>(inst_id), m) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_scene_set_lod(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 4 && Arboria::ABI::to_int && Arboria::ABI::to_float) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        double max_err = 1.5;
        Arboria::ABI::to_float(&max_err, const_cast<GDExtensionVariantPtr>(p_args[1]));
        int64_t lod_mode = 0, forced_lod = 0;
        Arboria::ABI::to_int(&lod_mode, const_cast<GDExtensionVariantPtr>(p_args[2]));
        Arboria::ABI::to_int(&forced_lod, const_cast<GDExtensionVariantPtr>(p_args[3]));
        ok = Arboria::VGSceneBridge::instance().set_instance_lod_params(static_cast<uint32_t>(inst_id), static_cast<float>(max_err), static_cast<uint32_t>(lod_mode), static_cast<uint32_t>(forced_lod)) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_scene_set_visible(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 2 && Arboria::ABI::to_int && Arboria::ABI::to_bool) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        uint8_t vis_u8 = 1;
        Arboria::ABI::to_bool(&vis_u8, const_cast<GDExtensionVariantPtr>(p_args[1]));
        bool vis = (vis_u8 != 0);
        ok = Arboria::VGSceneBridge::instance().set_instance_visible(static_cast<uint32_t>(inst_id), vis) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_scene_get_active_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = static_cast<int64_t>(Arboria::VGSceneBridge::instance().get_instance_count());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &count);
}

static void call_get_engine_signature(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    const char* sig = arboria_get_engine_signature();
    if (Arboria::ABI::from_string && Arboria::ABI::string_new_utf8) {
        Arboria::String s(sig);
        Arboria::ABI::from_string(r_return, s.ptr());
    }
}

static void call_get_engine_license_hash(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    const char* lhash = arboria_get_engine_license_hash();
    if (Arboria::ABI::from_string && Arboria::ABI::string_new_utf8) {
        Arboria::String s(lhash);
        Arboria::ABI::from_string(r_return, s.ptr());
    }
}

static void call_verify_engine_integrity(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = arboria_verify_engine_integrity() ? 1 : 0;
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static bool call_variant_method(
    GDExtensionVariantPtr p_target,
    const char* method_name,
    const GDExtensionConstVariantPtr* p_args,
    int p_arg_count,
    GDExtensionVariantPtr r_ret
) {
    if (!Arboria::ABI::variant_call || !p_target) return false;
    Arboria::StringName m_sname(method_name);

    alignas(8) uint8_t dummy_ret[24] = {0};
    GDExtensionVariantPtr target_ret = r_ret ? r_ret : dummy_ret;

    GDExtensionCallError err{};
    Arboria::ABI::variant_call(p_target, m_sname.ptr(), p_args, p_arg_count, target_ret, &err);
    if (err.error != GDEXTENSION_CALL_OK) {
        std::cerr << "[Arboria C++] Method '" << method_name 
                  << "' failed! Error: " << (int)err.error 
                  << ", arg: " << err.argument 
                  << ", expected: " << err.expected << std::endl;
        return false;
    }
    return true;
}

static Arboria::GPUDriverContext get_driver_context(GDExtensionVariantPtr rd) {
    Arboria::GPUDriverContext ctx{};
    ctx.call_method = call_variant_method;
    ctx.get_indexed = Arboria::ABI::variant_get_indexed;
    ctx.from_int = Arboria::ABI::from_int;
    ctx.from_bool = Arboria::ABI::from_bool;
    ctx.to_int = Arboria::ABI::to_int;
    ctx.rd = rd;
    return ctx;
}

static void call_dispatch_compute_native(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 4) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        const void* comp_pipe = p_args[1];
        const void* u_set = p_args[2];
        int64_t gx = 1;
        if (Arboria::ABI::to_int) Arboria::ABI::to_int(&gx, const_cast<GDExtensionVariantPtr>(p_args[3]));
        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGComputeDispatch::dispatch_cull_clusters_native(ctx, comp_pipe, u_set, gx) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_draw_indirect_native(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 5) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        const void* fb = p_args[1];
        const void* rast_pipe = p_args[2];
        const void* u_set = p_args[3];
        const void* cnt_buf = p_args[4];
        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGIndirectRenderer::draw_indirect_native(ctx, fb, rast_pipe, u_set, cnt_buf) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_render_scene_batch(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 10) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        const void* fb = p_args[1];
        const void* comp_pipe = p_args[2];
        const void* rast_pipe = p_args[3];
        const void* comp_sets = p_args[4];
        const void* gx_arr = p_args[5];
        const void* rast_sets = p_args[6];
        const void* cnt_bufs = p_args[7];
        int64_t count = 0;
        if (Arboria::ABI::to_int) Arboria::ABI::to_int(&count, const_cast<GDExtensionVariantPtr>(p_args[8]));
        const void* colors = p_args[9];

        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGRuntime::instance().render_scene_native(
            ctx, fb, comp_pipe, rast_pipe, comp_sets, gx_arr, rast_sets, cnt_bufs, count, colors
        ) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_render_scene_global(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 8) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        const void* fb = p_args[1];
        const void* comp_pipe = p_args[2];
        const void* rast_pipe = p_args[3];
        const void* comp_set = p_args[4];
        const void* rast_set = p_args[5];
        const void* indirect_buf = p_args[6];
        int64_t total_work = 0;
        if (Arboria::ABI::to_int) Arboria::ABI::to_int(&total_work, const_cast<GDExtensionVariantPtr>(p_args[7]));
        const void* colors = (p_argument_count >= 9) ? p_args[8] : nullptr;

        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::ArboriaRenderWorld::instance().render_scene_global(
            ctx, fb, comp_pipe, rast_pipe, comp_set, rast_set, indirect_buf, static_cast<uint32_t>(total_work), colors
        ) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_memory_set_budget(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t b = 0;
        Arboria::ABI::to_int(&b, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::ArboriaRenderWorld::instance().memory_set_budget(static_cast<size_t>(b));
    }
}

static void call_memory_get_budget(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t b = static_cast<int64_t>(Arboria::ArboriaRenderWorld::instance().memory_get_budget());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &b);
}

static void call_memory_get_resident_bytes(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t b = static_cast<int64_t>(Arboria::ArboriaRenderWorld::instance().memory_get_resident_bytes());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &b);
}

static void call_memory_get_allocated_bytes(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t b = static_cast<int64_t>(Arboria::ArboriaRenderWorld::instance().memory_get_allocated_bytes());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &b);
}

static void call_memory_get_page_faults(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t pf = static_cast<int64_t>(Arboria::ArboriaRenderWorld::instance().memory_get_page_faults());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &pf);
}

static void call_memory_get_evictions(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t ev = static_cast<int64_t>(Arboria::ArboriaRenderWorld::instance().memory_get_evictions());
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &ev);
}

static void call_streaming_update(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    if (p_argument_count >= 2 && Arboria::ABI::to_vector3 && Arboria::ABI::to_int) {
        float pos[3] = {0, 0, 0};
        Arboria::ABI::to_vector3(pos, const_cast<GDExtensionVariantPtr>(p_args[0]));
        int64_t frame = 0;
        Arboria::ABI::to_int(&frame, const_cast<GDExtensionVariantPtr>(p_args[1]));
        Arboria::ArboriaRenderWorld::instance().streaming_update(pos, static_cast<uint64_t>(frame));
    }
}

// ============================================================================
// GEOMETRIA MUTÁVEL VIRTUALIZADA (OPERAÇÃO MUTABLE GEOMETRY)
// ============================================================================

static void call_mutable_apply_depression(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t modified = 0;
    if (p_argument_count >= 5 && Arboria::ABI::to_int && Arboria::ABI::to_vector3 && Arboria::ABI::to_float && Arboria::ABI::to_bool) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        float center[3] = {0, 0, 0};
        Arboria::ABI::to_vector3(center, const_cast<GDExtensionVariantPtr>(p_args[1]));
        double radius = 0.5;
        Arboria::ABI::to_float(&radius, const_cast<GDExtensionVariantPtr>(p_args[2]));
        double depth = 0.1;
        Arboria::ABI::to_float(&depth, const_cast<GDExtensionVariantPtr>(p_args[3]));
        uint8_t subdivide = 1;
        Arboria::ABI::to_bool(&subdivide, const_cast<GDExtensionVariantPtr>(p_args[4]));

        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        modified = Arboria::ArboriaRenderWorld::instance().apply_depression(
            h, center, static_cast<float>(radius), static_cast<float>(depth), subdivide != 0
        );
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &modified);
}

static void call_mutable_rebuild_dag(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        auto stats = Arboria::ArboriaRenderWorld::instance().rebuild_dag_incremental(h);
        count = stats.modified_lod0_clusters;
    }
    if (Arboria::ABI::from_int) Arboria::ABI::from_int(r_return, &count);
}

static void call_mutable_export_obj(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 2 && Arboria::ABI::to_int && Arboria::ABI::to_string) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        Arboria::String s_raw;
        Arboria::ABI::to_string(s_raw.ptr(), const_cast<GDExtensionVariantPtr>(p_args[1]));
        std::string filepath = s_raw.to_utf8();
        ok = Arboria::ArboriaRenderWorld::instance().export_instance_to_obj(h, filepath) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_mutable_save(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 2 && Arboria::ABI::to_int && Arboria::ABI::to_string) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        Arboria::String s_raw;
        Arboria::ABI::to_string(s_raw.ptr(), const_cast<GDExtensionVariantPtr>(p_args[1]));
        std::string filepath = s_raw.to_utf8();
        ok = Arboria::ArboriaRenderWorld::instance().save_mutable_overlay(h, filepath) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_mutable_load(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 2 && Arboria::ABI::to_int && Arboria::ABI::to_string) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        Arboria::String s_raw;
        Arboria::ABI::to_string(s_raw.ptr(), const_cast<GDExtensionVariantPtr>(p_args[1]));
        std::string filepath = s_raw.to_utf8();
        ok = Arboria::ArboriaRenderWorld::instance().load_mutable_overlay(h, filepath) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

static void call_mutable_has_geometry(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 1 && Arboria::ABI::to_int) {
        int64_t inst_id = 0;
        Arboria::ABI::to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        Arboria::Handle h = Arboria::Handle::from_u64(static_cast<uint64_t>(inst_id));
        ok = Arboria::ArboriaRenderWorld::instance().has_mutable_geometry(h) ? 1 : 0;
    }
    if (Arboria::ABI::from_bool) Arboria::ABI::from_bool(r_return, &ok);
}

// ============================================================================
// INICIALIZAÇÃO DA EXTENSÃO NO GODOT
// ============================================================================

static void arboria_gdextension_initialize(void* userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        Arboria::VGRuntime::instance().initialize();
        Arboria::ArboriaRenderWorld::instance().initialize();
        std::cout << "[Arboria GDExtension] Backend Nativo ARBORIA V7 vinculado com sucesso ao Godot Forward+." << std::endl;
        
        if (Arboria::ABI::get_proc_address) {
            s_reg_class6 = (GDExtensionInterfaceClassdbRegisterExtensionClass6)Arboria::ABI::get_proc_address("classdb_register_extension_class6");
            s_reg_method = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)Arboria::ABI::get_proc_address("classdb_register_extension_class_method");
            
            if (s_reg_class6 && Arboria::ABI::string_name_new_utf8) {
                Arboria::StringName class_name("ArboriaNativeCore");
                Arboria::StringName parent_name("RefCounted");
                
                GDExtensionClassCreationInfo6 info = {};
                info.is_virtual = false;
                info.is_abstract = false;
                info.is_exposed = true;
                info.is_runtime = true;
                info.create_instance_func = arboria_create_instance;
                info.free_instance_func = arboria_free_instance;
                info.class_userdata = nullptr;
                
                s_reg_class6(Arboria::ABI::library, class_name.ptr(), parent_name.ptr(), &info);
                std::cout << "[Arboria GDExtension] Classe 'ArboriaNativeCore' registrada com sucesso no ClassDB." << std::endl;

                if (s_reg_method) {
                    GDExtensionClassLibraryPtr lib = Arboria::ABI::library;
                    GDExtensionConstStringNamePtr cname = class_name.ptr();

                    // --------------------------------------------------------
                    // API OFICIAL TIPADA COM CONTROLE DE GERAÇÃO (ETAPA 1)
                    // --------------------------------------------------------
                    register_method(lib, cname, "initialize", call_initialize, GDEXTENSION_VARIANT_TYPE_BOOL, true);

                    GDExtensionVariantType arg_str[] = { GDEXTENSION_VARIANT_TYPE_STRING };
                    const char* name_str[] = { "path" };
                    register_method(lib, cname, "register_mesh", call_register_mesh, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_str, name_str);

                    GDExtensionVariantType arg_int[] = { GDEXTENSION_VARIANT_TYPE_INT };
                    const char* name_h[] = { "mesh_handle" };
                    register_method(lib, cname, "unregister_mesh", call_unregister_mesh, GDEXTENSION_VARIANT_TYPE_BOOL, true, 1, arg_int, name_h);

                    register_method(lib, cname, "register_instance", call_register_instance, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_h);

                    GDExtensionVariantType args_upd[] = {
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_TRANSFORM3D,
                        GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_INT
                    };
                    const char* names_upd[] = { "instance_handle", "transform", "max_screen_error", "lod_mode", "forced_lod" };
                    register_method(lib, cname, "update_instance", call_update_instance, GDEXTENSION_VARIANT_TYPE_BOOL, true, 5, args_upd, names_upd);

                    const char* name_inst_h[] = { "instance_handle" };
                    register_method(lib, cname, "release_instance", call_release_instance, GDEXTENSION_VARIANT_TYPE_BOOL, true, 1, arg_int, name_inst_h);

                    GDExtensionVariantType args_cam[] = {
                        GDEXTENSION_VARIANT_TYPE_PROJECTION,
                        GDEXTENSION_VARIANT_TYPE_VECTOR3,
                        GDEXTENSION_VARIANT_TYPE_VECTOR2
                    };
                    const char* names_cam[] = { "cam_view_proj", "cam_pos", "viewport_size" };
                    register_method(lib, cname, "update_camera", call_update_camera, GDEXTENSION_VARIANT_TYPE_BOOL, true, 3, args_cam, names_cam);

                    register_method(lib, cname, "render_frame", call_render_frame, GDEXTENSION_VARIANT_TYPE_DICTIONARY, true);
                    register_method(lib, cname, "get_statistics", call_get_statistics, GDEXTENSION_VARIANT_TYPE_DICTIONARY, true);
                    register_method(lib, cname, "shutdown", call_shutdown, GDEXTENSION_VARIANT_TYPE_NIL, false);

                    // --------------------------------------------------------
                    // MÉTODOS DE COMPATIBILIDADE ANTERIOR
                    // --------------------------------------------------------
                    register_method(lib, cname, "is_active", call_is_active, GDEXTENSION_VARIANT_TYPE_BOOL, true);
                    register_method(lib, cname, "get_version", call_get_version, GDEXTENSION_VARIANT_TYPE_STRING, true);
                    register_method(lib, cname, "load_mesh", call_load_mesh, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_str, name_str);
                    register_method(lib, cname, "get_mesh_clusters_count", call_get_mesh_clusters_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_str);
                    register_method(lib, cname, "get_mesh_vertices_count", call_get_mesh_vertices_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_str);
                    register_method(lib, cname, "get_mesh_triangles_count", call_get_mesh_triangles_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_str);
                    register_method(lib, cname, "scene_create_instance", call_scene_create_instance, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_str);
                    register_method(lib, cname, "scene_destroy_instance", call_scene_destroy_instance, GDEXTENSION_VARIANT_TYPE_BOOL, true, 1, arg_int, name_inst_h);

                    GDExtensionVariantType args_xform[] = {
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_FLOAT
                    };
                    const char* names_xform[] = {
                        "instance_id", "m0", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m9", "m10", "m11"
                    };
                    register_method(lib, cname, "scene_set_transform_components", call_scene_set_transform_components, GDEXTENSION_VARIANT_TYPE_BOOL, true, 13, args_xform, names_xform);

                    GDExtensionVariantType args_lod[] = {
                        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT
                    };
                    const char* names_lod[] = { "instance_id", "max_screen_error", "lod_mode", "forced_lod" };
                    register_method(lib, cname, "scene_set_lod", call_scene_set_lod, GDEXTENSION_VARIANT_TYPE_BOOL, true, 4, args_lod, names_lod);

                    GDExtensionVariantType args_vis[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_BOOL };
                    const char* names_vis[] = { "instance_id", "visible" };
                    register_method(lib, cname, "scene_set_visible", call_scene_set_visible, GDEXTENSION_VARIANT_TYPE_BOOL, true, 2, args_vis, names_vis);
                    register_method(lib, cname, "scene_get_active_count", call_scene_get_active_count, GDEXTENSION_VARIANT_TYPE_INT, true);

                    // Segurança & Autenticidade
                    register_method(lib, cname, "get_engine_signature", call_get_engine_signature, GDEXTENSION_VARIANT_TYPE_STRING, true);
                    register_method(lib, cname, "get_engine_license_hash", call_get_engine_license_hash, GDEXTENSION_VARIANT_TYPE_STRING, true);
                    register_method(lib, cname, "verify_engine_integrity", call_verify_engine_integrity, GDEXTENSION_VARIANT_TYPE_BOOL, true);

                    // Passes nativos GPU
                    GDExtensionVariantType args_comp[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_INT
                    };
                    const char* names_comp[] = { "rd", "compute_pipeline", "uniform_set", "groups_x" };
                    register_method(lib, cname, "dispatch_compute_native", call_dispatch_compute_native, GDEXTENSION_VARIANT_TYPE_BOOL, true, 4, args_comp, names_comp);

                    GDExtensionVariantType args_draw[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID
                    };
                    const char* names_draw[] = { "rd", "framebuffer", "raster_pipeline", "uniform_set", "counter_buffer" };
                    register_method(lib, cname, "draw_indirect_native", call_draw_indirect_native, GDEXTENSION_VARIANT_TYPE_BOOL, true, 5, args_draw, names_draw);

                    GDExtensionVariantType args_batch[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_ARRAY,
                        GDEXTENSION_VARIANT_TYPE_ARRAY,
                        GDEXTENSION_VARIANT_TYPE_ARRAY,
                        GDEXTENSION_VARIANT_TYPE_ARRAY,
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY
                    };
                    const char* names_batch[] = {
                        "rd", "framebuffer", "compute_pipeline", "raster_pipeline",
                        "compute_sets", "groups_x", "raster_sets", "counter_bufs", "count",
                        "initial_colors"
                    };
                    register_method(lib, cname, "render_scene_batch", call_render_scene_batch, GDEXTENSION_VARIANT_TYPE_BOOL, true, 10, args_batch, names_batch);

                    GDExtensionVariantType args_global[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_PACKED_COLOR_ARRAY
                    };
                    const char* names_global[] = {
                        "rd", "framebuffer", "compute_pipeline", "raster_pipeline",
                        "compute_uniform_set", "raster_uniform_set", "indirect_args_buffer",
                        "total_work_items", "initial_colors"
                    };
                    register_method(lib, cname, "render_scene_global", call_render_scene_global, GDEXTENSION_VARIANT_TYPE_BOOL, true, 9, args_global, names_global);

                    GDExtensionVariantType arg_budget[] = { GDEXTENSION_VARIANT_TYPE_INT };
                    const char* name_budget[] = { "bytes" };
                    register_method(lib, cname, "memory_set_budget", call_memory_set_budget, GDEXTENSION_VARIANT_TYPE_NIL, false, 1, arg_budget, name_budget);
                    register_method(lib, cname, "memory_get_budget", call_memory_get_budget, GDEXTENSION_VARIANT_TYPE_INT, true, 0, nullptr, nullptr);
                    register_method(lib, cname, "memory_get_resident_bytes", call_memory_get_resident_bytes, GDEXTENSION_VARIANT_TYPE_INT, true, 0, nullptr, nullptr);
                    register_method(lib, cname, "memory_get_allocated_bytes", call_memory_get_allocated_bytes, GDEXTENSION_VARIANT_TYPE_INT, true, 0, nullptr, nullptr);
                    register_method(lib, cname, "memory_get_page_faults", call_memory_get_page_faults, GDEXTENSION_VARIANT_TYPE_INT, true, 0, nullptr, nullptr);
                    register_method(lib, cname, "memory_get_evictions", call_memory_get_evictions, GDEXTENSION_VARIANT_TYPE_INT, true, 0, nullptr, nullptr);

                    GDExtensionVariantType args_streaming[] = { GDEXTENSION_VARIANT_TYPE_VECTOR3, GDEXTENSION_VARIANT_TYPE_INT };
                    const char* names_streaming[] = { "camera_pos", "frame" };
                    register_method(lib, cname, "streaming_update", call_streaming_update, GDEXTENSION_VARIANT_TYPE_NIL, false, 2, args_streaming, names_streaming);

                    // Geometria Mutavel Virtualizada (OPERACAO MUTABLE GEOMETRY)
                    GDExtensionVariantType args_sculpt[] = {
                        GDEXTENSION_VARIANT_TYPE_INT,
                        GDEXTENSION_VARIANT_TYPE_VECTOR3,
                        GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_FLOAT,
                        GDEXTENSION_VARIANT_TYPE_BOOL
                    };
                    const char* names_sculpt[] = { "instance_handle", "center", "radius", "depth", "subdivide" };
                    register_method(lib, cname, "mutable_apply_depression", call_mutable_apply_depression, GDEXTENSION_VARIANT_TYPE_INT, true, 5, args_sculpt, names_sculpt);

                    const char* name_inst_only[] = { "instance_handle" };
                    register_method(lib, cname, "mutable_rebuild_dag", call_mutable_rebuild_dag, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_budget, name_inst_only);

                    GDExtensionVariantType args_path[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_STRING };
                    const char* names_path[] = { "instance_handle", "filepath" };
                    register_method(lib, cname, "mutable_export_obj", call_mutable_export_obj, GDEXTENSION_VARIANT_TYPE_BOOL, true, 2, args_path, names_path);
                    register_method(lib, cname, "mutable_save", call_mutable_save, GDEXTENSION_VARIANT_TYPE_BOOL, true, 2, args_path, names_path);
                    register_method(lib, cname, "mutable_load", call_mutable_load, GDEXTENSION_VARIANT_TYPE_BOOL, true, 2, args_path, names_path);
                    register_method(lib, cname, "mutable_has_geometry", call_mutable_has_geometry, GDEXTENSION_VARIANT_TYPE_BOOL, true, 1, arg_budget, name_inst_only);

                    std::cout << "[Arboria GDExtension] Metodos de 'ArboriaNativeCore' registrados com sucesso no ClassDB (GPU Scene Global + API Tipada + Streaming/Memoria + Mutable Geometry)." << std::endl;
                }
            }
        }
    }
}

static void arboria_gdextension_deinitialize(void* userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        Arboria::ArboriaRenderWorld::instance().shutdown();
        Arboria::VGSceneBridge::instance().clear();
        Arboria::VGRuntime::instance().shutdown();
        std::cout << "[Arboria GDExtension] Backend Nativo ARBORIA V7 desvinculado com sucesso." << std::endl;
    }
}

ARBORIA_API GDExtensionBool arboria_native_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization* r_initialization
) {
    if (!r_initialization) return 0;
    Arboria::ABI::init(p_get_proc_address, p_library);
    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->userdata = nullptr;
    r_initialization->initialize = arboria_gdextension_initialize;
    r_initialization->deinitialize = arboria_gdextension_deinitialize;
    return 1;
}
