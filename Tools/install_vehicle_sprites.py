#!/usr/bin/env python3
"""Install the style x colour vehicle matrix into both asset catalogs.

Both, not one: the Live Activity is a separate target with its own catalog, and
a sprite present in the app but missing from the extension shows up as a blank
avatar on the Lock Screen and nowhere else — the quietest kind of bug there is.
`VehicleAvatarCatalogTests` fails the build when the two drift, and this script
is the thing that keeps them from drifting in the first place.
"""
import glob, json, os, shutil, sys
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = [
    os.path.join(REPO, "TripTrack/Resources/Assets.xcassets"),
    os.path.join(REPO, "TripTrackLiveActivity/Assets.xcassets"),
]
# Largest render is the vehicle-detail hero at 64 pt; 256 px covers it at 3x
# with room for a bigger layout without shipping 1254 px of unseen detail.
LONGEST = 256

CONTENTS = {
    "images": [
        {"filename": None, "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def install(src, catalogs=CATALOGS, longest=LONGEST):
    name = os.path.splitext(os.path.basename(src))[0]
    im = Image.open(src).convert("RGBA")
    if max(im.size) > longest:
        im.thumbnail((longest, longest), Image.LANCZOS)
    written = 0
    for catalog in catalogs:
        imageset = os.path.join(catalog, f"{name}.imageset")
        os.makedirs(imageset, exist_ok=True)
        png = os.path.join(imageset, f"{name}.png")
        im.save(png, optimize=True)
        c = json.loads(json.dumps(CONTENTS))
        c["images"][0]["filename"] = f"{name}.png"
        with open(os.path.join(imageset, "Contents.json"), "w") as f:
            json.dump(c, f, indent=2)
            f.write("\n")
        written += os.path.getsize(png)
    return name, im.size, written


def prune(keep, catalogs=CATALOGS):
    """Remove pixel_* imagesets no longer in the matrix, so a silhouette that
    was dropped does not linger as dead weight in two targets."""
    removed = []
    for catalog in catalogs:
        for d in glob.glob(os.path.join(catalog, "pixel_*.imageset")):
            n = os.path.basename(d)[: -len(".imageset")]
            if n not in keep:
                shutil.rmtree(d)
                removed.append(n)
    return sorted(set(removed))


if __name__ == "__main__":
    srcdir = sys.argv[1]
    srcs = sorted(glob.glob(os.path.join(srcdir, "pixel_*.png")))
    if not srcs:
        sys.exit(f"no pixel_*.png in {srcdir}")
    keep, total = set(), 0
    for s in srcs:
        name, size, written = install(s)
        keep.add(name)
        total += written
    # Prune only on an explicit flag. Pruning by default deletes every sprite
    # that is not in the batch being installed — which is correct when the
    # batch IS the whole matrix and destructive the moment somebody installs
    # one style on its own, as happened the first time this ran.
    gone = prune(keep) if "--prune" in sys.argv else []
    print(f"installed {len(keep)} sprites x 2 catalogs at {LONGEST} px — {total//1024} KB total")
    if gone:
        print(f"pruned {len(gone)}: {', '.join(gone)}")
