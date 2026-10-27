"""Prototipe kerentanan geologi DIY berbasis data resmi Badan Geologi (bukan alat keselamatan).

Alur per titik:
  1. layer resmi (data/resmi): formasi geologi, KRB gempa, likuefaksi, gerakan tanah, tsunami, Sesar Opak
  2. kelas material -> Vs30 (digabung proxy kemiringan SRTM, Wald & Allen 2007)
  3. skenario gempa di Sesar Opak -> BSSA14 (PGA/PGV) -> MMI Worden 2012 (prototype/gmpe.py)
  4. tingkat bahaya 0-3 per jenis (resmi bila ada, perkiraan bila tidak)

Jalankan:  python -I prototype/kerentanan.py      (data resmi: python -I prototype/ambil_data_resmi.py)
"""
import gzip
import json
import math
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import data_resmi as resmi  # noqa: E402
import gmpe  # noqa: E402

CACHE = os.path.join(ROOT, "data", "elevasi_diy.json")
LITO = os.path.join(ROOT, "data", "litologi_dampak.json")
LAT0, LAT1, LON0, LON1, STEP = -8.15, -7.55, 110.05, 110.65, 0.01
MAGNITUDO = [round(5.0 + 0.1 * i, 1) for i in range(26)]  # 5,0 .. 7,5 untuk slider UI

KRB = {"Sangat Rendah": 0, "Rendah": 1, "Menengah": 2, "Tinggi": 3}
LIK50 = {"Zona Tidak Rentan Likuefaksi": 0, "Zona Kerentanan Likuefaksi Rendah": 1,
         "Zona Kerentanan Likuefaksi Sedang": 2, "Zona Kerentanan Likuefaksi Tinggi": 3}
LIK100 = {"1": 3, "2": 2}  # keterangan resmi: 1 = merata/rusak parah, 2 = tidak merata
GT = {"Sangat Rendah": 0, "Rendah": 1, "Menengah": 2, "Tinggi": 3}


# ---------- elevasi dan Vs30 proxy ----------
def grid():
    lats = [round(LAT0 + i * STEP, 4) for i in range(int(round((LAT1 - LAT0) / STEP)) + 1)]
    lons = [round(LON0 + j * STEP, 4) for j in range(int(round((LON1 - LON0) / STEP)) + 1)]
    return lats, lons


def baca_ubin(nama):
    """Ubin SRTM1 (3601x3601, int16 big-endian) dari AWS terrain tiles; nama = sudut barat-daya ubin."""
    with gzip.open(os.path.join(ROOT, "data", "srtm", nama + ".hgt.gz")) as f:
        return np.frombuffer(f.read(), ">i2").reshape(3601, 3601).astype(float)


def ambil_elevasi():
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    # S08E110 meliputi lat -8..-7, S09E110 meliputi lat -9..-8; keduanya lon 110..111
    atas, bawah = baca_ubin("S08E110"), baca_ubin("S09E110")
    peta = np.vstack([atas[:-1], bawah])  # baris 0 = lat -7.0, 1 baris = 1/3600 derajat
    lats, lons = grid()
    elev = []
    for la in lats:
        for lo in lons:
            r = (-7.0 - la) * 3600.0
            c = (lo - 110.0) * 3600.0
            w = STEP * 3600.0 / 2  # rata-rata blok ~1 km (setara data 30 arc-sec)
            blok = peta[int(r - w):int(r + w) + 1, int(c - w):int(c + w) + 1]
            elev.append(float(np.nanmean(np.where(blok < -1000, np.nan, blok))))
    data = {"lats": lats, "lons": lons, "elev": elev}
    with open(CACHE, "w") as f:
        json.dump(data, f)
    return data


