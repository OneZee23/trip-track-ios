#!/usr/bin/env python3
"""Build `Riddles.json` — the bundled layer of «places you can drive to» that
0.7.0 turns into automatic riddles on the Atlas.

Sources and licences (every one of them open; nothing proprietary, nothing
scraped from a site whose terms forbid it — Peakbagger was looked at and
rejected for exactly that reason):

  - OpenStreetMap via the Overpass API           → ODbL, © OpenStreetMap
    contributors. Passes, lighthouses, border crossings, ferry terminals,
    dams, bridges, viewpoints, observatories, coastal dead ends.
  - Wikidata via the SPARQL endpoint             → CC0. Extreme points of a
    country, geographic centres, tripoints, river lengths (P2043).
  - Natural Earth, through this project's own    → public domain. Only used
    `TripTrack/Resources/MapRegions.json`           here to name the region a
                                                    point falls into.

The extracted point set is a DERIVATIVE DATABASE of OSM, not a produced work
(a reader can pull the original coordinates straight back out of it), so both
this script and the resulting `Riddles.json` ship under ODbL, separately from
the application code — the same arrangement `Tools/build_map_regions.py`
already has for Natural Earth.

Quality rules, all of them from the 0.7.0 plan and none of them optional:

  * drivable or it does not exist — a point survives only within 300 m of a
    `highway=*` that a car may use (no `footway/path/steps/cycleway/track/
    service`, no `access=private|no`). Without this the set fills up with
    lighthouses you can only reach by boat, which for a driving game is a bug
    and not an edge case;
  * one point per geohash-7 cell (~150 m), the same cell «Места» uses, so the
    same object mapped twice collapses into one;
  * at most one point of a type per 50 km, ranked `wikidata` present > `ele`
    in the type's upper quartile > the rest. Without the cap `viewpoint` alone
    would bury every other type in the Caucasus and the Baltics;
  * names: `name:en` where OSM has it, otherwise the local `name`
    transliterated with the same BGN/PCGN-ish table as the region atlas. A
    toponym is data, not interface copy — the riddle LINE comes from
    `AppStrings`, only the object's own name comes from here.

Usage (the script talks to the network and caches every response, so a second
run is nearly free — delete `Tools/cache/` to refetch):

    cd Tools
    python3 build_secrets.py            # writes riddles.json next to itself
    python3 build_secrets.py --types pass,lighthouse     # a subset
    mv riddles.json ../TripTrack/Resources/Riddles.json

If a source stays unreachable for three attempts the script does NOT invent
points: it drops that type, says so on stderr and in the printed summary, and
writes the bundle from the types that did build. A type whose sources DID
answer but produced nothing lands in the same `missing` list (`note_empty_types`)
— a silent hole is worse than a missing type, and the first build shipped two
of them (`seaRoad`, `extreme`).
"""
import argparse
import hashlib
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
ATLAS = os.path.join(HERE, "..", "TripTrack", "Resources", "MapRegions.json")
SECRETS = os.path.join(HERE, "..", "TripTrack", "Resources", "Secrets.json")
AUTHORED = os.path.join(HERE, "authored.json")

