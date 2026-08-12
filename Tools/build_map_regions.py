#!/usr/bin/env python3
"""Build the bundled map dataset for the 6.1.0 «Моя карта» screen.

Sources (both public domain / open):
  - Natural Earth 1:10m admin-1 states & provinces  → region borders
  - pensnarik/russian-cities                        → RU city list per subject

The 1:50m cut was tried first and rejected: the whole Krasnodar Krai came out
as 128 points, which put Adler and Krasnaya Polyana OUTSIDE their own region.
1:10m keeps the coastal strip.

Output: a single compact JSON. Rings are flat [lat, lon, lat, lon, …] arrays
rounded to 3 decimals (~110 m), simplified with Douglas–Peucker at ~1.3 km —
finer than any border drawn at region zoom needs.

Usage — the three inputs are NOT committed (40 MB of source data for a 650 KB
result), so fetch them next to this script first:

    cd Tools
    NE=https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson
    curl -L -o ne10.geojson        $NE/ne_10m_admin_1_states_provinces.geojson
    curl -L -o ne10_places.geojson $NE/ne_10m_populated_places.geojson
    curl -L -o ru_cities.json \\
      https://raw.githubusercontent.com/pensnarik/russian-cities/master/russian-cities.json
    python3 build_map_regions.py
    mv map_regions.json ../TripTrack/Resources/MapRegions.json

Licences: Natural Earth is public domain; pensnarik/russian-cities is open.
"""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))

# Countries whose regions ship as separate fill/border units. Everything else
# on earth is unreachable by car from here, so a trip there falls back to the
# country row without geometry.
COUNTRIES = {
    "RUS": ("RU", "Россия", "Russia"),
    "GEO": ("GE", "Грузия", "Georgia"),
    "ARM": ("AM", "Армения", "Armenia"),
    "AZE": ("AZ", "Азербайджан", "Azerbaijan"),
    "KAZ": ("KZ", "Казахстан", "Kazakhstan"),
    "BLR": ("BY", "Беларусь", "Belarus"),
    "UKR": ("UA", "Украина", "Ukraine"),
    "FIN": ("FI", "Финляндия", "Finland"),
    "EST": ("EE", "Эстония", "Estonia"),
    "LVA": ("LV", "Латвия", "Latvia"),
    "LTU": ("LT", "Литва", "Lithuania"),
    "MDA": ("MD", "Молдова", "Moldova"),
    "POL": ("PL", "Польша", "Poland"),
    "MNG": ("MN", "Монголия", "Mongolia"),
    "TUR": ("TR", "Турция", "Türkiye"),
    "KGZ": ("KG", "Киргизия", "Kyrgyzstan"),
    "UZB": ("UZ", "Узбекистан", "Uzbekistan"),
    "TJK": ("TJ", "Таджикистан", "Tajikistan"),
    "TKM": ("TM", "Туркменистан", "Turkmenistan"),
    "NOR": ("NO", "Норвегия", "Norway"),
}

# Natural Earth swaps the two Moscow ISO codes (city ↔ oblast). Display names
# are right, ids are not — and the id is what everything else keys on.
ISO_FIXES = {("Москва", "RU-MOS"): "RU-MOW", ("Московская область", "RU-MOW"): "RU-MOS"}

# ---------------------------------------------------------------- geometry


