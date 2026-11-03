#include "arboria_geometric_compiler.h"
#include "arboria_mesh_resource.h"
#include "arboria_logger.h"
#include <algorithm>
#include <vector>
#include <queue>
#include <string>
#include <cstring>
#include <cmath>
#include <fstream>
#include <chrono>
#include <map>
#include <set>
#include <utility>
#include <limits>

namespace {

// ============================================================================
// QEM (Quadric Error Metrics) — simplificacao geometrica por edge-collapse
// ============================================================================

// Matriz quadrica 4x4 simetrica (10 elementos unicos)
struct QemQuadric {
    float m[10]; // [00,01,02,03, 11,12,13, 22,23, 33]

    QemQuadric() { std::memset(m, 0, sizeof(m)); }

    QemQuadric operator+(const QemQuadric& o) const {
        QemQuadric r;
        for (int i = 0; i < 10; ++i) r.m[i] = m[i] + o.m[i];
        return r;
    }

    // Avalia v^T * Q * v com v = (x, y, z, 1)
    float eval(float x, float y, float z) const {
        return m[0] * x * x + 2.f * m[1] * x * y + 2.f * m[2] * x * z + 2.f * m[3] * x
             + m[4] * y * y + 2.f * m[5] * y * z + 2.f * m[6] * y
             + m[7] * z * z + 2.f * m[8] * z
             + m[9];
    }
};

// Quadrico do plano definido por um triangulo (normalizada)
QemQuadric make_plane_quadric(const float* v0, const float* v1, const float* v2) {
    float nx = (v1[1] - v0[1]) * (v2[2] - v0[2]) - (v1[2] - v0[2]) * (v2[1] - v0[1]);
    float ny = (v1[2] - v0[2]) * (v2[0] - v0[0]) - (v1[0] - v0[0]) * (v2[2] - v0[2]);
    float nz = (v1[0] - v0[0]) * (v2[1] - v0[1]) - (v1[1] - v0[1]) * (v2[0] - v0[0]);
    float len = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (len < 1e-12f) return QemQuadric();
    nx /= len; ny /= len; nz /= len;
    float d = -(nx * v0[0] + ny * v0[1] + nz * v0[2]);
    QemQuadric q;
    q.m[0] = nx * nx;  q.m[1] = nx * ny; q.m[2] = nx * nz; q.m[3] = nx * d;
    q.m[4] = ny * ny;  q.m[5] = ny * nz; q.m[6] = ny * d;
    q.m[7] = nz * nz;  q.m[8] = nz * d;
    q.m[9] = d * d;
    return q;
}

// Resolve sistema 3x3 A*x = b por eliminacao de Gauss com pivotamento
bool solve3x3(float A[3][3], const float b[3], float x[3]) {
    float aug[3][4];
    for (int i = 0; i < 3; ++i) {
        aug[i][0] = A[i][0]; aug[i][1] = A[i][1]; aug[i][2] = A[i][2]; aug[i][3] = b[i];
    }
    for (int col = 0; col < 3; ++col) {
        int piv = col;
        float mv = std::abs(aug[col][col]);
        for (int r = col + 1; r < 3; ++r) {
            if (std::abs(aug[r][col]) > mv) { mv = std::abs(aug[r][col]); piv = r; }
        }
        if (mv < 1e-12f) return false;
        if (piv != col) {
            for (int k = 0; k < 4; ++k) std::swap(aug[col][k], aug[piv][k]);
        }
        for (int r = col + 1; r < 3; ++r) {
            float f = aug[r][col] / aug[col][col];
            for (int k = col; k < 4; ++k) aug[r][k] -= f * aug[col][k];
        }
    }
    for (int i = 2; i >= 0; --i) {
        x[i] = aug[i][3];
        for (int j = i + 1; j < 3; ++j) x[i] -= aug[i][j] * x[j];
        x[i] /= aug[i][i];
    }
    return true;
}

// Posicao ideal de colapso e erro para a aresta (p1, p2)
bool compute_collapse(const QemQuadric& q1, const QemQuadric& q2,
                      const float* p1, const float* p2,
                      float* out_pos, float& out_error) {
    QemQuadric q = q1 + q2;
    float A[3][3] = {
        {q.m[0], q.m[1], q.m[2]},
        {q.m[1], q.m[4], q.m[5]},
        {q.m[2], q.m[5], q.m[7]}
    };
    float b[3] = { -q.m[3], -q.m[6], -q.m[8] };
    float pos[3];
    if (!solve3x3(A, b, pos)) {
        pos[0] = (p1[0] + p2[0]) * 0.5f;
        pos[1] = (p1[1] + p2[1]) * 0.5f;
        pos[2] = (p1[2] + p2[2]) * 0.5f;
    }
    out_error = q.eval(pos[0], pos[1], pos[2]);
    out_pos[0] = pos[0]; out_pos[1] = pos[1]; out_pos[2] = pos[2];
    return true;
}

// Normaliza um vetor 3D (retorna false se degenerado)
bool normalize3(float v[3]) {
    float len = std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len < 1e-12f) return false;
    v[0] /= len; v[1] /= len; v[2] /= len;
    return true;
}

// Produto vetorial a x b
void cross3(const float* a, const float* b, float* out) {
    out[0] = a[1] * b[2] - a[2] * b[1];
    out[1] = a[2] * b[0] - a[0] * b[2];
    out[2] = a[0] * b[1] - a[1] * b[0];
}

// Declaracao antecipada: verificacao de inversao de face no QEM
static bool face_would_invert(
    uint32_t t, uint32_t a, uint32_t b, const float p[3],
    const std::vector<uint32_t>& vmap,
    const std::vector<float>& vpos,
    const std::vector<float>& in_verts,
    const std::vector<uint32_t>& in_tris,
    const std::vector<bool>& tdead);

// Simplificacao QEM: colapsa arestas de menor erro ate atingir target_triangles.
// Usa fila de prioridade com atualizacao preguiçosa (lazy) para recomputar
// erros apos cada colapso. Preserva arestas de bordo, arestas vivas e impede
// colapsos que invertram faces ou criem triangulos degenerados.
// Retorna o erro maximo de colapso efetivamente realizado (ou 0 se nao houve colapso).
// Se in_uvs for fornecido (nao nullptr), os UVs sao preservados atraves dos
// colapsos (media dos UVs dos vertices colapsados) e escritos em out_uvs.
float qem_simplify(
    const std::vector<float>& in_verts,
    const std::vector<uint32_t>& in_tris,
    uint32_t target_tris,
    float sharp_edge_threshold,
    std::vector<float>& out_verts,
    std::vector<uint32_t>& out_tris,
    const float* in_uvs = nullptr,
    std::vector<float>* out_uvs = nullptr)
{
    out_verts.clear();
    out_tris.clear();

    uint32_t nverts = static_cast<uint32_t>(in_verts.size() / 3);
    uint32_t ntris = static_cast<uint32_t>(in_tris.size() / 3);
    if (ntris == 0 || nverts < 3) return 0.0f;
    if (ntris <= target_tris || target_tris == 0) {
        out_verts = in_verts;
        out_tris = in_tris;
        return 0.0f;
    }
    target_tris = std::max(target_tris, 1u);

    // Quadrico por vertice (soma dos planos dos triangulos incidentes)
    std::vector<QemQuadric> vquad(nverts);
    std::vector<std::vector<uint32_t>> v2t(nverts);
    for (uint32_t t = 0; t < ntris; ++t) {
        for (int k = 0; k < 3; ++k) v2t[in_tris[t * 3 + k]].push_back(t);
    }
    for (uint32_t v = 0; v < nverts; ++v) {
        QemQuadric q;
        for (uint32_t t : v2t[v]) {
            const float* p0 = &in_verts[in_tris[t * 3] * 3];
            const float* p1 = &in_verts[in_tris[t * 3 + 1] * 3];
            const float* p2 = &in_verts[in_tris[t * 3 + 2] * 3];
            q = q + make_plane_quadric(p0, p1, p2);
        }
        vquad[v] = q;
    }

    // Chave de aresta (ordenada) para mapa de adjacencia
    auto edge_key = [](uint32_t a, uint32_t b) -> uint64_t {
        if (a > b) std::swap(a, b);
        return ((uint64_t)a << 32) | (uint64_t)b;
    };

    // Recontar incidencias de aresta com o estado atual (vmap/tdead).
    // Aresta eh interna se pertence a exatamente 2 triangulos vivos.
    // Declaracoes antecipadas (edge_count, vmap, tdead) para capturar por
    // referencia no lambda; variaveis usadas antes da declaracao causariam
    // erro de compilacao (lookup de nomes ocorre na definicao do lambda).
    std::map<uint64_t, int> edge_count;
    std::vector<uint32_t> vmap(nverts);
    for (uint32_t v = 0; v < nverts; ++v) vmap[v] = v;
    std::vector<bool> tdead(ntris, false);

    auto recompute_edge_count = [&]() {
        edge_count.clear();
        for (uint32_t t = 0; t < ntris; ++t) {
            if (tdead[t]) continue;
            uint32_t x = vmap[in_tris[t * 3]];
            uint32_t y = vmap[in_tris[t * 3 + 1]];
            uint32_t z = vmap[in_tris[t * 3 + 2]];
            if (x == y || y == z || x == z) continue; // degenerado
            edge_count[edge_key(x, y)]++;
            edge_count[edge_key(y, z)]++;
            edge_count[edge_key(z, x)]++;
        }
    };

    recompute_edge_count();

    // Estado de colapso
    std::vector<float> vpos = in_verts; // posicoes mutaveis
    std::vector<float> vuv(nverts * 2, 0.0f); // UVs mutaveis (preservacao atraves de colapsos)
    if (in_uvs) {
        for (uint32_t v = 0; v < nverts; ++v) {
            vuv[v * 2] = in_uvs[v * 2];
            vuv[v * 2 + 1] = in_uvs[v * 2 + 1];
        }
    }
    std::vector<bool> vdead(nverts, false);
    uint32_t remaining = ntris;
    float max_collapse_error = 0.0f; // erro maximo de colapso efetivamente realizado

    // Candidato de aresta para a fila de prioridade (min-heap por erro)
    struct EdgeCand {
        uint32_t a, b;   // indices originais (mapeados via vmap na hora de usar)
        float error;     // erro estimado no momento da insercao
        bool sharp;      // aresta viva (nao colapsar)
        bool operator>(const EdgeCand& o) const { return error > o.error; }
    };

    // Calcula se a aresta (a,b) e viva (angulo diedro > threshold).
    // Usa posicoes atuais (vpos) e mapeamento (vmap) para refletir colapsos ja feitos.
    // Normais sao normalizadas antes do produto escalar para angulo correto.
    // Normais degeneradas (vetor nulo) sao ignoradas.
    auto is_sharp_edge = [&](uint32_t a, uint32_t b) -> bool {
        float n1[3] = {0,0,0}, n2[3] = {0,0,0};
        bool found1 = false, found2 = false;
        for (uint32_t t2 = 0; t2 < ntris && !(found1 && found2); ++t2) {
            if (tdead[t2]) continue;
            uint32_t x = vmap[in_tris[t2 * 3]];
            uint32_t y = vmap[in_tris[t2 * 3 + 1]];
            uint32_t z = vmap[in_tris[t2 * 3 + 2]];
            if (x == y || y == z || x == z) continue; // degenerado
            bool has_a = (x == a || y == a || z == a);
            bool has_b = (x == b || y == b || z == b);
            if (has_a && has_b) {
                const float* p0 = &vpos[x * 3];
                const float* p1 = &vpos[y * 3];
                const float* p2 = &vpos[z * 3];
                float e1x = p1[0] - p0[0], e1y = p1[1] - p0[1], e1z = p1[2] - p0[2];
                float e2x = p2[0] - p0[0], e2y = p2[1] - p0[1], e2z = p2[2] - p0[2];
                float ea[3] = {e1x, e1y, e1z};
                float eb[3] = {e2x, e2y, e2z};
                float n[3]; cross3(ea, eb, n);
                float len = std::sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]);
                if (len < 1e-12f) continue; // normal degenerada, ignora
                n[0] /= len; n[1] /= len; n[2] /= len;
                if (!found1) { n1[0] = n[0]; n1[1] = n[1]; n1[2] = n[2]; found1 = true; }
                else { n2[0] = n[0]; n2[1] = n[1]; n2[2] = n[2]; found2 = true; }
            }
        }
        if (!found1 || !found2) return false;
        float dot = n1[0]*n2[0] + n1[1]*n2[1] + n1[2]*n2[2];
        dot = std::max(-1.f, std::min(1.f, dot));
        float angle = std::acos(dot);
        return angle > sharp_edge_threshold; // preserva aresta viva
    };

    // Conjunto de arestas vivas (sharp) pre-calculado na geometria original.
