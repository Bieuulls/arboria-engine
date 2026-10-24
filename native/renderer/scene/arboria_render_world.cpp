#include "arboria_render_world.h"
#include "arboria_streaming_manager.h"
#include "../gpu/arboria_memory_manager.h"
#include <iostream>

namespace Arboria {

ArboriaRenderWorld& ArboriaRenderWorld::instance() {
    static ArboriaRenderWorld s_inst;
    return s_inst;
}

void ArboriaRenderWorld::initialize() {
    if (m_initialized) return;
    m_initialized = true;
    std::cout << "[ArboriaRenderWorld] Inicializado com sucesso. Submissão global GPU ativa." << std::endl;
}

void ArboriaRenderWorld::shutdown() {
    if (!m_initialized) return;
    ArboriaInstanceRegistry::instance().clear();
    ArboriaMeshRegistry::instance().clear();
    ArboriaMaterialTable::instance().clear();
    m_initialized = false;
    std::cout << "[ArboriaRenderWorld] Finalizado com sucesso. Todos os recursos GPU liberados." << std::endl;
}

Handle ArboriaRenderWorld::register_mesh(const std::string& path) {
    return ArboriaMeshRegistry::instance().register_mesh(path);
}

bool ArboriaRenderWorld::unregister_mesh(Handle handle) {
    return ArboriaMeshRegistry::instance().unregister_mesh(handle);
}

Handle ArboriaRenderWorld::register_instance(Handle mesh_handle, uint32_t material_id) {
    return ArboriaInstanceRegistry::instance().register_instance(mesh_handle, material_id);
}

bool ArboriaRenderWorld::update_instance_transform(Handle instance_handle, const float transform[16]) {
    return ArboriaInstanceRegistry::instance().set_transform(instance_handle, transform);
}

bool ArboriaRenderWorld::update_instance_lod(Handle instance_handle, float max_screen_error, uint32_t lod_mode, uint32_t forced_lod) {
    return ArboriaInstanceRegistry::instance().set_lod_parameters(instance_handle, max_screen_error, lod_mode, forced_lod);
}

bool ArboriaRenderWorld::update_instance_visibility(Handle instance_handle, bool visible) {
    return ArboriaInstanceRegistry::instance().set_visibility(instance_handle, visible);
}

bool ArboriaRenderWorld::release_instance(Handle instance_handle) {
    return ArboriaInstanceRegistry::instance().unregister_instance(instance_handle);
}

std::shared_ptr<MutableGeometryOverlay> ArboriaRenderWorld::get_or_create_mutable_overlay(Handle instance_handle) {
    return ArboriaInstanceRegistry::instance().get_or_create_mutable_overlay(instance_handle);
}

std::shared_ptr<MutableGeometryOverlay> ArboriaRenderWorld::get_mutable_overlay(Handle instance_handle) const {
    return ArboriaInstanceRegistry::instance().get_mutable_overlay(instance_handle);
}

bool ArboriaRenderWorld::remove_mutable_overlay(Handle instance_handle) {
    return ArboriaInstanceRegistry::instance().remove_mutable_overlay(instance_handle);
}

bool ArboriaRenderWorld::has_mutable_geometry(Handle instance_handle) const {
    const InstanceRecord* rec = ArboriaInstanceRegistry::instance().get_instance(instance_handle);
    return rec && rec->has_mutable_geometry();
}

uint32_t ArboriaRenderWorld::apply_depression(Handle instance_handle, const float center[3], float radius, float depth, bool subdivide) {
    return ArboriaInstanceRegistry::instance().apply_depression(instance_handle, center, radius, depth, subdivide);
}

bool ArboriaRenderWorld::export_instance_to_obj(Handle instance_handle, const std::string& filepath) const {
    return ArboriaInstanceRegistry::instance().export_instance_to_obj(instance_handle, filepath);
}

DAGReconstructionStats ArboriaRenderWorld::rebuild_dag_incremental(Handle instance_handle) {
    return ArboriaInstanceRegistry::instance().rebuild_dag_incremental(instance_handle);
}

GPUMutableGeometryPatch ArboriaRenderWorld::prepare_gpu_geometry_patch(
    Handle instance_handle,
    uint32_t global_dynamic_vertex_base,
    uint32_t global_dynamic_triangle_base
) {
    return ArboriaInstanceRegistry::instance().prepare_gpu_geometry_patch(
        instance_handle,
        global_dynamic_vertex_base,
        global_dynamic_triangle_base
    );
}

MutablePhysicsMesh ArboriaRenderWorld::build_physics_collision_mesh(Handle instance_handle) {
    return ArboriaInstanceRegistry::instance().build_physics_collision_mesh(instance_handle);
}

bool ArboriaRenderWorld::save_mutable_overlay(Handle instance_handle, const std::string& filepath) const {
    return ArboriaInstanceRegistry::instance().save_mutable_overlay(instance_handle, filepath);
}

bool ArboriaRenderWorld::load_mutable_overlay(Handle instance_handle, const std::string& filepath) {
    return ArboriaInstanceRegistry::instance().load_mutable_overlay(instance_handle, filepath);
}

bool ArboriaRenderWorld::render_scene_global(
    const GPUDriverContext& ctx,
    const void* framebuffer,
    const void* compute_pipeline,
    const void* raster_pipeline,
    const void* compute_uniform_set,
    const void* raster_uniform_set,
    const void* indirect_args_buffer,
    uint32_t total_work_items,
    const void* initial_colors
) {
    if (!m_initialized || total_work_items == 0) return false;

    // 1. Passe Compute Culling Agrupado Global (Lote único de GPU)
    if (!ArboriaGPUScene::instance().dispatch_global_cull(ctx, compute_pipeline, compute_uniform_set, total_work_items)) {
        return false;
    }

    // 2. Passe Rasterizacao Indireta Agrupada Global (draw_count = 1 em lote único)
    if (!ArboriaGPUScene::instance().draw_global_indirect(ctx, framebuffer, raster_pipeline, raster_uniform_set, indirect_args_buffer, initial_colors)) {
        return false;
    }

    return true;
}

size_t ArboriaRenderWorld::get_registered_mesh_count() const {
    return ArboriaMeshRegistry::instance().get_mesh_count();
}

size_t ArboriaRenderWorld::get_active_instance_count() const {
    return ArboriaInstanceRegistry::instance().get_instance_count();
}

void ArboriaRenderWorld::memory_set_budget(size_t bytes) {
    ArboriaStreamingManager::instance().set_vram_budget(bytes);
}

size_t ArboriaRenderWorld::memory_get_budget() const {
    return ArboriaGPUMemoryManager::instance().get_budget();
}

size_t ArboriaRenderWorld::memory_get_resident_bytes() const {
    return ArboriaGPUMemoryManager::instance().get_statistics().resident_bytes;
}

size_t ArboriaRenderWorld::memory_get_allocated_bytes() const {
    return ArboriaGPUMemoryManager::instance().get_statistics().allocated_bytes;
}

uint32_t ArboriaRenderWorld::memory_get_page_faults() const {
    return ArboriaGPUMemoryManager::instance().get_statistics().page_faults;
}

uint32_t ArboriaRenderWorld::memory_get_evictions() const {
    return ArboriaGPUMemoryManager::instance().get_statistics().evictions_count;
}

void ArboriaRenderWorld::streaming_update(const float cam_pos[3], uint64_t current_frame) {
    ArboriaStreamingManager::instance().update(cam_pos, current_frame);
}

} // namespace Arboria
