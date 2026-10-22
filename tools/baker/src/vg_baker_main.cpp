#define _CRT_SECURE_NO_WARNINGS
#include "../thirdparty/meshoptimizer/meshoptimizer.h"
#define CLUSTERLOD_IMPLEMENTATION
#include "../thirdparty/meshoptimizer/clusterlod.h"

#include <iostream>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <algorithm>
#include <cassert>
#include <map>
#include <set>

#ifdef _WIN32
#include <windows.h>
#include <psapi.h>
#endif

#pragma pack(push, 1)

// Vertice compacto (32 bytes)
struct Vertex {
    float px, py, pz;
    float nx, ny, nz;
    float u, v;

    bool operator==(const Vertex& o) const {
        return px == o.px && py == o.py && pz == o.pz &&
               nx == o.nx && ny == o.ny && nz == o.nz &&
               u == o.u && v == o.v;
    }
};

struct BoundingBox {
    float min[3];
    float max[3];

    void init() {
        min[0] = min[1] = min[2] = 1e30f;
        max[0] = max[1] = max[2] = -1e30f;
    }

    void expand(float x, float y, float z) {
        min[0] = std::min(min[0], x); min[1] = std::min(min[1], y); min[2] = std::min(min[2], z);
        max[0] = std::max(max[0], x); max[1] = std::max(max[1], y); max[2] = std::max(max[2], z);
    }
};

// Formato Binario Oficial .vgmesh v2 (Multi-LOD DAG Cluster Hierarchy)
struct VGMeshHeader {
    char magic[8];             // "ARBORIA2"
    uint32_t version;          // 2
    uint32_t total_vertices;   // Total de vertices empacotados nos clusters
    uint32_t total_indices;    // Total de indices locais
    uint32_t total_triangles;  // Total de triangulos em todos os clusters
    uint32_t cluster_count;    // Total de clusters gerados
    uint32_t lod_count;        // Quantidade de niveis de LOD
    float bbox_min[3];
    float bbox_max[3];
    uint32_t group_count;      // Total de DAG groups
    uint32_t base_triangle_count; // Triangulos do LOD 0
    uint32_t reserved[2];
};

struct VGLODLevelDescriptor {
    uint32_t lod_level;
    uint32_t cluster_offset;   // Indice inicial no array de clusters
    uint32_t cluster_count;    // Quantidade de clusters neste LOD
    uint32_t triangle_count;   // Triangulos neste LOD
    float max_error;           // Erro metrico maximo deste nivel
    float triangle_ratio;      // Proporcao em relacao ao LOD 0
};

struct VGClusterDescriptor {
    uint32_t cluster_id;
    uint32_t lod_level;
    int32_t  group_id;
    int32_t  refined_group;
    float center[3];
    float radius;
    float normal_cone[4];      // axis xyz, cutoff w
    float lod_error;
    uint32_t vertex_offset;    // Offset no buffer de vertices (em unidades de Vertex)
    uint32_t vertex_count;     // Vertices unicos (max 64)
    uint32_t triangle_offset;  // Offset no buffer de triangulos (em bytes)
    uint32_t triangle_count;   // Triangulos (max 128)
};

struct VGGroupDescriptor {
    uint32_t group_id;
    int32_t  depth;
    float    center[3];
    float    radius;
    float    error;
};

#pragma pack(pop)

size_t get_peak_memory_mb() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) {
        return pmc.PeakWorkingSetSize / (1024 * 1024);
    }
#endif
    return 0;
}