USER_AGENT = "TripTrack-bundle-builder/0.7.0 (https://trip-track.app; open-data build script)"
# The main instance first, the mirror as the fallback. Both are shared boxes
# under constant load, so «unreachable» here usually means «busy» — hence the
# retries. `TT_OVERPASS_ENDPOINTS` (comma-separated) reorders them, which is
# how a long build can be split across two shells without both hammering the
# same server.
OVERPASS_ENDPOINTS = [e for e in os.environ.get("TT_OVERPASS_ENDPOINTS", "").split(",") if e] or [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"

# The same twenty countries the region atlas ships geometry for: everything
# else on earth is not reachable by car from here, so a riddle there could
# never be solved.
COUNTRIES = {
    "RU": "Russia", "GE": "Georgia", "AM": "Armenia", "AZ": "Azerbaijan",
    "KZ": "Kazakhstan", "BY": "Belarus", "UA": "Ukraine", "FI": "Finland",
    "EE": "Estonia", "LV": "Latvia", "LT": "Lithuania", "MD": "Moldova",
    "PL": "Poland", "MN": "Mongolia", "TR": "Türkiye", "KG": "Kyrgyzstan",
    "UZ": "Uzbekistan", "TJ": "Tajikistan", "TM": "Turkmenistan", "NO": "Norway",
}

# A car may use it. `track` is out on purpose: it is a field road, and half of
# them are gated. `service` is out because it is a car park aisle, which would
# make «reachable» true for every lighthouse with a footpath museum next door.
DRIVABLE = (
    '[highway]'
    '[highway!~"^(footway|path|steps|cycleway|bridleway|pedestrian|track|service|'
    'construction|proposed|raceway|escape|corridor|via_ferrata|busway)$"]'
    '[access!~"^(private|no)$"]'
)

ROAD_RADIUS = 300      # metres, «reachable by car»
BORDER_RADIUS = 50     # a border post sits ON the road
DEDUP_PRECISION = 7    # geohash-7 ≈ 150 m, the cell «Места» already uses
DENSITY_KM = 50.0      # at most one point of a type inside this radius
MAX_BYTES = 400 * 1024

# `node`/`way` are spelled out rather than using `nwr`: the shorthand makes
# Overpass scan relations too, and over an area the size of Russia that is the
# difference between twenty seconds and a gateway timeout.
OSM_TYPES = {
    # type          selectors (unioned)                           road radius
    "pass":        (['node[mountain_pass=yes]'], ROAD_RADIUS),
    "lighthouse":  (['node[man_made=lighthouse]', 'way[man_made=lighthouse]'], ROAD_RADIUS),
    "border":      (['node[barrier=border_control]'], BORDER_RADIUS),
    # The pier, not the route: a ferry relation's own geometry is the sea
    # crossing, and «drive to the sea crossing» is not a place.
    "ferry":       (['node[amenity=ferry_terminal]', 'way[amenity=ferry_terminal]'], ROAD_RADIUS),
    "dam":         (['way[waterway=dam][name]', 'node[waterway=dam][name]',
                     'way[man_made=dam][name]', 'node[man_made=dam][name]'], ROAD_RADIUS),
    # Only viewpoints notable enough to have a Wikidata item. The raw tag has
    # 263 000 nodes worldwide, most of them someone's favourite bench.
    "viewpoint":   (['node[tourism=viewpoint][wikidata]', 'way[tourism=viewpoint][wikidata]'],
                    ROAD_RADIUS),
    "observatory": (['node[man_made=observatory]', 'way[man_made=observatory]'], ROAD_RADIUS),
}

# Rivers this long make a bridge worth a riddle. The plan says 100 km; 300 km
# is what keeps the Overpass regex (one QID per river) inside a sane length
# and keeps «bridge over a big river» meaning the Volga and not a creek with
# an article.
RIVER_MIN_KM = 300

TRANSLIT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    # Ukrainian / Belarusian / Kazakh letters the Russian table has no row for.
    "і": "i", "ї": "yi", "є": "ye", "ґ": "g", "ў": "w", "ә": "a", "ғ": "gh",
    "қ": "q", "ң": "ng", "ө": "o", "ұ": "u", "ү": "u", "һ": "h",
}


def transliterate(name):
    """BGN/PCGN-flavoured, character by character — the same table and the
    same rule as `build_map_regions.py`: a real name where the source has one,
    a transliteration otherwise. Transliteration is not translation."""
    out = []
    for char in name:
        mapped = TRANSLIT.get(char.lower())
        if mapped is None:
            out.append(char)
            continue
        out.append(mapped.capitalize() if char.isupper() and mapped else mapped)
    return "".join(out)


# ------------------------------------------------------------------ network


# Countries a type could not be fetched for. Printed at the end and written
# into the bundle, because a silent hole in the data is the one thing worse
# than a missing type.
GAPS = []


class SourceUnreachable(Exception):
    """Three attempts, two endpoints, still nothing — the type is dropped."""


def cache_path(kind, key):
    digest = hashlib.sha1(key.encode("utf-8")).hexdigest()[:16]
    return os.path.join(CACHE, f"{kind}-{digest}.json")


# `TT_CACHE_ONLY=1` rebuilds the bundle from what `Tools/cache/` already
# holds and asks the network for nothing. That is how a build is finished
# when the public Overpass instance is having a bad day: whatever was
# fetched ships, whatever was not is reported as a gap — never invented.
CACHE_ONLY = os.environ.get("TT_CACHE_ONLY") == "1"


def cached_fetch(kind, key, fetch):
    os.makedirs(CACHE, exist_ok=True)
    path = cache_path(kind, key)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    if CACHE_ONLY:
        raise SourceUnreachable("not in cache and TT_CACHE_ONLY=1")
    payload = fetch()
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
    return payload


def overpass(query, label, tries=3):
    """POST to Overpass, second endpoint on failure, cached by query text."""
    def fetch():
        last = None
        for attempt in range(tries):
            endpoint = OVERPASS_ENDPOINTS[attempt % len(OVERPASS_ENDPOINTS)]
            try:
                request = urllib.request.Request(
                    endpoint,
                    data=urllib.parse.urlencode({"data": query}).encode("utf-8"),
                    headers={"User-Agent": USER_AGENT},
                )
                started = time.time()
                raw = urllib.request.urlopen(request, timeout=600).read()
                payload = json.loads(raw)
                print(f"    {label}: {len(payload.get('elements', []))} elements "
                      f"in {time.time() - started:.0f}s", flush=True)
                time.sleep(5)     # polite: the public instance is a shared box
                return payload
            except Exception as error:                      # noqa: BLE001
                last = error
                print(f"    {label}: attempt {attempt + 1} failed ({error})",
                      file=sys.stderr, flush=True)
                time.sleep(30 * (attempt + 1))
        raise SourceUnreachable(f"Overpass unreachable for {label}: {last}")
    return cached_fetch("overpass", query, fetch)