// Usado para nao colapsar arestas que definem rasgos/duros da malha.
    std::set<uint64_t> sharp_edges;
    for (uint32_t t = 0; t < ntris; ++t) {
        for (int k = 0; k < 3; ++k) {
            uint32_t a = in_tris[t * 3 + k];
            uint32_t b = in_tris[t * 3 + (k + 1) % 3];
            if (a > b) std::swap(a, b);
            if (is_sharp_edge(a, b)) sharp_edges.insert(edge_key(a, b));
        }
    }

    // Candidato de colapso para a aresta (a,b) com o estado atual
    auto make_candidate = [&](uint32_t a, uint32_t b) -> EdgeCand {
        float pos[3];
        float err;
        compute_collapse(vquad[a], vquad[b], &vpos[a * 3], &vpos[b * 3], pos, err);
        bool sharp = sharp_edges.count(edge_key(a, b)) > 0;
        return EdgeCand{a, b, err, sharp};
    };

    std::priority_queue<EdgeCand, std::vector<EdgeCand>, std::greater<EdgeCand>> pq;

    // Insere candidatos iniciais: arestas internas (edge_count == 2), nao vivas
    for (uint32_t t = 0; t < ntris; ++t) {
        for (int k = 0; k < 3; ++k) {
            uint32_t a = in_tris[t * 3 + k];
            uint32_t b = in_tris[t * 3 + (k + 1) % 3];
            if (a > b) std::swap(a, b);
            uint64_t ek = edge_key(a, b);
            auto it = edge_count.find(ek);
            if (it == edge_count.end() || it->second != 2) continue; // so arestas internas
            pq.push(make_candidate(a, b));
        }
    }

    // Loop principal com fila de prioridade e atualizacao preguiçosa
    while (!pq.empty() && remaining > target_tris) {
        EdgeCand c = pq.top();
        pq.pop();

        uint32_t a = vmap[c.a];
        uint32_t b = vmap[c.b];
        if (a == b) continue;
        if (vdead[a] || vdead[b]) continue;

        // Aresta nao e mais interna (adjacencia mudou apos colapsos anteriores) -> descarta
        uint64_t ek_cur = edge_key(a, b);
        auto it_cur = edge_count.find(ek_cur);
        if (it_cur == edge_count.end() || it_cur->second != 2) continue;

        // Re-verificar se a aresta e viva com o estado atual (geometria mudou)
        if (is_sharp_edge(a, b)) continue; // preserva arestas vivas

        // Recalcula o erro com o estado atual (atualizacao preguiçosa)
        float pos[3];
        float new_err;
        compute_collapse(vquad[a], vquad[b], &vpos[a * 3], &vpos[b * 3], pos, new_err);

        // Se o erro mudou significativamente, reinsere com novo erro e pula
        if (std::abs(new_err - c.error) > 1e-6f * std::max(1.0f, c.error)) {
            pq.push(EdgeCand{c.a, c.b, new_err, sharp_edges.count(edge_key(c.a, c.b)) > 0});
            continue;
        }

        // Verifica inversao de faces: colapsar b em a na posicao 'pos'
        bool invert = false;
        for (uint32_t t : v2t[a]) {
            if (tdead[t]) continue;
            invert = face_would_invert(t, a, b, pos, vmap, vpos, in_verts, in_tris, tdead);
            if (invert) break;
        }
        if (!invert) {
            for (uint32_t t : v2t[b]) {
                if (tdead[t]) continue;
                invert = face_would_invert(t, a, b, pos, vmap, vpos, in_verts, in_tris, tdead);
                if (invert) break;
            }
        }
        if (invert) continue; // rejeita colapso que inverte face

        // Verifica colapso agressivo demais (muitos triangulos degenerariam)
        uint32_t would_die = 0;
        for (uint32_t t = 0; t < ntris; ++t) {
            if (tdead[t]) continue;
            uint32_t x = vmap[in_tris[t * 3]];
            uint32_t y = vmap[in_tris[t * 3 + 1]];
            uint32_t z = vmap[in_tris[t * 3 + 2]];
            if ((x == a || x == b) && (y == a || y == b) && (z == a || z == b)) {
                if (x == y || y == z || x == z) would_die++;
            }
        }
        if (would_die > remaining / 2) continue;

        // Colapsa b em a na posicao ideal
        vdead[b] = true;
        vmap[b] = a;
        vpos[a * 3] = pos[0];
        vpos[a * 3 + 1] = pos[1];
        vpos[a * 3 + 2] = pos[2];
        // Preservacao de atributos: UVs.
        // Nao mediar UVs quando isso destruiria uma costura (vertices com UVs diferentes).
        // Manter os UVs do vertice sobrevivente (a) para preservar costuras.
        float du = vuv[a * 2] - vuv[b * 2];
        float dv = vuv[a * 2 + 1] - vuv[b * 2 + 1];
        if (du * du + dv * dv > 1e-6f) {
            // Costura UV detectada: manter UVs do vertice a, nao mediar
        } else {
            vuv[a * 2] = (vuv[a * 2] + vuv[b * 2]) * 0.5f;
            vuv[a * 2 + 1] = (vuv[a * 2 + 1] + vuv[b * 2 + 1]) * 0.5f;
        }
        vquad[a] = vquad[a] + vquad[b];
        if (new_err > max_collapse_error) max_collapse_error = new_err;

        // Marca triangulos degenerados
        for (uint32_t t = 0; t < ntris; ++t) {
            if (tdead[t]) continue;
            uint32_t x = vmap[in_tris[t * 3]];
            uint32_t y = vmap[in_tris[t * 3 + 1]];
            uint32_t z = vmap[in_tris[t * 3 + 2]];
            if (x == y || y == z || x == z) {
                tdead[t] = true;
                remaining--;
            }
        }

        // Atualizar adjacencia apos o colapso: arestas mudaram de conectividade
        recompute_edge_count();

        // Reinsere candidatos para arestas incidentes a a ou b (apos o colapso)
        auto reinsert_edges = [&](uint32_t v) {
            for (uint32_t t : v2t[v]) {
                if (tdead[t]) continue;
                for (int k = 0; k < 3; ++k) {
                    uint32_t v1 = vmap[in_tris[t * 3 + k]];
                    uint32_t v2 = vmap[in_tris[t * 3 + (k + 1) % 3]];
                    if (v1 == v2) continue;
                    if (v1 > v2) std::swap(v1, v2);
                    uint64_t ek = edge_key(v1, v2);
                    auto it = edge_count.find(ek);
                    if (it == edge_count.end() || it->second != 2) continue;
                    pq.push(make_candidate(v1, v2));
                }
            }
        };
        reinsert_edges(a);
        reinsert_edges(b);
    }

    // Compacta vertices vivos
    std::vector<uint32_t> new_index(nverts, 0xFFFFFFFFu);
    uint32_t nlive = 0;
    for (uint32_t v = 0; v < nverts; ++v) {
        if (!vdead[v]) { new_index[v] = nlive++; }
    }
    out_verts.resize(nlive * 3);
    if (out_uvs) out_uvs->resize(nlive * 2);
    for (uint32_t v = 0; v < nverts; ++v) {
        if (!vdead[v]) {
            uint32_t ni = new_index[v];
            out_verts[ni * 3] = vpos[v * 3];
            out_verts[ni * 3 + 1] = vpos[v * 3 + 1];
            out_verts[ni * 3 + 2] = vpos[v * 3 + 2];
            if (out_uvs) {
                (*out_uvs)[ni * 2] = vuv[v * 2];
                (*out_uvs)[ni * 2 + 1] = vuv[v * 2 + 1];
            }
        }
    }

    // Re-mapeia indices e remove triangulos mortos
    for (uint32_t t = 0; t < ntris; ++t) {
        if (tdead[t]) continue;
        uint32_t x = new_index[vmap[in_tris[t * 3]]];
        uint32_t y = new_index[vmap[in_tris[t * 3 + 1]]];
        uint32_t z = new_index[vmap[in_tris[t * 3 + 2]]];
        if (x == 0xFFFFFFFFu || y == 0xFFFFFFFFu || z == 0xFFFFFFFFu) continue;
        if (x == y || y == z || x == z) continue;
        out_tris.push_back(x);
        out_tris.push_back(y);
        out_tris.push_back(z);
    }

    return max_collapse_error;
}

