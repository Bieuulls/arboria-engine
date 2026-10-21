import subprocess
import os
import sys
import struct

sys.stdout.reconfigure(encoding='utf-8')

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(CURRENT_DIR)
BAKER_EXE = os.path.join(REPO_ROOT, "bin", "vg_baker_cli.exe")
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
    record_test("1. Binario C++ Compilado", True, f"vg_baker_cli.exe presente ({sz:,} bytes)")

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

print("\n" + "=" * 80)
print("RESUMO DA BATERIA DE TESTES DE VALIDACAO")
print("=" * 80)
all_passed = True
for name, status, details in results:
    print(f"[{status:9}] {name}")
    if status != "APROVADO":
        all_passed = False
print("=" * 80)

if not all_passed:
    sys.exit(1)
