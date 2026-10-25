"""Convert real ARBORIA benchmark artifacts (raw.csv and summary.md) to strict JSON metrics and AI feedback context.

This guarantees that the AI optimization feedback loop consumes real telemetry
from bench/results/raw.csv and bench/results/summary.md without any synthetic mocks.
"""
from __future__ import annotations
import argparse, csv, json, math, re, statistics
from pathlib import Path


def p95(values):
    values = sorted(values)
    return values[min(len(values) - 1, max(0, math.ceil(0.95 * len(values)) - 1))]


def derive(csv_path: Path, scenario: str, variant: str, instances: int, min_frames: int = 10):
    samples = []
    with csv_path.open(encoding='utf-8-sig', newline='') as f:
        reader = csv.DictReader(f)
        for raw in reader:
            row = {k.strip().strip('*'): v for k, v in raw.items() if k is not None}
            if row.get('scenario') == scenario and row.get('variant') == variant and int(row.get('instances', '-1')) == instances:
                samples.append(row)
    if len(samples) < min_frames:
        raise ValueError(f'Apenas {len(samples)} frames no CSV para ({scenario}, {variant}, {instances}); mínimo exigido: {min_frames}.')
    gpu = [float(r['gpu_render_ms']) for r in samples]
    frame = [float(r['frame_time_ms']) for r in samples]
    vram = [float(r['vram_mb']) for r in samples]
    if any(not math.isfinite(x) for x in gpu + frame + vram):
        raise ValueError('Dados de telemetria não finitos detectados.')
    
    # Busca campo de clusters visiveis do ARBORIA ou primitivas para baselines nativos
    vis_field = next((x for x in ('arb_clusters_vis', 'visible_clusters', 'clusters_visible', 'arboria_clusters_visible') if x in samples[0]), None)
    if vis_field is None or (vis_field == 'arb_clusters_vis' and variant in ('mesh_instance', 'multimesh')):
        vis_field = 'primitives'
    
    if vis_field not in samples[0]:
        raise ValueError('CSV não contém contador customizado de clusters ou primitivas visíveis.')
        
    visible = [float(r[vis_field]) for r in samples]
    if min(visible) <= 0:
        raise ValueError('Algum frame medido reporta zero geometria visível no benchmark real.')
        
    return {
        'gpu_p95_ms': p95(gpu),
        'frame_p95_ms': p95(frame),
        'vram_mb': statistics.mean(vram),
        'visible_clusters': statistics.median(visible),
        'samples': len(samples)
    }


def parse_summary_md(summary_path: Path) -> dict:
    """Extrai métricas consolidadas e decisão formal diretamente de bench/results/summary.md."""
    if not summary_path.is_file():
        return {"error": f"Arquivo não encontrado: {summary_path}"}
    
    text = summary_path.read_text(encoding="utf-8", errors="replace")
    
    decision = "DESCONHECIDO"
    dec_match = re.search(r"RESULTADO FINAL DA DECIS.+?:\*\*\s*`?([^`\n\r]+)`?", text, re.IGNORECASE)
    if dec_match:
        decision = dec_match.group(1).strip()
    
    hardware = {}
    for line in text.splitlines():
        if "Placa de Vídeo" in line and ":**" in line:
            hardware["gpu"] = line.split(":**", 1)[-1].strip()
        elif "Motor Godot" in line and ":**" in line:
            hardware["godot"] = line.split(":**", 1)[-1].strip()
        elif "API Gráfica" in line and ":**" in line:
            hardware["api"] = line.split(":**", 1)[-1].strip()

    # Parse da tabela de resultados
    rows = []
    in_table = False
    for line in text.splitlines():
        if "| Cenário | Instâncias | Variante |" in line:
            in_table = True
            continue
        if in_table:
            if not line.strip().startswith("|") or "---" in line:
                if rows:  # Fim da tabela
                    break
                continue
            cols = [c.strip() for c in line.split("|")[1:-1]]
            if len(cols) >= 12:
                rows.append({
                    "scenario": cols[0],
                    "instances": cols[1],
                    "variant": cols[2],
                    "status": cols[3],
                    "frame_p50": cols[4],
                    "frame_p95": cols[5],
                    "frame_p99": cols[6],
                    "cpu_p95": cols[7],
                    "gpu_p95": cols[8],
                    "vram_mb": cols[9],
                    "draws": cols[10],
                    "primitives": cols[11],
                    "clusters": cols[12] if len(cols) > 12 else "-"
                })

    return {
        "decision": decision,
        "hardware": hardware,
        "rows": rows
    }


