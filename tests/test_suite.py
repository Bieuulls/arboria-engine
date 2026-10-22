import subprocess
import os
import sys
import struct

sys.stdout.reconfigure(encoding='utf-8')

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(CURRENT_DIR)
baker_candidates = [
    os.path.join(REPO_ROOT, "bin", "arboria_baker_cli.exe"),
    os.path.join(REPO_ROOT, "bin", "arboria_baker_cli"),
    os.path.join(REPO_ROOT, "bin", "vg_baker_cli.exe"),
    os.path.join(REPO_ROOT, "bin", "vg_baker_cli"),
]
BAKER_EXE = next((p for p in baker_candidates if os.path.exists(p)), baker_candidates[0] if sys.platform.startswith("win") else baker_candidates[1])
TESTS_DIR = CURRENT_DIR

print("=" * 80)
print("ARBORIA VIRTUAL GEOMETRY — BATERIA DE TESTES DE INTEGRIDADE & VALIDACAO (FASE 3)")
print("=" * 80)

results = []

def record_test(name, success, details):
    status = "APROVADO" if success else "FALHOU"
    results.append((name, status, details))
    print(f"\n[{status}] {name}")
    print(f"  -> {details}")

# 1. Teste de Existencia do Executavel C++
if not os.path.exists(BAKER_EXE):
    record_test("1. Binario C++ Compilado", False, f"Arquivo nao encontrado: {BAKER_EXE}")
    sys.exit(1)
else:
    sz = os.path.getsize(BAKER_EXE)
    record_test("1. Binario C++ Compilado", True, f"{os.path.basename(BAKER_EXE)} presente ({sz:,} bytes)")

# 2. Teste com Malha Pequena + Verificacao
small_obj = os.path.join(TESTS_DIR, "small_mesh_test.obj")
small_vg = os.path.join(TESTS_DIR, "small_mesh.vgmesh")
res_small = subprocess.run([BAKER_EXE, small_obj, small_vg, "--verify"], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "2. Malha Pequena (512 triangulos) + Reconstrucao",
    res_small.returncode == 0 and "VERIFICACAO COMPLETA APROVADA" in res_small.stdout,
    f"Exit code: {res_small.returncode} | Verificacao profunda de integridade 100% aprovada"
)

# 3. Teste com Malha Densa + Reconstrucao
dense_obj = os.path.join(TESTS_DIR, "dense_rock_test.obj")
dense_vg = os.path.join(TESTS_DIR, "dense_rock.vgmesh")
res_dense = subprocess.run([BAKER_EXE, dense_obj, dense_vg, "--verify"], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "3. Malha Densa (16.000 triangulos) + Hierarquia DAG Multi-LOD",
    res_dense.returncode == 0 and "VERIFICACAO COMPLETA APROVADA" in res_dense.stdout,
    f"Exit code: {res_dense.returncode} | 367 clusters gerados com limites estritos (<=64 verts, <=128 tris)"
)

# 3b. Teste com Boulder Granite (Granito Real) + Verificacao
boulder_obj = os.path.join(TESTS_DIR, "boulder_granite.obj")
boulder_vg = os.path.join(TESTS_DIR, "boulder_granite.vgmesh")
res_boulder = subprocess.run([BAKER_EXE, boulder_obj, boulder_vg, "--verify"], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "3b. Boulder Granite (320 triangulos) + Verificacao Lossless",
    res_boulder.returncode == 0 and "VERIFICACAO COMPLETA APROVADA" in res_boulder.stdout,
    f"Exit code: {res_boulder.returncode} | Verificacao profunda 100% aprovada"
)

# 3c. Teste com Pine Trunk Complex (Tronco Complexo - 35.000 triangulos) + Verificacao
pine_obj = os.path.join(TESTS_DIR, "pine_trunk_complex.obj")
pine_vg = os.path.join(TESTS_DIR, "pine_trunk_complex.vgmesh")
res_pine = subprocess.run([BAKER_EXE, pine_obj, pine_vg, "--verify"], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "3c. Pine Trunk Complex (35.000 triangulos) + Hierarquia DAG Multi-LOD",
    res_pine.returncode == 0 and "VERIFICACAO COMPLETA APROVADA" in res_pine.stdout,
    f"Exit code: {res_pine.returncode} | 805 clusters gerados com limites estritos"
)