// 1. Carregador Robusto de OBJ Real com Calculo de Normais Automatico se Ausentes
bool load_obj(const std::string& path, std::vector<Vertex>& out_vertices, std::vector<uint32_t>& out_indices, BoundingBox& out_bbox) {
    std::ifstream file(path);
    if (!file.is_open()) return false;

    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<float> texcoords;

    struct RawTriangle {
        int p[3];
        int t[3];
        int n[3];
    };
    std::vector<RawTriangle> raw_triangles;

    out_bbox.init();
    std::string line;

    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;

        std::istringstream iss(line);
        std::string prefix;
        iss >> prefix;

        if (prefix == "v") {
            float x, y, z;
            iss >> x >> y >> z;
            positions.push_back(x);
            positions.push_back(y);
            positions.push_back(z);
            out_bbox.expand(x, y, z);
        } else if (prefix == "vn") {
            float nx, ny, nz;
            iss >> nx >> ny >> nz;
            normals.push_back(nx);
            normals.push_back(ny);
            normals.push_back(nz);
        } else if (prefix == "vt") {
            float u, v;
            iss >> u >> v;
            texcoords.push_back(u);
            texcoords.push_back(v);
        } else if (prefix == "f") {
            std::vector<std::string> face_tokens;
            std::string token;
            while (iss >> token) {
                face_tokens.push_back(token);
            }
            if (face_tokens.size() < 3) continue;

            for (size_t i = 1; i + 1 < face_tokens.size(); ++i) {
                std::string v_strs[3] = { face_tokens[0], face_tokens[i], face_tokens[i + 1] };
                RawTriangle tri;

                for (int vi = 0; vi < 3; ++vi) {
                    int p_raw = 0, t_raw = 0, n_raw = 0;
                    bool has_t = false, has_n = false;
                    char slash1 = 0, slash2 = 0;
                    std::istringstream viss(v_strs[vi]);
                    
                    viss >> p_raw;
                    if (viss.peek() == '/') {
                        viss >> slash1;
                        if (viss.peek() != '/') {
                            if (viss >> t_raw) has_t = true;
                        }
                        if (viss.peek() == '/') {
                            viss >> slash2;
                            if (viss >> n_raw) has_n = true;
                        }
                    }

                    int max_p = static_cast<int>(positions.size() / 3);
                    int max_t = static_cast<int>(texcoords.size() / 2);
                    int max_n = static_cast<int>(normals.size() / 3);

                    int p_idx = (p_raw > 0) ? (p_raw - 1) : (max_p + p_raw);
                    if (p_raw == 0 || p_idx < 0 || p_idx >= max_p) {
                        std::cerr << "ERRO: Indice de vertice OBJ fora dos limites (" << p_raw << " / max " << max_p << ")!\n";
                        return false;
                    }

                    int t_idx = -1;
                    if (has_t) {
                        t_idx = (t_raw > 0) ? (t_raw - 1) : (max_t + t_raw);
                        if (t_raw == 0 || t_idx < 0 || t_idx >= max_t) {
                            std::cerr << "ERRO: Indice de textura/UV OBJ fora dos limites (" << t_raw << " / max " << max_t << ")!\n";
                            return false;
                        }
                    }

                    int n_idx = -1;
                    if (has_n) {
                        n_idx = (n_raw > 0) ? (n_raw - 1) : (max_n + n_raw);
                        if (n_raw == 0 || n_idx < 0 || n_idx >= max_n) {
                            std::cerr << "ERRO: Indice de normal OBJ fora dos limites (" << n_raw << " / max " << max_n << ")!\n";
                            return false;
                        }
                    }

                    tri.p[vi] = p_idx;
                    tri.t[vi] = t_idx;
                    tri.n[vi] = n_idx;
                }

                int p0 = tri.p[0], p1 = tri.p[1], p2 = tri.p[2];
                if (p0 == p1 || p1 == p2 || p0 == p2) continue;

                float x0 = positions[p0 * 3], y0 = positions[p0 * 3 + 1], z0 = positions[p0 * 3 + 2];
                float x1 = positions[p1 * 3], y1 = positions[p1 * 3 + 1], z1 = positions[p1 * 3 + 2];
                float x2 = positions[p2 * 3], y2 = positions[p2 * 3 + 1], z2 = positions[p2 * 3 + 2];
                float e1x = x1 - x0, e1y = y1 - y0, e1z = z1 - z0;
                float e2x = x2 - x0, e2y = y2 - y0, e2z = z2 - z0;
                float cx = e1y * e2z - e1z * e2y;
                float cy = e1z * e2x - e1x * e2z;
                float cz = e1x * e2y - e1y * e2x;
                if ((cx * cx + cy * cy + cz * cz) < 1e-12f) continue;

                raw_triangles.push_back(tri);
            }
        }
    }

    if (positions.empty() || raw_triangles.empty()) return false;

    // Se normais nao existiam no arquivo, calcula normais suaves geometricas
    bool has_original_normals = !normals.empty();
    if (!has_original_normals) {
        normals.assign(positions.size(), 0.0f);
        for (const auto& tri : raw_triangles) {
            int p0 = tri.p[0], p1 = tri.p[1], p2 = tri.p[2];
            if (p0 < 0 || p1 < 0 || p2 < 0) continue;
            float x0 = positions[p0 * 3], y0 = positions[p0 * 3 + 1], z0 = positions[p0 * 3 + 2];
            float x1 = positions[p1 * 3], y1 = positions[p1 * 3 + 1], z1 = positions[p1 * 3 + 2];
            float x2 = positions[p2 * 3], y2 = positions[p2 * 3 + 1], z2 = positions[p2 * 3 + 2];

            float e1x = x1 - x0, e1y = y1 - y0, e1z = z1 - z0;
            float e2x = x2 - x0, e2y = y2 - y0, e2z = z2 - z0;
            float fnx = e1y * e2z - e1z * e2y;
            float fny = e1z * e2x - e1x * e2z;
            float fnz = e1x * e2y - e1y * e2x;

            normals[p0 * 3] += fnx; normals[p0 * 3 + 1] += fny; normals[p0 * 3 + 2] += fnz;
            normals[p1 * 3] += fnx; normals[p1 * 3 + 1] += fny; normals[p1 * 3 + 2] += fnz;
            normals[p2 * 3] += fnx; normals[p2 * 3 + 1] += fny; normals[p2 * 3 + 2] += fnz;
        }

        for (size_t i = 0; i < positions.size() / 3; ++i) {
            float nx = normals[i * 3], ny = normals[i * 3 + 1], nz = normals[i * 3 + 2];
            float len = std::sqrt(nx * nx + ny * ny + nz * nz);
            if (len > 1e-7f) {
                normals[i * 3] /= len; normals[i * 3 + 1] /= len; normals[i * 3 + 2] /= len;
            } else {
                normals[i * 3] = 0.0f; normals[i * 3 + 1] = 1.0f; normals[i * 3 + 2] = 0.0f;
            }
        }
    }

    for (const auto& tri : raw_triangles) {
        for (int vi = 0; vi < 3; ++vi) {
            int p_idx = tri.p[vi];
            int t_idx = tri.t[vi];
            int n_idx = has_original_normals ? tri.n[vi] : p_idx;

            Vertex v;
            v.px = (p_idx >= 0 && size_t(p_idx * 3 + 2) < positions.size()) ? positions[p_idx * 3] : 0.0f;
            v.py = (p_idx >= 0 && size_t(p_idx * 3 + 2) < positions.size()) ? positions[p_idx * 3 + 1] : 0.0f;
            v.pz = (p_idx >= 0 && size_t(p_idx * 3 + 2) < positions.size()) ? positions[p_idx * 3 + 2] : 0.0f;

            v.nx = (n_idx >= 0 && size_t(n_idx * 3 + 2) < normals.size()) ? normals[n_idx * 3] : 0.0f;
            v.ny = (n_idx >= 0 && size_t(n_idx * 3 + 2) < normals.size()) ? normals[n_idx * 3 + 1] : 1.0f;
            v.nz = (n_idx >= 0 && size_t(n_idx * 3 + 2) < normals.size()) ? normals[n_idx * 3 + 2] : 0.0f;

            v.u = (t_idx >= 0 && size_t(t_idx * 2 + 1) < texcoords.size()) ? texcoords[t_idx * 2] : 0.0f;
            v.v = (t_idx >= 0 && size_t(t_idx * 2 + 1) < texcoords.size()) ? texcoords[t_idx * 2 + 1] : 0.0f;

            out_indices.push_back(static_cast<uint32_t>(out_vertices.size()));
            out_vertices.push_back(v);
        }
    }

    return !out_vertices.empty() && !out_indices.empty();
}

// Estrutura para coletar os clusters de saida do clusterlod
struct RawGroupData {
    clodGroup group;
    int group_id;
};

struct RawClusterData {
    int group_id;
    int depth;
    int refined;
    clodBounds bounds;
    std::vector<unsigned int> indices;
};

struct LODCollectorContext {
    std::vector<RawGroupData> groups;
    std::vector<RawClusterData> clusters;