def kemiringan(E, i, j, nlat, nlon):
    """Gradien (m/m) dengan beda pusat; spasi grid ~1,1 km (setara data 30 arc-sec)."""
    d = STEP * 111_000.0
    i0, i1 = max(i - 1, 0), min(i + 1, nlat - 1)
    j0, j1 = max(j - 1, 0), min(j + 1, nlon - 1)
    gy = (E[i1][j] - E[i0][j]) / ((i1 - i0) * d)
    gx = (E[i][j1] - E[i][j0]) / ((j1 - j0) * d * math.cos(math.radians(-7.8)))
    return math.hypot(gx, gy)


# Titik jangkar slope -> Vs30 (aproksimasi tabel Wald & Allen 2007, tektonik aktif; verifikasi ke makalah)
ANCHOR = [(1e-4, 180.0), (2.2e-3, 360.0), (0.138, 760.0), (0.3, 1000.0)]


def vs30_dari_slope(s):
    if s <= ANCHOR[0][0]:
        return ANCHOR[0][1]
    for (s0, v0), (s1, v1) in zip(ANCHOR, ANCHOR[1:]):
        if s <= s1:
            t = (math.log10(s) - math.log10(s0)) / (math.log10(s1) - math.log10(s0))
            return v0 + t * (v1 - v0)
    return ANCHOR[-1][1]


# ---------- gabungan ----------
def analisis(lon, lat, elev, slope, lito, M=6.3):
    gs = resmi.cari("litologi_100k", lon, lat)
    g = gs[0] if gs else None
    kode = lito["pemetaan_simobj"].get(g["simobj"]) if g else None
    mat = lito["kelas"][kode] if kode else None

    # guncangan skenario
    d_opak = resmi.jarak_km("patahan_aktif_1m", lon, lat, lambda p: "Opak" in p["namobj"])
    vs_proxy = vs30_dari_slope(slope)
    vs30 = 0.3 * vs_proxy + 0.7 * mat["vs30"] if mat else vs_proxy  # litologi lebih dipercaya daripada topografi
    mmi, pga, pgv = gmpe.mmi(M, d_opak, vs30)  # Rjb ~ jarak ke jejak sesar
    mmi_per_m = {str(m): round(gmpe.mmi(m, d_opak, vs30)[0], 1) for m in MAGNITUDO}

    krb = resmi.cari("krb_gempa_50k", lon, lat)
    krb_lv = KRB.get(krb[0]["kelas"].replace("Kawasan Rawan Bencana Gempabumi ", "")) if krb else None

    # likuefaksi: 50K bila ada; jika hanya 100K (poligon kasar) dibatasi oleh kerentanan material
    l50, l100 = resmi.cari("likuefaksi_50k", lon, lat), resmi.cari("likuefaksi_100k", lon, lat)
    if l50:
        lik_lv, lik_src = LIK50.get(l50[0]["kerentanan"].strip()), "resmi 1:50.000"
    elif l100:
        lv = LIK100.get(str(l100[0]["kerentanan"]).strip())
        lik_lv = min(lv, 1 + mat["likuefaksi"]) if (lv is not None and mat) else lv
        lik_src = "resmi 1:100.000 (poligon kasar, dibatasi oleh material)"
    else:
        lik_lv, lik_src = (mat["likuefaksi"] if mat else None), "perkiraan dari material"

    # gerakan tanah: resmi 1:50.000; jika tidak ada, perkiraan material x kemiringan
    gt = [p for p in resmi.cari("gerakan_tanah_50k", lon, lat) if p.get("unsur") in GT]
    if gt:
        gt_lv, gt_src = GT[gt[0]["unsur"]], "resmi 1:50.000"
    else:
        gt_lv = round(mat["longsor"] * min(1.0, 0.4 + slope * 6)) if mat else None
        gt_src = "perkiraan dari material dan lereng"

    tsu = resmi.cari("krb_tsunami", lon, lat)
    lunak = resmi.cari("tanah_lunak", lon, lat)
    levels = [v for v in (krb_lv, lik_lv, gt_lv) if v is not None]
    return {
        "geologi": {"kode": g["simobj"], "formasi": g["namobj"], "umur": g["umurobj"]} if g else None,
        "material": {"kelas": kode, "nama": mat["nama"], "catatan": mat["catatan"]} if mat else None,
        "vs30": round(vs30),
        "elevasi_m": round(elev), "kemiringan": round(slope, 4),
        "jarak_sesar_opak_km": round(d_opak, 1),
        "skenario": {"M": M, "mmi": round(mmi, 1), "pga_g": round(pga, 2), "pgv_cms": round(pgv), "mmi_per_m": mmi_per_m},
        "krb_gempa": {"tingkat": krb_lv, "kelas": krb[0]["kelas"] if krb else None},
        "likuefaksi": {"tingkat": lik_lv, "sumber": lik_src},
        "gerakan_tanah": {"tingkat": gt_lv, "sumber": gt_src},
        "tsunami": bool(tsu),
        "tanah_lunak": lunak[0]["jenis_tana"] if lunak else None,
        "tingkat_keseluruhan": max(levels) if levels else None,
    }