// Verifica se colapsar b em a na posicao p inverteria a normal do triangulo t
static bool face_would_invert(
    uint32_t t,
    uint32_t a, uint32_t b,
    const float p[3],
    const std::vector<uint32_t>& vmap,
    const std::vector<float>& vpos,
    const std::vector<float>& in_verts,
    const std::vector<uint32_t>& in_tris,
    const std::vector<bool>& tdead)
{
    if (tdead[t]) return false;

    uint32_t x = vmap[in_tris[t * 3]];
    uint32_t y = vmap[in_tris[t * 3 + 1]];
    uint32_t z = vmap[in_tris[t * 3 + 2]];

    // O triangulo deve envolver a ou b para ser afetado pelo colapso
    if (x != a && x != b && y != a && y != b && z != a && z != b) return false;

    // Substitui b por a (o colapso move b para a na posicao p)
    if (x == b) x = a;
    if (y == b) y = a;
    if (z == b) z = a;
    if (x == y || y == z || x == z) return false; // degenerado (ja tratado)

    // Posicoes atuais (antes do colapso)
    const float* px = (x == a) ? p : &vpos[x * 3];
    const float* py = (y == a) ? p : &vpos[y * 3];
    const float* pz = (z == a) ? p : &vpos[z * 3];

    // Normal apos colapso
    float e1x = py[0] - px[0], e1y = py[1] - px[1], e1z = py[2] - px[2];
    float e2x = pz[0] - px[0], e2y = pz[1] - px[1], e2z = pz[2] - px[2];
    float ea[3] = {e1x, e1y, e1z};
    float eb[3] = {e2x, e2y, e2z};
    float nnew[3]; cross3(ea, eb, nnew);
    float len_new = std::sqrt(nnew[0]*nnew[0] + nnew[1]*nnew[1] + nnew[2]*nnew[2]);
    if (len_new < 1e-12f) return true; // degenerado apos colapso

    // Normal atual (antes do colapso, usando vpos)
    const float* cx = (x == a) ? &vpos[a * 3] : &vpos[x * 3];
    const float* cy = (y == a) ? &vpos[a * 3] : &vpos[y * 3];
    const float* cz = (z == a) ? &vpos[a * 3] : &vpos[z * 3];
    float ce1x = cy[0] - cx[0], ce1y = cy[1] - cx[1], ce1z = cy[2] - cx[2];
    float ce2x = cz[0] - cx[0], ce2y = cz[1] - cx[1], ce2z = cz[2] - cx[2];
    float ca[3] = {ce1x, ce1y, ce1z};
    float cb[3] = {ce2x, ce2y, ce2z};
    float ncur[3]; cross3(ca, cb, ncur);
    float len_cur = std::sqrt(ncur[0]*ncur[0] + ncur[1]*ncur[1] + ncur[2]*ncur[2]);
    if (len_cur < 1e-12f) return false;

    // Se o produto escalar das normais for negativo, a face inverteu
    float dot = (nnew[0]*ncur[0] + nnew[1]*ncur[1] + nnew[2]*ncur[2]) / (len_new * len_cur);
    return dot < 0.0f;
}

} // namespace

