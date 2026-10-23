#!/usr/bin/env python3
"""
ARBORIA ENGINE — GATE: VALIDATE IMAGES (tools/gates/validate_images.py)
Valida capturas de renderização: existência, integridade, ausência de frames pretos/corrompidos.
"""

import sys
import os
import argparse
from PIL import Image
import numpy as np

def validate_image(image_path: str, min_non_black_ratio: float = 0.01) -> bool:
    if not os.path.exists(image_path):
        print(f"[FAIL] Imagem não encontrada: {image_path}", file=sys.stderr)
        return False

    try:
        with Image.open(image_path) as img:
            w, h = img.size
            if w <= 0 or h <= 0:
                print(f"[FAIL] Dimensões inválidas ({w}x{h}): {image_path}", file=sys.stderr)
                return False

            arr = np.array(img.convert("RGB"))
            luminance = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
            non_black = np.count_nonzero(luminance > 5.0)
            ratio = non_black / (w * h)

            print(f"[VALIDATE IMAGE] {os.path.basename(image_path)}: {w}x{h}, pixels não-pretos: {ratio*100:.2f}%, luminância média: {np.mean(luminance):.2f}")

            if ratio < min_non_black_ratio:
                print(f"[FAIL] Imagem quase totalmente preta/vazia ({ratio*100:.2f}% < {min_non_black_ratio*100:.2f}%)", file=sys.stderr)
                return False

            return True
    except Exception as e:
        print(f"[FAIL] Erro ao abrir/processar {image_path}: {e}", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(description="Validação de imagens de renderização para gates")
    parser.add_argument("images", nargs="+", help="Caminho para uma ou mais imagens PNG/JPG")
    parser.add_argument("--min-ratio", type=float, default=0.01, help="Razão mínima de pixels visíveis não-pretos")
    args = parser.parse_args()

    all_passed = True
    for img_path in args.images:
        if not validate_image(img_path, args.min_ratio):
            all_passed = False

    sys.exit(0 if all_passed else 1)

if __name__ == "__main__":
    main()
