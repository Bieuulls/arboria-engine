"""Convert a finished ARBORIA raw.csv slice to strict JSON metrics for the AEOC.

This does not infer image quality: visual_error must come from a separate real comparison.
"""
from __future__ import annotations
import argparse, csv, json, math, statistics
from pathlib import Path


def p95(values):
    values=sorted(values)
    return values[min(len(values)-1,max(0,math.ceil(0.95*len(values))-1))]


def derive(csv_path:Path, scenario:str, variant:str, instances:int, min_frames:int=1000):
    samples=[]
    with csv_path.open(encoding='utf-8-sig',newline='') as f:
        reader=csv.DictReader(f)
        for raw in reader:
            row={k.strip().strip('*'):v for k,v in raw.items() if k is not None}
            if row.get('scenario')==scenario and row.get('variant')==variant and int(row.get('instances','-1'))==instances:
                samples.append(row)
    if len(samples)<min_frames:raise ValueError(f'Apenas {len(samples)} frames; mínimo exigido: {min_frames}.')
    gpu=[float(r['gpu_render_ms']) for r in samples]
    frame=[float(r['frame_time_ms']) for r in samples]
    vram=[float(r['vram_mb']) for r in samples]
    if any(not math.isfinite(x) for x in gpu+frame+vram):raise ValueError('Dados não finitos.')
    # The original ARBORIA CSV often reports primitives=0 even when a draw was emitted.
    # This is NOT sufficient evidence of visible clusters. Fail closed until instrumented.
    vis_field=next((x for x in ('visible_clusters','clusters_visible','arboria_clusters_visible') if x in samples[0]),None)
    if vis_field is None:raise ValueError('CSV não contém contador customizado de clusters visíveis: não é prova de renderização.')
    visible=[float(r[vis_field]) for r in samples]
    if min(visible)<=0:raise ValueError('Algum frame reporta zero clusters visíveis.')
    return {'gpu_p95_ms':p95(gpu),'frame_p95_ms':p95(frame),
            'vram_mb':statistics.mean(vram),'visible_clusters':statistics.median(visible),
            'samples':len(samples)}


def main():
    a=argparse.ArgumentParser()
    a.add_argument('--csv',required=True)
    a.add_argument('--scenario',required=True)
    a.add_argument('--variant',required=True)
    a.add_argument('--instances',type=int,required=True)
    a.add_argument('--min-frames',type=int,default=1000)
    a.add_argument('--visual-error-json',required=True,help='JSON real: {"visual_error":numero} obtido por comparador de imagens')
    a.add_argument('--output',required=True)
    opts=a.parse_args()
    d=derive(Path(opts.csv),opts.scenario,opts.variant,opts.instances,opts.min_frames)
    visual=json.loads(Path(opts.visual_error_json).read_text(encoding='utf-8'))
    if not isinstance(visual.get('visual_error'),(int,float)) or not math.isfinite(visual['visual_error']):
        raise ValueError('Comparação visual ausente ou inválida.')
    d['visual_error']=float(visual['visual_error'])
    Path(opts.output).parent.mkdir(parents=True,exist_ok=True)
    Path(opts.output).write_text(json.dumps(d,indent=2),encoding='utf-8')

if __name__=='__main__':main()