namespace Arboria {

ArboriaGeometricCompiler& ArboriaGeometricCompiler::instance() {
    static ArboriaGeometricCompiler s_inst;
    return s_inst;
}

void ArboriaGeometricCompiler::configure(const CompilerConfig& config) {
    m_config = config;
}

const CompilerConfig& ArboriaGeometricCompiler::get_config() const {
    return m_config;
}

CompiledMesh ArboriaGeometricCompiler::compile(
    const float* vertices, uint32_t vertex_count,
    const float* normals, const float* uvs,
    const uint32_t* indices, uint32_t index_count
) {
    auto t_start = std::chrono::high_resolution_clock::now();

    CompiledMesh result;
    m_last_stats = CompileStats{};
    m_last_stats.input_vertices = vertex_count;
    m_last_stats.input_triangles = index_count / 3;

    if (!vertices || vertex_count == 0 || !indices || index_count == 0 || index_count % 3 != 0) {
        ARBORIA_LOG_ERROR("[ArboriaGeometricCompiler] Dados de entrada invalidos.");
        return result;
    }

    // Validar que todos os indices de triangulo estao dentro do intervalo de vertices
    for (uint32_t i = 0; i < index_count; ++i) {
        if (indices[i] >= vertex_count) {
            ARBORIA_LOG_ERROR("[ArboriaGeometricCompiler] Indice de triangulo fora do intervalo de vertices.");
            return result;
        }
    }

    // 1. Gerar clusters via agrupamento espacial
    build_clusters(vertices, vertex_count, normals, uvs, indices, index_count,
                   result.clusters, result.vertices, result.indices);

    if (result.clusters.empty()) {
        ARBORIA_LOG_ERROR("[ArboriaGeometricCompiler] Nenhum cluster gerado.");
        return result;
    }

    // Gate 06: Corrigir ordem de winding (faceamento) dos clusters LOD 0 —
    // garante orientacao consistente (CCW) essencial para malhas importadas
    // com winding misto e para espelhamento de matrizes.
    validate_and_fix_winding(result.clusters, result.vertices, result.indices);

    // Contagem de clusters do LOD 0 (antes de build_lods anexar clusters de LODs superiores)
    const uint32_t lod0_cluster_count = static_cast<uint32_t>(result.clusters.size());

    // 3. Gerar niveis LOD (build_lods anexa clusters de LODs superiores a result.clusters)
    if (m_config.generate_lods) {
        build_lods(result.clusters, result.vertices, result.indices,
                   result.clusters, result.vertices, result.indices,
                   result.lods);
    } else {
        // Apenas LOD 0 com todos os clusters
        LOD lod0{};
        lod0.level = 0;
        lod0.offset = 0;
        lod0.clusters = static_cast<uint32_t>(result.clusters.size());
        lod0.triangles = 0;
        for (const auto& c : result.clusters) {
            lod0.triangles += c.triangle_count;
        }
        lod0.error = 0.0f;
        lod0.ratio = 1.0f;
        result.lods.push_back(lod0);
    }

    // Gate 06: Corrigir ordem de winding dos clusters de LOD > 0 gerados por build_lods,
    // garantindo faceamento consistente em todos os niveis de detalhe.
    validate_and_fix_winding(result.clusters, result.vertices, result.indices);

    // 2. Construir hierarquia DAG sobre TODOS os clusters (LOD 0 + superiores)
    build_dag_hierarchy(result.clusters, result.groups);

    // 2b. Definir campo refined para transicoes de LOD: clusters de LOD > 0
    // apontam para o grupo do cluster LOD 0 mais proximo espacalmente,
    // permitindo que o shader refine (volte para LOD 0) quando o erro excede o threshold.
    if (m_config.generate_lods && lod0_cluster_count > 0) {
        for (size_t i = lod0_cluster_count; i < result.clusters.size(); ++i) {
            auto& c = result.clusters[i];
            if (c.lod == 0) continue; // LOD 0 nunca precisa de refinamento
            int32_t best_group = -1;
            float best_dist_sq = std::numeric_limits<float>::max();
            for (uint32_t j = 0; j < lod0_cluster_count; ++j) {
                const auto& lod0c = result.clusters[j];
                float dx = c.center[0] - lod0c.center[0];
                float dy = c.center[1] - lod0c.center[1];
                float dz = c.center[2] - lod0c.center[2];
                float dist_sq = dx * dx + dy * dy + dz * dz;
                float radii_sum = c.radius + lod0c.radius;
                // So considera se as esferas se sobrepoem ou estao proximas
                if (dist_sq <= radii_sum * radii_sum * 4.0f) {
                    if (dist_sq < best_dist_sq) {
                        best_dist_sq = dist_sq;
                        best_group = lod0c.group;
                    }
                }
            }
            if (best_group >= 0) c.refined = best_group;
            else c.refined = -1; // nenhum LOD 0 proximo, sem refinamento
        }
    }

    // Gate 06: Validar continuidade de corte DAG entre niveis LOD —
    // clusters de LOD > 0 devem sobrepoem espacialmente o cluster LOD 0 referenciado
    // para garantir transicao geometrica contínua no refinamento.
    uint32_t dag_cut_failures = validate_dag_cut_continuity(result.clusters, result.vertices, result.indices);
    if (dag_cut_failures > 0) {
        ARBORIA_LOG_WARN("[ArboriaGeometricCompiler] " + std::to_string(dag_cut_failures) +
            " clusters de corte DAG fora da tolerancia de continuidade geometrica.");
    }

    // 4. Preencher cabecalho
    result.header.magic[0] = 'A'; result.header.magic[1] = 'R';
    result.header.magic[2] = 'B'; result.header.magic[3] = 'O';
    result.header.magic[4] = 'R'; result.header.magic[5] = 'I';
    result.header.magic[6] = 'A'; result.header.magic[7] = '2';
    result.header.version = 2;
    result.header.vertices = static_cast<uint32_t>(result.vertices.size());
    result.header.indices = static_cast<uint32_t>(result.indices.size());
    result.header.triangles = static_cast<uint32_t>(index_count / 3);
    result.header.clusters = static_cast<uint32_t>(result.clusters.size()); // Total clusters todos os LODs
    result.header.lods = static_cast<uint32_t>(result.lods.size());

    // Calcular bounding box da malha
    float bmin[3] = { vertices[0], vertices[1], vertices[2] };
    float bmax[3] = { vertices[0], vertices[1], vertices[2] };
    for (uint32_t i = 1; i < vertex_count; ++i) {
        const float* v = &vertices[i * 3];
        for (int j = 0; j < 3; ++j) {
            if (v[j] < bmin[j]) bmin[j] = v[j];
            if (v[j] > bmax[j]) bmax[j] = v[j];
        }
    }
    std::memcpy(result.header.bmin, bmin, sizeof(bmin));
    std::memcpy(result.header.bmax, bmax, sizeof(bmax));

    result.header.groups = static_cast<uint32_t>(result.groups.size());
    result.header.base_triangles = result.lods.empty() ? 0 : result.lods[0].triangles;
    result.header.reserved[0] = 0;
    result.header.reserved[1] = 0;

    // 5. Estatisticas
    float err_sum = 0.0f;
    float err_max = 0.0f;
    for (const auto& c : result.clusters) {
        err_sum += c.error;
        if (c.error > err_max) err_max = c.error;
    }
    m_last_stats.output_clusters = result.header.clusters;
    m_last_stats.output_groups = result.header.groups;
    m_last_stats.output_lods = result.header.lods;
    m_last_stats.cluster_error_avg = result.clusters.empty() ? 0.0f : err_sum / static_cast<float>(result.clusters.size());
    m_last_stats.cluster_error_max = err_max;

    auto t_end = std::chrono::high_resolution_clock::now();
    m_last_stats.compile_time_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    return result;
}

CompiledMesh ArboriaGeometricCompiler::recompile(const VGMeshResource& source) {
    if (!source.is_valid()) return CompiledMesh{};

    const auto& clusters = source.get_clusters();
    const auto& lods = source.get_lods();
    const auto& groups = source.get_groups();
    const auto& vertices = source.get_vertices();
    const auto& indices = source.get_indices();

    CompiledMesh result;
    result.header = source.get_header();
    result.lods = lods;
    result.clusters = clusters;
    result.groups = groups;
    result.vertices = vertices;
    result.indices = indices;

    return result;
}

bool ArboriaGeometricCompiler::write_vgmesh(const CompiledMesh& mesh, const std::string& filepath) const {
    if (!mesh.is_valid()) return false;

    std::ofstream file(filepath, std::ios::binary);
    if (!file.is_open()) {
        ARBORIA_LOG_ERROR("[ArboriaGeometricCompiler] Falha ao abrir para escrita: " + filepath);
        return false;
    }

    file.write(reinterpret_cast<const char*>(&mesh.header), sizeof(Header));
    if (!file.good()) return false;
    if (!file.write(reinterpret_cast<const char*>(mesh.lods.data()),
                     mesh.lods.size() * sizeof(LOD))) return false;
    if (!file.write(reinterpret_cast<const char*>(mesh.clusters.data()),
                     mesh.clusters.size() * sizeof(Cluster))) return false;
    if (!file.write(reinterpret_cast<const char*>(mesh.groups.data()),
                     mesh.groups.size() * sizeof(Group))) return false;
    if (!file.write(reinterpret_cast<const char*>(mesh.vertices.data()),
                     mesh.vertices.size() * sizeof(Vertex))) return false;
    if (!file.write(reinterpret_cast<const char*>(mesh.indices.data()),
                     mesh.indices.size())) return false;

    file.close();
    return true;
}

const ArboriaGeometricCompiler::CompileStats& ArboriaGeometricCompiler::get_last_stats() const {
    return m_last_stats;
}

void ArboriaGeometricCompiler::build_clusters(
    const float* vertices, uint32_t vertex_count,
    const float* normals, const float* uvs,
    const uint32_t* indices, uint32_t index_count,
    std::vector<Cluster>& out_clusters,
    std::vector<Vertex>& out_vertices,
    std::vector<uint8_t>& out_indices
) {
    out_clusters.clear();
    out_vertices.clear();
    out_indices.clear();

    uint32_t triangle_count = index_count / 3;
    uint32_t max_tris = m_config.max_triangles_per_cluster;
    uint32_t max_verts = m_config.max_vertices_per_cluster;
    if (max_verts > 256) max_verts = 256; // uint8_t indice suporta 0-255

    // Calcular bounding box para determinar o eixo dominante
    float bmin[3] = { vertices[0], vertices[1], vertices[2] };
    float bmax[3] = { vertices[0], vertices[1], vertices[2] };
    for (uint32_t i = 1; i < vertex_count; ++i) {
        const float* v = &vertices[i * 3];
        for (int j = 0; j < 3; ++j) {
            if (v[j] < bmin[j]) bmin[j] = v[j];
            if (v[j] > bmax[j]) bmax[j] = v[j];
        }
    }
    float extent[3] = { bmax[0] - bmin[0], bmax[1] - bmin[1], bmax[2] - bmin[2] };
    int dominant_axis = 0;
    if (extent[1] > extent[dominant_axis]) dominant_axis = 1;
    if (extent[2] > extent[dominant_axis]) dominant_axis = 2;

    // Calcular centroide de cada triangulo ao longo do eixo dominante
    struct TriCentroid {
        uint32_t tri_index;
        float centroid_val;
    };
    std::vector<TriCentroid> centroids(triangle_count);
    for (uint32_t t = 0; t < triangle_count; ++t) {
        float cx = 0.0f, cy = 0.0f, cz = 0.0f;
        for (int k = 0; k < 3; ++k) {
            uint32_t vi = indices[t * 3 + k];
            const float* v = &vertices[vi * 3];
            cx += v[0]; cy += v[1]; cz += v[2];
        }
        cx /= 3.0f; cy /= 3.0f; cz /= 3.0f;
        centroids[t].tri_index = t;
        centroids[t].centroid_val = (dominant_axis == 0) ? cx : (dominant_axis == 1 ? cy : cz);
    }

    // Ordenar triangulos pelo centroide ao longo do eixo dominante
    std::sort(centroids.begin(), centroids.end(),
        [](const TriCentroid& a, const TriCentroid& b) { return a.centroid_val < b.centroid_val; });

    // Construir adjacencia de triangulos (quais triangulos compartilham vertices)
    std::vector<std::vector<uint32_t>> vertex_to_tris(vertex_count);
    for (uint32_t t = 0; t < triangle_count; ++t) {
        for (int k = 0; k < 3; ++k) {
            vertex_to_tris[indices[t * 3 + k]].push_back(t);
        }
    }
    // Gate 13 otimizacao: adjacencia eh resolvida sob demanda durante o BFS
    // a partir de vertex_to_tris (construido acima em O(n)), evitando a
    // montagem de uma matriz de adjacencia O(n^2) antecipadamente.

    // Cada cluster re-indexa suas vertices localmente (indices locais de 0 a vertex_count-1)
    // Clusters crescem por BFS a partir de sementes, mantendo conectividade espaciale

    uint32_t next_cluster_id = 0;

    // Crescer clusters por BFS/flood-fill a partir de sementes na ordem dos centroides.
    // Triangulos que compartilham vertices são agregados ao mesmo cluster (conectividade espaciale).
    std::vector<char> assigned(triangle_count, 0);

    for (uint32_t s = 0; s < triangle_count; ++s) {
        uint32_t seed = centroids[s].tri_index;
        if (assigned[seed]) continue;

        Cluster c{};
        c.id = next_cluster_id++;
        c.lod = 0;
        c.group = -1;
        c.refined = -1;
        c.vertex_offset = static_cast<uint32_t>(out_vertices.size());
        c.triangle_offset = static_cast<uint32_t>(out_indices.size());

        std::vector<uint32_t> local_vert_map(vertex_count, 0xFFFFFFFFu);
        uint32_t next_local_index = 0;
        uint32_t tris_in_cluster = 0;
        uint32_t verts_in_cluster = 0;

        std::vector<uint32_t> queue;
        queue.push_back(seed);

        size_t qhead = 0;
        while (qhead < queue.size() && tris_in_cluster < max_tris && verts_in_cluster < max_verts) {
            uint32_t tri_idx = queue[qhead++];
            if (assigned[tri_idx]) continue;

            // Safety hard-cap: never exceed max_verts under any optimization level
            if (verts_in_cluster >= max_verts) break;

            // Pular triangulos degenerados: vertices duplicados ou area zero (colineares)
            uint32_t i0 = indices[tri_idx * 3];
            uint32_t i1 = indices[tri_idx * 3 + 1];
            uint32_t i2 = indices[tri_idx * 3 + 2];
            if (i0 == i1 || i1 == i2 || i0 == i2) continue;
            const float* v0 = &vertices[i0 * 3];
            const float* v1 = &vertices[i1 * 3];
            const float* v2 = &vertices[i2 * 3];
            float e1x = v1[0] - v0[0], e1y = v1[1] - v0[1], e1z = v1[2] - v0[2];
            float e2x = v2[0] - v0[0], e2y = v2[1] - v0[1], e2z = v2[2] - v0[2];
            float cx = e1y * e2z - e1z * e2y;
            float cy = e1z * e2x - e1x * e2z;
            float cz = e1x * e2y - e1y * e2x;
            if (cx * cx + cy * cy + cz * cz < 1e-12f) continue;

            // Verifica se todos os 3 vertices cabem no cluster (mapeados ja ou espaco para novos)
            uint32_t new_vert_slots[3];
            uint32_t new_vert_count = 0;
            bool can_add = true;

            for (int k = 0; k < 3; ++k) {
                uint32_t vi = indices[tri_idx * 3 + k];
                if (local_vert_map[vi] == 0xFFFFFFFFu) {
                    if (verts_in_cluster + new_vert_count + 1 > max_verts) {
                        can_add = false;
                        break;
                    }
                    new_vert_slots[new_vert_count++] = vi;
                }
            }

            if (!can_add) continue; // Nao consigo adicionar este triangulo neste cluster

            // Adiciona os novos vertices deste triangulo
            for (uint32_t k = 0; k < new_vert_count; ++k) {
                uint32_t vi = new_vert_slots[k];
                local_vert_map[vi] = next_local_index++; // Indice LOCAL dentro do cluster
                const float* v = &vertices[vi * 3];
                Vertex nv{};
                nv.position[0] = v[0]; nv.position[1] = v[1]; nv.position[2] = v[2];
                if (normals) {
                    const float* n = &normals[vi * 3];
                    nv.normal[0] = n[0]; nv.normal[1] = n[1]; nv.normal[2] = n[2];
                } else {
                    nv.normal[0] = 0.0f; nv.normal[1] = 1.0f; nv.normal[2] = 0.0f;
                }
                if (uvs) {
                    const float* uv = &uvs[vi * 2];
                    nv.uv[0] = uv[0]; nv.uv[1] = uv[1];
                } else {
                    nv.uv[0] = 0.0f; nv.uv[1] = 0.0f;
                }
                out_vertices.push_back(nv);
                verts_in_cluster++;
            }

            // Escreve indices locais do triangulo
            for (int k = 0; k < 3; ++k) {
                uint32_t vi = indices[tri_idx * 3 + k];
                out_indices.push_back(static_cast<uint8_t>(local_vert_map[vi]));
            }
            tris_in_cluster++;
            assigned[tri_idx] = true;

            // Enfileira vizinhos nao atribuidos (conectividade via vertices compartilhados)
            // Gate 13 otimizacao: vizinhos sao buscados sob demanda em vertex_to_tris,
            // evitando a montagem de uma matriz de adjacencia O(n^2) antecipadamente.
            // Um mesmo vizinho pode aparecer multiplas vezes (via vertices compartilhados),
            // mas eh filtrado pelo check de !assigned[nb].
            for (int k = 0; k < 3; ++k) {
                uint32_t vi = indices[tri_idx * 3 + k];
                for (uint32_t nb : vertex_to_tris[vi]) {
                    if (!assigned[nb]) queue.push_back(nb);
                }
            }
        }

        c.vertex_count = verts_in_cluster;
        c.triangle_count = tris_in_cluster;

        if (tris_in_cluster == 0) {
            // Cluster vazio, pular
            continue;
        }

        // Calcular bounding sphere (Ritter), normal cone e erro
        // Usar os dados locais do cluster (vertices e indices ja estao em out_vertices/out_indices)
        uint32_t local_tri_count = c.triangle_count;
        uint32_t local_base = static_cast<uint32_t>(out_indices.size()) - local_tri_count * 3;

        // Reconstruir indices locais para computacao
        std::vector<uint32_t> local_indices(local_tri_count * 3);
        for (uint32_t i = 0; i < local_tri_count * 3; ++i) {
            local_indices[i] = out_indices[local_base + i];
        }

        // Usar ponteiros para vertices locais
        const float* local_verts = reinterpret_cast<const float*>(out_vertices.data() + c.vertex_offset);

        compute_bounding_sphere(local_verts, local_indices.data(), local_tri_count * 3,
                                c.center, c.radius);

        // Normal cone (se houver normais)
        if (normals) {
            // Coletar normais das vertices locais
            std::vector<float> local_normals(local_tri_count * 3 * 3); // 3 vertices * 3 componentes * triangulos
            for (uint32_t i = 0; i < local_tri_count * 3; ++i) {
                uint32_t vi = local_indices[i];
                const Vertex& v = out_vertices[c.vertex_offset + vi];
                local_normals[i * 3] = v.normal[0];
                local_normals[i * 3 + 1] = v.normal[1];
                local_normals[i * 3 + 2] = v.normal[2];
            }
            compute_normal_cone(local_normals.data(), local_indices.data(), local_tri_count * 3, c.cone);
        } else {
            c.cone[0] = 0.0f; c.cone[1] = 1.0f; c.cone[2] = 0.0f; c.cone[3] = 1.0f;
        }

        c.error = compute_cluster_error(local_verts, local_indices.data(), local_tri_count * 3,
                                         c.center, c.radius);

        out_clusters.push_back(c);
    }

    m_last_stats.output_clusters = static_cast<uint32_t>(out_clusters.size());
}

void ArboriaGeometricCompiler::build_dag_hierarchy(
    std::vector<Cluster>& clusters,
    std::vector<Group>& out_groups
) {
    out_groups.clear();

    if (clusters.empty()) return;

    // ---- Grupo raiz (profundidade 0): bounding sphere sobre todos os clusters ----
    Group root{};
    root.id = 0;
    root.depth = 0;
    root.error = 0.0f;

    float bmin[3] = {
        clusters[0].center[0] - clusters[0].radius,
        clusters[0].center[1] - clusters[0].radius,
        clusters[0].center[2] - clusters[0].radius
    };
    float bmax[3] = {
        clusters[0].center[0] + clusters[0].radius,
        clusters[0].center[1] + clusters[0].radius,
        clusters[0].center[2] + clusters[0].radius
    };

    for (const auto& c : clusters) {
        bmin[0] = std::min(bmin[0], c.center[0] - c.radius);
        bmin[1] = std::min(bmin[1], c.center[1] - c.radius);
        bmin[2] = std::min(bmin[2], c.center[2] - c.radius);
        bmax[0] = std::max(bmax[0], c.center[0] + c.radius);
        bmax[1] = std::max(bmax[1], c.center[1] + c.radius);
        bmax[2] = std::max(bmax[2], c.center[2] + c.radius);
        if (c.error > root.error) root.error = c.error;
    }

    root.center[0] = (bmin[0] + bmax[0]) * 0.5f;
    root.center[1] = (bmin[1] + bmax[1]) * 0.5f;
    root.center[2] = (bmin[2] + bmax[2]) * 0.5f;
    float dx = bmax[0] - root.center[0];
    float dy = bmax[1] - root.center[1];
    float dz = bmax[2] - root.center[2];
    root.radius = std::sqrt(dx * dx + dy * dy + dz * dz);

    out_groups.push_back(root);

    // Todos os clusters pertencem inicialmente ao raiz
    for (auto& c : clusters) {
        c.group = 0;
        c.refined = -1;
    }

    // Subdivisao recursiva espaco-espaco em grupos filhos (hierarquia DAG multi-nivel)
    const uint32_t max_depth = 3;
    const uint32_t min_clusters_per_group = 2;
    uint32_t next_group_id = 1;

    std::vector<uint32_t> all_indices(clusters.size());
    for (uint32_t i = 0; i < clusters.size(); ++i) all_indices[i] = i;

    build_dag_subtree(clusters, all_indices, 0, 0, max_depth,
                      min_clusters_per_group, next_group_id, out_groups);
}

void ArboriaGeometricCompiler::build_dag_subtree(
    std::vector<Cluster>& clusters,
    const std::vector<uint32_t>& indices,
    uint32_t parent_group_id,
    uint32_t depth,
    uint32_t max_depth,
    uint32_t min_clusters_per_group,
    uint32_t& next_group_id,
    std::vector<Group>& out_groups
) {
    if (depth >= max_depth || indices.size() <= min_clusters_per_group) return;

    // Encontrar eixo dominante dos centros dos clusters deste subconjunto
    float cmin[3] = {
        clusters[indices[0]].center[0],
        clusters[indices[0]].center[1],
        clusters[indices[0]].center[2]
    };
    float cmax[3] = { cmin[0], cmin[1], cmin[2] };
    for (uint32_t idx : indices) {
        const auto& c = clusters[idx];
        for (int j = 0; j < 3; ++j) {
            cmin[j] = std::min(cmin[j], c.center[j]);
            cmax[j] = std::max(cmax[j], c.center[j]);
        }
    }
    float extent[3] = { cmax[0] - cmin[0], cmax[1] - cmin[1], cmax[2] - cmin[2] };
    int axis = 0;
    if (extent[1] > extent[axis]) axis = 1;
    if (extent[2] > extent[axis]) axis = 2;

    // Ordenar indices por centro ao longo do eixo dominante e dividir na mediana
    std::vector<uint32_t> sorted = indices;
    std::sort(sorted.begin(), sorted.end(),
        [&](uint32_t a, uint32_t b) {
            return clusters[a].center[axis] < clusters[b].center[axis];
        });

    size_t mid = sorted.size() / 2;
    std::vector<uint32_t> left(sorted.begin(), sorted.begin() + mid);
    std::vector<uint32_t> right(sorted.begin() + mid, sorted.end());

    // Criar grupo filho esquerdo com bounds e erro acumulado dos seus clusters
    Group gl{};
    gl.id = next_group_id++;
    gl.depth = depth + 1;
    gl.error = 0.0f;
    {
        float lmin[3] = {
            clusters[left[0]].center[0] - clusters[left[0]].radius,
            clusters[left[0]].center[1] - clusters[left[0]].radius,
            clusters[left[0]].center[2] - clusters[left[0]].radius
        };
        float lmax[3] = {
            clusters[left[0]].center[0] + clusters[left[0]].radius,
            clusters[left[0]].center[1] + clusters[left[0]].radius,
            clusters[left[0]].center[2] + clusters[left[0]].radius
        };
        for (uint32_t idx : left) {
            const auto& c = clusters[idx];
            lmin[0] = std::min(lmin[0], c.center[0] - c.radius);
            lmin[1] = std::min(lmin[1], c.center[1] - c.radius);
            lmin[2] = std::min(lmin[2], c.center[2] - c.radius);
            lmax[0] = std::max(lmax[0], c.center[0] + c.radius);
            lmax[1] = std::max(lmax[1], c.center[1] + c.radius);
            lmax[2] = std::max(lmax[2], c.center[2] + c.radius);
            if (c.error > gl.error) gl.error = c.error;
        }
        gl.center[0] = (lmin[0] + lmax[0]) * 0.5f;
        gl.center[1] = (lmin[1] + lmax[1]) * 0.5f;
        gl.center[2] = (lmin[2] + lmax[2]) * 0.5f;
        float ldx = lmax[0] - gl.center[0];
        float ldy = lmax[1] - gl.center[1];
        float ldz = lmax[2] - gl.center[2];
        gl.radius = std::sqrt(ldx * ldx + ldy * ldy + ldz * ldz);
    }
    out_groups.push_back(gl);

    // Criar grupo filho direito com bounds e erro acumulado dos seus clusters
    Group gr{};
    gr.id = next_group_id++;
    gr.depth = depth + 1;
    gr.error = 0.0f;
    {
        float rmin[3] = {
            clusters[right[0]].center[0] - clusters[right[0]].radius,
            clusters[right[0]].center[1] - clusters[right[0]].radius,
            clusters[right[0]].center[2] - clusters[right[0]].radius
        };
        float rmax[3] = {
            clusters[right[0]].center[0] + clusters[right[0]].radius,
            clusters[right[0]].center[1] + clusters[right[0]].radius,
            clusters[right[0]].center[2] + clusters[right[0]].radius
        };
        for (uint32_t idx : right) {
            const auto& c = clusters[idx];
            rmin[0] = std::min(rmin[0], c.center[0] - c.radius);
            rmin[1] = std::min(rmin[1], c.center[1] - c.radius);
            rmin[2] = std::min(rmin[2], c.center[2] - c.radius);
            rmax[0] = std::max(rmax[0], c.center[0] + c.radius);
            rmax[1] = std::max(rmax[1], c.center[1] + c.radius);
            rmax[2] = std::max(rmax[2], c.center[2] + c.radius);
            if (c.error > gr.error) gr.error = c.error;
        }
        gr.center[0] = (rmin[0] + rmax[0]) * 0.5f;
        gr.center[1] = (rmin[1] + rmax[1]) * 0.5f;
        gr.center[2] = (rmin[2] + rmax[2]) * 0.5f;
        float rdx = rmax[0] - gr.center[0];
        float rdy = rmax[1] - gr.center[1];
        float rdz = rmax[2] - gr.center[2];
        gr.radius = std::sqrt(rdx * rdx + rdy * rdy + rdz * rdz);
    }
    out_groups.push_back(gr);

    // Atribuir clusters aos grupos filhos (pai/filho no DAG)
    for (uint32_t idx : left) {
        clusters[idx].group = static_cast<int32_t>(gl.id);
        clusters[idx].refined = -1;
    }
    for (uint32_t idx : right) {
        clusters[idx].group = static_cast<int32_t>(gr.id);
        clusters[idx].refined = -1;
    }

    // Recursao em cada filho para aprofundar a hierarquia DAG
    build_dag_subtree(clusters, left, gl.id, depth + 1, max_depth,
                      min_clusters_per_group, next_group_id, out_groups);
    build_dag_subtree(clusters, right, gr.id, depth + 1, max_depth,
                      min_clusters_per_group, next_group_id, out_groups);
}

void ArboriaGeometricCompiler::build_lods(
    const std::vector<Cluster>& lod0_clusters,
    const std::vector<Vertex>& lod0_vertices,
    const std::vector<uint8_t>& lod0_indices,
    std::vector<Cluster>& io_all_clusters,
    std::vector<Vertex>& io_all_vertices,
    std::vector<uint8_t>& io_all_indices,
    std::vector<LOD>& out_lods
) {
    out_lods.clear();

    if (lod0_clusters.empty()) return;

    const uint32_t lod0_count = static_cast<uint32_t>(lod0_clusters.size());

    // LOD 0: resolucao completa (clusters ja estao em io_all_clusters, offset 0)
    LOD lod0{};
    lod0.level = 0;
    lod0.offset = 0;
    lod0.clusters = lod0_count;
    lod0.triangles = 0;
    for (const auto& c : lod0_clusters) lod0.triangles += c.triangle_count;
    lod0.error = 0.0f;
    lod0.ratio = 1.0f;
    out_lods.push_back(lod0);

    const uint32_t base_tris = lod0.triangles;
    if (base_tris == 0 || m_config.max_lod_levels < 2) return;

    // Coleta todos os triangulos do LOD 0 em arrays flat para simplificacao QEM
    std::vector<float> flat_verts;
    std::vector<uint32_t> flat_tris;
    std::vector<float> flat_uvs;
    flat_verts.reserve(lod0_vertices.size() * 3);
    flat_tris.reserve(base_tris * 3);
    flat_uvs.reserve(lod0_vertices.size() * 2);

    // Mapeia vertices globais do LOD 0 para indices flat (cada vertice de cluster eh unico)
    std::vector<uint32_t> global_to_flat(lod0_vertices.size(), 0xFFFFFFFFu);
    for (const auto& c : lod0_clusters) {
        for (uint32_t i = 0; i < c.triangle_count; ++i) {
            uint32_t base_byte = c.triangle_offset + i * 3;
            for (int k = 0; k < 3; ++k) {
                uint8_t local_vi = lod0_indices[base_byte + k];
                uint32_t gvi = c.vertex_offset + local_vi;
                if (global_to_flat[gvi] == 0xFFFFFFFFu) {
                    global_to_flat[gvi] = static_cast<uint32_t>(flat_verts.size() / 3);
                    const Vertex& gv = lod0_vertices[gvi];
                    flat_verts.push_back(gv.position[0]);
                    flat_verts.push_back(gv.position[1]);
                    flat_verts.push_back(gv.position[2]);
                    flat_uvs.push_back(gv.uv[0]);
                    flat_uvs.push_back(gv.uv[1]);
                }
                flat_tris.push_back(global_to_flat[gvi]);
            }
        }
    }

    // Niveis LOD superiores: simplificacao QEM progressiva com armazenamento real
    // de clusters, vertices e indices próprios por nivel.
    for (uint32_t lod = 1; lod < m_config.max_lod_levels; ++lod) {
        // Alvo de triangulos: reducao progressiva por fator 2 por nivel
        uint32_t target_tris = static_cast<uint32_t>(std::max(1.0f,
            static_cast<float>(base_tris) / std::pow(2.0f, static_cast<float>(lod))));
        if (target_tris >= base_tris) target_tris = base_tris / 2;
        if (target_tris == 0) target_tris = 1;

        // Simplifica com QEM (usa threshold de aresta viva do config)
        std::vector<float> sim_verts;
        std::vector<uint32_t> sim_tris;
        std::vector<float> sim_uvs;
        float lod_error = qem_simplify(flat_verts, flat_tris, target_tris,
                                       m_config.sharp_edge_threshold,
                                       sim_verts, sim_tris,
                                       flat_uvs.data(), &sim_uvs);

        if (sim_tris.empty() || sim_verts.empty()) {
            // Falhou: nao armazena geometria falsa, pular este nivel
            continue;
        }

        uint32_t sim_ntris = static_cast<uint32_t>(sim_tris.size() / 3);
        uint32_t sim_nverts = static_cast<uint32_t>(sim_verts.size() / 3);

        // Calcula normais por vertice (media das normais das faces incidentes)
        std::vector<float> sim_normals(sim_nverts * 3, 0.0f);
        std::vector<uint32_t> sim_normal_count(sim_nverts, 0);
        for (uint32_t t = 0; t < sim_ntris; ++t) {
            uint32_t i0 = sim_tris[t * 3];
            uint32_t i1 = sim_tris[t * 3 + 1];
            uint32_t i2 = sim_tris[t * 3 + 2];
            const float* p0 = &sim_verts[i0 * 3];
            const float* p1 = &sim_verts[i1 * 3];
            const float* p2 = &sim_verts[i2 * 3];
            float e1x = p1[0] - p0[0], e1y = p1[1] - p0[1], e1z = p1[2] - p0[2];
            float e2x = p2[0] - p0[0], e2y = p2[1] - p0[1], e2z = p2[2] - p0[2];
            float ea[3] = {e1x, e1y, e1z};
            float eb[3] = {e2x, e2y, e2z};
            float fn[3]; cross3(ea, eb, fn);
            float flen = std::sqrt(fn[0]*fn[0] + fn[1]*fn[1] + fn[2]*fn[2]);
            if (flen > 1e-12f) {
                fn[0] /= flen; fn[1] /= flen; fn[2] /= flen;
                for (uint32_t vi : {i0, i1, i2}) {
                    sim_normals[vi * 3] += fn[0];
                    sim_normals[vi * 3 + 1] += fn[1];
                    sim_normals[vi * 3 + 2] += fn[2];
                    sim_normal_count[vi]++;
                }
            }
        }
        for (uint32_t v = 0; v < sim_nverts; ++v) {
            if (sim_normal_count[v] > 0) {
                float len = std::sqrt(sim_normals[v*3]*sim_normals[v*3] +
                                     sim_normals[v*3+1]*sim_normals[v*3+1] +
                                     sim_normals[v*3+2]*sim_normals[v*3+2]);
                if (len > 1e-12f) {
                    sim_normals[v*3] /= len; sim_normals[v*3+1] /= len; sim_normals[v*3+2] /= len;
                } else {
                    sim_normals[v*3] = 0.f; sim_normals[v*3+1] = 1.f; sim_normals[v*3+2] = 0.f;
                }
            } else {
                sim_normals[v*3] = 0.f; sim_normals[v*3+1] = 1.f; sim_normals[v*3+2] = 0.f;
            }
        }

        // Re-clusteriza a malha simplificada (mesma logica BFS de build_clusters)
        std::vector<Cluster> new_clusters;
        std::vector<Vertex> new_vertices;
        std::vector<uint8_t> new_indices;

        build_clusters(sim_verts.data(), sim_nverts,
                       sim_normals.data(), sim_uvs.data(),
                       sim_tris.data(), static_cast<uint32_t>(sim_tris.size()),
                       new_clusters, new_vertices, new_indices);

        if (new_clusters.empty()) {
            // Falhou na clusterizacao: nao armazenar falsa simplificacao, pular nivel
            continue;
        }

        // Ajustar offsets dos clusters simplificados para os arrays globais
        uint32_t cluster_base = static_cast<uint32_t>(io_all_clusters.size());
        uint32_t vertex_base = static_cast<uint32_t>(io_all_vertices.size());
        uint32_t index_base = static_cast<uint32_t>(io_all_indices.size());

        uint32_t lod_tris = 0;
        for (auto& c : new_clusters) {
            c.vertex_offset += vertex_base;
            c.triangle_offset += index_base;
            c.lod = lod;  // Marcar nivel LOD correto no cluster
            lod_tris += c.triangle_count;
            io_all_clusters.push_back(c);
        }

        // Anexar vertices e indices simplificados aos arrays globais
        io_all_vertices.insert(io_all_vertices.end(), new_vertices.begin(), new_vertices.end());
        io_all_indices.insert(io_all_indices.end(), new_indices.begin(), new_indices.end());

        // Registrar LOD com offsets e contagens reais (nao referencia LOD 0)
        LOD lod_n{};
        lod_n.level = lod;
        lod_n.offset = cluster_base;
        lod_n.clusters = static_cast<uint32_t>(new_clusters.size());
        lod_n.triangles = lod_tris;
        lod_n.error = lod_error; // erro real de simplificacao QEM deste nivel
        lod_n.ratio = static_cast<float>(lod_tris) / static_cast<float>(base_tris);
        out_lods.push_back(lod_n);
    }
}

void ArboriaGeometricCompiler::compute_bounding_sphere(
    const float* vertices, const uint32_t* indices, uint32_t index_count,
    float center[3], float& radius
) {
    if (index_count == 0) {
        center[0] = center[1] = center[2] = 0.0f;
        radius = 0.0f;
        return;
    }

    // Algoritmo de Ritter: bounding sphere aproximado mais apertado que centróide
    // 1. Ponto x mais distante de ponto arbitrário p
    // 2. Ponto y mais distante de x
    // 3. Esfera inicial: centro = (x+y)/2, raio = |x-y|/2
    // 4. Expandir esfera para incluir todos os pontos

    const float* p = &vertices[indices[0] * 3];

    // Encontrar x mais distante de p
    uint32_t x_idx = indices[0];
    float max_dist_sq = 0.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        const float* v = &vertices[indices[i] * 3];
        float dx = v[0] - p[0], dy = v[1] - p[1], dz = v[2] - p[2];
        float d2 = dx * dx + dy * dy + dz * dz;
        if (d2 > max_dist_sq) { max_dist_sq = d2; x_idx = indices[i]; }
    }
    const float* x = &vertices[x_idx * 3];

