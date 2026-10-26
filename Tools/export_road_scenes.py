#!/usr/bin/env python3
"""Векторная дорога из утверждённых кадров «А · Живая дорога», 26.10.2026.

Эталон — итоговый frame.html: горизонтальная дорога, не ранний эскиз.
Запуск: python3 Tools/export_road_scenes.py
"""
from pathlib import Path
import json

DAY = '<svg class="road-scene" viewBox="0 0 408 211" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg"><rect width="408" height="211" fill="#74cad7"/><rect y="100" width="408" height="111" fill="#75a899"/><rect x="276" y="17" width="56" height="56" fill="#ffd070"/><path fill="#e7f7ef" d="M27 40h24V28h48v12h35v16H27zM181 18h46v11h35v16h-81z"/><path fill="#479388" d="M0 143V105h29v-11h49v17h31v-19h44v13h35V89h40v20h23V91h55v15h41V87h23v21h38v103H0z"/><path fill="#2e716a" d="M0 160v-23h31v12h32v-20h52v16h37v-13h58v20h43v-21h46v9h45v-13h64v84H0z"/><path fill="#be7f61" d="M0 178h408v33H0z"/><path fill="#e8ba7e" d="M0 183h408v8H0z"/><path fill="#516069" d="M0 192h408v19H0z"/><path fill="#e8d9a9" d="M0 202h42v3H0zm75 0h54v3H75zm82 0h54v3h-54zm82 0h54v3h-54zm83 0h36v3h-36z"/></svg>'
NIGHT = '<svg class="road-scene" viewBox="0 0 408 211" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg"><rect width="408" height="211" fill="#243450"/><rect x="287" y="29" width="38" height="38" fill="#e9d3a6"/><path fill="#9ab4bd" d="M29 34h4v4h-4zm76 16h4v4h-4zm85-26h4v4h-4zm164 16h4v4h-4zm-94 44h3v3h-3zM48 85h3v3h-3z"/><rect y="107" width="408" height="104" fill="#985a57"/><path fill="#3e5963" d="M0 149v-39h36v-19h38v19h36V91h44v16h43V93h31v17h44V88h39v21h39V94h58v117H0z"/><path fill="#243e4b" d="M0 164v-22h49v-14h40v18h51v-11h39v15h37v-17h47v16h42v-13h46v11h57v64H0z"/><path fill="#62434b" d="M0 182h408v29H0z"/><path fill="#c37a61" d="M0 184h408v6H0z"/><path fill="#35424a" d="M0 192h408v19H0z"/><path fill="#efc58e" d="M0 202h44v3H0zm80 0h48v3H80zm82 0h48v3h-48zm81 0h48v3h-48zm80 0h35v3h-35z"/></svg>'
PALETTES = {'dawn': {'#74cad7': '#f3bf9f', '#75a899': '#d7a291', '#ffd070': '#ffe4a0', '#e7f7ef': '#fff1d8', '#479388': '#a1848b', '#2e716a': '#637a7a'}, 'sunset': {'#74cad7': '#e87346', '#75a899': '#be6a5d', '#ffd070': '#ffd076', '#e7f7ef': '#f8c6a4', '#479388': '#86566b', '#2e716a': '#51475f'}}


def scene(time):
    art = NIGHT if time == "night" else DAY
    for before, after in PALETTES.get(time, {}).items():
        art = art.replace(before, after)
    return art.replace('class="road-scene"',
                       'width="408" height="211" shape-rendering="crispEdges"')


def main():
    root = Path(__file__).resolve().parents[1] / "TripTrack/Resources/Assets.xcassets/RoadScene"
    root.mkdir(exist_ok=True)
    info = {"author": "xcode", "version": 1}
    (root / "Contents.json").write_text(json.dumps({"info": info, "properties": {"provides-namespace": True}}, indent=2) + "\n")
    for time in ["dawn", "day", "sunset", "night"]:
        folder = root / (time + ".imageset")
        folder.mkdir(exist_ok=True)
        (folder / (time + ".svg")).write_text(scene(time) + "\n")
        contents = {"images": [{"filename": time + ".svg", "idiom": "universal"}],
                    "info": info, "properties": {"preserves-vector-representation": True}}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    main()
