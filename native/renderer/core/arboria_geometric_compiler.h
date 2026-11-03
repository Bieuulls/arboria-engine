#ifndef ARBORIA_GEOMETRIC_COMPILER_H
#define ARBORIA_GEOMETRIC_COMPILER_H

#include "arboria_types.h"
#include <vector>
#include <string>
#include <cstdint>

namespace Arboria {

class VGMeshResource;

// Configuracao do compilador geometrico
struct CompilerConfig {
    uint32_t max_vertices_per_cluster = 256;   // Limite de vertices por cluster
    uint32_t max_triangles_per_cluster = 128;  // Limite de triangulos por cluster
    float target_screen_error = 1.5f;          // Erro maximo na tela (pixels)
    bool enable_compression = true;            // Habilitar quantizacao de dados
    bool generate_lods = true;                 // Gerar niveis LOD
    uint32_t max_lod_levels = 4;               // Numero maximo de niveis LOD
    float lod_error_multiplier = 2.0f;         // Multiplicador de erro entre niveis LOD
    float sharp_edge_threshold = 0.7f;         // Limite de angulo diedro (rad) para arestas vivas (~40 graus)
};

// Resultado da compilacao de uma malha
struct CompiledMesh {
    Header header{};                           // Cabecalho ARBORIA2
    std::vector<LOD> lods;                     // Niveis LOD
    std::vector<Cluster> clusters;             // Clusters gerados
    std::vector<Group> groups;                 // Grupos DAG
    std::vector<Vertex> vertices;              // Vertices (opcionalmente quantizados)
    std::vector<uint8_t> indices;              // Indices de triangulos (bytes brutos)

    bool is_valid() const { return !clusters.empty() && !vertices.empty(); }
};

// Compilador Geometrico 2.0 (GATE B)
// Transforma malha bruta (vertices + indices) em clusters otimizados,
// hierarquia DAG, niveis LOD e saida binaria .vgmesh compatível com VGMeshResource.
class ARBORIA_CLASS ArboriaGeometricCompiler {
public:
    static ArboriaGeometricCompiler& instance();

    // Configura o compilador
    void configure(const CompilerConfig& config);
    const CompilerConfig& get_config() const;

    // Compila malha bruta em estrutura otimizada
    // vertices: array de posicoes (3 floats por vertice)
    // normals: array de normais (3 floats por vertice, pode ser nullptr)
    // uvs: array de UVs (2 floats por vertice, pode ser nullptr)
    // indices: array de indices de triangulos (3 por triangulo)
    CompiledMesh compile(
        const float* vertices, uint32_t vertex_count,
        const float* normals, const float* uvs,
        const uint32_t* indices, uint32_t index_count
    );

    // Compila a partir de um VGMeshResource ja carregado (recompilacao/otimizacao)
    CompiledMesh recompile(const VGMeshResource& source);

    // Escreve o resultado compilado em arquivo .vgmesh
    bool write_vgmesh(const CompiledMesh& mesh, const std::string& filepath) const;

    // Estatisticas de compilacao
    struct CompileStats {
        uint32_t input_triangles = 0;
        uint32_t input_vertices = 0;
        uint32_t output_clusters = 0;
        uint32_t output_groups = 0;
        uint32_t output_lods = 0;
        float cluster_error_avg = 0.0f;
        float cluster_error_max = 0.0f;
        double compile_time_ms = 0.0f;
        size_t output_file_bytes = 0;
    };
    const CompileStats& get_last_stats() const;

private:
    ArboriaGeometricCompiler() = default;
    ~ArboriaGeometricCompiler() = default;

    CompilerConfig m_config;
    CompileStats m_last_stats{};

    // Algoritmos internos de compilacao
    void build_clusters(
        const float* vertices, uint32_t vertex_count,
        const float* normals, const float* uvs,
        const uint32_t* indices, uint32_t index_count,
        std::vector<Cluster>& out_clusters,
        std::vector<Vertex>& out_vertices,
        std::vector<uint8_t>& out_indices
    );

    void build_dag_hierarchy(
        std::vector<Cluster>& clusters,
        std::vector<Group>& out_groups
    );

    // Subdivisao recursiva espac auxiliar do build_dag_hierarchy
    void build_dag_subtree(
        std::vector<Cluster>& clusters,
        const std::vector<uint32_t>& indices,
        uint32_t parent_group_id,
        uint32_t depth,
        uint32_t max_depth,
        uint32_t min_clusters_per_group,
        uint32_t& next_group_id,
        std::vector<Group>& out_groups
    );

    void build_lods(
        const std::vector<Cluster>& lod0_clusters,
        const std::vector<Vertex>& lod0_vertices,
        const std::vector<uint8_t>& lod0_indices,
        std::vector<Cluster>& io_all_clusters,
        std::vector<Vertex>& io_all_vertices,
        std::vector<uint8_t>& io_all_indices,
        std::vector<LOD>& out_lods
    );

    void compute_bounding_sphere(
        const float* vertices, const uint32_t* indices, uint32_t index_count,
        float center[3], float& radius
    );

    void compute_normal_cone(
        const float* normals, const uint32_t* indices, uint32_t index_count,
        float cone[4]
    );

    float compute_cluster_error(
        const float* vertices, const uint32_t* indices, uint32_t index_count,
        const float center[3], float radius
    );

    // ========================================================================
    // Gate 06 — Refinamento do DAG e continuidade geometrica
    // ========================================================================

    // Detecta e corrige a ordem de winding (faceamento) dos triangulos de um
    // cluster: garante que a normal calculada pelo produto vetorial das arestas
    // coincida com a normal armazenada nos vertices. Retorna o numero de faces
    // cuja ordem foi invertida. Essencial para malhas importadas com winding
    // misto (CW/CCW) e para espelhamento de matrizes (determinante negativo).
    uint32_t validate_and_fix_winding(
        std::vector<Cluster>& clusters,
        std::vector<Vertex>& vertices,
        std::vector<uint8_t>& indices
    ) const;

    // Detecta espelhamento (winding invertido) em um cluster comparando a normal
    // geometrica calculada com a normal armazenada. Retorna true se o cluster
    // precisa de correcao de winding.
    bool cluster_needs_winding_fix(
        const Cluster& c,
        const std::vector<Vertex>& vertices,
        const std::vector<uint8_t>& indices
    ) const;

    // Valida a continuidade de corte do DAG entre niveis LOD: para cada cluster
    // de LOD > 0 com campo 'refined' definido, verifica se os vertices na fronteira
    // de corte coincidem espacalmente com o cluster LOD 0 referenciado, dentro de
    // uma tolerancia. Retorna o numero de clusters de corte que falharam a validacao.
    uint32_t validate_dag_cut_continuity(
        const std::vector<Cluster>& clusters,
        const std::vector<Vertex>& vertices,
        const std::vector<uint8_t>& indices,
        float tolerance = 1e-3f
    ) const;

    // Aplica correcao de espelhamento a todos os clusters: inverte o winding de
    // faces cujo determinante da matriz de transformacao implicita e negativo,
    // garantindo orientacao consistente em malhas espelhadas.
    void apply_mirror_correction(
        std::vector<Cluster>& clusters,
        std::vector<Vertex>& vertices,
        std::vector<uint8_t>& indices
    ) const;
};

} // namespace Arboria

#endif // ARBORIA_GEOMETRIC_COMPILER_H
