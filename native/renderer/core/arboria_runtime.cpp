#include "arboria_runtime.h"
#include <iostream>
#include <cstring>

namespace Arboria {

VGRuntime& VGRuntime::instance() {
    static VGRuntime s_instance;
    return s_instance;
}

VGRuntime::VGRuntime() {
    initialize();
}

VGRuntime::~VGRuntime() {
    shutdown();
}

bool VGRuntime::initialize() {
    if (m_initialized) return true;
    m_initialized = true;
    std::cout << "[VGRuntime] Arboria Engine Native Runtime inicializado com sucesso." << std::endl;
    return true;
}

void VGRuntime::shutdown() {
    if (!m_initialized) return;
    m_mesh_pool.clear();
    m_meshes.clear();
    m_initialized = false;
    std::cout << "[VGRuntime] Arboria Engine Native Runtime finalizado." << std::endl;
}

Handle VGRuntime::register_mesh_handle(const std::string& filepath) {
    if (!m_initialized) initialize();

    auto mesh = std::make_shared<VGMeshResource>();
    if (!mesh->load_from_file(filepath)) {
        return Handle{};
    }

    return m_mesh_pool.allocate(mesh);
}

bool VGRuntime::unregister_mesh_handle(Handle handle) {
    return m_mesh_pool.release(handle);
}

std::shared_ptr<VGMeshResource> VGRuntime::get_mesh_by_handle(Handle handle) {
    auto ptr = m_mesh_pool.get(handle);
    if (ptr) return *ptr;
    return nullptr;
}

int32_t VGRuntime::register_mesh(const std::string& filepath) {
    if (!m_initialized) initialize();

    auto mesh = std::make_shared<VGMeshResource>();
    if (!mesh->load_from_file(filepath)) {
        return -1;
    }

    int32_t id = m_next_mesh_id++;
    m_meshes[id] = mesh;
    return id;
}

int32_t VGRuntime::register_mesh_from_memory(const uint8_t* data, size_t size) {
    if (!m_initialized) initialize();

    auto mesh = std::make_shared<VGMeshResource>();
    if (!mesh->load_from_memory(data, size)) {
        return -1;
    }

    int32_t id = m_next_mesh_id++;
    m_meshes[id] = mesh;
    return id;
}

bool VGRuntime::unregister_mesh(int32_t mesh_id) {
    auto it = m_meshes.find(mesh_id);
    if (it != m_meshes.end()) {
        m_meshes.erase(it);
        return true;
    }
    return false;
}

std::shared_ptr<VGMeshResource> VGRuntime::get_mesh(int32_t mesh_id) {
    auto it = m_meshes.find(mesh_id);
    if (it != m_meshes.end()) {
        return it->second;
    }
    return nullptr;
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
    bool compute_ok = VGComputeDispatch::dispatch_cull_clusters_batch(
        ctx,
        compute_pipeline,
        compute_sets_array,
        groups_x_array,
        count
    );
    if (!compute_ok) return false;

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