def sparql(query, label, tries=3):
    def fetch():
        last = None
        for attempt in range(tries):
            try:
                url = WIKIDATA_SPARQL + "?" + urllib.parse.urlencode(
                    {"query": query, "format": "json"})
                request = urllib.request.Request(url, headers={
                    "User-Agent": USER_AGENT,
                    "Accept": "application/sparql-results+json",
                })
                payload = json.load(urllib.request.urlopen(request, timeout=300))
                rows = payload["results"]["bindings"]
                print(f"    {label}: {len(rows)} rows", flush=True)
                time.sleep(2)
                return payload
            except Exception as error:                      # noqa: BLE001
                last = error
                print(f"    {label}: attempt {attempt + 1} failed ({error})",
                      file=sys.stderr, flush=True)
                time.sleep(30 * (attempt + 1))
        raise SourceUnreachable(f"Wikidata unreachable for {label}: {last}")
    return cached_fetch("sparql", query, fetch)


# ----------------------------------------------------------------- geometry


def geohash(lat, lon, precision):
    base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
    lat_range, lon_range = [-90.0, 90.0], [-180.0, 180.0]
    out, bits, value, is_lon = [], 0, 0, True
    while len(out) < precision:
        if is_lon:
            mid = sum(lon_range) / 2
            if lon >= mid:
                value = (value << 1) | 1
                lon_range[0] = mid
            else:
                value <<= 1
                lon_range[1] = mid
        else:
            mid = sum(lat_range) / 2
            if lat >= mid:
                value = (value << 1) | 1
                lat_range[0] = mid
            else:
                value <<= 1
                lat_range[1] = mid
        is_lon = not is_lon
        bits += 1
        if bits == 5:
            out.append(base32[value])
            bits, value = 0, 0
    return "".join(out)


