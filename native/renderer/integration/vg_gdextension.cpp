#include "../core/vg_types.h"
#include "../core/vg_runtime.h"
#include "../core/vg_security.h"
#include "vg_scene_bridge.h"
#include "../core/gdextension_interface.h"
#include <iostream>
#include <vector>
#include <cstring>
#include <string>

static GDExtensionInterfaceGetProcAddress g_get_proc_address = nullptr;
static GDExtensionClassLibraryPtr g_library = nullptr;

// Cache de interfaces do Godot GDExtension
static GDExtensionInterfaceStringNameNewWithUtf8Chars s_string_name_new_utf8 = nullptr;
static GDExtensionInterfaceStringNewWithUtf8Chars s_string_new_utf8 = nullptr;
static GDExtensionInterfaceStringToUtf8Chars s_string_to_utf8 = nullptr;
static GDExtensionInterfaceGetVariantFromTypeConstructor s_get_from_type_c = nullptr;
static GDExtensionInterfaceGetVariantToTypeConstructor s_get_to_type_c = nullptr;

static GDExtensionVariantFromTypeConstructorFunc s_from_bool = nullptr;
static GDExtensionVariantFromTypeConstructorFunc s_from_int = nullptr;
static GDExtensionVariantFromTypeConstructorFunc s_from_string = nullptr;

static GDExtensionTypeFromVariantConstructorFunc s_to_bool = nullptr;
static GDExtensionTypeFromVariantConstructorFunc s_to_int = nullptr;
static GDExtensionTypeFromVariantConstructorFunc s_to_float = nullptr;
static GDExtensionTypeFromVariantConstructorFunc s_to_string = nullptr;

class ArboriaNativeCoreInstance {
public:
    int id = 777;
};

static GDExtensionObjectPtr arboria_create_instance(void *p_class_userdata, GDExtensionBool p_notify_postinitialize) {
    auto c_obj = (GDExtensionInterfaceClassdbConstructObject2)g_get_proc_address("classdb_construct_object2");
    auto set_inst = (GDExtensionInterfaceObjectSetInstance)g_get_proc_address("object_set_instance");
    
    uint8_t parent_sname[32] = {0};
    uint8_t class_sname[32] = {0};
    s_string_name_new_utf8(parent_sname, "RefCounted");
    s_string_name_new_utf8(class_sname, "ArboriaNativeCore");
    
    GDExtensionObjectPtr obj = c_obj(parent_sname);
    ArboriaNativeCoreInstance* inst = new ArboriaNativeCoreInstance();
    set_inst(obj, class_sname, inst);
    return obj;
}

static void arboria_free_instance(void *p_class_userdata, GDExtensionClassInstancePtr p_instance) {
    delete (ArboriaNativeCoreInstance*)p_instance;
}

// ----------------------------------------------------------------------------
// Métodos de ArboriaNativeCore expostos ao Godot ClassDB
// ----------------------------------------------------------------------------

static void call_is_active(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t val = 1;
    if (s_from_bool) s_from_bool(r_return, &val);
}

static void call_get_version(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    const char* ver = Arboria::VGRuntime::instance().get_version_string();
    uint8_t str_raw[32] = {0};
    if (s_string_new_utf8) s_string_new_utf8(str_raw, ver);
    if (s_from_string) s_from_string(r_return, str_raw);
}

static void call_load_mesh(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t mesh_id = -1;
    if (p_argument_count >= 1 && s_to_string && s_string_to_utf8) {
        uint8_t str_raw[32] = {0};
        s_to_string(str_raw, const_cast<GDExtensionVariantPtr>(p_args[0]));
        char buf[1024] = {0};
        s_string_to_utf8(str_raw, buf, sizeof(buf) - 1);
        mesh_id = Arboria::VGRuntime::instance().register_mesh(buf);
    }
    if (s_from_int) s_from_int(r_return, &mesh_id);
}

