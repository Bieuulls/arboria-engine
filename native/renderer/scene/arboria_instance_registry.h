#ifndef ARBORIA_INSTANCE_REGISTRY_H
#define ARBORIA_INSTANCE_REGISTRY_H

#include "../core/arboria_types.h"
#include "../core/arboria_handle.h"
#include "../core/arboria_mutable_geometry.h"
#include "arboria_gpu_scene_types.h"
#include <vector>
#include <memory>
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

    // Overlay de Geometria Mutável (ETAPA 1)
    // Instâncias sem modificação mantêm nullptr (compartilhando 100% da malha original)
    // unique_ptr: cada instância é o único dono do seu overlay (não há compartilhamento entre instâncias)
    std::unique_ptr<MutableGeometryOverlay> mutable_overlay = nullptr;
    uint32_t geometry_version = 0;

    bool has_mutable_geometry() const {
        return mutable_overlay != nullptr && mutable_overlay->has_modifications();
    }

    // Dirty flag para reconstrucao incremental do buffer GPU
    bool dirty = false;
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

    // Gestão de Geometria Mutável por Instância
    // Retorna ponteiro bruto (não-transfere posse). A instância permanece dona exclusiva via unique_ptr.
    MutableGeometryOverlay* get_or_create_mutable_overlay(Handle instance_handle);
    const MutableGeometryOverlay* get_mutable_overlay(Handle instance_handle) const;
    bool remove_mutable_overlay(Handle instance_handle);

    // Operações de Edição Localizada de Geometria (ETAPA 2)
    uint32_t apply_depression(Handle instance_handle, const float center[3], float radius, float depth, bool subdivide = true);
    bool export_instance_to_obj(Handle instance_handle, const std::string& filepath) const;

    // Reconstrução Incremental do DAG (ETAPA 3)
    DAGReconstructionStats rebuild_dag_incremental(Handle instance_handle);

    // Preparação de Patch de Atualização GPU (ETAPA 4)
    GPUMutableGeometryPatch prepare_gpu_geometry_patch(Handle instance_handle, uint32_t global_dynamic_vertex_base, uint32_t global_dynamic_triangle_base);

    // Geração de Malha de Colisão Física (ETAPA 5)
    MutablePhysicsMesh build_physics_collision_mesh(Handle instance_handle);

    // Persistência Binária Versionada (.armut) (ETAPA 5)
    bool save_mutable_overlay(Handle instance_handle, const std::string& filepath) const;
    bool load_mutable_overlay(Handle instance_handle, const std::string& filepath);

    const InstanceRecord* get_instance(Handle instance_handle) const;
    size_t get_instance_count() const;

    // Constrói o buffer GPU de instâncias empacotado para o SSBO global da GPU
    // Calcula volumes delimitadores (bounding sphere e AABB) no espaço de mundo com suporte
    // a escalas não uniformes e espelhadas (negativas), e matriz normal inversa transposta
    // Se full_rebuild=true, reconstrói todas as instâncias; se false, processa apenas as sujas (dirty flags).
    size_t build_gpu_instance_buffer(std::vector<GPUInstanceData>& out_buffer, bool full_rebuild = false);

    // GPU Scene 2.0 — rastreamento de instâncias sujas para upload esparso (dirty-range)
    // Retorna os índices de slot (0-based) das instâncias marcadas como sujas.
    void get_dirty_indices(std::vector<uint32_t>& out_indices) const;
    // Retorna o intervalo [min_index, max_index] dos slots sujos para upload contíguo à GPU.
    // Retorna false se não houver instâncias sujas.
    bool get_dirty_range(uint32_t& min_index, uint32_t& max_index) const;
    // Número de instâncias atualmente sujas.
    size_t get_dirty_count() const;
    // Limpa o rastreamento de instâncias sujas (chamado após upload à GPU).
    void clear_dirty_tracking();

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

    // Cache persistente do buffer GPU entre frames (reutilizado em builds incrementais)
    mutable std::vector<GPUInstanceData> m_cached_buffer;

    // GPU Scene 2.0 — rastreamento de instâncias sujas para upload esparso
    std::vector<uint32_t> m_dirty_indices;      // Índices de slot (0-based) das instâncias sujas
    uint32_t m_dirty_min_index = UINT32_MAX;     // Índice mínimo sujo (para upload em range)
    uint32_t m_dirty_max_index = 0;              // Índice máximo sujo (para upload em range)
    bool m_first_build_done = false;             // Primeiro build completo já foi feito
};

} // namespace Arboria

#endif // ARBORIA_INSTANCE_REGISTRY_H