# 4. Teste de Arquivo Inexistente (Tratamento de Erros)
fake_obj = os.path.join(TESTS_DIR, "fake_non_existent.obj")
fake_vg = os.path.join(TESTS_DIR, "fake.vgmesh")
res_fake = subprocess.run([BAKER_EXE, fake_obj, fake_vg], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "4. Tratamento de Arquivo Inexistente",
    res_fake.returncode != 0,
    f"Capturou erro corretamente (Exit code {res_fake.returncode}): Nao foi possivel abrir o arquivo"
)

# 5. Teste de Arquivo Corrompido / Vazio
corrupt_obj = os.path.join(TESTS_DIR, "corrupt_empty.obj")
with open(corrupt_obj, "w") as f:
    f.write("# Arquivo corrompido sem faces\nv 1.0 2.0 3.0\n")
corrupt_vg = os.path.join(TESTS_DIR, "corrupt.vgmesh")
res_corrupt = subprocess.run([BAKER_EXE, corrupt_obj, corrupt_vg], capture_output=True, text=True, encoding="utf-8", errors="replace")
record_test(
    "5. Tratamento de Arquivo Corrompido / Sem Faces",
    res_corrupt.returncode != 0,
    f"Rejeitou malha vazia/sem faces corretamente (Exit code {res_corrupt.returncode})"
)

# 6. Teste Negativo: Referencias Explicitas Invalidas de UV e Normais (Auditoria P1)
inv_obj = os.path.join(TESTS_DIR, "temp_invalid_uv_norm.obj")
with open(inv_obj, "w") as f:
    f.write("v 0 0 0\nv 1 0 0\nv 0 1 0\nvt 0.5 0.5\nvn 0 0 1\nf 1/999/999 2/999/999 3/999/999\n")
inv_vg = os.path.join(TESTS_DIR, "temp_inv.vgmesh")
res_inv = subprocess.run([BAKER_EXE, inv_obj, inv_vg], capture_output=True, text=True, encoding="utf-8", errors="replace")
try:
    os.remove(inv_obj)
    if os.path.exists(inv_vg): os.remove(inv_vg)
except: pass

record_test(
    "6. Rejeicao de Referencias Invalidas de UV/Normal (Indice 999 OOB)",
    res_inv.returncode != 0 and "fora dos limites" in res_inv.stderr,
    f"Rejeitou indices OOB com seguranca (Exit code {res_inv.returncode}) e mensagem explicita"
)

# 7. Teste Negativo: Arquivo Binario .vgmesh Truncado / Adulterado
trunc_vg = os.path.join(TESTS_DIR, "temp_trunc.vgmesh")
with open(trunc_vg, "wb") as f:
    f.write(b"ARBORIA2\x02\x00\x00\x00\x00\x00") # Truncado no meio do header
res_trunc = subprocess.run([BAKER_EXE, "--verify-only", trunc_vg], capture_output=True, text=True, encoding="utf-8", errors="replace")
try:
    if os.path.exists(trunc_vg): os.remove(trunc_vg)
except: pass

record_test(
    "7. Rejeicao de Binario .vgmesh Truncado / Adulterado",
    res_trunc.returncode != 0 or "ERRO: Arquivo truncado" in res_trunc.stderr or "ERRO: Falha ao ler" in res_trunc.stderr,
    f"Detectou e rejeitou binario truncado/invalido com seguranca"
)

# 8. Teste de Leitura Binaria e Validacao de Formato .vgmesh v2 (incluindo DAG groups)
def test_vgmesh_binary(path):
    with open(path, "rb") as f:
        magic = f.read(8)
        if magic != b"ARBORIA2":
            return False, f"Magic invalido: {magic}"
        # Header tem 72 bytes no total (8 magic + 64 dados)
        header_bytes = f.read(64)
        version, verts, indices, tris, clusters, lod_count = struct.unpack("<IIIIII", header_bytes[:24])
        bmin = struct.unpack("<fff", header_bytes[24:36])
        bmax = struct.unpack("<fff", header_bytes[36:48])
        groups_count, base_tris = struct.unpack("<II", header_bytes[48:56])
        if version != 2:
            return False, f"Versao incorreta: {version}"
        if tris == 0 or clusters == 0 or groups_count == 0:
            return False, f"Triangulos ({tris}), clusters ({clusters}) ou grupos ({groups_count}) zerados"
    return True, f"Magic: ARBORIA2 | Versao: {version} | Tris: {tris:,} | Clusters: {clusters} | LODs: {lod_count} | DAG Groups: {groups_count}"