def haversine_km(a_lat, a_lon, b_lat, b_lon):
    r = 6371.0088
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = p2 - p1
    dl = math.radians(b_lon - a_lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def point_in_rings(lat, lon, rings):
    """Ray casting over the atlas's flat [lat, lon, …] rings."""
    inside = False
    for ring in rings:
        n = len(ring) // 2
        j = n - 1
        for i in range(n):
            yi, xi = ring[2 * i], ring[2 * i + 1]
            yj, xj = ring[2 * j], ring[2 * j + 1]
            if (yi > lat) != (yj > lat):
                if lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                    inside = not inside
            j = i
    return inside


class Atlas:
    """`MapRegions.json`, read only for the two things this script needs: the
    ISO 3166-2 id of the region a point falls in, and the bounding boxes that
    make that lookup cheap."""

    def __init__(self, path):
        with open(path, encoding="utf-8") as fh:
            payload = json.load(fh)
        self.regions = payload["regions"]
        self.grid = {}
        for index, region in enumerate(self.regions):
            b = region["b"]
            lat = math.floor(b[0] / 2) * 2
            while lat <= b[2]:
                lon = math.floor(b[1] / 2) * 2
                while lon <= b[3]:
                    self.grid.setdefault((lat, lon), []).append(index)
                    lon += 2
                lat += 2

    def region_id(self, lat, lon):
        cell = (math.floor(lat / 2) * 2, math.floor(lon / 2) * 2)
        for index in self.grid.get(cell, ()):
            region = self.regions[index]
            b = region["b"]
            if not (b[0] <= lat <= b[2] and b[1] <= lon <= b[3]):
                continue
            if point_in_rings(lat, lon, region["r"]):
                return region["id"]
        return None


# -------------------------------------------------------------- collection


def element_point(element):
    if "lat" in element and "lon" in element:
        return element["lat"], element["lon"]
    center = element.get("center")
    if center:
        return center["lat"], center["lon"]
    return None


def element_name(element):
    tags = element.get("tags") or {}
    english = tags.get("name:en")
    if english:
        return english
    local = tags.get("name") or tags.get("name:ru")
    if local:
        return transliterate(local)
    return None


def element_elevation(element):
    tags = element.get("tags") or {}
    raw = tags.get("ele")
    if not raw:
        return None
    match = re.match(r"^\s*(-?\d+(?:\.\d+)?)", str(raw))
    return float(match.group(1)) if match else None


def candidate(kind, lat, lon, name, wikidata=False, ele=None):
    # Rounded HERE, once, and not on the way out: the geohash-7 cell inside
    # the id is computed from this coordinate, and rounding afterwards would
    # let a point sitting on a cell boundary ship an id the app cannot
    # reproduce from the coordinate next to it.
    return {"t": kind, "lat": round(lat, 5), "lon": round(lon, 5), "name": name,
            "wikidata": bool(wikidata), "ele": ele}


def collect_osm_type(kind, selectors, radius):
    """One query per country: the candidates, then the roads near them, then
    the candidates near those roads. Both halves of the reachability test run
    on the server — a client-side one would mean downloading a road network.

    A country that will not answer is recorded as a gap and the rest of the
    world still ships: the public Overpass instance times out under load, and
    one flaky minute must not cost a whole type."""
    found, gaps = [], []
    for code, country in COUNTRIES.items():
        seeds = "".join(f"{s}(area.a);" for s in selectors)
        query = (
            f"[out:json][timeout:180];\n"
            f'area["ISO3166-1"="{code}"][admin_level=2]->.a;\n'
            f"({seeds})->.c;\n"
            f"way{DRIVABLE}(around.c:{radius})->.r;\n"
            f"(node.c(around.r:{radius}); way.c(around.r:{radius}););\n"
            f"out center tags;"
        )
        try:
            payload = overpass(query, f"{kind}/{code} ({country})")
        except SourceUnreachable as error:
            print(f"    GAP {kind}/{code}: {error}", file=sys.stderr)
            gaps.append(f"{kind}/{code}")
            continue
        for element in payload.get("elements", []):
            point = element_point(element)
            if point is None:
                continue
            tags = element.get("tags") or {}
            found.append(candidate(kind, point[0], point[1], element_name(element),
                                   wikidata="wikidata" in tags,
                                   ele=element_elevation(element)))
    if len(gaps) == len(COUNTRIES):
        raise SourceUnreachable(f"every country failed for {kind}")
    GAPS.extend(gaps)
    return found


def long_river_qids():
    """Wikidata QIDs of rivers at least RIVER_MIN_KM long — the filter that
    separates «bridge over the Volga» from «bridge over a ditch with an
    article»."""
    codes = " ".join(f'"{code}"' for code in COUNTRIES)
    query = f"""SELECT ?river WHERE {{
  VALUES ?iso {{ {codes} }}
  ?country wdt:P297 ?iso .
  ?river wdt:P31/wdt:P279* wd:Q4022 ; wdt:P17 ?country ; wdt:P2043 ?length .
  FILTER(?length >= {RIVER_MIN_KM})
}}"""
    payload = sparql(query, f"rivers >= {RIVER_MIN_KM} km")
    return sorted({row["river"]["value"].rsplit("/", 1)[-1]
                   for row in payload["results"]["bindings"]})


def collect_bridges():
    """A named bridge on a major road, within 8 m of a river that Wikidata
    says is long. Bridges need no separate reachability test — they ARE the
    road."""
    qids = long_river_qids()
    if not qids:
        raise SourceUnreachable("no long rivers came back from Wikidata")
    pattern = "^(" + "|".join(qids) + ")$"
    found = []
    for code, country in COUNTRIES.items():
        query = (
            f"[out:json][timeout:180];\n"
            f'area["ISO3166-1"="{code}"][admin_level=2]->.a;\n'
            f'way[waterway=river][wikidata~"{pattern}"](area.a)->.rv;\n'
            f'way[highway~"^(motorway|trunk|primary|secondary)$"][bridge][name]'
            f"(around.rv:8);\n"
            f"out center tags;"
        )
        try:
            payload = overpass(query, f"bridge/{code} ({country})")
        except SourceUnreachable as error:
            print(f"    GAP bridge/{code}: {error}", file=sys.stderr)
            GAPS.append(f"bridge/{code}")
            continue
        for element in payload.get("elements", []):
            point = element_point(element)
            if point is None:
                continue
            found.append(candidate("bridge", point[0], point[1], element_name(element),
                                   wikidata="wikidata" in (element.get("tags") or {})))
    return found


def collect_sea_roads():
    """«The road runs into the sea»: a drivable way with an end node on the
    shore and nothing continuing from it.

    Two queries per country, because a dead end is not a tag. The first pulls
    the drivable ways whose geometry touches the coastline (60 m — a road that
    ends AT the water, not one that runs along it); the second asks how many
    ways share each of their end nodes, and only degree-1 nodes survive.
    Without that second pass every road cut off by the download radius would
    look like a dead end."""
    found = []
    for code, country in COUNTRIES.items():
        query = (
            f"[out:json][timeout:180];\n"
            f'area["ISO3166-1"="{code}"][admin_level=2]->.a;\n'
            f"way[natural=coastline](area.a)->.sea;\n"
            f'way[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|'
            f'residential)$"][access!~"^(private|no)$"](around.sea:60);\n'
            f"out ids geom tags;"
        )
        try:
            payload = overpass(query, f"searoad/{code} ({country})")
        except SourceUnreachable as error:
            print(f"    GAP seaRoad/{code}: {error}", file=sys.stderr)
            GAPS.append(f"seaRoad/{code}")
            continue
        ends = {}          # node id → (lat, lon, way name)
        for element in payload.get("elements", []):
            nodes = element.get("nodes") or []
            geometry = element.get("geometry") or []
            if len(nodes) < 2 or len(geometry) != len(nodes):
                continue
            name = element_name(element)
            for index in (0, len(nodes) - 1):
                ends[nodes[index]] = (geometry[index]["lat"], geometry[index]["lon"], name)
        if not ends:
            continue
        # Degree check, 400 node ids at a time.
        ids = sorted(ends)
        degree = {}
        for start in range(0, len(ids), 400):
            chunk = ids[start:start + 400]
            listed = ",".join(str(i) for i in chunk)
            query = (
                f"[out:json][timeout:180];\n"
                f"node(id:{listed})->.n;\n"
                f"way[highway](bn.n);\n"
                f"out ids;"
            )
            try:
                payload = overpass(query, f"searoad-degree/{code} {start // 400 + 1}")
            except SourceUnreachable as error:
                print(f"    GAP seaRoad-degree/{code}: {error}", file=sys.stderr)
                GAPS.append(f"seaRoad-degree/{code}")
                continue
            wanted = set(chunk)
            for element in payload.get("elements", []):
                for node_id in element.get("nodes") or []:
                    if node_id in wanted:
                        degree[node_id] = degree.get(node_id, 0) + 1
        for node_id, (lat, lon, name) in ends.items():
            if degree.get(node_id, 0) == 1:
                found.append(candidate("seaRoad", lat, lon, name))
    return found


def parse_point(literal):
    """`Point(lon lat)` → (lat, lon)."""
    match = re.match(r"^Point\((-?[\d.]+) (-?[\d.]+)\)$", literal)
    if not match:
        return None
    return float(match.group(2)), float(match.group(1))


EXTREME_WORD = {"P1332": "northernmost point", "P1333": "southernmost point",
                "P1334": "easternmost point", "P1335": "westernmost point"}


def collect_extremes():
    """P1332…P1335 carry a coordinate value directly, on countries and on the
    admin-1 units that bother to state one."""
    codes = " ".join(f'"{code}"' for code in COUNTRIES)
    query = f"""SELECT ?placeLabel ?iso ?p ?coord WHERE {{
  VALUES ?iso {{ {codes} }}
  VALUES ?p {{ wdt:P1332 wdt:P1333 wdt:P1334 wdt:P1335 }}
  ?place wdt:P297 ?iso ; ?p ?coord .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}"""
    payload = sparql(query, "extreme points")
    found = []
    for row in payload["results"]["bindings"]:
        point = parse_point(row["coord"]["value"])
        if point is None:
            continue
        word = EXTREME_WORD.get(row["p"]["value"].rsplit("/", 1)[-1], "extreme point")
        label = row.get("placeLabel", {}).get("value") or COUNTRIES[row["iso"]["value"]]
        found.append(candidate("extreme", point[0], point[1],
                               f"{label} — {word}", wikidata=True))
    return found


def collect_centres():
    """Two kinds of «centre»: an item that IS one (Q590232 and its subclasses)
    and a country that merely states its own (P5140)."""
    found = []
    query = """SELECT ?xLabel ?coord WHERE {
  ?x wdt:P31/wdt:P279* wd:Q590232 ; wdt:P625 ?coord .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}"""
    payload = sparql(query, "geographic centres (items)")
    for row in payload["results"]["bindings"]:
        point = parse_point(row["coord"]["value"])
        if point:
            found.append(candidate("centre", point[0], point[1],
                                   row["xLabel"]["value"], wikidata=True))
    codes = " ".join(f'"{code}"' for code in COUNTRIES)
    query = f"""SELECT ?placeLabel ?coord WHERE {{
  VALUES ?iso {{ {codes} }}
  ?place wdt:P297 ?iso ; wdt:P5140 ?coord .
  SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
}}"""
    payload = sparql(query, "geographic centres (countries)")
    for row in payload["results"]["bindings"]:
        point = parse_point(row["coord"]["value"])
        if point:
            found.append(candidate("centre", point[0], point[1],
                                   f"{row['placeLabel']['value']} — geographic centre",
                                   wikidata=True))
    return found


def collect_tripoints():
    query = """SELECT ?xLabel ?coord WHERE {
  ?x wdt:P31/wdt:P279* wd:Q316655 ; wdt:P625 ?coord .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}"""
    payload = sparql(query, "tripoints")
    found = []
    for row in payload["results"]["bindings"]:
        point = parse_point(row["coord"]["value"])
        if point:
            found.append(candidate("tripoint", point[0], point[1],
                                   row["xLabel"]["value"], wikidata=True))
    return found


def keep_reachable(points):
    """Wikidata points have had no road test yet — one tiny Overpass query
    each, asking only whether a drivable way exists within 300 m."""
    kept = []
    for index, point in enumerate(points):
        query = (
            f"[out:json][timeout:60];\n"
            f"way{DRIVABLE}(around:{ROAD_RADIUS},{point['lat']:.6f},{point['lon']:.6f});\n"
            f"out ids 1;"
        )
        try:
            payload = overpass(query, f"reach {point['t']} {index + 1}/{len(points)}")
        except SourceUnreachable as error:
            print(f"    GAP reach/{point['t']}: {error}", file=sys.stderr)
            GAPS.append(f"reach/{point['t']}")
            continue
        if payload.get("elements"):
            kept.append(point)
    return kept


# ------------------------------------------------------------ post-process


def rank_key(point, high_elevation):
    """`wikidata` present, then `ele` in the type's upper quartile, then the
    rest — the significance proxy the plan spells out. Named before nameless
    inside a tier: a riddle whose card would read «—» is worth less."""
    tier = 0 if point["wikidata"] else (1 if (point["ele"] or -1e9) >= high_elevation else 2)
    return (tier, 0 if point["name"] else 1, -(point["ele"] or 0))


def upper_quartile(values):
    if not values:
        return float("inf")
    ordered = sorted(values)
    return ordered[int(len(ordered) * 0.75)] if len(ordered) > 3 else ordered[-1]


def thin(points, kind):
    """geohash-7 dedup, then the 50 km density cap, both over the ranked list
    so the survivor of a collision is always the more significant point."""
    cutoff = upper_quartile([p["ele"] for p in points if p["ele"] is not None])
    ordered = sorted(points, key=lambda p: rank_key(p, cutoff))
    seen_cells, kept, grid = set(), [], {}
    dropped_cell = dropped_dense = 0
    for point in ordered:
        cell = geohash(point["lat"], point["lon"], DEDUP_PRECISION)
        if cell in seen_cells:
            dropped_cell += 1
            continue
        seen_cells.add(cell)
        # 0.5° buckets: 50 km never reaches past the neighbouring bucket.
        key = (math.floor(point["lat"] * 2), math.floor(point["lon"] * 2))
        crowded = False
        for dy in (-2, -1, 0, 1, 2):
            for dx in (-2, -1, 0, 1, 2):
                for other in grid.get((key[0] + dy, key[1] + dx), ()):
                    if haversine_km(point["lat"], point["lon"],
                                    other["lat"], other["lon"]) < DENSITY_KM:
                        crowded = True
                        break
                if crowded:
                    break
            if crowded:
                break
        if crowded:
            dropped_dense += 1
            continue
        grid.setdefault(key, []).append(point)
        point["cell"] = cell
        # Rank position inside its own type, kept for `fit_budget`: by the time
        # the payload is built the list is sorted by id, and without this the
        # budget trim would cut by geohash alphabet instead of significance.
        point["rank"] = len(kept)
        kept.append(point)
    print(f"  {kind:11} {len(points):6} raw → {len(kept):5} kept "
          f"(same cell: {dropped_cell}, too close: {dropped_dense})")
    return kept


def build_payload(points, atlas, missing):
    """The bundle itself plus the rank of every riddle inside its type.

    Two return values on purpose: the file is sorted by `id` (so a diff between
    two builds is readable), and after that sort nothing in it remembers which
    point was the significant one — which is exactly what the budget trim needs.
    """
    riddles, ranks = [], {}
    for point in points:
        rid = f"{point['t']}:{point['cell']}"
        riddles.append({
            "id": rid,
            "t": point["t"],
            "c": [point["lat"], point["lon"]],
            "n": point["name"] or "",
            "r": atlas.region_id(point["lat"], point["lon"]),
        })
        ranks[rid] = point.get("rank", 0)
    riddles.sort(key=lambda r: r["id"])
    return {
        "v": 1,
        "generated": time.strftime("%Y-%m-%d"),
        "license": "ODbL (OSM) + CC0 (Wikidata)",
        "missing": missing,
        "gaps": sorted(set(GAPS)),
        "riddles": riddles,
    }, ranks


def trim_by_rank(riddles, kind, limit, ranks):
    """Keep the `limit` most significant riddles of `kind`, drop the rest.

    Significance is the rank `thin` gave the point (`wikidata` > `ele` upper
    quartile > the rest), NOT the position in the file: the payload is sorted by
    id long before the budget is measured, so «drop the tail» would mean «drop
    the geohashes late in the alphabet» — a silent, invisible-in-review bias.

    >>> rs = [{"id": "pass:c", "t": "pass"}, {"id": "pass:a", "t": "pass"},
    ...       {"id": "dam:b", "t": "dam"}]
    >>> ranks = {"pass:c": 0, "pass:a": 1, "dam:b": 0}
    >>> [r["id"] for r in trim_by_rank(rs, "pass", 1, ranks)]
    ['pass:c', 'dam:b']
    >>> [r["id"] for r in trim_by_rank(rs, "pass", 0, ranks)]
    ['dam:b']
    >>> [r["id"] for r in trim_by_rank(rs, "ferry", 0, ranks)]
    ['pass:c', 'pass:a', 'dam:b']
    """
    ofkind = sorted((r for r in riddles if r["t"] == kind),
                    key=lambda r: ranks.get(r["id"], 0))
    doomed = {r["id"] for r in ofkind[limit:]}
    return [r for r in riddles if r["id"] not in doomed]


def fit_budget(payload, ranks):
    """400 KB is the ceiling. Over it, the biggest type loses its LEAST
    SIGNIFICANT points — see `trim_by_rank` for why that is not the same as its
    tail."""
    while True:
        blob = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        if len(blob.encode("utf-8")) <= MAX_BYTES:
            return blob
        counts = {}
        for riddle in payload["riddles"]:
            counts[riddle["t"]] = counts.get(riddle["t"], 0) + 1
        fattest = max(counts, key=lambda k: counts[k])
        limit = int(counts[fattest] * 0.9)
        print(f"  over budget: trimmed {fattest} to {limit}")
        payload["riddles"] = trim_by_rank(payload["riddles"], fattest, limit, ranks)


def note_empty_types(missing, produced):
    """Every requested type that yielded nothing ends up in `missing` — not only
    the ones whose source threw.

    `collect_sea_roads` and `keep_reachable` answer `[]` when every query comes
    back empty instead of raising `SourceUnreachable`, so in the first build
    `seaRoad` and `extreme` were absent from the bundle AND absent from its list
    of absences. «A silent hole is worse than a missing type» is this script's
    own rule; this is where it is enforced.

    >>> note_empty_types(["dam"], {"pass": 12, "dam": 0, "seaRoad": 0})
    ['dam', 'seaRoad']
    >>> note_empty_types([], {"pass": 1})
    []
    """
    out = list(missing)
    for kind in produced:
        if produced[kind] == 0 and kind not in out:
            out.append(kind)
    return out


# ------------------------------------------------------- authored secrets


# Сторона ячейки geohash-7 в градусах — ОДНА И ТА ЖЕ по обеим осям: 35 бит
# делятся на 18 бит долготы (360 / 2**18) и 17 бит широты (180 / 2**17), и оба
# выражения дают одно число. То же `CELL_DEG`, что у бэкендового
# `tools/secret-cells.ts`; разошедшись, две копии дали бы разные покрытия
# одного полигона, а заметить это можно было бы только на телефоне.
CELL_DEG = 180 / 2 ** 17
METERS_PER_DEG_LAT = 111320


def geohash_center(cell):
    """Центр ячейки. Обратная `geohash()`, тем же обходом битов."""
    base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
    lat_range, lon_range = [-90.0, 90.0], [-180.0, 180.0]
    is_lon = True
    for char in cell:
        value = base32.index(char)
        for shift in range(4, -1, -1):
            bit = (value >> shift) & 1
            target = lon_range if is_lon else lat_range
            mid = sum(target) / 2
            if bit:
                target[0] = mid
            else:
                target[1] = mid
            is_lon = not is_lon
    return sum(lat_range) / 2, sum(lon_range) / 2


def polygon_rings(geojson):
    """GeoJSON → список колец [[lon, lat], …]; первое кольцо каждого полигона
    внешнее, остальные — дырки. Понимает Polygon/MultiPolygon/Feature/
    FeatureCollection, как и бэкендовый `loadPolygonGeometry`."""
    kind = geojson.get("type")
    if kind == "FeatureCollection":
        out = []
        for feature in geojson.get("features", []):
            out.extend(polygon_rings(feature))
        return out
    if kind == "Feature":
        return polygon_rings(geojson.get("geometry") or {})
    if kind == "Polygon":
        return [geojson["coordinates"]]
    if kind == "MultiPolygon":
        return list(geojson["coordinates"])
    raise SystemExit(f"authored: не GeoJSON с полигоном (type={kind!r})")


def inside_ring(lon, lat, ring):
    """Чётно-нечётное правило; кольцо в порядке GeoJSON — [долгота, широта]."""
    inside = False
    count = len(ring)
    j = count - 1
    for i in range(count):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lon < x_cross:
                inside = not inside
        j = i
    return inside


def inside_polygons(lon, lat, polygons):
    for rings in polygons:
        if not rings:
            continue
        if not inside_ring(lon, lat, rings[0]):
            continue
        if any(inside_ring(lon, lat, hole) for hole in rings[1:]):
            continue
        return True
    return False


def cells_covering_polygon(polygons):
    """Ячейки geohash-7, ЦЕНТР которых лежит внутри полигона.

    Ровно то же правило, что у бэкендового `cellsCoveringPolygon` без буфера:
    сервер проверяет трек по своему списку ячеек, телефон — по хешам этого,
    и списки обязаны совпадать до ячейки. Сетка кандидатов идёт шагом в
    сторону ячейки с запасом в одну по краю — тогда соседние пробы попадают в
    соседние ячейки без пропусков.
    """
    lats = [point[1] for rings in polygons for ring in rings for point in ring]
    lons = [point[0] for rings in polygons for ring in rings for point in ring]
    lat_from, lat_to = min(lats) - CELL_DEG, max(lats) + CELL_DEG
    lon_from, lon_to = min(lons) - CELL_DEG, max(lons) + CELL_DEG

    cells = set()
    lat_steps = int(math.ceil((lat_to - lat_from) / CELL_DEG)) + 1
    lon_steps = int(math.ceil((lon_to - lon_from) / CELL_DEG)) + 1
    if lat_steps * lon_steps > 500_000:
        raise SystemExit("authored: полигон слишком велик для покрытия ячейками")
    for i in range(lat_steps + 1):
        lat = min(lat_to, lat_from + i * CELL_DEG)
        for j in range(lon_steps + 1):
            lon = min(lon_to, lon_from + j * CELL_DEG)
            cells.add(geohash(lat, lon, 7))

    covered = set()
    for cell in cells:
        c_lat, c_lon = geohash_center(cell)
        if inside_polygons(c_lon, c_lat, polygons):
            covered.add(cell)
    return sorted(covered)


def cells_within_reach(lat, lon, reach_m):
    """Ячейка точки плюс те, чей центр не дальше `reach_m` — точечный секрет.

    Своя ячейка входит всегда, даже если её центр дальше: точка у самого края
    не должна остаться без ячейки, в которой она физически стоит.
    """
    covered = {geohash(lat, lon, 7)}
    if reach_m <= 0:
        return sorted(covered)
    lat_radius = reach_m / METERS_PER_DEG_LAT
    lon_radius = reach_m / max(METERS_PER_DEG_LAT * math.cos(math.radians(lat)), 1e-6)
    steps_lat = int(math.ceil(lat_radius / CELL_DEG)) + 1
    steps_lon = int(math.ceil(lon_radius / CELL_DEG)) + 1
    for i in range(-steps_lat, steps_lat + 1):
        for j in range(-steps_lon, steps_lon + 1):
            cell = geohash(lat + i * CELL_DEG, lon + j * CELL_DEG, 7)
            c_lat, c_lon = geohash_center(cell)
            if haversine_km(lat, lon, c_lat, c_lon) * 1000 <= reach_m:
                covered.add(cell)
    return sorted(covered)


def secret_hash(salt, cell):
    """Первые ЧЕТЫРЕ байта SHA-256(соль ‖ ячейка), big-endian.

    Одна арифметика с iOS `SecretHash.truncated` и с серверным
    `secret-hash.util.ts`. Разойдясь на байт, они дали бы секрет, который
    физически нельзя найти, — и ни один тест на телефоне этого не увидел бы.
    """
    digest = hashlib.sha256((salt + cell).encode("utf-8")).digest()
    value = 0
    for byte in digest[:4]:
        value = (value << 8) | byte
    return value


def build_authored(path):
    """`authored.json` → `TripTrack/Resources/Secrets.json`.

    В бандл уезжают ТОЛЬКО усечённые хеши: ни координаты, ни названия, ни
    истории. Полигон-исходник остаётся здесь, в `Tools/` (см. `Tools/README`),
    и в приложение не копируется — иначе список авторских секретов читался бы
    прямо из бандла, а вся ветка «найди сам» превратилась бы в список
    координат.
    """
    with open(path, encoding="utf-8") as fh:
        authored = json.load(fh)
    salt = authored["salt"]

    records = []
    for entry in authored["secrets"]:
        if "polygon" in entry:
            geo_path = os.path.join(os.path.dirname(os.path.abspath(path)), entry["polygon"])
            with open(geo_path, encoding="utf-8") as fh:
                cells = cells_covering_polygon(polygon_rings(json.load(fh)))
            polygon = True
        else:
            lat, lon = entry["point"]
            cells = cells_within_reach(lat, lon, float(entry.get("reach", 0)))
            polygon = False
        if not cells:
            raise SystemExit(f"authored: секрет {entry['id']} не покрыл ни одной ячейки")
        hashes = sorted({secret_hash(salt, cell) for cell in cells})
        print(f"  {entry['id']:16} cells={len(cells):5} hashes={len(hashes):5} polygon={polygon}")
        records.append({
            "id": entry["id"],
            "hashes": hashes,
            "reach": float(entry.get("reach", 0)),
            "symbol": entry["symbol"],
            "polygon": polygon,
        })

    payload = {"v": 1, "salt": salt, "secrets": records}
    out_path = os.path.normpath(SECRETS)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")
    print(f"{out_path}  {os.path.getsize(out_path) / 1024:.1f} KB")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--types", default="", help="comma-separated subset to build")
    parser.add_argument("--authored", nargs="?", const=AUTHORED, default=None,
                        help="build TripTrack/Resources/Secrets.json from authored.json "
                             "(hashes only — no coordinates leave Tools/) and exit")
    args = parser.parse_args()

    if args.authored:
        build_authored(os.path.normpath(args.authored))
        return

    wanted = set(filter(None, args.types.split(","))) or None

    atlas = Atlas(os.path.normpath(ATLAS))
    print(f"atlas: {len(atlas.regions)} regions")

    collectors = {}
    for kind, (selectors, radius) in OSM_TYPES.items():
        collectors[kind] = (lambda s=selectors, r=radius, k=kind:
                            collect_osm_type(k, s, r))
    collectors["bridge"] = collect_bridges
    collectors["seaRoad"] = collect_sea_roads
    collectors["extreme"] = lambda: keep_reachable(collect_extremes())
    collectors["centre"] = lambda: keep_reachable(collect_centres())
    collectors["tripoint"] = lambda: keep_reachable(collect_tripoints())

    kept, missing, produced = [], [], {}
    for kind, collect in collectors.items():
        if wanted and kind not in wanted:
            continue
        print(f"== {kind}", flush=True)
        produced.setdefault(kind, 0)
        try:
            raw = collect()
        except SourceUnreachable as error:
            print(f"  DROPPED: {error}", file=sys.stderr)
            missing.append(kind)
            continue
        survivors = thin(raw, kind)
        produced[kind] = len(survivors)
        kept.extend(survivors)

    missing = note_empty_types(missing, produced)
    payload, ranks = build_payload(kept, atlas, missing)
    blob = fit_budget(payload, ranks)
    out_path = os.path.join(HERE, "riddles.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(blob)

    by_type = {}
    for riddle in payload["riddles"]:
        by_type[riddle["t"]] = by_type.get(riddle["t"], 0) + 1
    print("\nriddles per type:")
    for kind in sorted(by_type):
        print(f"  {kind:11} {by_type[kind]}")
    unplaced = sum(1 for r in payload["riddles"] if not r["r"])
    print(f"total={len(payload['riddles'])}  outside any atlas region={unplaced}")
    if missing:
        print("MISSING TYPES (source unreachable or silent, nothing invented): "
              + ", ".join(missing))
    if GAPS:
        print("gaps (country/type pairs the source would not answer): "
              + ", ".join(sorted(set(GAPS))))
    print(f"{out_path}  {os.path.getsize(out_path) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
