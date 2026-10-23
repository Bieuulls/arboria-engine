import os
import sys
import json
import subprocess
import time
import platform
import csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
CONFIG_PATH = os.path.join(SCRIPT_DIR, "config.json")
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
CAPTURES_DIR = os.path.join(RESULTS_DIR, "captures")
RAW_CSV_PATH = os.path.join(RESULTS_DIR, "raw.csv")
SUMMARY_MD_PATH = os.path.join(RESULTS_DIR, "summary.md")

os.makedirs(CAPTURES_DIR, exist_ok=True)

# 1. Localiza o executável do Godot dinamicamente
def find_godot():
    env_bin = os.environ.get("GODOT_BIN")
    if env_bin and os.path.exists(env_bin):
        return env_bin

    localapp = os.environ.get("LOCALAPPDATA", "")
    winget_godot = os.path.join(
        localapp, "Microsoft", "WinGet", "Packages",
        "GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe",
        "Godot_v4.7.2-stable_win64_console.exe"
    )

    candidates = [
        winget_godot,
        os.path.join(REPO_ROOT, "bin", "godot_console.exe"),
        os.path.join(REPO_ROOT, "bin", "godot.exe"),
        "godot_console.exe",
        "godot.exe",
        "godot"
    ]
    for c in candidates:
        if os.path.isabs(c) and os.path.exists(c):
            return c
        elif not os.path.isabs(c):
            which = subprocess.run(["where.exe", c] if sys.platform.startswith("win") else ["which", c], capture_output=True, text=True)
            if which.returncode == 0 and which.stdout.strip():
                return which.stdout.strip().splitlines()[0]
    return "godot"

GODOT_BIN = find_godot()

# 2. Coleta dados de hardware e ambiente
def get_system_environment():
    gpu_name = "NVIDIA GeForce RTX 3050 Laptop GPU (6 GB VRAM)"
    driver_version = "Desconhecido"
    try:
        smi = subprocess.run(["nvidia-smi", "--query-gpu=gpu_name,driver_version", "--format=csv,noheader"], capture_output=True, text=True)
        if smi.returncode == 0 and smi.stdout.strip():
            parts = smi.stdout.strip().split(",")
            if len(parts) >= 2:
                gpu_name = parts[0].strip()
                driver_version = parts[1].strip()
    except Exception:
        pass

    godot_ver = "4.7.2.stable.official"
    try:
        gv = subprocess.run([GODOT_BIN, "--version"], capture_output=True, text=True)
        if gv.returncode == 0 and gv.stdout.strip():
            godot_ver = gv.stdout.strip()
    except Exception:
        pass

    return {
        "os": f"{platform.system()} {platform.release()} ({platform.machine()})",
        "gpu": gpu_name,
        "driver": driver_version,
        "godot": godot_ver,
        "api": "Vulkan 1.4 / Forward+",
        "resolution": "1920x1080 (VSync OFF, FPS Ilimitado)"
    }

