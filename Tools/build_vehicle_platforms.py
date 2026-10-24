#!/usr/bin/env python3
"""Deterministic isometric pixel platforms. Art pixels are enlarged 2x nearest."""
import json
from pathlib import Path
import numpy as np
from PIL import Image

CATALOG = Path(__file__).resolve().parents[1] / 'TripTrack/Resources/Assets.xcassets'
W, H, SIDE = 170, 85, 7


def tile(kind):
    rng = np.random.default_rng(7)
    im = np.zeros((H + SIDE, W, 4), dtype=np.uint8)
    for y in range(H):
        half = (y + .5) * 2 if y < H / 2 else (H - y - .5) * 2
        lo, hi = int(round(W / 2 - half)), int(round(W / 2 + half))
        for x in range(max(0, lo), min(W, hi)):
            noise = int(rng.integers(-6, 7))
            base = (58, 62, 70)
            if kind == 'carbon':
                base = (29, 32, 38) if (x // 2 + y // 2) % 2 else (43, 47, 54)
            elif kind in ('gold', 'neon'): base = (34, 36, 44)
            elif kind == 'chrome': base = (155 + (y % 3) * 8,) * 3
            elif kind == 'matte': base = (150, 148, 141)
            elif kind == 'camo':
                base = [(63, 73, 49), (85, 94, 61), (45, 55, 40)][(x // 8 + y // 5) % 3]
            elif kind == 'sunset': base = (89, 66, 72)
            im[y, x] = (*[max(0, min(255, n + noise)) for n in base], 255)
            if x in (lo, lo + 1, hi - 2, hi - 1):
                if kind == 'gold': im[y, x] = (214, 170, 72, 255)
                elif kind == 'neon': im[y, x] = (71, 223, 204, 255)
    for x in range(W):
        edge = int(H - abs(x - W / 2) / 2)
        for k in range(SIDE):
            if edge + k < H + SIDE:
                im[edge + k, x] = (*( (40, 43, 50) if x < W / 2 else (50, 54, 62)), 255)
    if kind == 'racing':
        for x in range(W // 2):
            y = int(H / 2 - x / 2)
            for d in range(3):
                if im[y + d, x, 3]:
                    im[y + d, x] = (*( (214, 52, 44) if (x // 4) % 2 == 0 else (240, 238, 232)), 255)
    if kind == 'matte':
        for offset in range(-int(W * .32), int(W * .32)):
            x, y = int(W / 2 + offset), int(H / 2 + offset / 2)
            for d in range(2):
                if im[y + d, x, 3]: im[y + d, x] = (232, 188, 46, 255)
    return Image.fromarray(im, 'RGBA').resize((W * 2, (H + SIDE) * 2), Image.Resampling.NEAREST)


def install(name, image):
    folder = CATALOG / f'{name}.imageset'
    folder.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2, 3):
        filename = f'{name}@{scale}x.png'
        image.resize((image.width * scale, image.height * scale), Image.Resampling.NEAREST).save(folder / filename, optimize=True)
        images.append({'idiom': 'universal', 'scale': f'{scale}x', 'filename': filename})
    (folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')


if __name__ == '__main__':
    for kind in ['asphalt', 'carbon', 'gold', 'neon', 'racing', 'chrome', 'matte', 'camo', 'sunset']:
        install(f'platform_{kind}', tile(kind))
    shadow = np.zeros((46, 92, 4), dtype=np.uint8)
    for y in range(46):
        half = min(y + 1, 46 - y) * 2
        shadow[y, max(0, 46 - half):min(92, 46 + half)] = (10, 12, 18, 70)
    install('platform_shadow', Image.fromarray(shadow, 'RGBA').resize((184, 92), Image.Resampling.NEAREST))
