#include "arboria_runtime.h"
#include "../scene/arboria_streaming_manager.h"
#include "../core/arboria_error.h"
#include "arboria_logger.h"
#include <cmath>
#include <cstring>

namespace Arboria {

VGRuntime& VGRuntime::instance() {
    static VGRuntime s_instance;
    return s_instance;
}

VGRuntime::VGRuntime() = default;

VGRuntime::~VGRuntime() = default;

bool VGRuntime::initialize() {
    if (m_initialized) return true;
    m_initialized = true;
    ARBORIA_LOG_INFO("[VGRuntime] Arboria Engine Native Runtime inicializado com sucesso.");
    return true;
}

void VGRuntime::shutdown() {
    if (!m_initialized) return;
    m_initialized = false;
    ARBORIA_LOG_INFO("[VGRuntime] Arboria Engine Native Runtime finalizado.");
}

void VGRuntime::set_camera(const float view_proj[16], const float cam_pos[3], const float viewport[2]) {
    std::memcpy(m_camera_view_proj, view_proj, 16 * sizeof(float));
    std::memcpy(m_camera_pos, cam_pos, 3 * sizeof(float));
    std::memcpy(m_viewport_size, viewport, 2 * sizeof(float));
    ARBORIA_LOG_INFO("[VGRuntime] Câmera atualizada via GDExtension: pos=("
        + std::to_string(m_camera_pos[0]) + ", " + std::to_string(m_camera_pos[1]) + ", " + std::to_string(m_camera_pos[2])
        + "), viewport=(" + std::to_string(m_viewport_size[0]) + "x" + std::to_string(m_viewport_size[1]) + ")");
}

void VGRuntime::get_camera(float view_proj[16], float cam_pos[3], float viewport[2]) const {
    std::memcpy(view_proj, m_camera_view_proj, 16 * sizeof(float));
    std::memcpy(cam_pos, m_camera_pos, 3 * sizeof(float));
    std::memcpy(viewport, m_viewport_size, 2 * sizeof(float));
}

Result<Handle> VGRuntime::register_mesh_handle(const std::string& filepath) {
    if (!m_initialized) initialize();

    auto res = ArboriaMeshRegistry::instance().register_mesh(filepath);
    if (!res.ok()) {
        return Result<Handle>::failure(res.error, res.message);
    }
    Handle h = res.value;

    // Registra streaming com base nas informacoes da malha
    RegisteredMeshInfo info = ArboriaMeshRegistry::instance().get_mesh_info(h);
    if (!info.handle.is_valid() || !info.resource) {
        ArboriaMeshRegistry::instance().unregister_mesh(h);
        return Result<Handle>::failure(ArboriaError::InvalidData, "Malha registrada mas sem recurso ou handle inválido");
    }

    float bounds_min[3] = {};
    float bounds_max[3] = {};
    info.resource->get_bounding_box(bounds_min, bounds_max);
    const float center_x = (bounds_min[0] + bounds_max[0]) * 0.5f;
    const float center_y = (bounds_min[1] + bounds_max[1]) * 0.5f;
    const float center_z = (bounds_min[2] + bounds_max[2]) * 0.5f;
    const float dx = bounds_max[0] - center_x;
    const float dy = bounds_max[1] - center_y;
    const float dz = bounds_max[2] - center_z;
    const float radius = std::sqrt(dx * dx + dy * dy + dz * dz);
    auto stream_status = ArboriaStreamingManager::instance().register_mesh_streaming(
        h, info.resource->get_cluster_count(), radius);
    if (!stream_status.ok()) {
        ArboriaMeshRegistry::instance().unregister_mesh(h);
        return Result<Handle>::failure(stream_status.error, stream_status.message);
    }
    return Result<Handle>::success(h);
}

Status VGRuntime::unregister_mesh_handle(Handle handle) {
    auto stream_status = ArboriaStreamingManager::instance().unregister_mesh_streaming(handle);
    auto reg_status = ArboriaMeshRegistry::instance().unregister_mesh(handle);
    if (!stream_status.ok()) return stream_status;
    if (!reg_status.ok()) return reg_status;
    return Status::success();
}

std::shared_ptr<VGMeshResource> VGRuntime::get_mesh_by_handle(Handle handle) {
    return ArboriaMeshRegistry::instance().get_mesh_resource(handle);
}

int32_t VGRuntime::register_mesh(const std::string& filepath) {
    if (!m_initialized) initialize();

    auto res = ArboriaMeshRegistry::instance().register_mesh(filepath);
    if (!res.ok()) {
        return -1;
    }
    return static_cast<int32_t>(res.value.index);
}

int32_t VGRuntime::register_mesh_from_memory(const uint8_t* data, size_t size) {
    if (!m_initialized) initialize();

    auto mesh = std::make_unique<VGMeshResource>();
    if (!mesh->load_from_memory(data, size)) {
        return -1;
    }

    auto res = ArboriaMeshRegistry::instance().register_mesh_resource("", std::move(mesh));
    if (!res.ok()) {
        return -1;
    }
    return static_cast<int32_t>(res.value.index);
}

bool VGRuntime::unregister_mesh(int32_t mesh_id) {
    RegisteredMeshInfo info = ArboriaMeshRegistry::instance().get_mesh_info_by_index(
        static_cast<uint32_t>(mesh_id));
    if (!info.handle.is_valid()) {
        return false;
    }
    auto status = ArboriaMeshRegistry::instance().unregister_mesh(info.handle);
    return status.ok();
}

std::shared_ptr<VGMeshResource> VGRuntime::get_mesh(int32_t mesh_id) {
    RegisteredMeshInfo info = ArboriaMeshRegistry::instance().get_mesh_info_by_index(
        static_cast<uint32_t>(mesh_id));
    return info.resource;
}

bool VGRuntime::render_scene_native(
    const GPUDriverContext& ctx,
    const void* framebuffer,
    const void* compute_pipeline,
    const void* raster_pipeline,
    const void* compute_sets_array,
    const void* groups_x_array,
    const void* raster_sets_array,
    const void* counter_bufs_array,
    int64_t count,
    const void* initial_colors
) {
    if (!m_initialized || count <= 0) return false;

    // FASE 1: Compute Culling & DAG selection (100% GPU via VGComputeDispatch)
    Status compute_status = VGComputeDispatch::dispatch_cull_clusters_batch(
        ctx,
        compute_pipeline,
        compute_sets_array,
        groups_x_array,
        count
    );
    if (!compute_status.ok()) {
        ARBORIA_LOG_ERROR("[VGRuntime] Falha no dispatch de compute: " + compute_status.message);
        return false;
    }

    // FASE 2: Indirect Rasterization Pass no Framebuffer Forward+ (via VGIndirectRenderer)
    bool raster_ok = VGIndirectRenderer::draw_indirect_batch(
        ctx,
        framebuffer,
        raster_pipeline,
        raster_sets_array,
        counter_bufs_array,
        count,
        initial_colors
    );
    return raster_ok;
}

} // namespace Arboria

