#!/usr/bin/env python3
"""Sit a set of vehicle sprites on one ground line at one scale.

Generated sprites arrive each centred in its own 1254 px square, which hides a
real problem: a hatchback that is genuinely shorter and a van that is genuinely
taller end up the same size on screen the moment anything scales them to fit a
tile. The proportions that make the silhouettes tell each other apart are
exactly what per-sprite fitting destroys.

So the set is placed rather than fitted: every sprite is cropped to its own
subject, scaled by ONE shared factor, and pinned to a common baseline on a
common canvas. After this a van IS taller than a hatchback in the asset itself,
and any view can size them all with the same frame without thinking about it.
"""
import argparse, os
import numpy as np
from PIL import Image

def bbox(im):
    a = np.array(im)
    ys, xs = np.where(a[:, :, 3] > 16)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sources", nargs="+", help="PNG files, transparent background")
    ap.add_argument("-o", "--outdir", required=True)
    ap.add_argument("--canvas", type=int, default=1254)
    # How much of the canvas width the WIDEST vehicle in the set may take. The
    # rest is breathing room, and it is shared — a later sprite that is wider
    # than everything here would need the whole set re-run, which is why the
    # set is normalised together rather than one at a time.
    ap.add_argument("--fill", type=float, default=0.92)
    # Baseline as a fraction of canvas height. Slightly below centre so a tall
    # van has headroom without a low sports car looking like it is falling.
    ap.add_argument("--baseline", type=float, default=0.78)
    a = ap.parse_args()

    ims, boxes = [], []
    for p in a.sources:
        im = Image.open(p).convert("RGBA")
        ims.append(im)
        boxes.append(bbox(im))

    widest = max(x1 - x0 for x0, _, x1, _ in boxes)
    scale = (a.canvas * a.fill) / widest

    os.makedirs(a.outdir, exist_ok=True)
    for p, im, (x0, y0, x1, y1) in zip(a.sources, ims, boxes):
        crop = im.crop((x0, y0, x1, y1))
        w = max(1, round(crop.width * scale))
        h = max(1, round(crop.height * scale))
        crop = crop.resize((w, h), Image.LANCZOS)
        out = Image.new("RGBA", (a.canvas, a.canvas), (0, 0, 0, 0))
        out.paste(crop, ((a.canvas - w) // 2, round(a.canvas * a.baseline) - h), crop)
        dst = os.path.join(a.outdir, os.path.basename(p))
        out.save(dst)
        print(f"{os.path.basename(p):24s} {w}x{h}  scale {scale:.3f}")

if __name__ == "__main__":
    main()
