#!/usr/bin/env python3
"""Recolour a vehicle sprite's bodywork without touching glass, wheels or lights.

Colour variants are the part of a vehicle-avatar set that must never cost an
art order. Hue-rotating the master cannot produce white or black — both have no
hue to rotate — so every variant here is an AUTHORED three-stop ramp
(shade / base / highlight) that the master's own shading is mapped onto. The
silhouette therefore stays pixel-identical across the whole set, which is the
one thing a generated set can never promise.

The mask is a hue gate, and it works only because the master keeps its body
(~30-37 deg) well clear of its glass (~188-190 deg). Run --inspect on any new
master before trusting it.
"""
import argparse, colorsys, json, os, sys
import numpy as np
from PIL import Image

# Ordered by real-world fleet frequency, which is also the order the picker
# should show them in. Each ramp is (shade, base, highlight).
RAMPS = {
    "white":  ((0xC6, 0xC9, 0xD1), (0xEB, 0xED, 0xF2), (0xFF, 0xFF, 0xFF)),
    "black":  ((0x17, 0x18, 0x1D), (0x2A, 0x2C, 0x33), (0x45, 0x48, 0x52)),
    "silver": ((0x84, 0x88, 0x91), (0xB6, 0xBA, 0xC2), (0xE6, 0xE8, 0xEC)),
    "gray":   ((0x4A, 0x4E, 0x57), (0x70, 0x75, 0x80), (0x9A, 0x9F, 0xAA)),
    "red":    ((0x8E, 0x1F, 0x18), (0xE0, 0x3B, 0x2C), (0xF2, 0x6E, 0x5C)),
    "blue":   ((0x1E, 0x44, 0x7A), (0x3B, 0x7D, 0xD8), (0x6F, 0xA8, 0xF0)),
    "orange": ((0x9A, 0x5A, 0x0C), (0xF5, 0x9E, 0x19), (0xFF, 0xC4, 0x6B)),
    "yellow": ((0xA8, 0x82, 0x08), (0xF2, 0xC4, 0x1B), (0xFF, 0xE6, 0x7A)),
    "green":  ((0x2A, 0x6B, 0x2E), (0x4C, 0xAF, 0x50), (0x86, 0xD9, 0x8A)),
}

# Body hue window in degrees, plus the saturation floor that separates paint
# from the near-neutral chrome, glass reflections and tyre highlights.
HUE_LO, HUE_HI = 12.0, 58.0
SAT_FLOOR = 0.30
VAL_FLOOR = 0.12


def to_hsv(rgb: np.ndarray):
    """Vectorised RGB->HSV. rgb float 0..1, returns h in degrees."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-9
    rm, gm, bm = (mx == r) & m, (mx == g) & m, (mx == b) & m
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = ((b - r)[gm] / d[gm]) + 2
    h[bm] = ((r - g)[bm] / d[bm]) + 4
    h *= 60.0
    s = np.where(mx > 1e-9, d / np.maximum(mx, 1e-9), 0.0)
    return h, s, mx


def body_mask(arr: np.ndarray):
    rgb = arr[..., :3].astype(np.float32) / 255.0
    alpha = arr[..., 3]
    h, s, v = to_hsv(rgb)
    return (alpha > 0) & (h >= HUE_LO) & (h <= HUE_HI) & (s >= SAT_FLOOR) & (v >= VAL_FLOOR), v


def ramp_lookup(ramp, t: np.ndarray) -> np.ndarray:
    """Piecewise-linear shade->base->highlight over t in 0..1."""
    shade, base, high = (np.array(c, dtype=np.float32) for c in ramp)
    out = np.empty(t.shape + (3,), dtype=np.float32)
    lo = t < 0.5
    a = (t[lo] / 0.5)[:, None]
    out[lo] = shade * (1 - a) + base * a
    hi = ~lo
    b = ((t[hi] - 0.5) / 0.5)[:, None]
    out[hi] = base * (1 - b) + high * b
    return out


def recolor(src: Image.Image, ramp) -> Image.Image:
    arr = np.array(src.convert("RGBA"))
    mask, v = body_mask(arr)
    if not mask.any():
        raise SystemExit("body mask is empty — the hue window does not fit this master")
    vals = v[mask]
    # Normalise against the body's own range, not 0..1, so a master painted in a
    # narrow band still uses the full ramp.
    lo, hi = np.percentile(vals, 2), np.percentile(vals, 98)
    t = np.clip((vals - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    out = arr.copy()
    out[mask, :3] = np.rint(ramp_lookup(ramp, t)).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def inspect(src: Image.Image):
    arr = np.array(src.convert("RGBA"))
    mask, _ = body_mask(arr)
    alpha = arr[..., 3]
    total = int((alpha > 0).sum())
    print(f"opaque px      : {total}")
    print(f"body px        : {int(mask.sum())}  ({100*mask.sum()/max(total,1):.1f}% of subject)")
    print(f"alpha levels   : {len(np.unique(alpha))} (2 = clean binary edge)")
    rgb = arr[..., :3].astype(np.float32) / 255.0
    h, s, _ = to_hsv(rgb)
    painted = (alpha > 0) & (s >= SAT_FLOOR)
    if painted.any():
        hs = h[painted]
        inside = ((hs >= HUE_LO) & (hs <= HUE_HI)).mean()
        print(f"saturated px inside body hue window: {100*inside:.1f}%")
        outside = hs[(hs < HUE_LO) | (hs > HUE_HI)]
        if len(outside):
            print(f"other saturated hues (glass etc.): {np.percentile(outside,[5,50,95]).round(0)} deg")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("master")
    ap.add_argument("-o", "--outdir", default=".")
    ap.add_argument("-p", "--prefix", default="pixel_car")
    ap.add_argument("--only", nargs="*", help="subset of colour names")
    ap.add_argument("--inspect", action="store_true")
    a = ap.parse_args()

    src = Image.open(a.master)
    if a.inspect:
        inspect(src)
        return

    os.makedirs(a.outdir, exist_ok=True)
    names = a.only or list(RAMPS)
    for name in names:
        if name not in RAMPS:
            sys.exit(f"unknown colour {name}; known: {', '.join(RAMPS)}")
        dst = os.path.join(a.outdir, f"{a.prefix}_{name}.png")
        recolor(src, RAMPS[name]).save(dst)
        print(f"wrote {dst}")


if __name__ == "__main__":
    main()