TITIK = {
    "Malioboro": (-7.793, 110.366),
    "Bantul kota": (-7.888, 110.329),
    "Parangtritis": (-8.025, 110.332),
    "Imogiri": (-7.930, 110.390),
    "Prambanan": (-7.752, 110.491),
    "Sleman": (-7.716, 110.355),
    "Kaliurang": (-7.600, 110.427),
    "Wates": (-7.862, 110.158),
    "Wonosari": (-7.965, 110.600),
}


def cari_grid(data, lat, lon):
    lats, lons, E = data["lats"], data["lons"], data["E2"]
    # sel terdekat; jarak tepat 0,5 sel dibulatkan ke atas (disamakan dengan mesin Dart)
    i = min(max(int(math.floor((lat - lats[0]) / STEP + 0.5 + 1e-9)), 0), len(lats) - 1)
    j = min(max(int(math.floor((lon - lons[0]) / STEP + 0.5 + 1e-9)), 0), len(lons) - 1)
    return E[i][j], kemiringan(E, i, j, len(lats), len(lons))


def main():
    data = ambil_elevasi()
    nlon = len(data["lons"])
    data["E2"] = [data["elev"][k * nlon:(k + 1) * nlon] for k in range(len(data["lats"]))]
    with open(LITO, encoding="utf-8") as f:
        lito = json.load(f)
    hasil = {}
    print("Skenario M6,3 di Sesar Opak (median BSSA14 + Worden 2012)\n")
    print(f"{'Lokasi':13}{'Formasi':26}{'Vs30':>5}{'Opak':>6}{'PGA':>6}{'MMI':>5}  KRB  Lik  Longs")
    for nama, (lat, lon) in TITIK.items():
        el, sl = cari_grid(data, lat, lon)
        h = analisis(lon, lat, el, sl, lito)
        hasil[nama] = {"lat": lat, "lon": lon, **h}
        f = h["geologi"]["formasi"][:24] if h["geologi"] else "-"
        print(f"{nama:13}{f:26}{h['vs30']:>5}{h['jarak_sesar_opak_km']:>6}{h['skenario']['pga_g']:>6}{h['skenario']['mmi']:>5}"
              f"  {h['krb_gempa']['tingkat']!s:>3}  {h['likuefaksi']['tingkat']!s:>3}  {h['gerakan_tanah']['tingkat']!s:>4}"
              f"{'  TSUNAMI' if h['tsunami'] else ''}")
    out = os.path.join(ROOT, "data", "hasil_contoh.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(hasil, f, ensure_ascii=False, indent=1)
    ui = os.path.join(ROOT, "ui", "data.js")  # dibaca mockup UI (dibuka langsung dari berkas)
    with open(ui, "w", encoding="utf-8") as f:
        f.write("// DIHASILKAN prototype/kerentanan.py. Sumber layer: Badan Geologi (Geoportal ESDM).\n")
        f.write("const LOK = " + json.dumps(hasil, ensure_ascii=False) + ";\n")
    print("\nDisimpan:", out, "dan", ui)


if __name__ == "__main__":
    main()