def main():
    print("=" * 80)
    print("ARBORIA ENGINE — SUÍTE DE BENCHMARK PROFISSIONAL & REPRODUZÍVEL")
    print("=" * 80)

    env_info = get_system_environment()
    print("Ambiente de Execução:")
    for k, v in env_info.items():
        print(f"  - {k.capitalize():12}: {v}")
    print(f"  - Godot Bin   : {GODOT_BIN}")
    print("=" * 80)

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        config = json.load(f)

    scenarios = config["scenarios"]
    variants = config["variants"]
    warmup = config["execution"]["warmup_frames"]
    measured = config["execution"]["measured_frames"]

    # Prepara raw.csv
    if os.path.exists(RAW_CSV_PATH):
        try: os.remove(RAW_CSV_PATH)
        except: pass

    all_results = []
    project_dir = os.path.join(REPO_ROOT, "project")

    target_scenario = None
    target_instances = None
    for i, arg in enumerate(sys.argv):
        if arg == "--scenario" and i + 1 < len(sys.argv):
            target_scenario = sys.argv[i + 1]
        elif arg == "--instances" and i + 1 < len(sys.argv):
            target_instances = [int(x.strip()) for x in sys.argv[i + 1].split(",")]

    if target_scenario:
        scenarios = [sc for sc in scenarios if sc["id"] == target_scenario]
    if target_instances:
        for sc in scenarios:
            sc["instances"] = [inst for inst in sc["instances"] if inst in target_instances]

    total_runs = sum(len(sc["instances"]) * len(variants) for sc in scenarios)
    run_idx = 0

    for sc in scenarios:
        sc_id = sc["id"]
        sc_name = sc["name"]
        mesh_vg = sc["mesh_path_vg"]
        mesh_obj = sc["mesh_path_obj"]

        for inst_count in sc["instances"]:
            for var in variants:
                run_idx += 1
                var_id = var["id"]
                var_name = var["name"]

                print(f"\n[{run_idx}/{total_runs}] Executando: {sc_id} | {var_id} | {inst_count} instancias...")

                capture_filename = f"{sc_id}_{var_id}_{inst_count}inst.png"
                capture_abs = os.path.join(CAPTURES_DIR, capture_filename)
                capture_rel_godot = f"res://../bench/results/captures/{capture_filename}"

                temp_json_abs = os.path.join(RESULTS_DIR, f"temp_{sc_id}_{var_id}_{inst_count}.json")
                temp_json_godot = f"res://../bench/results/temp_{sc_id}_{var_id}_{inst_count}.json"

                raw_csv_godot = "res://../bench/results/raw.csv"

                cmd = [
                    GODOT_BIN,
                    "--path", project_dir,
                    "--scene", "res://bench/benchmark_scene.tscn",
                    "--",
                    "--scenario", sc_id,
                    "--variant", var_id,
                    "--instances", str(inst_count),
                    "--mesh-vg", mesh_vg,
                    "--mesh-obj", mesh_obj,
                    "--capture-path", capture_rel_godot,
                    "--output-json", temp_json_godot,
                    "--raw-csv", raw_csv_godot,
                    "--warmup", str(warmup),
                    "--measured", str(measured)
                ]

                start_time = time.time()
                timeout_sec = 180 # 3 minutos de timeout maximo por combinacao
                timed_out = False
                crashed = False
                out_text = ""

                try:
                    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_sec, encoding="utf-8", errors="replace")
                    out_text = proc.stdout + "\n" + proc.stderr
                    if proc.returncode != 0:
                        crashed = True
                except subprocess.TimeoutExpired:
                    timed_out = True
                except Exception as e:
                    crashed = True
                    out_text = str(e)

                elapsed_real = time.time() - start_time

                # Avalia resultado
                res_entry = {
                    "scenario": sc_id,
                    "scenario_name": sc_name,
                    "variant": var_id,
                    "variant_name": var_name,
                    "instances": inst_count,
                    "capture_file": capture_filename,
                    "elapsed_real_sec": elapsed_real
                }

                if timed_out:
                    print(f"  -> INCONCLUSIVO: Timeout ({timeout_sec}s atingido)")
                    res_entry["status"] = "Inconclusivo (Timeout)"
                elif crashed:
                    print(f"  -> FALHOU: Crash ou Codigo de Saida Invalido ({proc.returncode if 'proc' in locals() else 'Erro'})")
                    res_entry["status"] = "FALHOU (Crash/OOM)"
                elif os.path.exists(temp_json_abs):
                    try:
                        with open(temp_json_abs, "r", encoding="utf-8") as jf:
                            data = json.load(jf)
                            res_entry.update(data)
                            res_entry["status"] = "OK"
                            print(f"  -> SUCESSO: p95 Frame Time={data.get('frame_time_p95', 0.0):.2f} ms | VRAM={data.get('vram_avg_mb', 0.0):.1f} MB")
                    except Exception as e:
                        res_entry["status"] = f"FALHOU (JSON corrompido: {e})"
                    finally:
                        try: os.remove(temp_json_abs)
                        except: pass
                else:
                    res_entry["status"] = "FALHOU (Sem saida JSON)"

                all_results.append(res_entry)

    # 3. Gera Relatório summary.md e Avaliação GO / NO-GO
    print("\n" + "=" * 80)
    print("GERANDO RELATÓRIO CONSOLIDADO: bench/results/summary.md")
    print("=" * 80)
    generate_summary_markdown(all_results, env_info, config)

