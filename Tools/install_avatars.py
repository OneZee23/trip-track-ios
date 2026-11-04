#!/usr/bin/env python3
"""Installs TripTrack's avatar artwork into the asset catalog (the Android app ships the same images).

Usage: python3 Tools/install_avatars.py <dir with the 512 px masters named by code point, e.g. 1f60e.png>
Writes TripTrack/Resources/Assets.xcassets/Avatars/avatar_<code>.imageset at 256 px, one universal image: the
largest avatar (the profile's 48 pt glyph) is about 64 pt, 192 px on a 3x screen.
"""
import json
import pathlib
import sys
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'TripTrack/Resources/Assets.xcassets/Avatars'
CODES = ['1f60e', '1f642', '1f604', '1f920', '1f978', '1f9d4', '1f468_200d_1f9b3', '1f469', '1f469_200d_1f9b0',
         '1f471_200d_2640', '1f475', '1f436', '1f305', '1f3b8', '1f4f7', '1f3ae', '1f680', '1f699']

src = pathlib.Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}, 'properties': {'provides-namespace': True}}, indent=2) + '\n')
for code in CODES:
    folder = OUT / f'avatar_{code}.imageset'
    folder.mkdir(exist_ok=True)
    Image.open(src / f'{code}.png').convert('RGBA').resize((256, 256), Image.LANCZOS).save(folder / f'avatar_{code}.png', optimize=True)
    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': f'avatar_{code}.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1},
    }, indent=2) + '\n')
    print(folder.relative_to(ROOT))