    // Encontrar y mais distante de x
    uint32_t y_idx = x_idx;
    max_dist_sq = 0.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        const float* v = &vertices[indices[i] * 3];
        float dx = v[0] - x[0], dy = v[1] - x[1], dz = v[2] - x[2];
        float d2 = dx * dx + dy * dy + dz * dz;
        if (d2 > max_dist_sq) { max_dist_sq = d2; y_idx = indices[i]; }
    }
    const float* y = &vertices[y_idx * 3];

    // Esfera inicial a partir do diametro x-y
    center[0] = (x[0] + y[0]) * 0.5f;
    center[1] = (x[1] + y[1]) * 0.5f;
    center[2] = (x[2] + y[2]) * 0.5f;
    float dx = y[0] - x[0], dy = y[1] - x[1], dz = y[2] - x[2];
    radius = std::sqrt(dx * dx + dy * dy + dz * dz) * 0.5f;

    // Expandir esfera para incluir todos os pontos
    float radius_sq = radius * radius;
    for (uint32_t i = 0; i < index_count; ++i) {
        const float* v = &vertices[indices[i] * 3];
        float ddx = v[0] - center[0], ddy = v[1] - center[1], ddz = v[2] - center[2];
        float d2 = ddx * ddx + ddy * ddy + ddz * ddz;
        if (d2 > radius_sq) {
            float d = std::sqrt(d2);
            float old_r = radius;
            radius = (old_r + d) * 0.5f;
            float shift = (radius - old_r) / d;
            center[0] += ddx * shift;
            center[1] += ddy * shift;
            center[2] += ddz * shift;
            radius_sq = radius * radius;
        }
    }
}