def rdp(points, eps):
    """Douglas–Peucker on (lon, lat) pairs. Iterative — rings can be long."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        lo, hi = stack.pop()
        if hi <= lo + 1:
            continue
        ax, ay = points[lo]
        bx, by = points[hi]
        dx, dy = bx - ax, by - ay
        norm = math.hypot(dx, dy)
        best, best_i = -1.0, -1
        for i in range(lo + 1, hi):
            px, py = points[i]
            if norm == 0:
                d = math.hypot(px - ax, py - ay)
            else:
                d = abs(dy * px - dx * py + bx * ay - by * ax) / norm
            if d > best:
                best, best_i = d, i
        if best > eps:
            keep[best_i] = True
            stack.append((lo, best_i))
            stack.append((best_i, hi))
    return [p for p, k in zip(points, keep) if k]


def rings_of(geom):
    """GeoJSON geometry → list of outer rings as (lon, lat) lists."""
    t, coords = geom["type"], geom["coordinates"]
    if t == "Polygon":
        return [coords[0]]
    if t == "MultiPolygon":
        return [poly[0] for poly in coords]
    return []


def ring_span(ring):
    lons = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    return math.hypot(max(lons) - min(lons), max(lats) - min(lats))


def prepare(geom, min_span, max_rings, detail=0.006, lo=0.008, hi=0.05):
    """Simplify each ring with a tolerance proportional to its own span.

    A fixed epsilon is the wrong trade: 1.3 km shreds Adjara's coastline yet
    leaves Yakutia carrying 4 000 points nobody will ever see — you only ever
    look at a big region from far away. Scaling the tolerance to the ring
    keeps small regions crisp and stops the giants from dominating the file.
    """
    out = []
    for ring in rings_of(geom):
        span = ring_span(ring)
        if span < min_span:
            continue
        simple = rdp(ring, max(lo, min(hi, span * detail)))
        if len(simple) < 4:
            continue
        out.append((span, simple))
    out.sort(key=lambda x: -x[0])
    return [r for _, r in out[:max_rings]]


def flat(ring):
    """(lon, lat) pairs → flat [lat, lon, …] rounded to 3 decimals."""
    vals = []
    for lon, lat in ring:
        vals.append(round(lat, 3))
        vals.append(round(lon, 3))
    return vals


def bbox_of(rings):
    lats = [v for r in rings for v in r[0::2]]
    lons = [v for r in rings for v in r[1::2]]
    return [round(min(lats), 3), round(min(lons), 3), round(max(lats), 3), round(max(lons), 3)]


def centroid_of(rings):
    """Area-weighted centroid of the largest ring — a label anchor, not a
    mean of vertices (which drifts into the sea on curved coastlines)."""
    big = max(rings, key=len)
    n = len(big) // 2
    a = cx = cy = 0.0
    for i in range(n):
        y0, x0 = big[2 * i], big[2 * i + 1]
        j = (i + 1) % n
        y1, x1 = big[2 * j], big[2 * j + 1]
        cross = x0 * y1 - x1 * y0
        a += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if abs(a) < 1e-9:
        return [round(sum(big[0::2]) / n, 3), round(sum(big[1::2]) / n, 3)]
    a *= 0.5
    return [round(cy / (6 * a), 3), round(cx / (6 * a), 3)]


def point_in_rings(lat, lon, rings):
    """Ray casting over flat [lat, lon, …] rings."""
    inside = False
    for r in rings:
        n = len(r) // 2
        j = n - 1
        for i in range(n):
            yi, xi = r[2 * i], r[2 * i + 1]
            yj, xj = r[2 * j], r[2 * j + 1]
            if (yi > lat) != (yj > lat):
                if lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                    inside = not inside
            j = i
    return inside


# ------------------------------------------------------------------ build


# BGN/PCGN-flavoured transliteration, used only for cities Natural Earth has
# never heard of. Well-known places take their real English name instead —
# «Moscow», not «Moskva».
TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}


def transliterate(name):
    out = []
    for char in name:
        lower = char.lower()
        mapped = TRANSLIT.get(lower)
        if mapped is None:
            out.append(char)
            continue
        out.append(mapped.capitalize() if char.isupper() and mapped else mapped)
    return "".join(out)


def english_city_names():
    """Russian → English city names from Natural Earth's populated places."""
    path = os.path.join(HERE, "ne10_places.geojson")
    if not os.path.exists(path):
        return {}
    data = json.load(open(path))
    table = {}
    for feature in data["features"]:
        p = feature["properties"]
        if p.get("ADM0_A3") != "RUS":
            continue
        ru, en = p.get("NAME_RU"), p.get("NAME_EN") or p.get("NAME")
        if ru and en:
            table[ru] = en
    return table


