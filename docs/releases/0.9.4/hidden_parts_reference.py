"""Reference semantics of hidden parts (0.9.4). Generates hidden-parts-vectors.json; iOS, Android and the backend
test against the same numbers. Plain haversine on clean synthetic tracks, so the odometer rules (5 m step, accuracy
gates) agree with it exactly; the apps must use their own odometer (`TripDistanceGate`) in production."""
import json, math, pathlib

R = 6371000.0
def hav(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

SLIVER_METRES = 100.0
PHOTO_NEAR_METRES = 150.0

def prefix(points, breaks):
    """Cumulative distance; nothing is counted across a recording break (a point at or after a break starts a run)."""
    d, out, seg = 0.0, [0.0], segments(points, breaks)
    for i in range(1, len(points)):
        if seg[i] == seg[i - 1]:
            d += hav(points[i]['c'], points[i - 1]['c'])
        out.append(d)
    return out

def segments(points, breaks):
    return [sum(1 for b in breaks if p['t'] >= b) for p in points]

def resolve(points, breaks, start_m, end_m, sections, zone):
    """-> hidden flags per point. start_m/end_m: 0 = none. sections: [[from_t, to_t]] inclusive. zone: None or
    {'c': [lat, lon], 'r': metres} (strictly inside is hidden, as `PrivacyZone`)."""
    n = len(points)
    d = prefix(points, breaks)
    total = d[-1] if n else 0.0
    hidden = [False] * n
    for i, p in enumerate(points):
        if start_m > 0 and d[i] < start_m: hidden[i] = True
        if end_m > 0 and total - d[i] < end_m: hidden[i] = True
        if any(f <= p['t'] <= t for f, t in sections): hidden[i] = True
        if zone and hav(p['c'], zone['c']) < zone['r']: hidden[i] = True
    seg = segments(points, breaks)
    # Visible runs split at recording breaks; a run under 2 points, or under 100 m with hidden on both sides, is hidden.
    changed = True
    while changed:
        changed = False
        for a, b in runs(hidden, seg, visible=True):
            left = a > 0 and hidden[a - 1]
            right = b < n - 1 and hidden[b + 1]
            if (b - a + 1) < 2 or (left and right and d[b] - d[a] < SLIVER_METRES):
                for i in range(a, b + 1): hidden[i] = True
                changed = True
    return hidden

def runs(hidden, seg, visible):
    out, i, n = [], 0, len(hidden)
    while i < n:
        if (not hidden[i]) == visible:
            j = i
            while j + 1 < n and (not hidden[j + 1]) == visible and (not visible or seg[j + 1] == seg[i]):
                j += 1
            out.append((i, j)); i = j + 1
        else:
            i += 1
    return out

def hidden_ranges(points, hidden):
    seg = [0] * len(points)
    return [[points[a]['t'], points[b]['t']] for a, b in runs(hidden, seg, visible=False)]

def visible_runs(points, hidden, breaks):
    return [[a, b] for a, b in runs(hidden, segments(points, breaks), visible=True)]

def preview(points, hidden, breaks):
    """The uploaded preview: visible runs one after another; previewBreaks = index where each run after the first starts."""
    coords, brk = [], []
    for k, (a, b) in enumerate(visible_runs(points, hidden, breaks)):
        if k: brk.append(len(coords))
        coords += [points[i]['c'] for i in range(a, b + 1)]
    return coords, brk

def public_numbers(points, hidden, breaks):
    d = prefix(points, breaks)
    vr = visible_runs(points, hidden, breaks)
    if not vr: return {'distance': 0.0, 'start': None, 'end': None}
    return {'distance': round(sum(d[b] - d[a] for a, b in vr), 1), 'start': points[vr[0][0]]['t'], 'end': points[vr[-1][1]]['t']}

def photo_hidden(photo, points, hidden, ranges, zone):
    if photo.get('capturedAt') is not None:
        return any(f <= photo['capturedAt'] <= t for f, t in ranges)
    c = photo.get('coordinate')
    if c is None: return False
    if zone and hav(c, zone['c']) < zone['r']: return True
    return any(hidden[i] and hav(c, p['c']) <= PHOTO_NEAR_METRES for i, p in enumerate(points))

# Synthetic track: due east from (45.0, 39.0), one point every 10 s and ~10 m, 3 km long (301 points).
def track(n=301, step_m=10.0):
    lon_step = step_m / (R * math.cos(math.radians(45.0)) * math.pi / 180)
    return [{'t': i * 10, 'c': [45.0, round(39.0 + i * lon_step, 7)]} for i in range(n)]

CASES = [
 # Thresholds sit between points on purpose: a tie at a point would let float rounding pick a side differently on each platform.
 ('start-505', dict(start_m=505, end_m=0, sections=[], zone=None, breaks=[])),
 ('end-705', dict(start_m=0, end_m=705, sections=[], zone=None, breaks=[])),
 ('both-and-middle', dict(start_m=205, end_m=305, sections=[[1200, 1500]], zone=None, breaks=[])),
 ('overlapping-sections', dict(start_m=0, end_m=0, sections=[[500, 900], [800, 1100]], zone=None, breaks=[])),
 ('sliver-between', dict(start_m=0, end_m=0, sections=[[1000, 1200], [1270, 1500]], zone=None, breaks=[])),
 ('everything-hidden', dict(start_m=1605, end_m=1605, sections=[], zone=None, breaks=[])),
 ('zone-and-start', dict(start_m=205, end_m=0, sections=[], zone={'c': [45.0, 39.0], 'r': 305}, breaks=[])),
 ('recording-break', dict(start_m=0, end_m=505, sections=[], zone=None, breaks=[1505])),
 ('no-mask', dict(start_m=0, end_m=0, sections=[], zone=None, breaks=[])),
]
PHOTOS = [
 {'id': 'p-start-time', 'capturedAt': 20},
 {'id': 'p-middle-time', 'capturedAt': 1300},
 {'id': 'p-visible-time', 'capturedAt': 2000},
 {'id': 'p-no-time-near-start', 'coordinate': [45.0005, 39.0003]},
 {'id': 'p-no-time-far', 'coordinate': [45.02, 39.02]},
 {'id': 'p-nothing'},
]

def main():
    pts = track()
    out = {'about': 'Hidden parts 0.9.4 reference vectors; see hidden-parts-spec.md. Times are seconds from the trip start.',
           'points': pts, 'photos': PHOTOS, 'sliverMetres': SLIVER_METRES, 'photoNearMetres': PHOTO_NEAR_METRES, 'cases': []}
    for name, c in CASES:
        h = resolve(pts, c['breaks'], c['start_m'], c['end_m'], c['sections'], c['zone'])
        rng = hidden_ranges(pts, h)
        coords, brk = preview(pts, h, c['breaks'])
        out['cases'].append({
            'name': name, 'input': {'startMetres': c['start_m'], 'endMetres': c['end_m'], 'sections': c['sections'], 'zone': c['zone'], 'recordingBreaks': c['breaks']},
            'expect': {'hiddenRanges': rng, 'visibleRuns': visible_runs(pts, h, c['breaks']), 'previewPointCount': len(coords),
                       'previewBreaks': brk, 'publicNumbers': public_numbers(pts, h, c['breaks']),
                       'hiddenPhotoIds': [p['id'] for p in PHOTOS if photo_hidden(p, pts, h, rng, c['zone'])]}})
    path = pathlib.Path(__file__).with_name('hidden-parts-vectors.json')
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    for c in out['cases']: print(c['name'], c['expect']['hiddenRanges'], c['expect']['visibleRuns'], c['expect']['previewBreaks'], c['expect']['publicNumbers'], c['expect']['hiddenPhotoIds'])

if __name__ == '__main__':
    main()
