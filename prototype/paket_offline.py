"""Kemas data resmi + elevasi menjadi paket ringkas untuk aplikasi (offline) -> app/assets/data/

Isi paket (satu berkas JSON per lapisan, hanya atribut yang dipakai mesin kerentanan):
  litologi, krb_gempa, likuefaksi_50k, likuefaksi_100k, gerakan_tanah, tsunami, tanah_lunak, sesar_opak,
  elevasi (grid), litologi_dampak (kelas material)

Jalankan:  python -I prototype/paket_offline.py   (setelah ambil_data_resmi.py dan kerentanan.py)
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESMI = os.path.join(ROOT, "data", "resmi")
OUT = os.path.join(ROOT, "app", "assets", "data")

# nama paket -> (berkas sumber, atribut yang disimpan)
POLIGON = {
    "litologi": ("litologi_100k", ["simobj", "namobj", "umurobj"]),
    "krb_gempa": ("krb_gempa_50k", ["kelas"]),
    "likuefaksi_50k": ("likuefaksi_50k", ["kerentanan"]),
    "likuefaksi_100k": ("likuefaksi_100k", ["kerentanan"]),
    "gerakan_tanah": ("gerakan_tanah_50k", ["unsur"]),
    "tsunami": ("krb_tsunami", ["unsur"]),
    "tanah_lunak": ("tanah_lunak", ["jenis_tana"]),
}


def bulatkan(koor, n=4):
    """Bulatkan koordinat ke n desimal (~11 m) dan buang titik berurutan yang sama."""
    if isinstance(koor[0], (int, float)):
        return [round(koor[0], n), round(koor[1], n)]
    hasil = [bulatkan(k, n) for k in koor]
    if isinstance(hasil[0][0], (int, float)):
        bersih = [hasil[0]]
        for p in hasil[1:]:
            if p != bersih[-1]:
                bersih.append(p)
        return bersih
    return hasil


def kemas_poligon(nama, sumber, atribut):
    with open(os.path.join(RESMI, sumber + ".geojson"), encoding="utf-8") as f:
        fitur = json.load(f)["features"]
    keluar = []
    for ft in fitur:
        g = ft.get("geometry")
        if not g or g["type"] not in ("Polygon", "MultiPolygon"):
            continue
        poly = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        poly = [[c for c in (bulatkan(r) for r in p) if len(c) >= 4] for p in poly]
        poly = [p for p in poly if p]
        if not poly:
            continue
        keluar.append({"p": {k: ft["properties"].get(k) for k in atribut}, "g": poly})
    return keluar


def main():
    os.makedirs(OUT, exist_ok=True)
    ringkas = {}
    for nama, (sumber, atribut) in POLIGON.items():
        data = kemas_poligon(nama, sumber, atribut)
        path = os.path.join(OUT, nama + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
        ringkas[nama] = (len(data), os.path.getsize(path))

    # Sesar Opak: hanya garis yang namanya memuat "Opak"
    with open(os.path.join(RESMI, "patahan_aktif_1m.geojson"), encoding="utf-8") as f:
        sesar = json.load(f)["features"]
    garis = []
    for ft in sesar:
        if "Opak" in (ft["properties"].get("namobj") or ""):
            g = ft["geometry"]
            garis += [bulatkan(g["coordinates"])] if g["type"] == "LineString" else [bulatkan(x) for x in g["coordinates"]]
    with open(os.path.join(OUT, "sesar_opak.json"), "w") as f:
        json.dump(garis, f, separators=(",", ":"))

    with open(os.path.join(ROOT, "data", "elevasi_diy.json")) as f:
        e = json.load(f)
    with open(os.path.join(OUT, "elevasi.json"), "w") as f:
        json.dump({"lat0": e["lats"][0], "lon0": e["lons"][0], "step": 0.01, "nlat": len(e["lats"]),
                   "nlon": len(e["lons"]), "elev": [round(x, 1) for x in e["elev"]]}, f, separators=(",", ":"))

    with open(os.path.join(ROOT, "data", "litologi_dampak.json"), encoding="utf-8") as f:
        l = json.load(f)
    with open(os.path.join(OUT, "litologi_dampak.json"), "w", encoding="utf-8") as f:
        json.dump({"kelas": l["kelas"], "pemetaan_simobj": l["pemetaan_simobj"]}, f, ensure_ascii=False, separators=(",", ":"))

    total = 0
    for berkas in sorted(os.listdir(OUT)):
        ukuran = os.path.getsize(os.path.join(OUT, berkas))
        total += ukuran
        print(f"{berkas:24}{ukuran / 1024:9.0f} KB")
    print(f"{'TOTAL':24}{total / 1024:9.0f} KB")


if __name__ == "__main__":
    main()