// ----------------------------------------------------------------------------
// C Export API Implementation
// ----------------------------------------------------------------------------

ARBORIA_API int arboria_init() {
    return Arboria::VGRuntime::instance().initialize() ? 0 : -1;
}

ARBORIA_API void arboria_shutdown() {
    Arboria::VGRuntime::instance().shutdown();
}

ARBORIA_API const char* arboria_get_version() {
    return Arboria::VGRuntime::instance().get_version_string();
}

ARBORIA_API int32_t arboria_load_mesh(const char* filepath) {
    if (!filepath) return -1;
    return Arboria::VGRuntime::instance().register_mesh(filepath);
}

ARBORIA_API int32_t arboria_load_mesh_from_memory(const uint8_t* data, size_t size) {
    if (!data || size == 0) return -1;
    return Arboria::VGRuntime::instance().register_mesh_from_memory(data, size);
}

ARBORIA_API int arboria_unload_mesh(int32_t mesh_id) {
    return Arboria::VGRuntime::instance().unregister_mesh(mesh_id) ? 0 : -1;
}

ARBORIA_API int arboria_get_mesh_header(int32_t mesh_id, Arboria::Header* out_header) {
    if (!out_header) return -1;
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return -2;
    *out_header = mesh->get_header();
    return 0;
}

ARBORIA_API int arboria_get_mesh_bounds(int32_t mesh_id, float out_bmin[3], float out_bmax[3]) {
    if (!out_bmin || !out_bmax) return -1;
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return -2;
    mesh->get_bounding_box(out_bmin, out_bmax);
    return 0;
}

ARBORIA_API const void* arboria_get_gpu_clusters_ptr(int32_t mesh_id, size_t* out_size_bytes) {
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return nullptr;
    if (out_size_bytes) *out_size_bytes = mesh->get_gpu_clusters_byte_size();
    return mesh->get_gpu_clusters().data();
}

ARBORIA_API const void* arboria_get_packed_vertices_ptr(int32_t mesh_id, size_t* out_size_bytes) {
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return nullptr;
    if (out_size_bytes) *out_size_bytes = mesh->get_packed_vertices_byte_size();
    return mesh->get_packed_vertices().data();
}

ARBORIA_API const void* arboria_get_packed_triangles_ptr(int32_t mesh_id, size_t* out_size_bytes) {
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return nullptr;
    if (out_size_bytes) *out_size_bytes = mesh->get_packed_triangles_byte_size();
    return mesh->get_packed_triangles().data();
}

ARBORIA_API int arboria_build_camera_ubo(
    const Arboria::CameraViewSettings* settings,
    uint32_t total_clusters,
    const float model_matrix[16],
    Arboria::CameraUniforms* out_ubo
) {
    if (!settings || !out_ubo) return -1;
    *out_ubo = Arboria::VGComputeDispatch::build_camera_uniforms(*settings, total_clusters, model_matrix);
    return 0;
}

ARBORIA_API int arboria_simulate_cull(
    int32_t mesh_id,
    const Arboria::CameraUniforms* ubo,
    uint32_t* out_visible_clusters,
    uint32_t* out_triangles_drawn
) {
    if (!ubo) return -1;
    auto mesh = Arboria::VGRuntime::instance().get_mesh(mesh_id);
    if (!mesh || !mesh->is_valid()) return -2;

    auto result = Arboria::VGComputeDispatch::simulate_cull_offline(*mesh, *ubo);
    if (out_visible_clusters) *out_visible_clusters = result.visible_cluster_count;
    if (out_triangles_drawn) *out_triangles_drawn = result.total_triangles_drawn;
    return 0;
}
