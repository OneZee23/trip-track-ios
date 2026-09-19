#!/usr/bin/env python3
"""Build the bundled map dataset for the «Атлас» screen.

Sources (all public domain / open):
  - Natural Earth 1:10m admin-1 states & provinces  → region borders
  - Natural Earth 1:10m admin-0 countries            → country name/centroid/bbox
  - Natural Earth 1:10m populated places             → RU→EN city names
  - pensnarik/russian-cities                         → RU city list per subject

The 1:50m cut was tried first and rejected: the whole Krasnodar Krai came out
as 128 points, which put Adler and Krasnaya Polyana OUTSIDE their own region.
1:10m keeps the coastal strip.

Regions are simplified with a tolerance SCALED to each ring's own span
(`detail 0.002, lo 0.003, hi 0.012`, ~0.7.0): a fixed epsilon is the wrong
trade — it shreds a small region's coastline or leaves a giant carrying
thousands of points nobody will ever see.

Countries — everything on earth, not just the 20 the app breaks into
regions — used to carry their own ring (`countries[].r`, flat 0.01°
tolerance) for a border drawn on the Atlas at world zoom, plus a label.
`--no-country-rings` (on by default since 17 Sep 2026) drops that ring: the
owner's device showed the border visibly offset near Japan/Philippines at
world zoom, and — borders aside — geopolitics has no place on this map.
`countries[].c`/`.b`/`id`/`ru`/`en` still ship (name lookups: milestone and
extreme-point copy read them via `RegionAtlas.countryName(_:)`), and the ring
machinery (`country_geometry`, `min_span`, the exclave force-keep below)
stays in this file in case a future version wants the shape back — it just
does not reach the JSON.

Countries used to ship as a name-only list of the 20 driveable ones. As of
0.7.0 every country on earth gets an entry (§3.3 of the atlas-look spec):
the 20 keep their hand-picked `ru`/`en` (Natural Earth's «Молдавия»,
«Туркмения», «Белоруссия», «Turkey» disagree with product decisions already
made — «Молдова», «Туркменистан», «Беларусь», «Türkiye» — so those twenty
are NOT re-sourced from Natural Earth's names), every other country takes
its `NAME_RU`/`NAME_EN` straight from the admin-0 row. Multiple admin-0
features can share one ISO_A2 (France + Clipperton Island, Australia + its
island territories) — their rings are pooled before simplifying, one country
entry, not two.

Output: a single compact JSON. Rings are flat [lat, lon, lat, lon, …] arrays
rounded to 3 decimals (~110 m).

Usage — the four inputs are NOT committed (source data for a few-MB result),
so this script fetches them itself on first run, into `Tools/cache/`
(gitignored):

    python3 Tools/build_map_regions.py
    mv Tools/map_regions.json TripTrack/Resources/MapRegions.json

Re-running reuses whatever is already in `Tools/cache/`; delete a file there
to force a re-fetch.

Licences: Natural Earth is public domain; pensnarik/russian-cities is open.
"""
import argparse, json, math, os, sys, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")

NE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson"
SOURCES = {
    "ne_10m_admin_1_states_provinces.geojson": f"{NE}/ne_10m_admin_1_states_provinces.geojson",
    "ne_10m_admin_0_countries.geojson": f"{NE}/ne_10m_admin_0_countries.geojson",
    "ne_10m_populated_places.geojson": f"{NE}/ne_10m_populated_places.geojson",
    "ru_cities.json": "https://raw.githubusercontent.com/pensnarik/russian-cities/master/russian-cities.json",
}

ADMIN1_PATH = os.path.join(CACHE, "ne_10m_admin_1_states_provinces.geojson")
ADMIN0_PATH = os.path.join(CACHE, "ne_10m_admin_0_countries.geojson")
PLACES_PATH = os.path.join(CACHE, "ne_10m_populated_places.geojson")
RU_CITIES_PATH = os.path.join(CACHE, "ru_cities.json")


def ensure_cached():
    """Fetch every source into `Tools/cache/` if it is not already there.
    A failed fetch stops the build with the URL that failed — geometry is
    never invented when a download is unavailable."""
    os.makedirs(CACHE, exist_ok=True)
    for name, url in SOURCES.items():
        path = os.path.join(CACHE, name)
        if os.path.exists(path) and os.path.getsize(path) > 0:
            continue
        print(f"fetching {name} ...")
        req = urllib.request.Request(url, headers={"User-Agent": "TripTrack (map atlas build)"})
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                data = resp.read()
        except Exception as exc:  # noqa: BLE001 — any failure here is fatal to the build
            sys.exit(
                f"BLOCKED: could not fetch {name}\n  {url}\n  {exc}\n"
                f"Download it by hand into {path} and re-run."
            )
        with open(path, "wb") as fh:
            fh.write(data)
        print(f"  {len(data) / 1024:.0f} KB")