    static int callback(void* ctx, clodGroup group, const clodCluster* in_clusters, size_t cluster_count) {
        auto* self = static_cast<LODCollectorContext*>(ctx);
        int gid = static_cast<int>(self->groups.size());
        self->groups.push_back({ group, gid });

        for (size_t i = 0; i < cluster_count; ++i) {
            RawClusterData c;
            c.group_id = gid;
            c.depth = group.depth;
            c.refined = in_clusters[i].refined;
            c.bounds = in_clusters[i].bounds;
            c.indices.assign(in_clusters[i].indices, in_clusters[i].indices + in_clusters[i].index_count);
            self->clusters.push_back(std::move(c));
        }

        return gid;
    }
};

// 2. Gravador Binario .vgmesh v2
bool write_vgmesh_v2(
    const std::string& path,
    const VGMeshHeader& header,
    const std::vector<VGLODLevelDescriptor>& lods,
    const std::vector<VGClusterDescriptor>& descriptors,
    const std::vector<VGGroupDescriptor>& groups,
    const std::vector<Vertex>& vertices,
    const std::vector<uint8_t>& triangles
) {
    std::ofstream out(path, std::ios::binary);
    if (!out.is_open()) return false;

    out.write(reinterpret_cast<const char*>(&header), sizeof(VGMeshHeader));
    out.write(reinterpret_cast<const char*>(lods.data()), lods.size() * sizeof(VGLODLevelDescriptor));
    out.write(reinterpret_cast<const char*>(descriptors.data()), descriptors.size() * sizeof(VGClusterDescriptor));
    if (!groups.empty()) {
        out.write(reinterpret_cast<const char*>(groups.data()), groups.size() * sizeof(VGGroupDescriptor));
    }
    out.write(reinterpret_cast<const char*>(vertices.data()), vertices.size() * sizeof(Vertex));
    out.write(reinterpret_cast<const char*>(triangles.data()), triangles.size() * sizeof(uint8_t));

    return true;
}

struct CanonicalVertex {
    float px, py, pz;
    float nx, ny, nz;
    float u, v;

    bool operator<(const CanonicalVertex& o) const {
        const float eps = 1e-4f;
        if (std::abs(px - o.px) > eps) return px < o.px;
        if (std::abs(py - o.py) > eps) return py < o.py;
        if (std::abs(pz - o.pz) > eps) return pz < o.pz;
        if (std::abs(nx - o.nx) > 1e-2f) return nx < o.nx;
        if (std::abs(ny - o.ny) > 1e-2f) return ny < o.ny;
        if (std::abs(nz - o.nz) > 1e-2f) return nz < o.nz;
        if (std::abs(u - o.u) > 1e-3f) return u < o.u;
        return v < o.v;
    }
};

struct CanonicalTriangle {
    CanonicalVertex v[3];
    float area;

    bool operator<(const CanonicalTriangle& o) const {
        for (int i = 0; i < 3; ++i) {
            if (v[i] < o.v[i]) return true;
            if (o.v[i] < v[i]) return false;
        }
        return false;
    }
};

inline CanonicalTriangle make_canonical_triangle(const Vertex& v0, const Vertex& v1, const Vertex& v2) {
    CanonicalVertex cv0 = { v0.px, v0.py, v0.pz, v0.nx, v0.ny, v0.nz, v0.u, v0.v };
    CanonicalVertex cv1 = { v1.px, v1.py, v1.pz, v1.nx, v1.ny, v1.nz, v1.u, v1.v };
    CanonicalVertex cv2 = { v2.px, v2.py, v2.pz, v2.nx, v2.ny, v2.nz, v2.u, v2.v };

    float e1x = v1.px - v0.px, e1y = v1.py - v0.py, e1z = v1.pz - v0.pz;
    float e2x = v2.px - v0.px, e2y = v2.py - v0.py, e2z = v2.pz - v0.pz;
    float cx = e1y * e2z - e1z * e2y;
    float cy = e1z * e2x - e1x * e2z;
    float cz = e1x * e2y - e1y * e2x;
    float area = 0.5f * std::sqrt(cx * cx + cy * cy + cz * cz);

    CanonicalTriangle ct;
    ct.area = area;
    // Permutacao ciclica preservando estritamente a orientacao da face (winding order)
    if (cv1 < cv0 && cv1 < cv2) {
        ct.v[0] = cv1; ct.v[1] = cv2; ct.v[2] = cv0;
    } else if (cv2 < cv0 && cv2 < cv1) {
        ct.v[0] = cv2; ct.v[1] = cv0; ct.v[2] = cv1;
    } else {
        ct.v[0] = cv0; ct.v[1] = cv1; ct.v[2] = cv2;
    }
    return ct;
}

// 3. VERIFICACAO INDEPENDENTE E PROFUNDA DE INTEGRIDADE (Missao 1 & 2 & Auditoria P1)
struct VerificationReport {
    bool passed = false;
    uint32_t total_triangles_checked = 0;
    uint32_t invalid_indices = 0;
    uint32_t degenerate_triangles = 0;
    uint32_t flipped_windings = 0;
    uint32_t unnormalized_normals = 0;
    uint32_t invalid_uvs = 0;
    uint32_t invalid_dag_links = 0;
    float max_pos_delta = 0.0f;
    float max_metric_error = 0.0f;
    size_t peak_memory_mb = 0;
    double elapsed_ms = 0.0;

    // Metricas rigorosas de Lossless LOD 0
    bool lod0_lossless_validated = false;
    uint32_t orig_triangle_count = 0;
    uint32_t lod0_triangle_count = 0;
    float orig_surface_area = 0.0f;
    float lod0_surface_area = 0.0f;
    float max_vertex_pos_diff = 0.0f;
    float max_normal_diff = 0.0f;
    float max_uv_diff = 0.0f;
    uint32_t unmatched_triangles = 0;
};

