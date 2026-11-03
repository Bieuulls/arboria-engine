#ifndef ARBORIA_COMPILER_BRIDGE_H
#define ARBORIA_COMPILER_BRIDGE_H

#include "arboria_geometric_compiler.h"
#include "arboria_runtime.h"
#include "arboria_mesh_resource.h"
#include <vector>
#include <cstdint>

namespace Arboria {

// Ponte entre o Compilador Geometrico (ArboriaGeometricCompiler) e o runtime
// de recursos de malha (VGMeshResource / VGRuntime).
//
// Conecta: compile() -> serializacao .vgmesh em memoria -> register_mesh_from_memory()
// Permitindo que o compilador corrigido (QEM, DAG, LOD, VGMESH) alimente o
// pipeline de producao Godot/Vulkan sem depender do baker (meshoptimizer) de codigo fechado.
class ARBORIA_CLASS ArboriaCompilerBridge {
public:
    // Serializa um CompiledMesh para bytes .vgmesh na memoria.
    // Layout binario identico a write_vgmesh:
    //   Header (72B) | LODs (24B cada) | Clusters (68B cada) | Groups (28B cada)
    //   Vertices (32B cada) | Indices (1 byte cada)
    static std::vector<uint8_t> serialize_to_vgmesh(const CompiledMesh& mesh);

    // Compila malha bruta via ArboriaGeometricCompiler, serializa para .vgmesh
    // e registra no VGRuntime via register_mesh_from_memory.
    // Retorna mesh_id (>= 0, slot do pool) ou -1 em caso de falha.
    static int compile_and_register_mesh(
        const float* vertices,  uint32_t vertex_count,
        const float* normals,   const float* uvs,
        const uint32_t* indices, uint32_t index_count,
        const CompilerConfig& config = CompilerConfig{});

    // Apenas compila (sem registrar) — util para inspecao offline e testes.
    static CompiledMesh compile_only(
        const float* vertices,  uint32_t vertex_count,
        const float* normals,   const float* uvs,
        const uint32_t* indices, uint32_t index_count,
        const CompilerConfig& config = CompilerConfig{});

    // Carrega bytes .vgmesh diretamente em um VGMeshResource (sem passar pelo registry).
    static bool load_vgmesh_bytes(VGMeshResource& out_resource, const uint8_t* data, size_t size);

    // Estatisticas da ultima compilacao realizada por compile_only / compile_and_register_mesh.
    static const ArboriaGeometricCompiler::CompileStats& get_last_stats();

private:
    ArboriaCompilerBridge() = delete;
};

} // namespace Arboria

#endif // ARBORIA_COMPILER_BRIDGE_H