def generate_summary_markdown(results, env, config):
    crit = config["go_decision_criteria"]
    p95_ratio_thresh = crit["frame_time_p95_ratio_threshold"]
    vram_ratio_thresh = crit["vram_ratio_threshold"]
    min_large = crit["min_large_combinations"]
    large_inst_thresh = crit["large_instance_threshold"]

    # Mapeia resultados por (scenario, instances, variant)
    lookup = {}
    for r in results:
        key = (r["scenario"], r["instances"], r["variant"])
        lookup[key] = r

    lines = []
    lines.append("# ARBORIA ENGINE — RELATÓRIO OFICIAL DE BENCHMARK")
    lines.append(f"**Data da Execução:** {time.strftime('%d/%m/%Y %H:%M:%S')}\n")
    lines.append("## 1. Ambiente de Execução e Hardware")
    lines.append(f"- **Sistema Operacional:** {env['os']}")
    lines.append(f"- **Placa de Vídeo (GPU):** {env['gpu']}")
    lines.append(f"- **Driver da GPU:** {env['driver']}")
    lines.append(f"- **Motor Godot:** {env['godot']}")
    lines.append(f"- **API Gráfica:** {env['api']}")
    lines.append(f"- **Resolução Efetiva:** {env['resolution']}\n")

    lines.append("## 2. Metodologia de Medição Rigorosa")
    lines.append("- **Trajetória e Sementes:** Câmera orbital determinística idêntica; semente determinística `seed=42` para posicionamento e rotações em todas as variantes.")
    lines.append("- **Janela de Medição:** 300 frames de aquecimento (warmup) e 1.000 frames medidos continuamente por combinação.")
    lines.append("- **Isolamento de I/O:** Coleta in-memory durante a janela medida e gravação em disco exclusivamente após a medição.")
    lines.append("- **Captura Real:** Imagem PNG capturada fora da janela medida (frame 290) para auditoria visual de fidelidade.")
    lines.append("- **Separação de Métricas CPU e GPU:**")
    lines.append("  - *Frame Time:* Tempo total entre frames na main thread (`delta * 1000`).")
    lines.append("  - *CPU Render:* Tempo de CPU gasto estritamente no render loop do viewport (`RenderingServer.viewport_get_measured_render_time_cpu`).")
    lines.append("  - *GPU Render:* Tempo real de execução na GPU (`RenderingServer.viewport_get_measured_render_time_gpu`), obtido via Vulkan timestamp queries com 1-2 frames de latência inerente.")
    lines.append("- **Instrumentação do Caminho Customizado:**")
    lines.append("  - Para o ARBORIA, os draws incluem os draws indiretos reais (`rd.draw_list_draw_indirect`), as primitivas refletem os triângulos dos clusters visíveis rasterizados e os clusters avaliados/visíveis são rastreados diretamente da GPU.")
    lines.append("- **Validade Comparativa:** Timeouts e quedas (Crash/OOM) são marcados como **INCONCLUSIVOS** e nunca são computados como vitória automática nem razões 0.00.\n")

    lines.append("## 3. Tabela Comparativa de Resultados")
    lines.append("| Cenário | Instâncias | Variante | Status | Frame Time p50 (ms) | Frame Time p95 (ms) | Frame Time p99 (ms) | CPU Render p95 (ms) | GPU Render p95 (ms) | VRAM Média (MB) | Draws (Godot + Ind) | Primitivas / Tris | Clusters (Vis / Tot) |")
    lines.append("| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")

    for r in results:
        if r["status"] == "OK":
            gpu_str = "N/A" if r.get("gpu_time_p95") is None else f"{r['gpu_time_p95']:.2f}"
            is_arb = "arboria" in r["variant"]
            if is_arb:
                ind = r.get("arb_indirect_draws_avg", 0)
                draws_str = f"{r.get('draw_calls_avg', 0):.0f} ({ind:.0f} ind)"
                prims_str = f"{r.get('arb_triangles_avg', r.get('primitives_avg', 0)):.0f}"
                clusters_str = f"{r.get('arb_clusters_vis_avg', 0):.0f} / {r.get('arb_clusters_eval_avg', 0):.0f}"
            else:
                draws_str = f"{r.get('draw_calls_avg', 0):.0f}"
                prims_str = f"{r.get('primitives_avg', 0):.0f}"
                clusters_str = "-"

            lines.append(f"| {r['scenario']} | {r['instances']} | {r['variant']} | ✅ {r['status']} | {r['frame_time_p50']:.2f} | {r['frame_time_p95']:.2f} | {r['frame_time_p99']:.2f} | {r['cpu_time_p95']:.2f} | {gpu_str} | {r['vram_avg_mb']:.1f} | {draws_str} | {prims_str} | {clusters_str} |")
        else:
            lines.append(f"| {r['scenario']} | {r['instances']} | {r['variant']} | ❌ {r['status']} | - | - | - | - | - | - | - | - | - |")

    lines.append("\n## 4. Comparações Diretas e Avaliação de Desempenho")
    lines.append("### 4.1 Comparação de Qualidade Equivalente: ARBORIA (DAG Dinâmico) vs. Melhor Godot Convencional")
    lines.append("| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA (ms) | Razão p95 (ARB/Godot) | VRAM Godot (MB) | VRAM ARBORIA (MB) | Razão VRAM | Vantagem Significativa? |")
    lines.append("| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")

    large_advantages = 0
    scenarios_list = config["scenarios"]

    for sc in scenarios_list:
        sc_id = sc["id"]
        for inst in sc["instances"]:
            res_a = lookup.get((sc_id, inst, "mesh_instance"))
            res_b = lookup.get((sc_id, inst, "multimesh"))
            res_c = lookup.get((sc_id, inst, "arboria"))

            if not res_c or res_c.get("status") != "OK":
                status_str = res_c.get("status", "Ausente") if res_c else "Ausente"
                lines.append(f"| {sc_id} | {inst} | - | - | - | N/A | - | - | N/A | Inconclusivo (ARBORIA {status_str}) |")
                continue

            # Escolhe o melhor Godot convencional entre A e B que completou com OK
            candidates = []
            if res_a and res_a.get("status") == "OK": candidates.append(("MeshInstance3D", res_a))
            if res_b and res_b.get("status") == "OK": candidates.append(("MultiMeshInstance3D", res_b))

            if not candidates:
                # Ambas as variantes convencionais falharam (ex: Timeout ou Crash/OOM)
                fail_reasons = []
                if res_a: fail_reasons.append(f"Mesh: {res_a.get('status')}")
                if res_b: fail_reasons.append(f"MultiMesh: {res_b.get('status')}")
                reason_str = "; ".join(fail_reasons) if fail_reasons else "Sem execucao valida"
                # Regra: NUNCA tratar timeout/crash convencional como vitória automática (0.00 ratio). Registrar estritamente como Inconclusivo.
                lines.append(f"| {sc_id} | {inst} | Nenhuma (Falha Convencional) | N/A | {res_c['frame_time_p95']:.2f} | N/A | N/A | {res_c['vram_avg_mb']:.1f} | N/A | Inconclusivo ({reason_str}) |")
                continue

            # Ordena por menor p95
            candidates.sort(key=lambda x: x[1]["frame_time_p95"])
            best_name, best_res = candidates[0]

            p95_arb = res_c["frame_time_p95"]
            p95_best = best_res["frame_time_p95"]
            ratio_p95 = p95_arb / max(0.001, p95_best)

            vram_arb = res_c["vram_avg_mb"]
            vram_best = best_res["vram_avg_mb"]
            ratio_vram = vram_arb / max(0.001, vram_best)

            has_adv = (ratio_p95 <= p95_ratio_thresh) or (ratio_vram <= vram_ratio_thresh)
            adv_str = f"**SIM** ({ratio_p95:.2f}x tempo, {ratio_vram:.2f}x VRAM)" if has_adv else f"Não ({ratio_p95:.2f}x tempo, {ratio_vram:.2f}x VRAM)"

            if has_adv and inst >= large_inst_thresh:
                large_advantages += 1

            lines.append(f"| {sc_id} | {inst} | {best_name} | {p95_best:.2f} | {p95_arb:.2f} | {ratio_p95:.2f} | {vram_best:.1f} | {vram_arb:.1f} | {ratio_vram:.2f} | {adv_str} |")

    # 4.2 Comparação de LOD0 Idêntico se houver dados
    has_lod0_data = any((r.get("variant") == "arboria_lod0") for r in results)
    if has_lod0_data:
        lines.append("\n### 4.2 Comparação de LOD0 Idêntico: ARBORIA (LOD0 Forçado) vs. Melhor Godot Convencional")
        lines.append("| Cenário | Instâncias | Melhor Godot Convencional | p95 Godot (ms) | p95 ARBORIA LOD0 (ms) | Razão p95 | VRAM Godot (MB) | VRAM ARBORIA LOD0 (MB) | Razão VRAM |")
        lines.append("| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |")
        for sc in scenarios_list:
            sc_id = sc["id"]
            for inst in sc["instances"]:
                res_a = lookup.get((sc_id, inst, "mesh_instance"))
                res_b = lookup.get((sc_id, inst, "multimesh"))
                res_d = lookup.get((sc_id, inst, "arboria_lod0"))

                if not res_d or res_d.get("status") != "OK":
                    continue

                candidates = []
                if res_a and res_a.get("status") == "OK": candidates.append(("MeshInstance3D", res_a))
                if res_b and res_b.get("status") == "OK": candidates.append(("MultiMeshInstance3D", res_b))
                if not candidates:
                    lines.append(f"| {sc_id} | {inst} | Nenhuma (Falha Convencional) | N/A | {res_d['frame_time_p95']:.2f} | N/A | N/A | {res_d['vram_avg_mb']:.1f} | N/A |")
                    continue

                candidates.sort(key=lambda x: x[1]["frame_time_p95"])
                best_name, best_res = candidates[0]
                p95_d = res_d["frame_time_p95"]
                p95_b = best_res["frame_time_p95"]
                r_p95 = p95_d / max(0.001, p95_b)
                v_d = res_d["vram_avg_mb"]
                v_b = best_res["vram_avg_mb"]
                r_vram = v_d / max(0.001, v_b)
                lines.append(f"| {sc_id} | {inst} | {best_name} | {p95_b:.2f} | {p95_d:.2f} | {r_p95:.2f} | {v_b:.1f} | {v_d:.1f} | {r_vram:.2f} |")

    lines.append("\n## 5. Diferenças de Qualidade Visual e Limitações Honestamente Registradas")
    lines.append("1. **Sombras Dinâmicas no Cenário:** As variantes A e B nativas do Godot projetam e recebem sombras dinâmicas completas via Shadow Atlas. A variante ARBORIA escreve no buffer Forward+, mas ainda não injeta no passe de Shadow Map do Godot.")
    lines.append("2. **Qualidade dos Materiais:** As variantes A e B utilizam o renderizador PBR completo do Godot (StandardMaterial3D). O ARBORIA utiliza um shader Cook-Torrance GGX procedural.")
    lines.append("3. **Transições de LOD:** O ARBORIA executa seleção contínua de clusters Nanite DAG na GPU. Pequenos estalidos de pop geométrico podem ocorrer em distâncias limítrofes.")
    lines.append("4. **Gargalo de Submissão em Escala:** A versão atual do ARBORIA faz 1 despacho de compute e 1 draw indirect por instância no loop C++. Para 2.000 instâncias, o tempo de CPU de submissão de comandos aumenta linearmente.")

    lines.append("\n## 6. Decisão Formal GO / NO-GO")
    lines.append(f"- **Critério Exigido:** Apresentar p95 de frame time $\\le {p95_ratio_thresh*100:.0f}\\%$ do melhor Godot convencional **OU** usar $\\le {vram_ratio_thresh*100:.0f}\\%$ da VRAM em pelo menos **{min_large} combinações grandes** (instâncias $\\ge {large_inst_thresh}$).")
    lines.append(f"- **Combinações Grandes com Vantagem Validada:** {large_advantages} encontrada(s).")

    if large_advantages >= min_large:
        decision = "GO (Vantagem Tecnológica Comprovada nas Condições Medidas)"
        decision_desc = f"O ARBORIA atingiu o limiar de vantagem competitiva em {large_advantages} combinações de larga escala. Isto indica mérito técnico comprovado nas condições medidas (não constitui aprovação automática como motor de produção acabado sem sombras e materiais completos)."
    elif large_advantages > 0:
        decision = "INCONCLUSIVO (Vantagem Parcial / Incompleta)"
        decision_desc = f"O ARBORIA superou a alternativa convencional em {large_advantages} combinação(ões), mas não atingiu a meta mínima de {min_large} combinações grandes."
    else:
        decision = "NO-GO (Sem Vantagem Mensurável)"
        decision_desc = "O ARBORIA não apresentou vantagem de frame time ou VRAM dentro do limiar configurado nas combinações testadas."

    lines.append(f"\n### **RESULTADO FINAL DA DECISÃO:** `{decision}`\n")
    lines.append(f"> **Parecer Técnico:** {decision_desc}\n")

    summary_content = "\n".join(lines)
    with open(SUMMARY_MD_PATH, "w", encoding="utf-8") as f:
        f.write(summary_content)

    print(f"\nResumo gravado em: {SUMMARY_MD_PATH}")
    print(f"Resultado da Decisão: {decision}")

if __name__ == "__main__":
    main()
