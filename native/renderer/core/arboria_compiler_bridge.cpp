#include "arboria_compiler_bridge.h"
#include "arboria_logger.h"
#include <cstring>
#include <algorithm>

namespace Arboria {

std::vector<uint8_t> ArboriaCompilerBridge::serialize_to_vgmesh(const CompiledMesh& mesh) {
    if (!mesh.is_valid()) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] CompiledMesh invalido — nao ha clusters ou vertices para serializar.");
        return {};
    }

    // Tamanho total = Header + LODs + Clusters + Groups + Vertices + Indices
    size_t total_size = sizeof(Header) +
        mesh.lods.size() * sizeof(LOD) +
        mesh.clusters.size() * sizeof(Cluster) +
        mesh.groups.size() * sizeof(Group) +
        mesh.vertices.size() * sizeof(Vertex) +
        mesh.indices.size();

    std::vector<uint8_t> out;
    out.reserve(total_size);

    // 1. Header (72 bytes)
    out.insert(out.end(), reinterpret_cast<const uint8_t*>(&mesh.header),
                  reinterpret_cast<const uint8_t*>(&mesh.header) + sizeof(Header));

    // 2. LODs
    if (!mesh.lods.empty()) {
        out.insert(out.end(), reinterpret_cast<const uint8_t*>(mesh.lods.data()),
                      reinterpret_cast<const uint8_t*>(mesh.lods.data()) + mesh.lods.size() * sizeof(LOD));
    }

    // 3. Clusters
    if (!mesh.clusters.empty()) {
        out.insert(out.end(), reinterpret_cast<const uint8_t*>(mesh.clusters.data()),
                      reinterpret_cast<const uint8_t*>(mesh.clusters.data()) + mesh.clusters.size() * sizeof(Cluster));
    }

    // 4. Groups (DAG)
    if (!mesh.groups.empty()) {
        out.insert(out.end(), reinterpret_cast<const uint8_t*>(mesh.groups.data()),
                      reinterpret_cast<const uint8_t*>(mesh.groups.data()) + mesh.groups.size() * sizeof(Group));
    }

    // 5. Vertices
    if (!mesh.vertices.empty()) {
        out.insert(out.end(), reinterpret_cast<const uint8_t*>(mesh.vertices.data()),
                      reinterpret_cast<const uint8_t*>(mesh.vertices.data()) + mesh.vertices.size() * sizeof(Vertex));
    }

    // 6. Indices (1 byte por indice de vertice local)
    if (!mesh.indices.empty()) {
        out.insert(out.end(), mesh.indices.begin(), mesh.indices.end());
    }

    ARBORIA_LOG_INFO("[ArboriaCompilerBridge] Serializado CompiledMesh para " +
        std::to_string(out.size()) + " bytes .vgmesh (clusters=" +
        std::to_string(mesh.clusters.size()) + ", vertices=" +
        std::to_string(mesh.vertices.size()) + ", lods=" +
        std::to_string(mesh.lods.size()) + ", groups=" +
        std::to_string(mesh.groups.size()) + ").");

    return out;
}

int ArboriaCompilerBridge::compile_and_register_mesh(
    const float* vertices,  uint32_t vertex_count,
    const float* normals,   const float* uvs,
    const uint32_t* indices, uint32_t index_count,
    const CompilerConfig& config)
{
    if (!vertices || vertex_count == 0 || !indices || index_count == 0) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] Entrada invalida: vertices ou indices nulos/vazios.");
        return -1;
    }

    // 1. Compilar malha bruta via compilador geometrico
    CompiledMesh compiled = ArboriaGeometricCompiler::instance().compile(
        vertices, vertex_count, normals, uvs, indices, index_count);

    if (!compiled.is_valid()) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] Falha na compilacao geometrica da malha.");
        return -1;
    }

    // 2. Serializar para bytes .vgmesh na memoria
    auto vgmesh_bytes = serialize_to_vgmesh(compiled);
    if (vgmesh_bytes.empty()) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] Falha na serializacao .vgmesh da malha compilada.");
        return -1;
    }

    // 3. Registrar no VGRuntime via load_from_memory (cria VGMeshResource + pool entry)
    int mesh_id = VGRuntime::instance().register_mesh_from_memory(
        vgmesh_bytes.data(), vgmesh_bytes.size());

    if (mesh_id < 0) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] Falha ao registrar malha compilada no VGRuntime.");
        return -1;
    }

    ARBORIA_LOG_INFO("[ArboriaCompilerBridge] Malha compilada registrada com sucesso: mesh_id=" +
        std::to_string(mesh_id) + " (clusters=" + std::to_string(compiled.clusters.size()) +
        ", lods=" + std::to_string(compiled.lods.size()) + ", groups=" +
        std::to_string(compiled.groups.size()) + ").");

    return mesh_id;
}

CompiledMesh ArboriaCompilerBridge::compile_only(
    const float* vertices,  uint32_t vertex_count,
    const float* normals,   const float* uvs,
    const uint32_t* indices, uint32_t index_count,
    const CompilerConfig& config)
{
    return ArboriaGeometricCompiler::instance().compile(
        vertices, vertex_count, normals, uvs, indices, index_count);
}

bool ArboriaCompilerBridge::load_vgmesh_bytes(
    VGMeshResource& out_resource, const uint8_t* data, size_t size)
{
    if (!data || size == 0) {
        ARBORIA_LOG_ERROR("[ArboriaCompilerBridge] Dados .vgmesh nulos ou vazios.");
        return false;
    }
    return out_resource.load_from_memory(data, size);
}

const ArboriaGeometricCompiler::CompileStats& ArboriaCompilerBridge::get_last_stats() {
    return ArboriaGeometricCompiler::instance().get_last_stats();
}

} // namespace Arboria