# Countries whose regions ship as separate fill/border units. Everything else
# on earth gets a country-level outline only (§3.3, 0.7.0) — a trip there
# falls back to the country row without a region breakdown.
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


def simplify_rings(rings, min_span, max_rings, detail=0.002, lo=0.003, hi=0.012, max_points=None):
    """Simplify each ring with a tolerance proportional to its own span.

    A fixed epsilon is the wrong trade: 1.3 km shreds Adjara's coastline yet
    leaves Yakutia carrying 4 000 points nobody will ever see — you only ever
    look at a big region from far away. Scaling the tolerance to the ring
    keeps small regions crisp and stops the giants from dominating the file.

    0.7.0: tightened from 0.006/0.008/0.05 and — as important — the old call
    site coarsened every country but Russia to `lo=0.02`, which is exactly
    what shredded Adjara's coastal ring and put Kobuleti on the wrong side of
    it (Batumi → Kobuleti landed outside GE-AJ). The finer, UNIFORM tolerance
    below fixes that as a side effect of not treating "abroad" as cheaper to
    draw than home.

    A ring that already has few points (a small city-level subject — Ganja,
    Valmiera, Mingecevir) is passed through UNSIMPLIFIED: RDP on 10–20 points
    saves nothing worth having and can push an already-thin ring under the
    twelve-vertex floor the bundle test holds every region to, for a few
    hundred bytes of savings on a 3.5 MB file.

    `max_points`, when given, re-simplifies at a coarser (scaled-up) uniform
    tolerance until the region's total vertex count fits — the handful of
    Arctic giants (Krasnoyarsk Krai, Yakutia, Arkhangelsk, Norway's Nordland)
    that the finer 0.7.0 tolerance alone still leaves over
    `MapRenderCostTests.testRegionOutlinesAreSmallEnoughToDrawAtOnce`'s 3 000-
    point render budget. Only THEIR tolerance grows; every other region keeps
    the fine, uniform pass above.
    """
    def pass_at(scale):
        out = []
        for ring in rings:
            span = ring_span(ring)
            if span < min_span:
                continue
            if len(ring) <= 24:
                simple = ring
            else:
                simple = rdp(ring, max(lo, min(hi, span * detail)) * scale)
            if len(simple) < 4:
                continue
            out.append((span, simple))
        out.sort(key=lambda x: -x[0])
        return out[:max_rings]

    scale = 1.0
    scored = pass_at(scale)
    if max_points is not None:
        total = sum(len(r) for _, r in scored)  # r is a list of (lon, lat) points here
        while total > max_points and scale < 64:
            scale *= 1.5
            scored = pass_at(scale)
            total = sum(len(r) for _, r in scored)
    return [r for _, r in scored]