void ArboriaGeometricCompiler::compute_normal_cone(
    const float* normals, const uint32_t* indices, uint32_t index_count,
    float cone[4]
) {
    if (index_count == 0 || !normals) {
        cone[0] = 0.0f; cone[1] = 1.0f; cone[2] = 0.0f; cone[3] = 1.0f;
        return;
    }

    // Calcular normal media
    float nx = 0.0f, ny = 0.0f, nz = 0.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        uint32_t vi = indices[i];
        const float* n = &normals[vi * 3];
        nx += n[0]; ny += n[1]; nz += n[2];
    }
    float len = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 0.0f) {
        nx /= len; ny /= len; nz /= len;
    } else {
        nx = 0.0f; ny = 1.0f; nz = 0.0f;
    }

    // Encontrar angulo maximo (cutoff) do cone
    float max_cos = 1.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        uint32_t vi = indices[i];
        const float* n = &normals[vi * 3];
        float dot = nx * n[0] + ny * n[1] + nz * n[2];
        if (dot < max_cos) max_cos = dot;
    }
    float cutoff = std::acos(std::max(-1.0f, std::min(1.0f, max_cos)));

    cone[0] = nx; cone[1] = ny; cone[2] = nz; cone[3] = cutoff;
}

float ArboriaGeometricCompiler::compute_cluster_error(
    const float* vertices, const uint32_t* indices, uint32_t index_count,
    const float center[3], float radius
) {
    if (index_count == 0) return 0.0f;

    // Erro geometrico como desviopadrao das distancias dos vertices ao centro
    float mean_dist = 0.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        uint32_t vi = indices[i];
        const float* v = &vertices[vi * 3];
        float dx = v[0] - center[0];
        float dy = v[1] - center[1];
        float dz = v[2] - center[2];
        mean_dist += std::sqrt(dx * dx + dy * dy + dz * dz);
    }
    mean_dist /= static_cast<float>(index_count);

    float variance = 0.0f;
    for (uint32_t i = 0; i < index_count; ++i) {
        uint32_t vi = indices[i];
        const float* v = &vertices[vi * 3];
        float dx = v[0] - center[0];
        float dy = v[1] - center[1];
        float dz = v[2] - center[2];
        float dist = std::sqrt(dx * dx + dy * dy + dz * dz);
        float diff = dist - mean_dist;
        variance += diff * diff;
    }
    variance /= static_cast<float>(index_count);

    return std::sqrt(variance);
}