def main():
    admin1 = json.load(open(os.path.join(HERE, "ne10.geojson")))
    cities_raw = json.load(open(os.path.join(HERE, "ru_cities.json")))
    english = english_city_names()

    regions = []
    for feat in admin1["features"]:
        p = feat["properties"]
        entry = COUNTRIES.get(p.get("adm0_a3"))
        if entry is None:
            continue
        cc, _, _ = entry
        # Abroad you pass through; a 2 km border there is plenty, and it
        # stops Latvia's 119 municipalities from outweighing all of Russia.
        rings = prepare(feat["geometry"], min_span=0.06, max_rings=24,
                        lo=0.008 if cc == "RU" else 0.02)
        if not rings:
            continue
        flat_rings = [flat(r) for r in rings]
        ru = p.get("name_ru") or p.get("name_local") or p.get("name")
        en = p.get("name_en") or p.get("name") or ru
        # Natural Earth carries a few nameless placeholder features (e.g.
        # RU-X01~). A region with no name has nothing to show on a card.
        if not ru or not en:
            continue
        rid = p.get("iso_3166_2") or f"{cc}-{(p.get('code_hasc') or en)[-3:]}"
        rid = ISO_FIXES.get((ru, rid), rid)
        regions.append({
            "id": rid,
            "cc": cc,
            "ru": ru,
            "en": en,
            "c": centroid_of(flat_rings),
            "b": bbox_of(flat_rings),
            "r": flat_rings,
        })

    countries = [
        {"id": cc, "ru": ru, "en": en}
        for _, (cc, ru, en) in sorted(COUNTRIES.items(), key=lambda kv: kv[1][0])
    ]

    # --- Cities, assigned to a region by point-in-polygon ------------------
    ru_regions = [r for r in regions if r["cc"] == "RU"]
    cities, fallback = [], 0
    for c in cities_raw:
        try:
            lat, lon = float(c["coords"]["lat"]), float(c["coords"]["lon"])
        except (KeyError, TypeError, ValueError):
            continue
        home = None
        for r in ru_regions:
            b = r["b"]
            if b[0] <= lat <= b[2] and b[1] <= lon <= b[3] and point_in_rings(lat, lon, r["r"]):
                home = r["id"]
                break
        if home is None:
            best, bd = None, 1e9
            for r in ru_regions:
                d = (r["c"][0] - lat) ** 2 + (r["c"][1] - lon) ** 2
                if d < bd:
                    best, bd = r["id"], d
            home, fallback = best, fallback + 1
        name = c["name"]
        cities.append({"n": name, "e": english.get(name) or transliterate(name),
                       "r": home, "c": [round(lat, 3), round(lon, 3)],
                       "p": int(c.get("population") or 0)})

    payload = {"v": 1, "regions": regions, "countries": countries, "cities": cities}
    out_path = os.path.join(HERE, "map_regions.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))

    pts = sum(len(r) // 2 for x in regions for r in x["r"])
    print(f"regions={len(regions)} pts={pts}  countries={len(countries)}")
    print(f"cities={len(cities)} (nearest-centroid fallback: {fallback})")
    print(f"{out_path}  {os.path.getsize(out_path)/1024:.0f} KB")

    by_id = {r["id"]: r for r in regions}
    from collections import Counter
    cc = Counter(c["r"] for c in cities)
    for rid in ("RU-KDA", "RU-MOS", "RU-MOW", "RU-ROS", "RU-STA", "RU-SPE"):
        if rid in by_id:
            print(f"  {by_id[rid]['ru']:26} {cc.get(rid, 0):3} городов")


if __name__ == "__main__":
    main()