def country_geometry(raw_rings, min_span=0.15, max_rings=12, eps=0.01, force_centroids=None):
    """Country outline: flat 0.01° tolerance, rings under `min_span` (~micro-
    states) dropped, the twelve largest by span kept. `centroid`/`bbox` come
    from the FULL unfiltered geometry — a country whose only ring fell under
    the span floor still needs a label anchor and a box for LOD sizing, just
    no polygon to fill. Returns ([], None, None) when there is no usable
    geometry at all.

    `force_centroids` — `[lat, lon]` pairs (a country's own driveable
    regions' centroids) that MUST end up covered by a kept ring, independent
    of span rank. Without this, Russia's Kaliningrad ring (span ≈3.37°) sat
    at rank 14 among Russia's 189 span-qualifying rings — two past
    `max_rings=12` — while Crimea (rank 11) kept its slot; Kaliningrad read
    as unclaimed space between Poland and Lithuania at world zoom. A region
    exists in the bundle only because someone can drive there, so its
    country's outline can never silently drop the ground under it. This can
    push a country past `max_rings` (Russia now carries 13) — the overall
    4 MB bundle budget is what's held to, not a fixed ring count per country.
    """
    usable = [r for r in raw_rings if len(r) >= 4]
    if not usable:
        return [], None, None
    all_flat = [flat(r) for r in usable]
    scored = []
    for ring in usable:
        span = ring_span(ring)
        if span < min_span:
            continue
        simple = rdp(ring, eps)
        if len(simple) < 4:
            continue
        scored.append((span, simple))
    scored.sort(key=lambda x: -x[0])

    kept = list(scored[:max_rings])
    if force_centroids:
        kept_ids = {id(simple) for _, simple in kept}
        for span, simple in scored[max_rings:]:
            if id(simple) in kept_ids:
                continue
            ring_flat = flat(simple)
            if any(point_in_rings(lat, lon, [ring_flat]) for lat, lon in force_centroids):
                kept.append((span, simple))
                kept_ids.add(id(simple))

    rings = [flat(r) for _, r in kept]
    return rings, centroid_of(all_flat), bbox_of(all_flat)


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
    if not os.path.exists(PLACES_PATH):
        return {}
    data = json.load(open(PLACES_PATH, encoding="utf-8"))
    table = {}
    for feature in data["features"]:
        p = feature["properties"]
        if p.get("ADM0_A3") != "RUS":
            continue
        ru, en = p.get("NAME_RU"), p.get("NAME_EN") or p.get("NAME")
        if ru and en:
            table[ru] = en
    return table


