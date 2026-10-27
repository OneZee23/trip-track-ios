#!/usr/bin/env python3
"""Векторная дорога «Живая дорога», сцены в редакции 27.10.2026.

Первая редакция (26.10, кадры «А · Живая дорога») заменена после разбора
на TestFlight 98: ночью квадратная луна была ярче машины, а кромка дороги
и небо заката почти совпадали по оттенку с акцентом. Теперь полумесяц и
ступенчатое солнце в правом верхнем углу, кромка нейтральная, закат —
сиреневые сумерки. Остальное (силуэты, дорога, разметка) прежнее.
Запуск: python3 Tools/export_road_scenes.py
"""
from pathlib import Path
import json

SCENES = {
    'dawn': '<svg xmlns="http://www.w3.org/2000/svg" width="408" height="211" shape-rendering="crispEdges" viewBox="0 0 408 211" preserveAspectRatio="none"><rect width="408" height="211" fill="#f3bf9f" /><rect y="100" width="408" height="111" fill="#d7a291" /><path fill="#ffe4a0" d="M364 17h10v2h-10zM360 19h18v2h-18zM356 21h26v2h-26zM356 23h26v2h-26zM354 25h30v2h-30zM354 27h30v2h-30zM352 29h34v2h-34zM352 31h34v2h-34zM352 33h34v2h-34zM352 35h34v2h-34zM352 37h34v2h-34zM354 39h30v2h-30zM354 41h30v2h-30zM356 43h26v2h-26zM356 45h26v2h-26zM360 47h18v2h-18zM364 49h10v2h-10z" /><path fill="#fff1d8" d="M27 40h24V28h48v12h35v16H27zM181 18h46v11h35v16h-81z" /><path fill="#a1848b" d="M0 143V105h29v-11h49v17h31v-19h44v13h35V89h40v20h23V91h55v15h41V87h23v21h38v103H0z" /><path fill="#637a7a" d="M0 160v-23h31v12h32v-20h52v16h37v-13h58v20h43v-21h46v9h45v-13h64v84H0z" /><path fill="#a08672" d="M0 178h408v33H0z" /><path fill="#e8ba7e" d="M0 183h408v8H0z" /><path fill="#516069" d="M0 192h408v19H0z" /><path fill="#e8d9a9" d="M0 202h42v3H0zm75 0h54v3H75zm82 0h54v3h-54zm82 0h54v3h-54zm83 0h36v3h-36z" /></svg>',
    'day': '<svg xmlns="http://www.w3.org/2000/svg" width="408" height="211" shape-rendering="crispEdges" viewBox="0 0 408 211" preserveAspectRatio="none"><rect width="408" height="211" fill="#74cad7" /><rect y="100" width="408" height="111" fill="#75a899" /><path fill="#ffd070" d="M364 17h10v2h-10zM360 19h18v2h-18zM356 21h26v2h-26zM356 23h26v2h-26zM354 25h30v2h-30zM354 27h30v2h-30zM352 29h34v2h-34zM352 31h34v2h-34zM352 33h34v2h-34zM352 35h34v2h-34zM352 37h34v2h-34zM354 39h30v2h-30zM354 41h30v2h-30zM356 43h26v2h-26zM356 45h26v2h-26zM360 47h18v2h-18zM364 49h10v2h-10z" /><path fill="#e7f7ef" d="M27 40h24V28h48v12h35v16H27zM181 18h46v11h35v16h-81z" /><path fill="#479388" d="M0 143V105h29v-11h49v17h31v-19h44v13h35V89h40v20h23V91h55v15h41V87h23v21h38v103H0z" /><path fill="#2e716a" d="M0 160v-23h31v12h32v-20h52v16h37v-13h58v20h43v-21h46v9h45v-13h64v84H0z" /><path fill="#a08672" d="M0 178h408v33H0z" /><path fill="#e8ba7e" d="M0 183h408v8H0z" /><path fill="#516069" d="M0 192h408v19H0z" /><path fill="#e8d9a9" d="M0 202h42v3H0zm75 0h54v3H75zm82 0h54v3h-54zm82 0h54v3h-54zm83 0h36v3h-36z" /></svg>',
    'sunset': '<svg xmlns="http://www.w3.org/2000/svg" width="408" height="211" shape-rendering="crispEdges" viewBox="0 0 408 211" preserveAspectRatio="none"><rect y="0" width="408" height="40" fill="#5b4373" /><rect y="40" width="408" height="22" fill="#7a4f80" /><rect y="62" width="408" height="18" fill="#b9677f" /><rect y="80" width="408" height="20" fill="#e3a35f" /><rect y="100" width="408" height="111" fill="#e3a35f" /><path fill="#ffd076" d="M375 77h10v2h-10zM371 79h18v2h-18zM367 81h26v2h-26zM367 83h26v2h-26zM365 85h30v2h-30zM365 87h30v2h-30zM363 89h34v2h-34zM363 91h34v2h-34zM363 93h34v2h-34zM363 95h34v2h-34zM363 97h34v2h-34zM365 99h30v2h-30zM365 101h30v2h-30zM367 103h26v2h-26zM367 105h26v2h-26zM371 107h18v2h-18zM375 109h10v2h-10z" /><path fill="#c98aa0" d="M27 40h24V28h48v12h35v16H27zM181 18h46v11h35v16h-81z" /><path fill="#86566b" d="M0 143V105h29v-11h49v17h31v-19h44v13h35V89h40v20h23V91h55v15h41V87h23v21h38v103H0z" /><path fill="#51475f" d="M0 160v-23h31v12h32v-20h52v16h37v-13h58v20h43v-21h46v9h45v-13h64v84H0z" /><path fill="#a08672" d="M0 178h408v33H0z" /><path fill="#e8ba7e" d="M0 183h408v8H0z" /><path fill="#516069" d="M0 192h408v19H0z" /><path fill="#e8d9a9" d="M0 202h42v3H0zm75 0h54v3H75zm82 0h54v3h-54zm82 0h54v3h-54zm83 0h36v3h-36z" /></svg>',
    'night': '<svg xmlns="http://www.w3.org/2000/svg" width="408" height="211" shape-rendering="crispEdges" viewBox="0 0 408 211" preserveAspectRatio="none"><rect width="408" height="211" fill="#243450" /><path fill="#e9d3a6" d="M364 21h10v2h-10zM360 23h10v2h-10zM358 25h10v2h-10zM358 27h8v2h-8zM356 29h8v2h-8zM356 31h8v2h-8zM356 33h8v2h-8zM356 35h8v2h-8zM356 37h8v2h-8zM358 39h8v2h-8zM358 41h10v2h-10zM360 43h10v2h-10zM364 45h10v2h-10z" /><path fill="#9ab4bd" d="M29 34h4v4h-4zM105 50h4v4h-4zM190 24h4v4h-4zM260 84h3v3h-3zM48 85h3v3h-3z" /><rect y="107" width="408" height="104" fill="#985a57" /><path fill="#3e5963" d="M0 149v-39h36v-19h38v19h36V91h44v16h43V93h31v17h44V88h39v21h39V94h58v117H0z" /><path fill="#243e4b" d="M0 164v-22h49v-14h40v18h51v-11h39v15h37v-17h47v16h42v-13h46v11h57v64H0z" /><path fill="#62434b" d="M0 182h408v29H0z" /><path fill="#7d6b5e" d="M0 184h408v6H0z" /><path fill="#35424a" d="M0 192h408v19H0z" /><path fill="#efc58e" d="M0 202h44v3H0zm80 0h48v3H80zm82 0h48v3h-48zm81 0h48v3h-48zm80 0h35v3h-35z" /></svg>',
}


def main():
    root = Path(__file__).resolve().parents[1] / "TripTrack/Resources/Assets.xcassets/RoadScene"
    root.mkdir(exist_ok=True)
    info = {"author": "xcode", "version": 1}
    (root / "Contents.json").write_text(json.dumps({"info": info, "properties": {"provides-namespace": True}}, indent=2) + "\n")
    for time, svg in SCENES.items():
        folder = root / (time + ".imageset")
        folder.mkdir(exist_ok=True)
        (folder / (time + ".svg")).write_text(svg + "\n")
        contents = {"images": [{"filename": time + ".svg", "idiom": "universal"}],
                    "info": info, "properties": {"preserves-vector-representation": True}}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    main()
