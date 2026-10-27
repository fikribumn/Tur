"""Unduh layer resmi Badan Geologi (Geoportal ESDM) untuk DIY -> data/resmi/*.geojson

Sumber: https://geoportal.esdm.go.id/gis4/rest/services (ArcGIS REST, terbuka tanpa kunci)
Jalankan:  python -I prototype/ambil_data_resmi.py
"""
import json
import os
import time

import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "resmi")
BASE = "https://geoportal.esdm.go.id/gis4/rest/services/"
BBOX = "110.0,-8.2,110.7,-7.5"  # DIY + sekitarnya (minx,miny,maxx,maxy)

# nama berkas -> (layanan, layer)
LAYER = {
    "litologi_100k": ("BGS_PM/Geologi_Litologi", 0),
    "krb_gempa_50k": ("BGV_GT/KRB_Gempa_Bumi", 0),
    "likuefaksi_100k": ("BGE_GT/Kerentanan_Likuefaksi", 0),
    "likuefaksi_50k": ("BGE_GT/Kerentanan_Likuefaksi_Skala_1_50000", 0),
    "gerakan_tanah_50k": ("BGV_GT/Zona_Kerentanan_Gerakan_Tanah", 0),
    "krb_tsunami": ("BGV_GT/KRB_Tsunami", 0),
    "tanah_lunak": ("BGE_GT/Sebaran_Tanah_Lunak_Indonesia", 0),
    "patahan_aktif_1m": ("BGS_PM/Patahan_Aktif_Skala_Besar", 0),
    "patahan_aktif_kecil": ("BGS_PM/Patahan_Aktif_Skala_Kecil", 0),
}
PAGE = 500
SIMPLIFY = 0.0003  # derajat, ~30 m; cukup untuk lookup titik skala 1:50.000-1:100.000


def _get(sesi, url, params):
    for percobaan in range(4):
        try:
            r = sesi.get(url, params=params, timeout=180)
            r.raise_for_status()
            return r.json()
        except (requests.RequestException, ValueError):
            time.sleep(3 * (percobaan + 1))
    raise RuntimeError(f"gagal mengunduh {url}")


def unduh(sesi, svc, lid):
    """Ambil daftar ObjectID dulu, lalu unduh per kelompok (paging offset bisa berhenti dini
    bila ada fitur yang geometrinya hilang setelah disederhanakan)."""
    url = f"{BASE}{svc}/MapServer/{lid}/query"
    dasar = dict(geometry=BBOX, geometryType="esriGeometryEnvelope", inSR=4326,
                 spatialRel="esriSpatialRelIntersects", where="1=1")
    ids = _get(sesi, url, {**dasar, "returnIdsOnly": "true", "f": "json"}).get("objectIds") or []
    fitur = []
    for i in range(0, len(ids), PAGE):
        kelompok = ",".join(str(x) for x in ids[i:i + PAGE])
        d = _get(sesi, url, dict(objectIds=kelompok, outFields="*", outSR=4326, returnGeometry="true",
                                 maxAllowableOffset=SIMPLIFY, geometryPrecision=5, f="geojson"))
        fitur += d.get("features", [])
    return fitur


def main():
    os.makedirs(OUT, exist_ok=True)
    sesi = requests.Session()
    meta = {"sumber": BASE, "bbox": BBOX, "diambil": time.strftime("%Y-%m-%d"), "layer": {}}
    for nama, (svc, lid) in LAYER.items():
        fitur = unduh(sesi, svc, lid)
        with open(os.path.join(OUT, nama + ".geojson"), "w", encoding="utf-8") as f:
            json.dump({"type": "FeatureCollection", "features": fitur}, f, ensure_ascii=False)
        meta["layer"][nama] = {"layanan": svc, "jumlah_fitur": len(fitur)}
        print(f"{nama:22}{len(fitur):6} fitur")
    with open(os.path.join(OUT, "_sumber.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