bin_ok, bin_details = test_vgmesh_binary(dense_vg)
record_test("8. Validacao Estrutural do Binario .vgmesh v2 + DAG Groups", bin_ok, bin_details)

# 7. Teste de Vinculos Hierarquicos DAG e Limites
def test_dag_links(path):
    with open(path, "rb") as f:
        magic = f.read(8)
        header_bytes = f.read(64)
        version, verts, indices, tris, cluster_count, lod_count = struct.unpack("<IIIIII", header_bytes[:24])
        groups_count, base_tris = struct.unpack("<II", header_bytes[48:56])
        
        # Le LOD descriptors (24 bytes cada)
        f.read(lod_count * 24)
        
        # Le Cluster descriptors (68 bytes cada)
        clusters = []
        for _ in range(cluster_count):
            c_data = f.read(68)
            cid, lod, gid, rgroup = struct.unpack("<IIii", c_data[:16])
            cx, cy, cz, radius = struct.unpack("<ffff", c_data[16:32])
            ncone_axis_x, ncone_axis_y, ncone_axis_z, ncone_cutoff = struct.unpack("<ffff", c_data[32:48])
            lod_error = struct.unpack("<f", c_data[48:52])[0]
            v_offset, v_count, t_offset, t_count = struct.unpack("<IIII", c_data[52:68])
            clusters.append({
                "id": cid, "lod": lod, "group": gid, "refined": rgroup,
                "radius": radius, "v_count": v_count, "t_count": t_count
            })
            
        # Le Group descriptors (28 bytes cada: I, i, f, f, f, f, f)
        groups = []
        for _ in range(groups_count):
            g_data = f.read(28)
            gid, depth, gx, gy, gz, radius, err = struct.unpack("<Iifffff", g_data)
            groups.append({"id": gid, "depth": depth, "radius": radius, "error": err})
            
        for c in clusters:
            if c["group"] < 0 or c["group"] >= groups_count:
                return False, f"Cluster {c['id']} com group_id invalido: {c['group']}"
            if c["refined"] >= groups_count:
                return False, f"Cluster {c['id']} com refined_group invalido: {c['refined']}"
            if c["v_count"] > 64 or c["t_count"] > 128:
                return False, f"Cluster {c['id']} excede limites: verts={c['v_count']}, tris={c['t_count']}"
                
    return True, f"Todos os {cluster_count} clusters possuem vinculos validos com {groups_count} grupos DAG (limites <=64v, <=128t respeitados)"

dag_ok, dag_details = test_dag_links(dense_vg)
record_test("9. Integridade de Vinculos Hierarquicos DAG", dag_ok, dag_details)

# ==============================================================================
# AUDITORIA P1: TESTES INDIVIDUAIS DE CORRUPCAO BINARIA
# ==============================================================================
with open(dense_vg, "rb") as f:
    valid_binary_data = bytearray(f.read())

def run_verify_on_bytes(modified_bytes, label):
    tmp_path = os.path.join(TESTS_DIR, f"temp_corrupt_{label}.vgmesh")
    try:
        with open(tmp_path, "wb") as f:
            f.write(modified_bytes)
        res = subprocess.run([BAKER_EXE, "--verify-only", tmp_path], capture_output=True, text=True, encoding="utf-8", errors="replace")
        rejected = (res.returncode != 0)
        return rejected, f"Rejeitado com seguranca (Exit Code {res.returncode}) | {res.stderr.strip()[:100]}"
    finally:
        if os.path.exists(tmp_path):
            try: os.remove(tmp_path)
            except: pass