// ============================================================================
// Gate 06 — Refinamento do DAG e continuidade geometrica
// ============================================================================

// Verifica se um cluster precisa de correcao de winding comparando a normal
// geometrica calculada (produto vetorial das arestas) com a normal armazenada
// nos vertices. Amostra as faces do cluster; se a maioria tiver ponto escalar
// negativo entre normal calculada e normal armazenada, retorna true.
bool ArboriaGeometricCompiler::cluster_needs_winding_fix(
    const Cluster& c,
    const std::vector<Vertex>& vertices,
    const std::vector<uint8_t>& indices) const
{
    if (c.triangle_count == 0 || c.vertex_count < 3) return false;

    uint32_t base = c.triangle_offset;
    uint32_t voff = c.vertex_offset;
    int mismatches = 0;
    int checked = 0;
    const int max_check = 8; // amostragem limitada para desempenho

    for (uint32_t i = 0; i < c.triangle_count && checked < max_check; ++i) {
        uint32_t idx0 = indices[base + i * 3];
        uint32_t idx1 = indices[base + i * 3 + 1];
        uint32_t idx2 = indices[base + i * 3 + 2];
        if (idx0 >= c.vertex_count || idx1 >= c.vertex_count || idx2 >= c.vertex_count) continue;

        const Vertex& v0 = vertices[voff + idx0];
        const Vertex& v1 = vertices[voff + idx1];
        const Vertex& v2 = vertices[voff + idx2];

        float e1x = v1.position[0] - v0.position[0];
        float e1y = v1.position[1] - v0.position[1];
        float e1z = v1.position[2] - v0.position[2];
        float e2x = v2.position[0] - v0.position[0];
        float e2y = v2.position[1] - v0.position[1];
        float e2z = v2.position[2] - v0.position[2];

        float nx = e1y * e2z - e1z * e2y;
        float ny = e1z * e2x - e1x * e2z;
        float nz = e1x * e2y - e1y * e2x;
        float len = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-12f) continue; // degenerada, ignora
        nx /= len; ny /= len; nz /= len;

        // Normal media armazenada nos 3 vertices
        float sx = (v0.normal[0] + v1.normal[0] + v2.normal[0]) / 3.0f;
        float sy = (v0.normal[1] + v1.normal[1] + v2.normal[1]) / 3.0f;
        float sz = (v0.normal[2] + v1.normal[2] + v2.normal[2]) / 3.0f;
        float slen = std::sqrt(sx * sx + sy * sy + sz * sz);
        if (slen < 1e-12f) continue;
        sx /= slen; sy /= slen; sz /= slen;

        float dot = nx * sx + ny * sy + nz * sz;
        if (dot < 0.0f) mismatches++;
        checked++;
    }

    return checked > 0 && mismatches > checked / 2;
}

