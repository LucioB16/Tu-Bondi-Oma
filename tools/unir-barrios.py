import json

def point_in_ring(lon, lat, ring):
    inside = False
    n = len(ring)
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if ((yi > lat) != (yj > lat)) and (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside

def in_geom(lon, lat, geom):
    t = geom['type']
    if t == 'Polygon':
        if not point_in_ring(lon, lat, geom['coordinates'][0]):
            return False
        for hole in geom['coordinates'][1:]:
            if point_in_ring(lon, lat, hole):
                return False
        return True
    elif t == 'MultiPolygon':
        for poly in geom['coordinates']:
            if not point_in_ring(lon, lat, poly[0]):
                continue
            hole_hit = any(point_in_ring(lon, lat, hole) for hole in poly[1:])
            if not hole_hit:
                return True
        return False
    return False

barrios = json.load(open('/tmp/barrios.geojson'))['features']
# bbox prefilter
prepped = []
for f in barrios:
    name = f['properties']['Nombre']
    coords = []
    def walk(g):
        if isinstance(g[0], (int, float)):
            coords.append(g)
        else:
            for part in g:
                walk(part)
    walk(f['geometry']['coordinates'])
    lons = [c[0] for c in coords]; lats = [c[1] for c in coords]
    prepped.append((name, (min(lons), min(lats), max(lons), max(lats)), f['geometry']))

route = json.load(open("/tmp/route.json"))
print("route type:", type(route))
print("keys:", list(route.keys()) if isinstance(route, dict) else len(route))
from collections import defaultdict
by_barrio = defaultdict(list)
unmatched = []
for p in route['paradas']:
    lon = float(p['lon']); lat = float(p['lat'])
    found = None
    for name, (x0, y0, x1, y1), geom in prepped:
        if not (x0 <= lon <= x1 and y0 <= lat <= y1):
            continue
        if in_geom(lon, lat, geom):
            found = name
            break
    if found:
        by_barrio[found].append(p)
    else:
        unmatched.append(p['codigo'])

print('matched barrios:', len(by_barrio))
for b in sorted(by_barrio):
    print(f'{b}: {len(by_barrio[b])} paradas, ej: {by_barrio[b][0]["codigo"]} {by_barrio[b][0]["parada_nombre"]}')
print('unmatched:', unmatched)
json.dump({b: [{'code': p['codigo'], 'name': p['parada_nombre']} for p in ps] for b, ps in by_barrio.items()},
          open('/tmp/seed_catalog.json', 'w'), ensure_ascii=False, indent=1)