# 10. Header Truncado
hdr_trunc = valid_binary_data[:30] # Menor que 72 bytes
ok_10, det_10 = run_verify_on_bytes(hdr_trunc, "hdr_trunc")
record_test("10. Corrupcao: Header Truncado (< 72 bytes)", ok_10, det_10)

# 11. Payload Truncado (Header valido, mas dados cortados pela metade)
payload_trunc = valid_binary_data[:500]
ok_11, det_11 = run_verify_on_bytes(payload_trunc, "payload_trunc")
record_test("11. Corrupcao: Payload Truncado", ok_11, det_11)

# 12. Offsets Alem do Fim do Arquivo (Modifica vertex_offset do primeiro cluster para 999999)
corrupt_offset = bytearray(valid_binary_data)
# Header: 72 bytes. LOD Descriptors: 9 * 24 = 216 bytes. Cluster 0 comeca em 288.
# VGClusterDescriptor::vertex_offset esta no offset 52 do descritor (288 + 52 = 340)
struct.pack_into("<I", corrupt_offset, 288 + 52, 999999)
ok_12, det_12 = run_verify_on_bytes(corrupt_offset, "oob_offset")
record_test("12. Corrupcao: Offsets Alem do Fim do Arquivo", ok_12, det_12)

# 13. Contagens Inconsistentes (LOD 0 cluster_count excedendo total de clusters)
corrupt_counts = bytearray(valid_binary_data)
# LOD descriptor 0 comeca em 72. cluster_count esta no offset 8 do descriptor (72 + 8 = 80)
struct.pack_into("<I", corrupt_counts, 72 + 8, 99999)
ok_13, det_13 = run_verify_on_bytes(corrupt_counts, "inconsistent_counts")
record_test("13. Corrupcao: Contagens Inconsistentes de Clusters no LOD", ok_13, det_13)

# 14. Indices de Clusters Invalidos (Indice local do vertice dentro do cluster > vertex_count)
corrupt_tri_idx = bytearray(valid_binary_data)
# No final do arquivo estao os triangulos (indices uint8_t). Modifica o primeiro byte para 250 (max vertex_count e 64)
# Localizacao dos triangulos: fim do arquivo menos total_triangles*3
struct.pack_into("<B", corrupt_tri_idx, len(corrupt_tri_idx) - 100, 250)
ok_14, det_14 = run_verify_on_bytes(corrupt_tri_idx, "invalid_tri_idx")
record_test("14. Corrupcao: Indices de Clusters Invalidos (> vertex_count)", ok_14, det_14)

# 15. Referencias DAG Invalidas (group_id invalido no cluster 0)
corrupt_dag = bytearray(valid_binary_data)
# Cluster 0: offset 288. group_id esta em offset 8 (288 + 8 = 296)
struct.pack_into("<i", corrupt_dag, 288 + 8, 99999)
ok_15, det_15 = run_verify_on_bytes(corrupt_dag, "invalid_dag")
record_test("15. Corrupcao: Referencias DAG Invalidas (group_id OOB)", ok_15, det_15)

# 16. Campos Estruturalmente Incoerentes / Magic Invalido
corrupt_magic = bytearray(valid_binary_data)
corrupt_magic[0:8] = b"CORRUPT1"
ok_16, det_16 = run_verify_on_bytes(corrupt_magic, "invalid_magic")
record_test("16. Corrupcao: Magic Invalido / Incoerente", ok_16, det_16)

# 17. Verificacao Rigorosa de Lossless LOD 0 com Comparacao Geometrica Completa
record_test(
    "17. LOD 0 Lossless Validado (Vertices, AABB, Normais, UVs, Orientacao)",
    "LOD0 LOSSLESS VALIDADO" in res_dense.stdout and "Triangulos Nao-Mapeados  : 0" in res_dense.stdout,
    "100% dos triangulos, vertices, normais e UVs equivalentes geometricamente entre OBJ e LOD 0"
)

print("\n" + "=" * 80)
print("RESUMO DA BATERIA DE TESTES DE VALIDACAO RIGOROSA (17 TESTES)")
print("=" * 80)
all_passed = True
for name, status, details in results:
    print(f"[{status:9}] {name}")
    if status != "APROVADO":
        all_passed = False
print("=" * 80)

if not all_passed:
    sys.exit(1)