def build_countries(regions, include_rings=False):
    """One entry per country on earth: the 20 atlas countries keep their
    hand-picked names (Natural Earth's «Молдавия»/«Туркмения»/«Белоруссия»/
    Turkey disagree with product decisions already made), everyone else
    takes NAME_RU/NAME_EN straight from admin-0. Multiple admin-0 features
    sharing one ISO_A2 (dependencies) are pooled into a single entry.

    `regions` — the already-built region list, so each country's outline can
    be forced to cover every one of its OWN regions' centroids (exclaves like
    Kaliningrad, Nakhchivan) regardless of span rank; see `country_geometry`.

    `include_rings` — off by default (`--no-country-rings`, 17 Sep 2026): the
    Atlas no longer draws a country border or a country label at world zoom
    (the owner's device showed the border visibly offset near Japan and the
    Philippines, and geopolitics has no place on this map besides), so
    `countries[].r` is dead weight — every entry still ships `id`/`ru`/`en`/
    `c`/`b` for `RegionAtlas.countryName(_:)` (used by milestone/extreme-point
    copy) and for a future label anchor, just no ring to trace.
    """
    admin0 = json.load(open(ADMIN0_PATH, encoding="utf-8"))
    by_cc = {cc: (ru, en) for cc, ru, en in COUNTRIES.values()}
    centroids_by_cc = {}
    for region in regions:
        centroids_by_cc.setdefault(region["cc"], []).append(region["c"])

    grouped = {}
    for feat in admin0["features"]:
        p = feat["properties"]
        entry = COUNTRIES.get(p.get("ADM0_A3"))
        if entry is not None:
            code = entry[0]
        else:
            code = p.get("ISO_A2")
            if not code or code == "-99":
                code = p.get("ISO_A2_EH")
            if not code or code == "-99":
                continue  # disputed micro-territory with no usable code
        grouped.setdefault(code, []).append(feat)

    countries = []
    for code, feats in sorted(grouped.items()):
        if code in by_cc:
            ru, en = by_cc[code]
        else:
            named = next(
                (f for f in feats if f["properties"].get("TYPE") in ("Country", "Sovereign country")),
                feats[0],
            )
            p = named["properties"]
            ru = p.get("NAME_RU") or p.get("NAME")
            en = p.get("NAME_EN") or p.get("NAME")
            if not ru or not en:
                continue
        raw_rings = [ring for f in feats for ring in rings_of(f["geometry"])]
        rings, centroid, bbox = country_geometry(
            raw_rings, force_centroids=centroids_by_cc.get(code))
        if bbox is None:
            continue
        row = {"id": code, "ru": ru, "en": en, "c": centroid, "b": bbox}
        if include_rings and rings:
            row["r"] = rings
        countries.append(row)
    return countries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--no-country-rings", action="store_true", default=True,
        help="omit countries[].r (country border rings) from the output — "
             "on by default since the Atlas stopped drawing a country "
             "border or label at world zoom (17 Sep 2026)",
    )
    args = parser.parse_args()

    ensure_cached()

    admin1 = json.load(open(ADMIN1_PATH, encoding="utf-8"))
    cities_raw = json.load(open(RU_CITIES_PATH, encoding="utf-8"))
    english = english_city_names()

    regions = []
    # Natural Earth occasionally tags TWO rows with the same iso_3166_2 — a
    # rural district and the city inside it that outgrew a municipality of
    # its own (Latvia's Rezekne city vs. Rezeknes municipality, Azerbaijan's
    # district/municipality pairs). Group by the FINAL id first and pool
    # every ring under it, so a drive through either half still resolves and
    # the id never appears twice in the output — a duplicate id would make
    # `RegionAtlas.regionIndexById` silently drop one of the two.
    grouped_geoms = {}
    meta = {}       # rid -> (cc, ru, en, raw point count of its biggest contributor)
    for feat in admin1["features"]:
        p = feat["properties"]
        entry = COUNTRIES.get(p.get("adm0_a3"))
        if entry is None:
            continue
        cc, _, _ = entry
        ru = p.get("name_ru") or p.get("name_local") or p.get("name")
        en = p.get("name_en") or p.get("name") or ru
        # Natural Earth carries a few nameless placeholder features (e.g.
        # RU-X01~). A region with no name has nothing to show on a card.
        if not ru or not en:
            continue
        rid = p.get("iso_3166_2") or f"{cc}-{(p.get('code_hasc') or en)[-3:]}"
        rid = ISO_FIXES.get((ru, rid), rid)
        geoms = rings_of(feat["geometry"])
        grouped_geoms.setdefault(rid, []).extend(geoms)
        points = sum(len(r) for r in geoms)
        if rid not in meta or points > meta[rid][3]:
            meta[rid] = (cc, ru, en, points)

    for rid, raw_rings in grouped_geoms.items():
        cc, ru, en, _ = meta[rid]
        # 2 800, not 3 000: leaves headroom below MapRenderCostTests' budget
        # for the flat→round-trip and for the next region that edges close.
        #
        # No vertex-count floor here on purpose (0.7.0 fix-up): a handful of
        # city-level subjects (Nakhchivan city AZ-NX, Mingecevir AZ-MI,
        # Valmiera LV-VMR) genuinely carry fewer than twelve points in
        # Natural Earth's OWN source data — confirmed single `Polygon`
        # geometries, nothing lost in the multipart-merge above. A vertex
        # floor is a guard against RDP throwing away too much detail; these
        # rings are never simplified at all (≤24 raw points, passthrough in
        # `simplify_rings`), so there is nothing to over-simplify and nothing
        # to guard against. Dropping them because the SOURCE is sparse would
        # fabricate a hole in the atlas where a real, driveable place is —
        # worse than a nine-sided polygon. `MapRegionsBundleTests` enforces
        # the quality floor only where it can mean something: regions large
        # enough that RDP had real work to do.
        rings = simplify_rings(raw_rings, min_span=0.06, max_rings=24, max_points=2_800)
        if not rings:
            continue
        flat_rings = [flat(r) for r in rings]
        regions.append({
            "id": rid,
            "cc": cc,
            "ru": ru,
            "en": en,
            "c": centroid_of(flat_rings),
            "b": bbox_of(flat_rings),
            "r": flat_rings,
        })

    countries = build_countries(regions, include_rings=not args.no_country_rings)

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

    payload = {"v": 2, "regions": regions, "countries": countries, "cities": cities}
    out_path = os.path.join(HERE, "map_regions.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))

    pts = sum(len(r) // 2 for x in regions for r in x["r"])
    country_pts = sum(len(r) // 2 for c in countries for r in c.get("r", []))
    with_rings = sum(1 for c in countries if c.get("r"))
    print(f"regions={len(regions)} pts={pts}  countries={len(countries)} "
          f"(with rings: {with_rings}, pts={country_pts})")
    print(f"cities={len(cities)} (nearest-centroid fallback: {fallback})")
    print(f"{out_path}  {os.path.getsize(out_path) / 1024:.0f} KB")

    by_id = {r["id"]: r for r in regions}
    from collections import Counter
    cc = Counter(c["r"] for c in cities)
    for rid in ("RU-KDA", "RU-MOS", "RU-MOW", "RU-ROS", "RU-STA", "RU-SPE"):
        if rid in by_id:
            print(f"  {by_id[rid]['ru']:26} {cc.get(rid, 0):3} городов")


if __name__ == "__main__":
    main()
