#!/usr/bin/env python3
"""Render the authored D2 app icon and its iOS appearances.

Run: python3 Tools/build_app_icons.py
Requires Google Chrome (or --chrome /path/to/chromium) and Pillow.
The source SVGs are local; rendering never loads remote resources.
"""

import argparse
import json
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "Tools/AppIcon"
CATALOG = REPO / "TripTrack/Resources/Assets.xcassets"
LIVE_CATALOG = REPO / "TripTrackLiveActivity/Assets.xcassets"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def artwork(filename, dev=False):
    root = ET.parse(SOURCE / filename).getroot()
    root.attrib = {"viewBox": "0 0 1024 1024", "width": "2048", "height": "2048"}
    definitions, scene, outer_border = list(root)

    # The board previews iOS's rounded mask and edge lighting. The asset must
    # fill the square; iOS owns that mask and renders its own edge treatment.
    definitions.remove(definitions.find(f"{{{SVG}}}clipPath"))
    definitions.remove(definitions.find(f"{{{SVG}}}linearGradient"))
    scene.attrib.clear()
    scene.remove(list(scene)[-1])
    root.remove(outer_border)

    if dev:
        # Vector lettering stays legible at Home Screen size and doesn't depend
        # on fonts installed on the machine running this script.
        badge = ET.fromstring(f'''<g xmlns="{SVG}" transform="translate(312 102)">
          <rect width="400" height="166" rx="46" fill="#C8472D"/>
          <g fill="none" stroke="#FFFFFF" stroke-width="17" stroke-linejoin="round" stroke-linecap="square">
            <path d="M65 46 V120 H91 C136 120 136 46 91 46 Z"/>
            <path d="M216 46 H158 V120 H216 M158 83 H205"/>
            <path d="M254 46 L287 120 H294 L327 46"/>
          </g>
        </g>''')
        root.append(badge)
    return ET.tostring(root, encoding="unicode")


def render(chrome, svg, destination, work):
    html = work / "icon.html"
    html.write_text(
        '<!doctype html><meta charset="utf-8">'
        '<style>html,body{margin:0;width:2048px;height:2048px;overflow:hidden}'
        'svg{display:block}</style>' + svg
    )
    screenshot = work / "render.png"
    subprocess.run(
        [str(chrome), "--headless", "--disable-gpu", "--hide-scrollbars",
         "--no-first-run", "--no-default-browser-check", "--disable-background-networking",
         "--force-device-scale-factor=1", "--window-size=2048,2048",
         f"--user-data-dir={work / 'chrome-profile'}", f"--screenshot={screenshot}", html.as_uri()],
        check=True, capture_output=True, timeout=60,
    )
    with Image.open(screenshot) as rendered:
        image = rendered.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
    # The blue design is a preview of a user-selected tint. iOS expects a
    # grayscale master and applies the user's tint itself.
    if "Tinted" in destination.name:
        image = image.convert("L")
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)
    print(f"{destination.relative_to(REPO)} ({image.width} × {image.height}, {image.mode})")


def write_contents(path, entries):
    path.write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chrome", type=Path)
    args = parser.parse_args()
    cache = Path.home() / "Library/Caches/ms-playwright"
    cached = sorted(cache.glob(
        "chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell"
    ), reverse=True) + sorted(cache.glob(
        "chromium-*/chrome-mac-*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
    ), reverse=True)
    chrome = args.chrome or next(iter(cached), Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    if not chrome.is_file():
        parser.error("Chrome not found; pass --chrome /path/to/chromium")

    appearances = [("", "D2.svg", None), ("Dark", "D-dark.svg", "dark"),
                   ("Tinted", "D-tinted-preview.svg", "tinted")]
    with tempfile.TemporaryDirectory(prefix="triptrack-app-icon-") as temp:
        for name, dev in [("AppIcon", False), ("AppIconDev", True)]:
            directory = CATALOG / f"{name}.appiconset"
            entries = []
            for suffix, source, appearance in appearances:
                filename = f"{name}{suffix}.png"
                render(chrome, artwork(source, dev), directory / filename, Path(temp))
                entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
                if appearance:
                    entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
                entries.append(entry)
            write_contents(directory / "Contents.json", entries)

    # The Live Activity shows this at 28–40 pt. 120 px covers the 3× display
    # without duplicating a full 1024 px App Store image in the extension.
    directory = LIVE_CATALOG / "app_icon.imageset"
    entries = []
    for suffix, _, appearance in appearances[:2]:
        filename = f"app_icon{'_dark' if suffix else ''}.png"
        with Image.open(CATALOG / "AppIcon.appiconset" / f"AppIcon{suffix}.png") as icon:
            icon.resize((120, 120), Image.Resampling.LANCZOS).save(directory / filename, optimize=True)
        entry = {"filename": filename, "idiom": "universal"}
        if appearance:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        entries.append(entry)
    write_contents(directory / "Contents.json", entries)


if __name__ == "__main__":
    main()
