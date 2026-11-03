#ifndef ARBORIA_MESH_LOADER_H
#define ARBORIA_MESH_LOADER_H

#include <string>
#include <vector>
#include <cstdint>

namespace Arboria {

// Resultado da leitura de um arquivo de malha (.obj / .gltf / .glb).
// Contem posicoes (3 floats por vertice) e, quando disponiveis, normais
// (3 floats por vertice), UVs (2 floats por vertice) e indices (triangulos).
struct LoadedMesh {
    std::vector<float> vertices;   // posicoes: [x, y, z, x, y, z, ...]
    std::vector<float> normals;    // [nx, ny, nz, ...] (vazio se nao houver no arquivo)
    std::vector<float> uvs;        // [u, v, u, v, ...] (vazio se nao houver no arquivo)
    std::vector<uint32_t> indices; // indices de triangulos: [i0, i1, i2, ...]
    bool valid = false;
    std::string error;
};

// Carrega um arquivo de malha (.obj ou .gltf/.glb) e extrai vertices/indices.
// Retorna LoadedMesh com valid == true em caso de sucesso.
LoadedMesh load_mesh_file(const std::string& filepath);

// ============================================================================
// Gate 10 — Importacao em Lote
// ============================================================================

struct BatchImportResult {
    std::string filepath;   // Caminho do arquivo importado
    LoadedMesh mesh;        // Malha carregada (valida apenas se success == true)
    bool success = false;   // true se o arquivo foi carregado com sucesso
};

// Importa multiplos arquivos de malha em lote.
// Retorna um resultado por arquivo, na mesma ordem da entrada.
// Arquivos que falharem terao success == false e mesh.error preenchido.
std::vector<BatchImportResult> load_mesh_batch(const std::vector<std::string>& filepaths);

// ============================================================================
// Gate 10 — Validacao de Integridade
// ============================================================================

struct MeshIntegrityReport {
    bool valid = true;                                  // true se nao ha erros criticos
    std::vector<std::string> errors;                    // Erros que tornam a malha invalida
    std::vector<std::string> warnings;                  // Avisos (nao impedem uso, mas merecem atencao)
    uint32_t vertex_count = 0;                          // Numero de vertices
    uint32_t index_count = 0;                           // Numero de indices
    uint32_t triangle_count = 0;                        // Numero de triangulos (index_count / 3)
    bool has_degenerate_triangles = false;              // Triangulos com 3 indices iguais
    bool has_out_of_range_indices = false;              // Indices referencia vertex nao existente
    bool has_duplicate_vertices = false;                // Vertices duplicados (mesma posicao)
    bool missing_normals = false;                       // Sem normais
    bool missing_uvs = false;                           // Sem UVs
};

// Valida a integridade estructural de uma LoadedMesh.
// Verifica: indices dentro do intervalo, triangulos degenerados, contagem de indices multiplo de 3,
// presenca de vertices e indices, entre outros.
MeshIntegrityReport validate_mesh_integrity(const LoadedMesh& mesh);

} // namespace Arboria

#endif // ARBORIA_MESH_LOADER_H