static void call_get_mesh_clusters_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && s_to_int) {
        int64_t m_id = 0;
        s_to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().clusters);
    }
    if (s_from_int) s_from_int(r_return, &count);
}

static void call_get_mesh_vertices_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && s_to_int) {
        int64_t m_id = 0;
        s_to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().vertices);
    }
    if (s_from_int) s_from_int(r_return, &count);
}

static void call_get_mesh_triangles_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = 0;
    if (p_argument_count >= 1 && s_to_int) {
        int64_t m_id = 0;
        s_to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        auto m = Arboria::VGRuntime::instance().get_mesh(static_cast<int32_t>(m_id));
        if (m) count = static_cast<int64_t>(m->get_header().triangles);
    }
    if (s_from_int) s_from_int(r_return, &count);
}

static void call_scene_create_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t inst_id = 0;
    if (p_argument_count >= 1 && s_to_int) {
        int64_t m_id = 0;
        s_to_int(&m_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        inst_id = Arboria::VGSceneBridge::instance().register_instance(static_cast<int32_t>(m_id));
    }
    if (s_from_int) s_from_int(r_return, &inst_id);
}

static void call_scene_destroy_instance(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 1 && s_to_int) {
        int64_t inst_id = 0;
        s_to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        ok = Arboria::VGSceneBridge::instance().unregister_instance(static_cast<uint32_t>(inst_id)) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_scene_set_transform_components(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 13 && s_to_int && s_to_float) {
        int64_t inst_id = 0;
        s_to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        float m[16] = {0};
        for (int i = 0; i < 12; ++i) {
            double v = 0.0;
            s_to_float(&v, const_cast<GDExtensionVariantPtr>(p_args[1 + i]));
            m[i] = static_cast<float>(v);
        }
        m[15] = 1.0f;
        ok = Arboria::VGSceneBridge::instance().set_instance_transform(static_cast<uint32_t>(inst_id), m) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_scene_set_lod(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 4 && s_to_int && s_to_float) {
        int64_t inst_id = 0;
        double max_err = 1.5;
        int64_t lod_mode = 0;
        int64_t forced_lod = 0;
        s_to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        s_to_float(&max_err, const_cast<GDExtensionVariantPtr>(p_args[1]));
        s_to_int(&lod_mode, const_cast<GDExtensionVariantPtr>(p_args[2]));
        s_to_int(&forced_lod, const_cast<GDExtensionVariantPtr>(p_args[3]));
        ok = Arboria::VGSceneBridge::instance().set_instance_lod_params(
            static_cast<uint32_t>(inst_id),
            static_cast<float>(max_err),
            static_cast<uint32_t>(lod_mode),
            static_cast<uint32_t>(forced_lod)
        ) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_scene_set_visible(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = 0;
    if (p_argument_count >= 2 && s_to_int && s_to_bool) {
        int64_t inst_id = 0;
        uint8_t vis = 1;
        s_to_int(&inst_id, const_cast<GDExtensionVariantPtr>(p_args[0]));
        s_to_bool(&vis, const_cast<GDExtensionVariantPtr>(p_args[1]));
        ok = Arboria::VGSceneBridge::instance().set_instance_visible(static_cast<uint32_t>(inst_id), vis != 0) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_scene_get_active_count(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    int64_t count = static_cast<int64_t>(Arboria::VGSceneBridge::instance().get_instance_count());
    if (s_from_int) s_from_int(r_return, &count);
}

static void call_get_engine_signature(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    std::string token = Arboria::SecurityModule::instance().get_traceable_token();
    uint8_t str_raw[32] = {0};
    if (s_string_new_utf8) s_string_new_utf8(str_raw, token.c_str());
    if (s_from_string) s_from_string(r_return, str_raw);
}

static void call_get_engine_license_hash(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    const char* hash = Arboria::SecurityModule::instance().get_signature().license_hash;
    uint8_t str_raw[32] = {0};
    if (s_string_new_utf8) s_string_new_utf8(str_raw, hash);
    if (s_from_string) s_from_string(r_return, str_raw);
}

static void call_verify_engine_integrity(void *method_userdata, GDExtensionClassInstancePtr p_instance, const GDExtensionConstVariantPtr *p_args, GDExtensionInt p_argument_count, GDExtensionVariantPtr r_return, GDExtensionCallError *r_error) {
    uint8_t ok = Arboria::SecurityModule::instance().verify_runtime_integrity() ? 1 : 0;
    if (s_from_bool) s_from_bool(r_return, &ok);
}

// ----------------------------------------------------------------------------
// PIPELINE GPU NATIVO C++ (EXECUÇÃO REAL NO RENDERINGDEVICE)
// ----------------------------------------------------------------------------

static GDExtensionInterfaceVariantCall s_variant_call = nullptr;
static GDExtensionInterfaceVariantGetIndexed s_variant_get_indexed = nullptr;
static GDExtensionInterfaceVariantDestroy s_variant_destroy = nullptr;

static bool call_variant_method(
    GDExtensionVariantPtr p_target,
    const char* method_name,
    const GDExtensionConstVariantPtr* p_args,
    int p_arg_count,
    GDExtensionVariantPtr r_ret
) {
    if (!s_variant_call || !s_string_name_new_utf8 || !p_target) return false;
    uint8_t m_sname[32] = {0};
    s_string_name_new_utf8(m_sname, method_name);

    uint8_t dummy_ret[32] = {0};
    GDExtensionVariantPtr target_ret = r_ret ? r_ret : dummy_ret;

    GDExtensionCallError err{};
    s_variant_call(p_target, m_sname, p_args, p_arg_count, target_ret, &err);
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
    ctx.get_indexed = s_variant_get_indexed;
    ctx.from_int = s_from_int;
    ctx.from_bool = s_from_bool;
    ctx.to_int = s_to_int;
    ctx.rd = rd;
    return ctx;
}

static void call_dispatch_compute_native(
    void *method_userdata,
    GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args,
    GDExtensionInt p_argument_count,
    GDExtensionVariantPtr r_return,
    GDExtensionCallError *r_error
) {
    uint8_t ok = 0;
    if (p_argument_count >= 4) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        GDExtensionConstVariantPtr compute_pipeline = p_args[1];
        GDExtensionConstVariantPtr uniform_set = p_args[2];
        int64_t groups_x = 1;
        if (s_to_int) s_to_int(&groups_x, const_cast<GDExtensionVariantPtr>(p_args[3]));

        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGComputeDispatch::dispatch_cull_clusters_native(ctx, compute_pipeline, uniform_set, groups_x) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_draw_indirect_native(
    void *method_userdata,
    GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args,
    GDExtensionInt p_argument_count,
    GDExtensionVariantPtr r_return,
    GDExtensionCallError *r_error
) {
    uint8_t ok = 0;
    if (p_argument_count >= 5) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        GDExtensionConstVariantPtr fb = p_args[1];
        GDExtensionConstVariantPtr raster_pipe = p_args[2];
        GDExtensionConstVariantPtr uniform_set = p_args[3];
        GDExtensionConstVariantPtr counter_buf = p_args[4];

        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGIndirectRenderer::draw_indirect_native(ctx, fb, raster_pipe, uniform_set, counter_buf) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

static void call_render_scene_batch(
    void *method_userdata,
    GDExtensionClassInstancePtr p_instance,
    const GDExtensionConstVariantPtr *p_args,
    GDExtensionInt p_argument_count,
    GDExtensionVariantPtr r_return,
    GDExtensionCallError *r_error
) {
    uint8_t ok = 0;
    if (p_argument_count >= 10) {
        GDExtensionVariantPtr rd = const_cast<GDExtensionVariantPtr>(p_args[0]);
        GDExtensionConstVariantPtr fb = p_args[1];
        GDExtensionConstVariantPtr compute_pipeline = p_args[2];
        GDExtensionConstVariantPtr raster_pipe = p_args[3];
        GDExtensionConstVariantPtr compute_sets = p_args[4];
        GDExtensionConstVariantPtr groups_x = p_args[5];
        GDExtensionConstVariantPtr raster_sets = p_args[6];
        GDExtensionConstVariantPtr counter_bufs = p_args[7];
        int64_t count = 0;
        if (s_to_int) s_to_int(&count, const_cast<GDExtensionVariantPtr>(p_args[8]));
        GDExtensionConstVariantPtr initial_colors = p_args[9];

        Arboria::GPUDriverContext ctx = get_driver_context(rd);
        ok = Arboria::VGRuntime::instance().render_scene_native(
            ctx, fb, compute_pipeline, raster_pipe,
            compute_sets, groups_x, raster_sets, counter_bufs, count,
            initial_colors
        ) ? 1 : 0;
    }
    if (s_from_bool) s_from_bool(r_return, &ok);
}

// Helper para registro seguro de métodos no ClassDB
static void register_method(
    GDExtensionInterfaceClassdbRegisterExtensionClassMethod reg_m,
    GDExtensionClassLibraryPtr lib,
    GDExtensionConstStringNamePtr class_name,
    const char *name_str,
    GDExtensionClassMethodCall call_fn,
    GDExtensionVariantType return_type,
    bool has_return,
    uint32_t arg_count = 0,
    const GDExtensionVariantType *arg_types = nullptr,
    const char **arg_names = nullptr
) {
    uint8_t m_name[32] = {0};
    s_string_name_new_utf8(m_name, name_str);

    uint8_t empty_sname[32] = {0};
    s_string_name_new_utf8(empty_sname, "");

    uint8_t empty_str[32] = {0};
    s_string_new_utf8(empty_str, "");

    GDExtensionPropertyInfo ret_info = {};
    if (has_return) {
        ret_info.type = return_type;
        ret_info.name = empty_sname;
        ret_info.class_name = empty_sname;
        ret_info.hint = 0;
        ret_info.hint_string = empty_str;
        ret_info.usage = 6;
    }

    std::vector<GDExtensionPropertyInfo> args_info(arg_count);
    std::vector<std::vector<uint8_t>> arg_names_storage(arg_count, std::vector<uint8_t>(32, 0));
    std::vector<GDExtensionClassMethodArgumentMetadata> args_meta(arg_count, GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);

    for (uint32_t i = 0; i < arg_count; ++i) {
        s_string_name_new_utf8(arg_names_storage[i].data(), arg_names ? arg_names[i] : "arg");
        args_info[i].type = arg_types[i];
        args_info[i].name = arg_names_storage[i].data();
        args_info[i].class_name = empty_sname;
        args_info[i].hint = 0;
        args_info[i].hint_string = empty_str;
        args_info[i].usage = 6;
    }

    GDExtensionClassMethodInfo minfo = {};
    minfo.name = m_name;
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

    reg_m(lib, class_name, &minfo);
}

static void arboria_gdextension_initialize(void* userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
        Arboria::VGRuntime::instance().initialize();
        std::cout << "[Arboria GDExtension] Backend Nativo ARBORIA V7 vinculado com sucesso ao Godot Forward+." << std::endl;
        
        if (g_get_proc_address) {
            auto reg6 = (GDExtensionInterfaceClassdbRegisterExtensionClass6)g_get_proc_address("classdb_register_extension_class6");
            auto reg_method_fn = (GDExtensionInterfaceClassdbRegisterExtensionClassMethod)g_get_proc_address("classdb_register_extension_class_method");
            
            s_string_name_new_utf8 = (GDExtensionInterfaceStringNameNewWithUtf8Chars)g_get_proc_address("string_name_new_with_utf8_chars");
            s_string_new_utf8 = (GDExtensionInterfaceStringNewWithUtf8Chars)g_get_proc_address("string_new_with_utf8_chars");
            s_string_to_utf8 = (GDExtensionInterfaceStringToUtf8Chars)g_get_proc_address("string_to_utf8_chars");
            s_get_from_type_c = (GDExtensionInterfaceGetVariantFromTypeConstructor)g_get_proc_address("get_variant_from_type_constructor");
            s_get_to_type_c = (GDExtensionInterfaceGetVariantToTypeConstructor)g_get_proc_address("get_variant_to_type_constructor");

            s_variant_call = (GDExtensionInterfaceVariantCall)g_get_proc_address("variant_call");
            s_variant_get_indexed = (GDExtensionInterfaceVariantGetIndexed)g_get_proc_address("variant_get_indexed");
            s_variant_destroy = (GDExtensionInterfaceVariantDestroy)g_get_proc_address("variant_destroy");

            if (s_get_from_type_c) {
                s_from_bool = s_get_from_type_c(GDEXTENSION_VARIANT_TYPE_BOOL);
                s_from_int = s_get_from_type_c(GDEXTENSION_VARIANT_TYPE_INT);
                s_from_string = s_get_from_type_c(GDEXTENSION_VARIANT_TYPE_STRING);
            }
            if (s_get_to_type_c) {
                s_to_bool = s_get_to_type_c(GDEXTENSION_VARIANT_TYPE_BOOL);
                s_to_int = s_get_to_type_c(GDEXTENSION_VARIANT_TYPE_INT);
                s_to_float = s_get_to_type_c(GDEXTENSION_VARIANT_TYPE_FLOAT);
                s_to_string = s_get_to_type_c(GDEXTENSION_VARIANT_TYPE_STRING);
            }
            
            if (reg6 && s_string_name_new_utf8) {
                uint8_t class_name[32] = {0};
                uint8_t parent_name[32] = {0};
                s_string_name_new_utf8(class_name, "ArboriaNativeCore");
                s_string_name_new_utf8(parent_name, "RefCounted");
                
                GDExtensionClassCreationInfo6 info = {};
                info.is_virtual = false;
                info.is_abstract = false;
                info.is_exposed = true;
                info.is_runtime = true;
                info.create_instance_func = arboria_create_instance;
                info.free_instance_func = arboria_free_instance;
                info.class_userdata = nullptr;
                
                reg6(g_library, class_name, parent_name, &info);
                std::cout << "[Arboria GDExtension] Classe 'ArboriaNativeCore' registrada com sucesso no ClassDB." << std::endl;

                if (reg_method_fn) {
                    register_method(reg_method_fn, g_library, class_name, "is_active", call_is_active, GDEXTENSION_VARIANT_TYPE_BOOL, true);
                    register_method(reg_method_fn, g_library, class_name, "get_version", call_get_version, GDEXTENSION_VARIANT_TYPE_STRING, true);

                    GDExtensionVariantType arg_str[] = { GDEXTENSION_VARIANT_TYPE_STRING };
                    const char* name_str[] = { "path" };
                    register_method(reg_method_fn, g_library, class_name, "load_mesh", call_load_mesh, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_str, name_str);

                    GDExtensionVariantType arg_int[] = { GDEXTENSION_VARIANT_TYPE_INT };
                    const char* name_mid[] = { "mesh_id" };
                    register_method(reg_method_fn, g_library, class_name, "get_mesh_clusters_count", call_get_mesh_clusters_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_mid);
                    register_method(reg_method_fn, g_library, class_name, "get_mesh_vertices_count", call_get_mesh_vertices_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_mid);
                    register_method(reg_method_fn, g_library, class_name, "get_mesh_triangles_count", call_get_mesh_triangles_count, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_mid);

                    register_method(reg_method_fn, g_library, class_name, "scene_create_instance", call_scene_create_instance, GDEXTENSION_VARIANT_TYPE_INT, true, 1, arg_int, name_mid);

                    const char* name_iid[] = { "instance_id" };
                    register_method(reg_method_fn, g_library, class_name, "scene_destroy_instance", call_scene_destroy_instance, GDEXTENSION_VARIANT_TYPE_BOOL, true, 1, arg_int, name_iid);

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
                    register_method(reg_method_fn, g_library, class_name, "scene_set_transform_components", call_scene_set_transform_components, GDEXTENSION_VARIANT_TYPE_BOOL, true, 13, args_xform, names_xform);

                    GDExtensionVariantType args_lod[] = {
                        GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_FLOAT, GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_INT
                    };
                    const char* names_lod[] = { "instance_id", "max_screen_error", "lod_mode", "forced_lod" };
                    register_method(reg_method_fn, g_library, class_name, "scene_set_lod", call_scene_set_lod, GDEXTENSION_VARIANT_TYPE_BOOL, true, 4, args_lod, names_lod);

                    GDExtensionVariantType args_vis[] = { GDEXTENSION_VARIANT_TYPE_INT, GDEXTENSION_VARIANT_TYPE_BOOL };
                    const char* names_vis[] = { "instance_id", "visible" };
                    register_method(reg_method_fn, g_library, class_name, "scene_set_visible", call_scene_set_visible, GDEXTENSION_VARIANT_TYPE_BOOL, true, 2, args_vis, names_vis);

                    register_method(reg_method_fn, g_library, class_name, "scene_get_active_count", call_scene_get_active_count, GDEXTENSION_VARIANT_TYPE_INT, true);

                    // Métodos de Autenticidade, Rastreabilidade e Assinatura Criptográfica
                    register_method(reg_method_fn, g_library, class_name, "get_engine_signature", call_get_engine_signature, GDEXTENSION_VARIANT_TYPE_STRING, true);
                    register_method(reg_method_fn, g_library, class_name, "get_engine_license_hash", call_get_engine_license_hash, GDEXTENSION_VARIANT_TYPE_STRING, true);
                    register_method(reg_method_fn, g_library, class_name, "verify_engine_integrity", call_verify_engine_integrity, GDEXTENSION_VARIANT_TYPE_BOOL, true);

                    // --------------------------------------------------------
                    // PIPELINE GPU NATIVO (EXECUÇÃO REAL NO RENDERINGDEVICE)
                    // --------------------------------------------------------
                    GDExtensionVariantType args_comp[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_INT
                    };
                    const char* names_comp[] = { "rd", "compute_pipeline", "uniform_set", "groups_x" };
                    register_method(reg_method_fn, g_library, class_name, "dispatch_compute_native", call_dispatch_compute_native, GDEXTENSION_VARIANT_TYPE_BOOL, true, 4, args_comp, names_comp);

                    GDExtensionVariantType args_draw[] = {
                        GDEXTENSION_VARIANT_TYPE_OBJECT,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID,
                        GDEXTENSION_VARIANT_TYPE_RID
                    };
                    const char* names_draw[] = { "rd", "framebuffer", "raster_pipeline", "uniform_set", "counter_buffer" };
                    register_method(reg_method_fn, g_library, class_name, "draw_indirect_native", call_draw_indirect_native, GDEXTENSION_VARIANT_TYPE_BOOL, true, 5, args_draw, names_draw);

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
                    register_method(reg_method_fn, g_library, class_name, "render_scene_batch", call_render_scene_batch, GDEXTENSION_VARIANT_TYPE_BOOL, true, 10, args_batch, names_batch);

                    std::cout << "[Arboria GDExtension] Metodos de 'ArboriaNativeCore' registrados com sucesso no ClassDB (Assinatura Ativa & Pipeline GPU C++ Vinculado)." << std::endl;
                }
            }
        }
    }
}

static void arboria_gdextension_deinitialize(void* userdata, GDExtensionInitializationLevel level) {
    if (level == GDEXTENSION_INITIALIZATION_SCENE) {
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
    g_get_proc_address = p_get_proc_address;
    g_library = p_library;
    r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
    r_initialization->userdata = nullptr;
    r_initialization->initialize = arboria_gdextension_initialize;
    r_initialization->deinitialize = arboria_gdextension_deinitialize;
    return 1;
}
