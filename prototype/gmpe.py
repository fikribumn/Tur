"""Guncangan tanah: BSSA14 (Boore dkk. 2014) -> PGA/PGV, lalu konversi ke MMI (Worden dkk. 2012).

BSSA14: koefisien PGA dan PGV disalin dari implementasi OpenQuake (oq-engine, hazardlib/gsim/boore_2014.py,
        varian global tanpa koreksi regional Dc3 dan tanpa suku cekungan).
Worden 2012: koefisien PGA/PGV ditulis dari ingatan, BELUM diverifikasi terhadap makalah
        (BSSA 102(1), doi:10.1785/0120110156). Tes kewajaran ada di bagian bawah berkas ini.
Hanya pustaka standar.
"""
import math

# kolom: e1(strike-slip) e4 e5 e6 Mh c1 c2 c3 h c Vc f4 f5
BSSA14 = {
    "pga": dict(e1=0.4856, e4=1.431, e5=0.05053, e6=-0.1662, Mh=5.5, c1=-1.134, c2=0.1917, c3=-0.008088,
                h=4.5, c=-0.6, Vc=1500.0, f4=-0.15, f5=-0.00701),
    "pgv": dict(e1=5.078, e4=1.073, e5=-0.1536, e6=0.2252, Mh=6.2, c1=-1.243, c2=0.1489, c3=-0.00344,
                h=5.3, c=-0.84, Vc=1300.0, f4=-0.10, f5=-0.00844),
}
MREF, RREF, VREF, F1, F3 = 4.5, 1.0, 760.0, 0.0, 0.1

# Worden 2012: MMI = c1 + c2*log10(Y) bila log10(Y) <= t1, selain itu c3 + c4*log10(Y)  (PGA cm/s2, PGV cm/s)
WORDEN = {"pga": (1.78, 1.55, -1.60, 3.70, 1.57), "pgv": (3.78, 1.47, 2.89, 3.16, 0.53)}


def _fe_fp(C, M, rjb):
    d = M - C["Mh"]
    fe = C["e1"] + (C["e4"] * d + C["e5"] * d * d if M <= C["Mh"] else C["e6"] * d)
    r = math.sqrt(rjb ** 2 + C["h"] ** 2)
    fp = (C["c1"] + C["c2"] * (M - MREF)) * math.log(r / RREF) + C["c3"] * (r - RREF)
    return fe, fp


def gerak_tanah(M, rjb_km, vs30):
    """Median PGA (g) dan PGV (cm/s) untuk sesar mendatar (strike-slip), Rjb dalam km."""
    fe, fp = _fe_fp(BSSA14["pga"], M, rjb_km)
    pga_batuan = math.exp(fe + fp)
    out = {}
    for k, C in BSSA14.items():
        fe, fp = _fe_fp(C, M, rjb_km)
        flin = C["c"] * math.log(min(vs30, C["Vc"]) / VREF)
        vs = min(vs30, VREF)
        f2 = C["f4"] * (math.exp(C["f5"] * (vs - 360.0)) - math.exp(C["f5"] * 400.0))
        fnl = F1 + f2 * math.log((pga_batuan + F3) / F3)
        out[k] = math.exp(fe + fp + flin + fnl)
    return out["pga"], out["pgv"]


def _mmi(y, koef):
    c1, c2, c3, c4, t1 = koef
    x = math.log10(max(y, 1e-6))
    m = c1 + c2 * x if x <= t1 else c3 + c4 * x
    return max(1.0, min(10.0, m))


def mmi(M, rjb_km, vs30):
    """MMI rata-rata dari konversi PGA dan PGV; ikut mengembalikan PGA (g) dan PGV (cm/s)."""
    pga, pgv = gerak_tanah(M, rjb_km, vs30)
    m = 0.5 * (_mmi(pga * 980.665, WORDEN["pga"]) + _mmi(pgv, WORDEN["pgv"]))
    return m, pga, pgv


if __name__ == "__main__":
    # Tes kewajaran (nilai pegangan umum, bukan validasi):
    #  - PGA 0,1 g sekitar MMI VI; 0,3 g sekitar VII-VIII
    #  - M6,5 sesar mendatar, Rjb 10 km, batuan (Vs30 760): PGA sekitar 0,15-0,25 g
    print("konversi:", [(g, round(_mmi(g * 980.665, WORDEN['pga']), 1)) for g in (0.02, 0.05, 0.1, 0.3, 0.6)])
    for vs in (760, 400, 250):
        m, a, v = mmi(6.5, 10, vs)
        print(f"M6.5 Rjb10 Vs30={vs}: PGA={a:.2f} g, PGV={v:.0f} cm/s, MMI={m:.1f}")
    for M in (5.0, 6.0, 7.0):
        print(f"M{M} Vs30=760: PGA di Rjb 5/20/50 km =", [round(gerak_tanah(M, r, 760)[0], 3) for r in (5, 20, 50)])
