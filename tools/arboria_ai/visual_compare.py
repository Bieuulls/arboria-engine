"""Real PNG comparison for identical scene/camera/settings (not a semantic validator)."""
from __future__ import annotations
import argparse, json
from pathlib import Path


def compare_png(reference: Path, candidate: Path) -> dict:
    try:
        from PIL import Image, ImageChops, ImageStat
    except ImportError as ex:
        raise RuntimeError('Instale Pillow (`python -m pip install Pillow`) para comparação visual.') from ex
    if not reference.is_file() or not candidate.is_file():
        raise ValueError('Referência ou captura candidata ausente.')
    with Image.open(reference) as im1, Image.open(candidate) as im2:
        if im1.size != im2.size or im1.size[0]<=0:
            raise ValueError('Imagens com tamanhos diferentes; use a mesma resolução.')
        a,b=im1.convert('RGB'),im2.convert('RGB')
        delta=ImageChops.difference(a,b)
        means=ImageStat.Stat(delta).mean
        mae=sum(means)/3/255
        return {'visual_error':float(mae),'image_width':a.width,'image_height':a.height,
                'reference':str(reference.resolve()),'candidate':str(candidate.resolve())}


def main():
    parser=argparse.ArgumentParser(description='Comparar PNGs reais com mesma câmera/luz; saída visual_error = MAE RGB normalizado.')
    parser.add_argument('--reference',required=True)
    parser.add_argument('--candidate',required=True)
    parser.add_argument('--output',required=True)
    a=parser.parse_args()
    out=compare_png(Path(a.reference),Path(a.candidate))
    dst=Path(a.output);dst.parent.mkdir(parents=True,exist_ok=True)
    dst.write_text(json.dumps(out,indent=2),encoding='utf-8')
    print(json.dumps(out,ensure_ascii=False))

if __name__=='__main__':main()
