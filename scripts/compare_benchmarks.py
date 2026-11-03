#!/usr/bin/env python3
"""ARBORIA ENGINE — CI Benchmark Regression Comparator.

Compara BENCHMARK_RESULTS.csv de uma execução CI contra o baseline
armazenado e falha quando qualquer métrica excede o threshold de regressão.

Uso:
    python scripts/compare_benchmarks.py \
        --baseline validation/final_certification/BENCHMARK_RESULTS.csv \
        --current benchmark_results_pr.csv \
        --threshold 10 \
        --output benchmark_diff.json
"""

import argparse
import csv
import json
import sys
from typing import Dict, List, Tuple


# Chave de indexação: (Build, Cenario)
BenchmarkKey = Tuple[str, str]


def load_benchmarks(path: str) -> Dict[BenchmarkKey, dict]:
    """Carrega BENCHMARK_RESULTS.csv e indexa por (Build, Cenario)."""
    results: Dict[BenchmarkKey, dict] = {}
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["Build"], row["Cenario"])
            results[key] = row
    return results


def _pct_change(base_val: float, curr_val: float) -> float:
    if base_val <= 0:
        return 0.0
    return ((curr_val - base_val) / base_val) * 100.0


def compare(
    baseline: Dict[BenchmarkKey, dict],
    current: Dict[BenchmarkKey, dict],
    threshold_pct: float = 10.0,
) -> Tuple[bool, List[dict], List[dict]]:
    """Compara current vs baseline.

    Retorna (tem_regressao, todos_os_diffs, regressoes).
    """
    regressions: List[dict] = []
    diffs: List[dict] = []

    metrics = ["Edit CPU (ms)", "DAG Upd (ms)", "Upload (ms)", "Frame p95 (ms)"]

    for key, curr_row in current.items():
        if key not in baseline:
            diffs.append({
                "build": key[0],
                "cenario": key[1],
                "status": "NOVO",
                "metric": "n/a",
                "baseline": "n/a",
                "current": "n/a",
                "pct_change": "n/a",
            })
            continue

        base_row = baseline[key]

        for metric in metrics:
            try:
                base_val = float(base_row[metric])
                curr_val = float(curr_row[metric])
            except (ValueError, KeyError):
                # Métrica projetada (ex.: Cenario F marcado PROJETADO) — ignora comparação.
                continue

            pct_change = _pct_change(base_val, curr_val)

            diffs.append({
                "build": key[0],
                "cenario": key[1],
                "metric": metric,
                "baseline": base_val,
                "current": curr_val,
                "pct_change": round(pct_change, 2),
            })

            if pct_change > threshold_pct:
                regressions.append({
                    "build": key[0],
                    "cenario": key[1],
                    "metric": metric,
                    "baseline": base_val,
                    "current": curr_val,
                    "pct_change": round(pct_change, 2),
                    "threshold": threshold_pct,
                })

    return len(regressions) > 0, diffs, regressions


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compara benchmarks de CI contra baseline e detecta regressões."
    )
    parser.add_argument("--baseline", required=True, help="Caminho do baseline CSV")
    parser.add_argument("--current", required=True, help="Caminho do CSV da execução atual")
    parser.add_argument(
        "--threshold", type=float, default=10.0, help="Threshold de regressão em %%"
    )
    parser.add_argument("--output", default="benchmark_diff.json", help="Arquivo JSON de saída")
    args = parser.parse_args()

    baseline = load_benchmarks(args.baseline)
    current = load_benchmarks(args.current)

    has_regression, diffs, regressions = compare(baseline, current, args.threshold)

    output = {
        "has_regression": has_regression,
        "threshold_pct": args.threshold,
        "regression_count": len(regressions),
        "regressions": regressions,
        "all_diffs": diffs,
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    if has_regression:
        print(f"\nREGRESSÕES DE BENCHMARK DETECTADAS ({len(regressions)}):")
        for r in regressions:
            print(
                f"  {r['build']}/{r['cenario']} {r['metric']}: "
                f"{r['baseline']} -> {r['current']} "
                f"({r['pct_change']}% > {r['threshold']}%)"
            )
        print("\nCI falhou por regressão de performance.")
        return 1

    print("\nSem regressões de benchmark detectadas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
