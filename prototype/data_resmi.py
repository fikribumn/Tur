"""Pencarian titik pada layer resmi Badan Geologi (data/resmi/*.geojson). Hanya pustaka standar."""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "resmi")
_cache = {}


def _muat(nama):
    if nama not in _cache:
        with open(os.path.join(DIR, nama + ".geojson"), encoding="utf-8") as f:
            fitur = json.load(f)["features"]
        for ft in fitur:
            g = ft.get("geometry")
            if not g:
                ft["_poly"] = []
                continue
            polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]] if g["type"] == "Polygon" else []
            ft["_poly"] = [(p, _bbox(p[0])) for p in polys]
            ft["_garis"] = g["coordinates"] if g["type"] == "LineString" else \
                g["coordinates"] if g["type"] == "MultiLineString" else None
            ft["_tipe"] = g["type"]
        _cache[nama] = fitur
    return _cache[nama]


def _bbox(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def _dalam_ring(x, y, ring):
    masuk = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            masuk = not masuk
        j = i
    return masuk


def _dalam_poligon(x, y, poly, bb):
    if not (bb[0] <= x <= bb[2] and bb[1] <= y <= bb[3]):
        return False
    if not _dalam_ring(x, y, poly[0]):
        return False
    return not any(_dalam_ring(x, y, lubang) for lubang in poly[1:])


def cari(nama, lon, lat):
    """Semua fitur layer yang memuat titik, dari yang bboxnya paling kecil (paling spesifik)."""
    hasil = []
    for ft in _muat(nama):
        for poly, bb in ft["_poly"]:
            if _dalam_poligon(lon, lat, poly, bb):
                hasil.append(((bb[2] - bb[0]) * (bb[3] - bb[1]), ft["properties"]))
                break
    hasil.sort(key=lambda t: t[0])
    return [p for _, p in hasil]


def jarak_km(nama, lon, lat, filter_fn=None):
    """Jarak terdekat (km) titik ke garis di layer (pendekatan bidang lokal)."""
    kx, ky = 111.32 * math.cos(math.radians(lat)), 110.57
    terbaik = None
    for ft in _muat(nama):
        if filter_fn and not filter_fn(ft["properties"]):
            continue
        g = ft["geometry"]
        garis = [g["coordinates"]] if g["type"] == "LineString" else g["coordinates"]
        for ln in garis:
            for (x1, y1), (x2, y2) in zip(ln, ln[1:]):
                ax, ay, bx, by = (x1 - lon) * kx, (y1 - lat) * ky, (x2 - lon) * kx, (y2 - lat) * ky
                dx, dy = bx - ax, by - ay
                t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
                d = math.hypot(ax + t * dx, ay + t * dy)
                terbaik = d if terbaik is None else min(terbaik, d)
    return terbaik