// Detecta e corrige a ordem de winding dos triangulos de um cluster:
// inverte dois indices de cada face cuja normal calculada esteja oposta
// à normal armazenada. Retorna o numero de faces corrigidas.
uint32_t ArboriaGeometricCompiler::validate_and_fix_winding(
    std::vector<Cluster>& clusters,
    std::vector<Vertex>& vertices,
    std::vector<uint8_t>& indices) const
{
    uint32_t fixed = 0;
    for (auto& c : clusters) {
        if (!cluster_needs_winding_fix(c, vertices, indices)) continue;

        uint32_t base = c.triangle_offset;
        uint32_t voff = c.vertex_offset;
        for (uint32_t i = 0; i < c.triangle_count; ++i) {
            uint32_t p0 = base + i * 3;
            uint32_t p1 = p0 + 1;
            uint32_t p2 = p0 + 2;
            uint32_t idx0 = indices[p0];
            uint32_t idx1 = indices[p1];
            uint32_t idx2 = indices[p2];
            if (idx0 >= c.vertex_count || idx1 >= c.vertex_count || idx2 >= c.vertex_count) continue;

            const Vertex& v0 = vertices[voff + idx0];
            const Vertex& v1 = vertices[voff + idx1];
            const Vertex& v2 = vertices[voff + idx2];

            float e1x = v1.position[0] - v0.position[0];
            float e1y = v1.position[1] - v0.position[1];
            float e1z = v1.position[2] - v0.position[2];
            float e2x = v2.position[0] - v0.position[0];
            float e2y = v2.position[1] - v0.position[1];
            float e2z = v2.position[2] - v0.position[2];

            float nx = e1y * e2z - e1z * e2y;
            float ny = e1z * e2x - e1x * e2z;
            float nz = e1x * e2y - e1y * e2x;
            float len = std::sqrt(nx * nx + ny * ny + nz * nz);
            if (len < 1e-12f) continue;
            nx /= len; ny /= len; nz /= len;

            float sx = (v0.normal[0] + v1.normal[0] + v2.normal[0]) / 3.0f;
            float sy = (v0.normal[1] + v1.normal[1] + v2.normal[1]) / 3.0f;
            float sz = (v0.normal[2] + v1.normal[2] + v2.normal[2]) / 3.0f;
            float slen = std::sqrt(sx * sx + sy * sy + sz * sz);
            if (slen < 1e-12f) continue;
            sx /= slen; sy /= slen; sz /= slen;

            float dot = nx * sx + ny * sy + nz * sz;
            if (dot < 0.0f) {
                // Inverte o winding trocando idx1 e idx2
                std::swap(indices[p1], indices[p2]);
                fixed++;
            }
        }
    }
    return fixed;
}

// Aplica correcao de espelhamento a todos os clusters: inverte o winding de
// faces cujos vertices indiquem orientacao espelhada (determinante negativo),
// garantindo consistencia em malhas importadas com transformacoes espelhadas.
void ArboriaGeometricCompiler::apply_mirror_correction(
    std::vector<Cluster>& clusters,
    std::vector<Vertex>& vertices,
    std::vector<uint8_t>& indices) const
{
    // A correcao de espelhamento e, na pratica, a mesma que a correcao de winding:
    // faces com normal geometrica oposta à normal armazenada indicam espelhamento.
    // Reusa validate_and_fix_winding para corrigir todos os clusters de uma vez.
    (void)validate_and_fix_winding(clusters, vertices, indices);
}

// Valida a continuidade de corte do DAG entre niveis LOD: para cada cluster de
// LOD > 0 com campo 'refined' definido, verifica se a esfera delimitadora do
// cluster sobrepoe a esfera do cluster LOD 0 referenciado (pelo grupo 'refined'),
// indicando que a transicao de corte e geometrica mente contínua.
// Retorna o numero de clusters de corte que falharam a validacao (fora da tolerancia).
uint32_t ArboriaGeometricCompiler::validate_dag_cut_continuity(
    const std::vector<Cluster>& clusters,
    const std::vector<Vertex>& vertices,
    const std::vector<uint8_t>& indices,
    float tolerance) const
{
    (void)vertices;
    (void)indices;

    uint32_t failed = 0;
    uint32_t lod0_count = 0;
    for (const auto& c : clusters) {
        if (c.lod == 0) lod0_count++;
    }

    for (const auto& c : clusters) {
        if (c.lod == 0) continue; // LOD 0 nao precisa de refinamento
        if (c.refined < 0) continue; // sem grupo de refinamento definido

        // Encontra o cluster LOD 0 cujo grupo corresponde a c.refined
        bool found_overlap = false;
        for (const auto& l0 : clusters) {
            if (l0.lod != 0) continue;
            if (l0.group != c.refined) continue;

            // Verifica sobreposicao de esferas delimitadoras (corte contínuo)
            float dx = c.center[0] - l0.center[0];
            float dy = c.center[1] - l0.center[1];
            float dz = c.center[2] - l0.center[2];
            float dist_sq = dx * dx + dy * dy + dz * dz;
            float radii_sum = c.radius + l0.radius;
            float threshold = radii_sum * radii_sum + tolerance;
            if (dist_sq <= threshold) {
                found_overlap = true;
                break;
            }
        }

        if (!found_overlap) failed++;
    }

    return failed;
}

} // namespace Arboria