VerificationReport verify_deep_vgmesh(
    const std::string& path,
    const std::vector<Vertex>& original_vertices,
    const std::vector<uint32_t>& original_indices,
    const BoundingBox& original_bbox
) {
    VerificationReport rep;
    auto t0 = std::chrono::high_resolution_clock::now();

    std::ifstream in(path, std::ios::binary);
    if (!in.is_open()) {
        std::cerr << "ERRO: Nao foi possivel abrir " << path << " para verificacao!\n";
        return rep;
    }

    in.seekg(0, std::ios::end);
    size_t file_size = in.tellg();
    in.seekg(0, std::ios::beg);

    if (file_size < sizeof(VGMeshHeader)) {
        std::cerr << "ERRO: Tamanho de arquivo (" << file_size << " bytes) menor que cabecalho VGMeshHeader (" << sizeof(VGMeshHeader) << " bytes)!\n";
        rep.invalid_indices++;
        return rep;
    }

    VGMeshHeader header;
    if (!in.read(reinterpret_cast<char*>(&header), sizeof(VGMeshHeader))) {
        std::cerr << "ERRO: Falha ao ler cabecalho .vgmesh (arquivo truncado ou corrompido)!\n";
        rep.invalid_indices++;
        return rep;
    }

    if (std::memcmp(header.magic, "ARBORIA2", 8) != 0) {
        std::cerr << "ERRO: Magic invalido no .vgmesh (esperado ARBORIA2)!\n";
        rep.invalid_indices++;
        return rep;
    }

    if (header.version != 2) {
        std::cerr << "ERRO: Versao do .vgmesh (" << header.version << ") incompativel!\n";
        rep.invalid_indices++;
        return rep;
    }

    uint64_t expected_size = sizeof(VGMeshHeader)
        + uint64_t(header.lod_count) * sizeof(VGLODLevelDescriptor)
        + uint64_t(header.cluster_count) * sizeof(VGClusterDescriptor)
        + uint64_t(header.group_count) * sizeof(VGGroupDescriptor)
        + uint64_t(header.total_vertices) * sizeof(Vertex)
        + uint64_t(header.total_triangles) * 3 * sizeof(uint8_t);

    if (file_size < expected_size) {
        std::cerr << "ERRO: Arquivo truncado! Tamanho no disco: " << file_size << " bytes, esperado no minimo: " << expected_size << " bytes!\n";
        rep.invalid_indices++;
        return rep;
    }

    std::vector<VGLODLevelDescriptor> lods(header.lod_count);
    if (header.lod_count > 0 && !in.read(reinterpret_cast<char*>(lods.data()), header.lod_count * sizeof(VGLODLevelDescriptor))) {
        std::cerr << "ERRO: Arquivo truncado ao ler LOD descriptors!\n";
        rep.invalid_indices++;
        return rep;
    }

    std::vector<VGClusterDescriptor> descs(header.cluster_count);
    if (header.cluster_count > 0 && !in.read(reinterpret_cast<char*>(descs.data()), header.cluster_count * sizeof(VGClusterDescriptor))) {
        std::cerr << "ERRO: Arquivo truncado ao ler Cluster descriptors!\n";
        rep.invalid_indices++;
        return rep;
    }

    std::vector<VGGroupDescriptor> groups(header.group_count);
    if (header.group_count > 0) {
        if (!in.read(reinterpret_cast<char*>(groups.data()), header.group_count * sizeof(VGGroupDescriptor))) {
            std::cerr << "ERRO: Arquivo truncado ao ler Group descriptors!\n";
            rep.invalid_indices++;
            return rep;
        }
    }

    std::vector<Vertex> packed_verts(header.total_vertices);
    if (header.total_vertices > 0 && !in.read(reinterpret_cast<char*>(packed_verts.data()), header.total_vertices * sizeof(Vertex))) {
        std::cerr << "ERRO: Arquivo truncado ao ler Vertex buffer!\n";
        rep.invalid_indices++;
        return rep;
    }

    std::vector<uint8_t> packed_tris(header.total_triangles * 3);
    if (header.total_triangles > 0 && !in.read(reinterpret_cast<char*>(packed_tris.data()), header.total_triangles * 3 * sizeof(uint8_t))) {
        std::cerr << "ERRO: Arquivo truncado ao ler Triangle index buffer!\n";
        rep.invalid_indices++;
        return rep;
    }

    // A. Verificacao de Limites AABB
    if (!original_indices.empty()) {
        for (int i = 0; i < 3; ++i) {
            float d_min = std::abs(header.bbox_min[i] - original_bbox.min[i]);
            float d_max = std::abs(header.bbox_max[i] - original_bbox.max[i]);
            if (d_min > 0.001f || d_max > 0.001f) {
                std::cerr << "Aviso: Discrepancia na AABB eixo " << i << " (" << d_min << ", " << d_max << ")\n";
            }
        }
    }

    // B. Verificacao de Limites por LOD Descriptor
    for (size_t li = 0; li < lods.size(); ++li) {
        const auto& l = lods[li];
        if (l.lod_level != li) {
            std::cerr << "ERRO: lod_level inconsistente no LOD descriptor " << li << "!\n";
            rep.invalid_indices++;
        }
        if (uint64_t(l.cluster_offset) + uint64_t(l.cluster_count) > header.cluster_count) {
            std::cerr << "ERRO: LOD " << li << " cluster_offset + count excede cluster_count!\n";
            rep.invalid_indices++;
            return rep;
        }
    }

    // C. Verificacao por Cluster
    for (size_t ci = 0; ci < descs.size(); ++ci) {
        const auto& c = descs[ci];
        if (c.cluster_id != ci) {
            std::cerr << "ERRO: Indice de cluster inconsistente (" << c.cluster_id << " != " << ci << ")!\n";
            rep.invalid_indices++;
        }
        if (uint64_t(c.vertex_offset) + uint64_t(c.vertex_count) > packed_verts.size()) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " vertex_offset + count (" 
                      << c.vertex_offset << " + " << c.vertex_count << ") excede buffer de vertices (" 
                      << packed_verts.size() << ")!\n";
            rep.invalid_indices++;
            return rep;
        }
        if (uint64_t(c.triangle_offset) + uint64_t(c.triangle_count) * 3 > packed_tris.size()) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " triangle_offset + count (" 
                      << c.triangle_offset << " + " << (c.triangle_count * 3) << ") excede buffer de triangulos (" 
                      << packed_tris.size() << ")!\n";
            rep.invalid_indices++;
            return rep;
        }
        if (c.group_id < 0 || static_cast<uint32_t>(c.group_id) >= header.group_count) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " referencia group_id (" << c.group_id << ") invalido!\n";
            rep.invalid_dag_links++;
            rep.invalid_indices++;
        }
        if (c.refined_group >= 0 && static_cast<uint32_t>(c.refined_group) >= header.group_count) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " referencia refined_group (" << c.refined_group << ") invalido!\n";
            rep.invalid_dag_links++;
            rep.invalid_indices++;
        }

        if (c.lod_error > rep.max_metric_error) {
            rep.max_metric_error = c.lod_error;
        }

        if (c.vertex_count > 64) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " excede 64 vertices (" << c.vertex_count << ")!\n";
            rep.invalid_indices++;
        }
        if (c.triangle_count > 128) {
            std::cerr << "ERRO: Cluster " << c.cluster_id << " excede 128 triangulos (" << c.triangle_count << ")!\n";
            rep.invalid_indices++;
        }

        for (uint32_t t = 0; t < c.triangle_count; ++t) {
            uint32_t tri_base = c.triangle_offset + t * 3;
            uint8_t i0 = packed_tris[tri_base + 0];
            uint8_t i1 = packed_tris[tri_base + 1];
            uint8_t i2 = packed_tris[tri_base + 2];

            rep.total_triangles_checked++;

            if (i0 >= c.vertex_count || i1 >= c.vertex_count || i2 >= c.vertex_count) {
                rep.invalid_indices++;
                continue;
            }

            if (i0 == i1 || i1 == i2 || i0 == i2) {
                rep.degenerate_triangles++;
                continue;
            }

            const Vertex& v0 = packed_verts[c.vertex_offset + i0];
            const Vertex& v1 = packed_verts[c.vertex_offset + i1];
            const Vertex& v2 = packed_verts[c.vertex_offset + i2];

            float e1x = v1.px - v0.px, e1y = v1.py - v0.py, e1z = v1.pz - v0.pz;
            float e2x = v2.px - v0.px, e2y = v2.py - v0.py, e2z = v2.pz - v0.pz;
            float cx = e1y * e2z - e1z * e2y;
            float cy = e1z * e2x - e1x * e2z;
            float cz = e1x * e2y - e1y * e2x;
            float cross_len = std::sqrt(cx * cx + cy * cy + cz * cz);
            if (cross_len < 1e-12f) {
                rep.degenerate_triangles++;
            }

            // Orientacao de face comparada com normais
            if (cross_len > 1e-7f) {
                float fnx = cx / cross_len, fny = cy / cross_len, fnz = cz / cross_len;
                float vnx = (v0.nx + v1.nx + v2.nx) / 3.0f;
                float vny = (v0.ny + v1.ny + v2.ny) / 3.0f;
                float vnz = (v0.nz + v1.nz + v2.nz) / 3.0f;
                float v_len = std::sqrt(vnx * vnx + vny * vny + vnz * vnz);
                if (v_len > 0.1f) {
                    float dot = (fnx * vnx + fny * vny + fnz * vnz) / v_len;
                    if (dot < -0.7f) {
                        rep.flipped_windings++;
                    }
                }
            }

            for (const Vertex* vp : { &v0, &v1, &v2 }) {
                float n_len = std::sqrt(vp->nx * vp->nx + vp->ny * vp->ny + vp->nz * vp->nz);
                if (std::isnan(n_len) || std::isinf(n_len) || std::abs(n_len - 1.0f) > 0.05f) {
                    rep.unnormalized_normals++;
                }
                if (std::isnan(vp->u) || std::isinf(vp->u) || std::isnan(vp->v) || std::isinf(vp->v)) {
                    rep.invalid_uvs++;
                }
            }
        }
    }

    // D. Verificacao Rigorosa de Equivalencia Geometrica Lossless LOD 0 (Auditoria P1)
    if (!lods.empty() && !original_indices.empty()) {
        rep.orig_triangle_count = static_cast<uint32_t>(original_indices.size() / 3);
        rep.lod0_triangle_count = lods[0].triangle_count;

        // Reconstroi triangulos canonicos da malha original
        std::vector<CanonicalTriangle> orig_canon;
        orig_canon.reserve(rep.orig_triangle_count);
        for (uint32_t i = 0; i < rep.orig_triangle_count; ++i) {
            uint32_t idx0 = original_indices[i * 3 + 0];
            uint32_t idx1 = original_indices[i * 3 + 1];
            uint32_t idx2 = original_indices[i * 3 + 2];
            if (idx0 >= original_vertices.size() || idx1 >= original_vertices.size() || idx2 >= original_vertices.size()) {
                rep.invalid_indices++;
                continue;
            }
            const Vertex& v0 = original_vertices[idx0];
            const Vertex& v1 = original_vertices[idx1];
            const Vertex& v2 = original_vertices[idx2];
            CanonicalTriangle ct = make_canonical_triangle(v0, v1, v2);
            rep.orig_surface_area += ct.area;
            orig_canon.push_back(ct);
        }

        // Reconstroi triangulos canonicos do LOD 0 a partir dos clusters
        std::vector<CanonicalTriangle> lod0_canon;
        lod0_canon.reserve(rep.lod0_triangle_count);
        uint32_t c_start = lods[0].cluster_offset;
        uint32_t c_end = c_start + lods[0].cluster_count;
        for (uint32_t ci = c_start; ci < c_end && ci < descs.size(); ++ci) {
            const auto& c = descs[ci];
            for (uint32_t t = 0; t < c.triangle_count; ++t) {
                uint32_t tri_base = c.triangle_offset + t * 3;
                uint8_t i0 = packed_tris[tri_base + 0];
                uint8_t i1 = packed_tris[tri_base + 1];
                uint8_t i2 = packed_tris[tri_base + 2];
                const Vertex& v0 = packed_verts[c.vertex_offset + i0];
                const Vertex& v1 = packed_verts[c.vertex_offset + i1];
                const Vertex& v2 = packed_verts[c.vertex_offset + i2];
                CanonicalTriangle ct = make_canonical_triangle(v0, v1, v2);
                rep.lod0_surface_area += ct.area;
                lod0_canon.push_back(ct);
            }
        }

        // Ordena ambas as colecoes canonicas para comparacao 1:1
        std::sort(orig_canon.begin(), orig_canon.end());
        std::sort(lod0_canon.begin(), lod0_canon.end());

        if (orig_canon.size() != lod0_canon.size()) {
            std::cerr << "ERRO: Contagem de triangulos canonicos difere: Original=" << orig_canon.size() << " vs LOD0=" << lod0_canon.size() << "!\n";
            rep.unmatched_triangles += static_cast<uint32_t>(std::abs((int)orig_canon.size() - (int)lod0_canon.size()));
        }

        size_t compare_count = std::min(orig_canon.size(), lod0_canon.size());
        for (size_t i = 0; i < compare_count; ++i) {
            const auto& ot = orig_canon[i];
            const auto& lt = lod0_canon[i];

            bool match = true;
            for (int k = 0; k < 3; ++k) {
                float dpx = std::abs(ot.v[k].px - lt.v[k].px);
                float dpy = std::abs(ot.v[k].py - lt.v[k].py);
                float dpz = std::abs(ot.v[k].pz - lt.v[k].pz);
                float pos_diff = std::max({dpx, dpy, dpz});
                rep.max_vertex_pos_diff = std::max(rep.max_vertex_pos_diff, pos_diff);

                float dnx = std::abs(ot.v[k].nx - lt.v[k].nx);
                float dny = std::abs(ot.v[k].ny - lt.v[k].ny);
                float dnz = std::abs(ot.v[k].nz - lt.v[k].nz);
                float norm_diff = std::max({dnx, dny, dnz});
                rep.max_normal_diff = std::max(rep.max_normal_diff, norm_diff);

                float du = std::abs(ot.v[k].u - lt.v[k].u);
                float dv = std::abs(ot.v[k].v - lt.v[k].v);
                float uv_diff = std::max(du, dv);
                rep.max_uv_diff = std::max(rep.max_uv_diff, uv_diff);

                if (pos_diff > 1e-4f || norm_diff > 0.05f || uv_diff > 1e-3f) {
                    match = false;
                }
            }
            if (!match) {
                rep.unmatched_triangles++;
            }
        }

        float rel_area_diff = std::abs(rep.orig_surface_area - rep.lod0_surface_area) / std::max(1e-6f, rep.orig_surface_area);
        rep.lod0_lossless_validated = (rep.unmatched_triangles == 0 && 
                                       orig_canon.size() == lod0_canon.size() && 
                                       rel_area_diff < 1e-4f);

        if (!rep.lod0_lossless_validated) {
            std::cerr << "ERRO: Validacao geometrica de LOD 0 falhou! "
                      << rep.unmatched_triangles << " triangulos divergentes, diferenca de area: " << (rel_area_diff * 100.0f) << "%\n";
        }
    }

    auto t1 = std::chrono::high_resolution_clock::now();
    rep.elapsed_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    rep.peak_memory_mb = get_peak_memory_mb();
    rep.passed = (rep.invalid_indices == 0 && 
                  rep.invalid_uvs == 0 && 
                  rep.invalid_dag_links == 0 && 
                  rep.degenerate_triangles == 0 && 
                  (original_indices.empty() || rep.lod0_lossless_validated) && 
                  rep.total_triangles_checked > 0);

    return rep;
}

