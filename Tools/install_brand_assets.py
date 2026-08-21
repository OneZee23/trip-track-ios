#!/usr/bin/env python3
"""Install brand-kit PNGs into the app's asset catalog at sensible sizes.

The kit is authored at 1254 px because that is what the image generator emits.
Nothing in the app draws these anywhere near that: the largest is an empty-state
illustration at ~140 pt, i.e. 420 px on a 3x screen. Shipping the masters as-is
would put ~20x more pixels in the bundle than any screen can show, twice over
once the Live Activity target gets its copy.

Downscaling uses LANCZOS rather than NEAREST on purpose. The masters are soft-
edged renders of pixel art, not true indexed sprites, so integer-factor nearest
is not available and nearest at a fractional factor produces uneven blocks —
some 3 px wide, some 4. LANCZOS keeps the block grid even; the app then draws
with `.interpolation(.none)`, which is where the crisp edges come from.
"""
import json, os, shutil, sys
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = "/Users/onezee/Desktop/Projects/3-TripTrack/Screenshots"
CATALOG = os.path.join(REPO, "TripTrack/Resources/Assets.xcassets")

# source stem -> (asset name, longest edge in px)
# Sizes are display size at 3x, rounded up to leave headroom for a layout change.
ASSETS = {
    # Achievement category headers, shown at ~40-56 pt -> 192 px covers 64 pt @3x
    "badge-distance":      ("badge_distance", 192),
    "badge-exploration":   ("badge_exploration", 192),
    "badge-special":       ("badge_special", 192),
    "badge-streaks":       ("badge_streaks", 192),
    "badge-exclusive":     ("badge_exclusive", 192),
    # Empty-state illustrations. Every call site pins width to 96 pt
    # (GarageView.swift:289, OnboardingView.swift:98), so 288 px is the real
    # requirement; 384 leaves a third spare for a larger layout.
    "empty-trips":         ("empty_trips", 384),
    "empty-map":           ("empty_map", 384),
    "empty-achievements":  ("empty_achievements", 384),
    "empty-notifications": ("empty_notifications", 384),
    "empty-garage":        ("empty_garage", 384),
    "empty-search":        ("empty_search", 384),
    # Onboarding heroes — also 96 pt in the current layout
    "onboard-track":       ("onboard_track", 384),
    "onboard-fog":         ("onboard_fog", 384),
    "onboard-memory":      ("onboard_memory", 384),
    # Map annotations, shown at ~24-32 pt
    "pin-start":           ("pin_start", 128),
    "pin-finish":          ("pin_finish", 128),
    # Second wave: the states that were still wearing system glyphs
    "empty-data":          ("empty_data", 384),
    "empty-offline":       ("empty_offline", 384),
    "error-generic":       ("error_generic", 384),
    "success-sent":        ("success_sent", 384),
    "empty-followers":     ("empty_followers", 384),
    "empty-companions":    ("empty_companions", 384),
    "empty-roads":         ("empty_roads", 384),
    "empty-photos":        ("empty_photos", 384),
    "badge-locked":        ("badge_locked", 384),
    "onboard-notify":      ("onboard_notify", 384),
    # Club marks, shown at 44 pt in the catalogue and 84 pt on the detail
    "club-miata":          ("club_miata", 256),
    "club-vag":            ("club_vag", 256),
    "club-trucking":       ("club_trucking", 256),
    "club-offroad":        ("club_offroad", 256),
    "club-subaru":         ("club_subaru", 256),
}

CONTENTS = {
    "images": [
        {"filename": None, "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def install(stem, name, longest, catalog=CATALOG, kit=KIT, force=False):
    src = os.path.join(kit, f"{stem}.png")
    if not os.path.exists(src):
        return f"SKIP {stem}: not in kit"
    imageset = os.path.join(catalog, f"{name}.imageset")
    png = os.path.join(imageset, f"{name}.png")
    if os.path.exists(png) and not force:
        return f"SKIP {name}: already installed (use --force)"
    os.makedirs(imageset, exist_ok=True)
    im = Image.open(src).convert("RGBA")
    if max(im.size) > longest:
        im.thumbnail((longest, longest), Image.LANCZOS)
    im.save(png, optimize=True)
    c = json.loads(json.dumps(CONTENTS))
    c["images"][0]["filename"] = f"{name}.png"
    with open(os.path.join(imageset, "Contents.json"), "w") as f:
        json.dump(c, f, indent=2)
        f.write("\n")
    return f"ok   {name}  {im.size[0]}x{im.size[1]}  {os.path.getsize(png)//1024} KB"


if __name__ == "__main__":
    force = "--force" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("-")]
    total = 0
    for stem, (name, longest) in ASSETS.items():
        if only and stem not in only and name not in only:
            continue
        line = install(stem, name, longest, force=force)
        print(line)
        p = os.path.join(CATALOG, f"{name}.imageset", f"{name}.png")
        if os.path.exists(p):
            total += os.path.getsize(p)
    print(f"\ntotal installed payload: {total//1024} KB")
