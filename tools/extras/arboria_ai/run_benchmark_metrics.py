"""
ARBORIA AI - EXECUTOR DE BENCHMARK REAL E GERAÇÃO DE MÉTRICAS AEOC (CORRIGIDO)
Executa a cena real no Godot Forward+ Vulkan na GPU física,
coleta métricas reais emitidas pelo runtime (sem números fixos),
compara visualmente o frame gerado com o baseline de referência,
e gera o JSON de métricas validado.
"""

from __future__ import annotations
import os
import sys
import json
import argparse
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.arboria_ai.bench import checked_metrics, REQUIRED
from tools.arboria_ai.visual_compare import compare_png

GODOT_BIN = r"D:\ARBORIA_ENGINE\bin\godot.exe"
DEFAULT_OUTPUT_METRICS = REPO_ROOT / "artifacts" / "aeoc_metrics.json"
DEFAULT_REF_IMAGE = REPO_ROOT / "artifacts" / "baseline_reference.png"
DEFAULT_CAND_IMAGE = REPO_ROOT / "artifacts" / "candidate_test.png"

def run_benchmark(
    mode: str = "candidate",
    reference_img: Path = DEFAULT_REF_IMAGE,
    candidate_img: Path = DEFAULT_CAND_IMAGE,
    output_metrics: Path = DEFAULT_OUTPUT_METRICS,
    instances: int = 80
) -> int:
    output_metrics.parent.mkdir(parents=True, exist_ok=True)
    if output_metrics.exists():
        try: output_metrics.unlink()
        except: pass

    # Se referencia nao existe no local padrao, verifica se existe na worktree baseline irma
    if not reference_img.exists():
        try:
            alt_ref = reference_img.parent.parent.parent / "baseline" / "artifacts" / reference_img.name
            if alt_ref.exists():
                reference_img = alt_ref
        except Exception:
            pass

    actual_mode = mode
    if not reference_img.exists():
        actual_mode = "baseline"

    # Determina o caminho de saida da captura para esta execucao
    target_capture = reference_img if actual_mode == "baseline" else candidate_img
    target_capture.parent.mkdir(parents=True, exist_ok=True)
    if target_capture.exists():
        try: target_capture.unlink()
        except: pass

    proj_dir = REPO_ROOT / "project"
    target_capture_str = str(target_capture.resolve()).replace("\\", "/")

    cmd = [
        GODOT_BIN,
        "--rendering-driver", "vulkan",
        "--path", str(proj_dir),
        "scenes/arboria_massive_world_demo.tscn",
        "--",
        "--benchmark",
        f"--instances={instances}",
        f"--capture-path={target_capture_str}"
    ]

    print(f"[AEOC Benchmark ({mode.upper()})] Executando Godot Forward+ Vulkan:")
    print(f"  Comando: {' '.join(cmd)}")
    
    log_run = REPO_ROOT / "artifacts" / "godot_benchmark_exec.log"
    with open(log_run, "w", encoding="utf-8", errors="replace") as f_log:
        proc = subprocess.run(cmd, stdout=f_log, stderr=subprocess.STDOUT, timeout=45)
    stdout = log_run.read_text(encoding="utf-8", errors="replace")
    
    if proc.returncode != 0:
        print(f"[AEOC Benchmark Error] Godot falhou com codigo {proc.returncode}:\n{stdout}", file=sys.stderr)
        return 1

    # Rejeita imediatamente erros de shader ou runtime
    if "SCRIPT ERROR" in stdout or "Compile error" in stdout or "Shader compilation failed" in stdout:
        print(f"[AEOC Benchmark Error] Erro de shader ou script detectado:\n{stdout}", file=sys.stderr)
        return 1

    # Proíbe reutilização de capturas antigas: verifica se a captura foi realmente gerada nesta execução
    if not target_capture.exists() or target_capture.stat().st_size <= 0:
        print(f"[AEOC Benchmark Error] Captura visual obrigatoria nao foi gerada pelo Godot: {target_capture}", file=sys.stderr)
        return 1

    # Extrai metricas reais emitidas pelo Godot
    metrics_data = None
    for line in stdout.splitlines():
        if "[METRICS_DATA]" in line:
            raw_json = line.split("[METRICS_DATA]")[1].strip()
            try:
                metrics_data = json.loads(raw_json)
                break
            except Exception as e:
                print(f"[AEOC Benchmark Warning] Falha ao parsear METRICS_DATA: {e}")

    if not metrics_data:
        print(f"[AEOC Benchmark Error] O Godot nao emitiu a tag [METRICS_DATA]. Stdout:\n{stdout}", file=sys.stderr)
        return 1

    # Valida presença de todas as grandezas físicas reais (sem valores fixos)
    frame_p95_ms = float(metrics_data.get("frame_p95_ms", 0.0))
    gpu_p95_ms = float(metrics_data.get("gpu_p95_ms", 0.0))
    vram_mb = float(metrics_data.get("vram_mb", 0.0))
    vis_clusters = float(metrics_data.get("visible_clusters", 0.0))
    triangles_drawn = float(metrics_data.get("triangles_drawn", 0.0))
    cpu_submission_ms = float(metrics_data.get("cpu_submission_ms", 0.0))

    if frame_p95_ms <= 0.0 or gpu_p95_ms <= 0.0 or vram_mb <= 0.0:
        print(f"[AEOC Benchmark Error] Metricas fisicas invalidas (zero ou negativas): frame={frame_p95_ms}, gpu={gpu_p95_ms}, vram={vram_mb}", file=sys.stderr)
        return 1

    if vis_clusters <= 0.0:
        print(f"[AEOC Benchmark Error] Falha de geometria: zero clusters visiveis registrados.", file=sys.stderr)
        return 1

    # Comparação visual pixel a pixel
    visual_error = 0.0
    if actual_mode == "candidate":
        if not reference_img.exists():
            print(f"[AEOC Benchmark Error] Imagem de referencia ausente para comparacao: {reference_img}", file=sys.stderr)
            return 1
        try:
            v_res = compare_png(reference_img, target_capture)
            visual_error = float(v_res.get("visual_error", 0.0))
            print(f"[AEOC Benchmark Visual] Erro visual MAE vs Referencia: {visual_error:.6f}")
        except Exception as e:
            print(f"[AEOC Benchmark Error] Falha na comparacao visual de imagens: {e}", file=sys.stderr)
            return 1

    metrics = {
        "gpu_p95_ms": gpu_p95_ms,
        "frame_p95_ms": frame_p95_ms,
        "vram_mb": vram_mb,
        "visible_clusters": vis_clusters,
        "visual_error": visual_error,
        "cpu_submission_ms": cpu_submission_ms,
        "triangles_drawn": triangles_drawn,
        "mode": actual_mode,
        "capture_file": str(target_capture.resolve())
    }

    # Valida usando o validador estrito checked_metrics
    try:
        output_metrics.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
        checked_metrics(output_metrics)
    except Exception as e:
        print(f"[AEOC Benchmark Error] checked_metrics rejeitou o arquivo gerado: {e}", file=sys.stderr)
        if output_metrics.exists(): output_metrics.unlink()
        return 1

    print(f"[AEOC Benchmark Sucesso] Metricas reais salvas em {output_metrics}:\n{json.dumps(metrics, indent=2)}")
    return 0

def main():
    parser = argparse.ArgumentParser(description="Executor de benchmark real e gerador de metricas AEOC")
    parser.add_argument("--mode", choices=["baseline", "candidate"], default="candidate", help="Modo de execucao")
    parser.add_argument("--reference-img", type=Path, default=DEFAULT_REF_IMAGE, help="Caminho da imagem de referencia")
    parser.add_argument("--candidate-img", type=Path, default=DEFAULT_CAND_IMAGE, help="Caminho da captura candidata")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_METRICS, help="Caminho do JSON de metricas gerado")
    parser.add_argument("--instances", type=int, default=80, help="Contagem de instancias")
    args = parser.parse_args()

    return run_benchmark(
        mode=args.mode,
        reference_img=args.reference_img,
        candidate_img=args.candidate_img,
        output_metrics=args.output,
        instances=args.instances
    )

if __name__ == "__main__":
    sys.exit(main())
