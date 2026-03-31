# Road Coverage: Server Architecture Plan

## Problem

Current territory exploration uses geohash-6 grid (~1.2 km x 0.6 km tiles). This gives a rough "fog of war" metric but doesn't track actual road coverage — which streets were driven and which remain.

MapKit has no API to access road network data. Apps like Wandrer.earth and CityStrides solve this with OpenStreetMap (OSM) data processed server-side.

## Target Architecture

```
┌─────────────┐       ┌──────────────────┐       ┌───────────────┐
│  TripTrack   │──────▶│   TripTrack API   │──────▶│    PostGIS    │
│   (iOS)      │◀──────│  (FastAPI / Go)   │◀──────│  (PostgreSQL) │
└─────────────┘       └──────────────────┘       └───────────────┘
                              │      ▲
                              ▼      │
                       ┌──────────────────┐
                       │  Overpass API     │
                       │  (OpenStreetMap)  │
                       └──────────────────┘
```

## Server Responsibilities

### 1. Road Data Ingestion
- Query Overpass API for all `highway=*` ways within a city/region bounding box
- Filter by relevant road types: `primary`, `secondary`, `tertiary`, `residential`, `trunk`, `motorway`, `unclassified`, `living_street`
- Store road geometries (LineString) in PostGIS with spatial indexes
- Periodic refresh (OSM updates weekly)

Example Overpass query:
```
[out:json][timeout:30];
area[name="Краснодар"]->.city;
way(area.city)["highway"~"primary|secondary|tertiary|residential|trunk|motorway"];
out geom;
```

### 2. Map-Matching
- Receive GPS track from client (array of lat/lon/timestamp)
- For each GPS point, find nearest OSM road segment within 30m (`ST_DWithin`)
- Mark matched road segments as "driven" for that user
- Return: list of matched road IDs, coverage stats

Options:
- **Simple:** PostGIS `ST_DWithin` + `ST_Distance` (good enough for car GPS)
- **Advanced:** Valhalla Meili (open source, Hidden Markov Model map-matching — handles GPS noise, tunnels, parallel roads)

### 3. Coverage API
- `GET /coverage/{city}` → total roads, driven roads, percentage, per-road-type breakdown
- `GET /coverage/{city}/geojson` → GeoJSON of driven/undriven roads for map rendering
- `POST /trips/{trip_id}/match` → submit GPS track, get matched roads back

## Data Estimates

| City       | Road segments | Raw data  |
|------------|--------------|-----------|
| Krasnodar  | ~15-20K      | ~10-15 MB |
| Moscow     | ~200-300K    | ~100-150 MB |
| All Russia | ~millions    | ~20 GB    |

Strategy: load cities on demand as users request them. Cache indefinitely, refresh monthly.

## Client Changes (TripTrack iOS)

Minimal changes needed:
- After trip completion, send track points to server
- Receive coverage data back, store locally for offline display
- RegionsView/ExplorationView: replace geohash-based city % with server-provided road %
- Add road overlay to ScratchMapView (driven = colored, undriven = gray)
- Fallback to current geohash system when offline or server unavailable

## Tech Stack

- **Database:** PostgreSQL + PostGIS extension
- **API:** Python (FastAPI) or Go — lightweight, stateless
- **Map-matching:** Start with PostGIS spatial queries, upgrade to Valhalla if needed
- **Hosting:** Single VPS is enough for initial scale (personal use + small user base)
- **Data source:** Overpass API (free, public) → cache in PostGIS

## Migration Path

1. **Phase 0 (current):** Geohash-6 grid, all on device
2. **Phase 1:** Server with road data for top cities. Client sends tracks, receives road coverage. Geohash system remains as fallback.
3. **Phase 2:** On-demand city loading, GeoJSON overlays on map, per-street detail view
4. **Phase 3:** Social features (leaderboards, city completion rankings)

## References

- [Overpass API docs](https://wiki.openstreetmap.org/wiki/Overpass_API)
- [Wandrer.earth](https://wandrer.earth) — reference implementation (Strava-connected)
- [CityStrides](https://citystrides.com) — street-level completion tracking
- [Valhalla Meili](https://github.com/valhalla/valhalla) — open source map-matching
- [PostGIS ST_DWithin](https://postgis.net/docs/ST_DWithin.html) — spatial proximity query