def get_latest_benchmark_context(repo_root: Path) -> str:
    """Gera bloco de telemetria estritamente real para alimentar os prompts da IA."""
    summary_path = repo_root / "bench" / "results" / "summary.md"
    csv_path = repo_root / "bench" / "results" / "raw.csv"
    
    lines = ["[TELEMETRIA REAL DO BENCHMARK OFICIAL ARBORIA]"]
    if summary_path.exists():
        parsed = parse_summary_md(summary_path)
        lines.append(f"Decisão Técnica Atual: {parsed.get('decision', 'N/A')}")
        hw = parsed.get("hardware", {})
        if hw:
            lines.append(f"Ambiente: GPU {hw.get('gpu', 'Desconhecida')} | Godot {hw.get('godot', '4.x')} | {hw.get('api', 'Vulkan')}")
        lines.append("Resultados Medidos (Amostras p95 reais):")
        for r in parsed.get("rows", []):
            lines.append(f" - {r['scenario']} {r['instances']} instâncias [{r['variant']}]: Frame p95={r['frame_p95']}ms, CPU p95={r['cpu_p95']}ms, GPU p95={r['gpu_p95']}ms, VRAM={r['vram_mb']}MB, Draws={r['draws']}, Tris={r['primitives']}, Clusters={r['clusters']}")
    elif csv_path.exists():
        lines.append(f"Dados brutos em {csv_path.name}: medições reais disponíveis.")
    else:
        lines.append("Aviso: Nenhum benchmark foi gerado ainda. Não há dados sintéticos permitidos.")
        
    return "\n".join(lines)


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--csv', default='bench/results/raw.csv')
    a.add_argument('--summary', default='bench/results/summary.md')
    a.add_argument('--scenario', default='dense_rock')
    a.add_argument('--variant', default='arboria')
    a.add_argument('--instances', type=int, default=500)
    a.add_argument('--min-frames', type=int, default=10)
    a.add_argument('--visual-error-json', help='JSON real: {"visual_error":numero} obtido por comparador de imagens')
    a.add_argument('--output', help='Caminho JSON para exportar métricas')
    a.add_argument('--context-only', action='store_true', help='Imprime apenas o contexto para o prompt da IA')
    opts = a.parse_args()

    repo = Path('.').resolve()
    if opts.context_only:
        print(get_latest_benchmark_context(repo))
        return

    csv_p = Path(opts.csv)
    if not csv_p.is_absolute():
        csv_p = repo / csv_p
    d = derive(csv_p, opts.scenario, opts.variant, opts.instances, opts.min_frames)
    
    if opts.visual_error_json:
        visual = json.loads(Path(opts.visual_error_json).read_text(encoding='utf-8'))
        if not isinstance(visual.get('visual_error'), (int, float)) or not math.isfinite(visual['visual_error']):
            raise ValueError('Comparação visual ausente ou inválida.')
        d['visual_error'] = float(visual['visual_error'])
        
    if opts.output:
        out_p = Path(opts.output)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(d, indent=2), encoding='utf-8')
        print(f"Métricas reais derivadas salvas em {out_p}")
    else:
        print(json.dumps(d, indent=2))


if __name__ == '__main__':
    main()