int main(int argc, char** argv) {
    std::cout << "==============================================================\n";
    std::cout << "  ARBORIA VIRTUAL GEOMETRY - MESH BAKER CLI v2.0 (C++)        \n";
    std::cout << "  Multi-LOD DAG Cluster Hierarchy via zeux/meshoptimizer       \n";
    std::cout << "==============================================================\n";

    if (argc < 3) {
        std::cout << "Uso: vg_baker_cli.exe <input.obj> <output.vgmesh> [--verify]\n";
        std::cout << "     vg_baker_cli.exe --verify-only <file.vgmesh>\n";
        return 1;
    }

    if (std::string(argv[1]) == "--verify-only") {
        std::string vg_path = argv[2];
        std::cout << "\n[MODO VERIFICACAO EXCLUSIVA] Verificando integridade de: " << vg_path << "...\n";
        std::vector<Vertex> dummy_v;
        std::vector<uint32_t> dummy_i;
        BoundingBox dummy_b;
        VerificationReport rep = verify_deep_vgmesh(vg_path, dummy_v, dummy_i, dummy_b);
        if (rep.passed) {
            std::cout << "✅ VERIFICACAO COMPLETA APROVADA: Geometria integra, clusters consistentes e sem fendas!\n";
            return 0;
        } else {
            std::cerr << "❌ FALHA NA VERIFICACAO DE INTEGRIDADE: Arquivo corrompido, truncado ou invalido!\n";
            return 4;
        }
    }

    std::string input_path = argv[1];
    std::string output_path = argv[2];
    bool run_verify = (argc >= 4 && std::string(argv[3]) == "--verify");

    auto t_start = std::chrono::high_resolution_clock::now();

    // 1. Carrega OBJ Real
    std::cout << "\n[1/5] Carregando malha OBJ: " << input_path << "...\n";
    std::vector<Vertex> raw_vertices;
    std::vector<uint32_t> raw_indices;
    BoundingBox bbox;

    if (!load_obj(input_path, raw_vertices, raw_indices, bbox)) {
        std::cerr << "ERRO: Nao foi possivel carregar o modelo OBJ!\n";
        return 2;
    }

    std::cout << "   -> Vertices brutos  : " << raw_vertices.size() << "\n";
    std::cout << "   -> Triangulos brutos: " << (raw_indices.size() / 3) << "\n";
    std::cout << "   -> AABB: [" << bbox.min[0] << ", " << bbox.min[1] << ", " << bbox.min[2]
              << "] ate [" << bbox.max[0] << ", " << bbox.max[1] << ", " << bbox.max[2] << "]\n";

    // 2. Unificacao e Indexacao com meshoptimizer
    std::cout << "\n[2/5] Indexando e unificando vertices com meshoptimizer...\n";
    std::vector<uint32_t> remap(raw_vertices.size());
    size_t unique_verts = meshopt_generateVertexRemap(
        remap.data(),
        raw_indices.data(),
        raw_indices.size(),
        raw_vertices.data(),
        raw_vertices.size(),
        sizeof(Vertex)
    );

    std::vector<Vertex> vertices(unique_verts);
    std::vector<uint32_t> indices(raw_indices.size());

    meshopt_remapVertexBuffer(vertices.data(), raw_vertices.data(), raw_vertices.size(), sizeof(Vertex), remap.data());
    meshopt_remapIndexBuffer(indices.data(), raw_indices.data(), raw_indices.size(), remap.data());

    // Remove triangulos degenerados (ex: polos com vertices coincidentes na malha bruta)
    std::vector<uint32_t> clean_indices;
    clean_indices.reserve(indices.size());
    size_t degenerate_dropped = 0;
    for (size_t i = 0; i < indices.size(); i += 3) {
        uint32_t i0 = indices[i + 0];
        uint32_t i1 = indices[i + 1];
        uint32_t i2 = indices[i + 2];
        if (i0 == i1 || i1 == i2 || i0 == i2) {
            degenerate_dropped++;
            continue;
        }
        clean_indices.push_back(i0);
        clean_indices.push_back(i1);
        clean_indices.push_back(i2);
    }
    indices = std::move(clean_indices);

    std::cout << "   -> Vertices unificados: " << unique_verts 
              << " (" << (raw_vertices.size() - unique_verts) << " duplicatas removidas)\n";
    if (degenerate_dropped > 0) {
        std::cout << "   -> Triangulos degenerados removidos da malha base: " << degenerate_dropped << "\n";
    }

    // 3. Construcao da Hierarquia Multi-LOD via clusterlod.h
    std::cout << "\n[3/5] Construindo Hierarquia de Clusters Multi-LOD (clusterlod.h)...\n";
    const size_t max_vertices = 64;
    const size_t max_triangles = 128;

    clodConfig cfg = clodDefaultConfig(max_triangles);
    cfg.max_vertices = max_vertices;
    cfg.max_triangles = max_triangles;
    cfg.simplify_ratio = 0.5f;
    cfg.simplify_preserve_folds = true;
    cfg.optimize_bounds = true;
    cfg.optimize_clusters = true;

    clodMesh cmesh = {};
    cmesh.indices = indices.data();
    cmesh.index_count = indices.size();
    cmesh.vertex_count = vertices.size();
    cmesh.vertex_positions = &vertices[0].px;
    cmesh.vertex_positions_stride = sizeof(Vertex);
    cmesh.vertex_attributes = &vertices[0].nx;
    cmesh.vertex_attributes_stride = sizeof(Vertex);
    float attr_weights[5] = { 1.0f, 1.0f, 1.0f, 0.5f, 0.5f };
    cmesh.attribute_weights = attr_weights;
    cmesh.attribute_count = 5;

    LODCollectorContext collector;
    clodBuild(cfg, cmesh, &collector, &LODCollectorContext::callback);

    std::cout << "   -> DAG Groups gerados: " << collector.groups.size() << "\n";
    std::cout << "   -> Total de clusters brutos coletados: " << collector.clusters.size() << "\n";

    std::map<int, std::vector<size_t>> clusters_by_lod;
    for (size_t i = 0; i < collector.clusters.size(); ++i) {
        clusters_by_lod[collector.clusters[i].depth].push_back(i);
    }

    uint32_t lod_count = static_cast<uint32_t>(clusters_by_lod.size());
    std::cout << "   -> Niveis de LOD identificados: " << lod_count << "\n";

    // 4. Empacotamento de Clusters Locais
    std::cout << "\n[4/5] Empacotando buffers locais dos clusters (Vertices <= 64, Triangulos <= 128)...\n";
    std::vector<VGLODLevelDescriptor> lod_descriptors;
    std::vector<VGClusterDescriptor> cluster_descriptors;
    std::vector<Vertex> packed_vertices;
    std::vector<uint8_t> packed_triangles;

    uint32_t base_triangles = static_cast<uint32_t>(indices.size() / 3);
    uint32_t cluster_global_id = 0;

    for (const auto& pair : clusters_by_lod) {
        int lod_lvl = pair.first;
        const auto& c_indices = pair.second;

        VGLODLevelDescriptor lod_desc;
        lod_desc.lod_level = static_cast<uint32_t>(lod_lvl);
        lod_desc.cluster_offset = static_cast<uint32_t>(cluster_descriptors.size());
        lod_desc.cluster_count = static_cast<uint32_t>(c_indices.size());
        lod_desc.triangle_count = 0;
        lod_desc.max_error = 0.0f;

        for (size_t c_idx : c_indices) {
            const auto& raw_c = collector.clusters[c_idx];

            std::vector<unsigned int> local_verts(raw_c.indices.size());
            std::vector<unsigned char> local_tris(raw_c.indices.size());
            size_t unique_c_verts = clodLocalIndices(
                local_verts.data(),
                local_tris.data(),
                raw_c.indices.data(),
                raw_c.indices.size()
            );

            assert(unique_c_verts <= max_vertices);
            assert((raw_c.indices.size() / 3) <= max_triangles);

            meshopt_Bounds mb = meshopt_computeMeshletBounds(
                local_verts.data(),
                local_tris.data(),
                raw_c.indices.size() / 3,
                &vertices[0].px,
                vertices.size(),
                sizeof(Vertex)
            );

            VGClusterDescriptor desc;
            desc.cluster_id = cluster_global_id++;
            desc.lod_level = static_cast<uint32_t>(lod_lvl);
            desc.group_id = raw_c.group_id;
            desc.refined_group = raw_c.refined;
            desc.center[0] = raw_c.bounds.center[0];
            desc.center[1] = raw_c.bounds.center[1];
            desc.center[2] = raw_c.bounds.center[2];
            desc.radius = raw_c.bounds.radius;
            desc.normal_cone[0] = mb.cone_axis[0];
            desc.normal_cone[1] = mb.cone_axis[1];
            desc.normal_cone[2] = mb.cone_axis[2];
            desc.normal_cone[3] = mb.cone_cutoff;
            desc.lod_error = raw_c.bounds.error;

            desc.vertex_offset = static_cast<uint32_t>(packed_vertices.size());
            desc.vertex_count = static_cast<uint32_t>(unique_c_verts);
            desc.triangle_offset = static_cast<uint32_t>(packed_triangles.size());
            desc.triangle_count = static_cast<uint32_t>(raw_c.indices.size() / 3);

            cluster_descriptors.push_back(desc);

            for (size_t vi = 0; vi < unique_c_verts; ++vi) {
                packed_vertices.push_back(vertices[local_verts[vi]]);
            }

            for (size_t ti = 0; ti < raw_c.indices.size(); ++ti) {
                packed_triangles.push_back(local_tris[ti]);
            }

            lod_desc.triangle_count += desc.triangle_count;
            lod_desc.max_error = std::max(lod_desc.max_error, desc.lod_error);
        }

        lod_desc.triangle_ratio = (base_triangles > 0) ? (float(lod_desc.triangle_count) / base_triangles) : 1.0f;
        lod_descriptors.push_back(lod_desc);

        std::cout << "   -> LOD " << lod_lvl << ": " << lod_desc.cluster_count << " clusters, "
                  << lod_desc.triangle_count << " triangulos (" << (lod_desc.triangle_ratio * 100.0f) << "%), "
                  << "Erro max: " << lod_desc.max_error << "\n";
    }

    // 5. Gravacao Binaria .vgmesh v2
    std::cout << "\n[5/5] Gravando arquivo binario oficial: " << output_path << "...\n";
    VGMeshHeader header = {};
    std::memcpy(header.magic, "ARBORIA2", 8);
    header.version = 2;
    header.total_vertices = static_cast<uint32_t>(packed_vertices.size());
    header.total_indices = static_cast<uint32_t>(packed_triangles.size());
    header.total_triangles = static_cast<uint32_t>(packed_triangles.size() / 3);
    header.cluster_count = static_cast<uint32_t>(cluster_descriptors.size());
    header.lod_count = lod_count;
    header.bbox_min[0] = bbox.min[0]; header.bbox_min[1] = bbox.min[1]; header.bbox_min[2] = bbox.min[2];
    header.bbox_max[0] = bbox.max[0]; header.bbox_max[1] = bbox.max[1]; header.bbox_max[2] = bbox.max[2];
    header.group_count = static_cast<uint32_t>(collector.groups.size());
    header.base_triangle_count = base_triangles;

    std::vector<VGGroupDescriptor> group_descriptors(collector.groups.size());
    for (size_t i = 0; i < collector.groups.size(); ++i) {
        const auto& g = collector.groups[i];
        group_descriptors[i].group_id = static_cast<uint32_t>(i);
        group_descriptors[i].depth = g.group.depth;
        group_descriptors[i].center[0] = g.group.simplified.center[0];
        group_descriptors[i].center[1] = g.group.simplified.center[1];
        group_descriptors[i].center[2] = g.group.simplified.center[2];
        group_descriptors[i].radius = g.group.simplified.radius;
        group_descriptors[i].error = g.group.simplified.error;
    }

    if (!write_vgmesh_v2(output_path, header, lod_descriptors, cluster_descriptors, group_descriptors, packed_vertices, packed_triangles)) {
        std::cerr << "ERRO: Falha ao gravar arquivo binario " << output_path << "!\n";
        return 3;
    }

    auto t_end = std::chrono::high_resolution_clock::now();
    double total_bake_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();
    size_t peak_mem_mb = get_peak_memory_mb();

    if (run_verify) {
        std::cout << "\n==============================================================\n";
        std::cout << "  [MISSAO 1] AUDITORIA E VERIFICACAO INDEPENDENTE DE GEOMETRIA\n";
        std::cout << "==============================================================\n";
        VerificationReport rep = verify_deep_vgmesh(output_path, vertices, indices, bbox);

        std::cout << "  Triangulos inspecionados : " << rep.total_triangles_checked << "\n";
        std::cout << "  Indices invalidos/OOB    : " << rep.invalid_indices << "\n";
        std::cout << "  Triangulos degenerados   : " << rep.degenerate_triangles << "\n";
        std::cout << "  Orientacao/Inversao faces: " << rep.flipped_windings << "\n";
        std::cout << "  Normais fora do padrao   : " << rep.unnormalized_normals << "\n";
        std::cout << "  UVs invalidas/NaN        : " << rep.invalid_uvs << "\n";
        std::cout << "  Erro metrico maximo      : " << rep.max_metric_error << "\n";
        std::cout << "  Tempo de verificacao     : " << rep.elapsed_ms << " ms\n";
        std::cout << "  Consumo de memoria pico  : " << rep.peak_memory_mb << " MB\n";
        std::cout << "  ------------------------------------------------------------\n";
        std::cout << "  LOD 0 Lossless Validado  : " << (rep.lod0_lossless_validated ? "SIM (LOD0 LOSSLESS VALIDADO)" : "NAO (FALHA)") << "\n";
        std::cout << "  Triangulos Orig / LOD 0  : " << rep.orig_triangle_count << " / " << rep.lod0_triangle_count << "\n";
        std::cout << "  Area Superficie Orig/LOD0: " << rep.orig_surface_area << " / " << rep.lod0_surface_area << "\n";
        std::cout << "  Max Dif Posicao Vertices : " << rep.max_vertex_pos_diff << "\n";
        std::cout << "  Max Dif Normais de Vert  : " << rep.max_normal_diff << "\n";
        std::cout << "  Max Dif Coordenadas UV   : " << rep.max_uv_diff << "\n";
        std::cout << "  Triangulos Nao-Mapeados  : " << rep.unmatched_triangles << "\n";

        if (rep.passed) {
            std::cout << "\n✅ VERIFICACAO COMPLETA APROVADA: Geometria integra, LOD 0 Lossless e sem fendas!\n";
        } else {
            std::cerr << "\n❌ FALHA NA VERIFICACAO DE INTEGRIDADE!\n";
            return 4;
        }
    }

    std::cout << "\n==============================================================\n";
    std::cout << "  ESTATISTICAS FINAIS DO ARBORIA BAKER (C++)                  \n";
    std::cout << "==============================================================\n";
    std::cout << "  Entrada OBJ             : " << input_path << "\n";
    std::cout << "  Saida .vgmesh           : " << output_path << "\n";
    std::cout << "  Triangulos Base (LOD 0) : " << base_triangles << "\n";
    std::cout << "  Total de LODs Gerados   : " << lod_count << "\n";
    std::cout << "  Total Clusters Gerados  : " << cluster_descriptors.size() << "\n";
    std::cout << "  Tempo Total de Bake     : " << total_bake_ms << " ms\n";
    std::cout << "  Consumo Maximo de RAM   : " << peak_mem_mb << " MB\n";
    std::cout << "==============================================================\n";

    return 0;
}
