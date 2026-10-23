"""Evidence-based benchmarking: no zero geometry or missing metric may pass."""
from __future__ import annotations
import json, math, statistics
from pathlib import Path

REQUIRED = ('gpu_p95_ms','frame_p95_ms','vram_mb','visible_clusters','visual_error')


def checked_metrics(path: Path, required=REQUIRED) -> dict:
    if not path.is_file():
        raise ValueError('Benchmark não gerou o arquivo JSON de métricas: '+str(path))
    m=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(m, dict): raise ValueError('Métricas precisam ser objeto JSON.')
    for name in required:
        x=m.get(name)
        if not isinstance(x, (int,float)) or isinstance(x,bool) or not math.isfinite(x):
            raise ValueError('Métrica ausente ou inválida: '+name)
    if m['gpu_p95_ms'] <= 0 or m['frame_p95_ms'] <= 0 or m['vram_mb'] <= 0:
        raise ValueError('Tempos GPU/frame e memória devem ser positivos.')
    if m['visible_clusters'] <= 0:
        raise ValueError('CENA INVÁLIDA: zero clusters visíveis; não há evidência de desenho.')
    if m['visual_error'] < 0: raise ValueError('Erro visual negativo.')
    return {k:float(v) for k,v in m.items() if isinstance(v,(int,float)) and not isinstance(v,bool) and math.isfinite(v)}


def aggregate(samples: list[dict]) -> dict:
    if not samples: raise ValueError('Sem amostras de benchmark.')
    keys=set(samples[0]);
    if any(set(x)!=keys for x in samples): raise ValueError('Métricas inconsistentes entre repetições.')
    return {k:statistics.median(s[k] for s in samples) for k in sorted(keys)}


def compare(base: dict, candidate: dict, cfg: dict) -> tuple[bool,list[str]]:
    notes=[]
    metric=cfg.get('primary_metric','gpu_p95_ms')
    if metric not in base or metric not in candidate: return False,['Métrica principal ausente: '+metric]
    before,after=base[metric],candidate[metric]
    if before <= 0: return False,['Baseline inválida.']
    gain_pct=100*(before-after)/before
    min_gain=cfg.get('min_gain_pct',3.0)
    notes.append(f'Ganho {metric}: {gain_pct:.2f}% (mínimo {min_gain:.2f}%)')
    if gain_pct < min_gain: notes.append('Ganho insuficiente ou regressão.')
    max_reg=cfg.get('max_regression_pct',2.0)
    for name in ('frame_p95_ms','gpu_p95_ms','vram_mb'):
        if name in (metric,):continue
        if candidate[name]>base[name]*(1+max_reg/100):
            notes.append(f'Regressão em {name}: {candidate[name]:.4f} vs {base[name]:.4f}')
    # Fewer visible clusters are EXPECTED when optimizing culling or LOD.
    # Geometry correctness is guarded by the independent, required visual_error.
    # Strict parity may be enabled only in geometry-identical scenarios.
    if cfg.get('require_cluster_count_parity',False):
        tol=cfg.get('cluster_count_tolerance_pct',0.5)
        if abs(candidate['visible_clusters']-base['visible_clusters']) > base['visible_clusters']*tol/100:
            notes.append('Contagem de clusters divergiu além da tolerância de paridade.')
    visual_limit=cfg.get('max_visual_error',0.01)
    if candidate['visual_error'] > visual_limit:
        notes.append(f'Erro visual acima do limite: {candidate["visual_error"]:.6f} > {visual_limit}')
    if candidate['visual_error'] > base['visual_error']+cfg.get('max_visual_error_increase',0.005):
        notes.append('Diferença visual piorou versus baseline.')
    passed= (gain_pct>=min_gain and len(notes)==1)
    return passed,notes
