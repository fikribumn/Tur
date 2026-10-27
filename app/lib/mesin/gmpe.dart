// BSSA14 (Boore dkk. 2014) -> PGA/PGV, lalu konversi ke MMI (Worden dkk. 2012).
// Port dari prototype/gmpe.py. Koefisien Worden belum diverifikasi terhadap makalah aslinya.
import 'dart:math' as math;

class _Koef {
  final double e1, e4, e5, e6, mh, c1, c2, c3, h, c, vc, f4, f5;
  const _Koef(this.e1, this.e4, this.e5, this.e6, this.mh, this.c1, this.c2, this.c3, this.h, this.c, this.vc,
      this.f4, this.f5);
}

const _pga = _Koef(0.4856, 1.431, 0.05053, -0.1662, 5.5, -1.134, 0.1917, -0.008088, 4.5, -0.6, 1500.0, -0.15, -0.00701);
const _pgv = _Koef(5.078, 1.073, -0.1536, 0.2252, 6.2, -1.243, 0.1489, -0.00344, 5.3, -0.84, 1300.0, -0.10, -0.00844);

const _mref = 4.5, _rref = 1.0, _vref = 760.0, _f1 = 0.0, _f3 = 0.1;

// Worden 2012: (c1, c2, c3, c4, t1) untuk PGA (cm/s2) dan PGV (cm/s)
const _wPga = (1.78, 1.55, -1.60, 3.70, 1.57);
const _wPgv = (3.78, 1.47, 2.89, 3.16, 0.53);

class GerakTanah {
  final double mmi, pgaG, pgvCms;
  const GerakTanah(this.mmi, this.pgaG, this.pgvCms);
}

double _log10(double x) => math.log(x) / math.ln10;

double _feFp(_Koef k, double m, double rjb) {
  final d = m - k.mh;
  final fe = k.e1 + (m <= k.mh ? k.e4 * d + k.e5 * d * d : k.e6 * d);
  final r = math.sqrt(rjb * rjb + k.h * k.h);
  final fp = (k.c1 + k.c2 * (m - _mref)) * math.log(r / _rref) + k.c3 * (r - _rref);
  return fe + fp;
}

double _median(_Koef k, double m, double rjb, double vs30, double pgaBatuan) {
  final flin = k.c * math.log(math.min(vs30, k.vc) / _vref);
  final vs = math.min(vs30, _vref);
  final f2 = k.f4 * (math.exp(k.f5 * (vs - 360.0)) - math.exp(k.f5 * 400.0));
  final fnl = _f1 + f2 * math.log((pgaBatuan + _f3) / _f3);
  return math.exp(_feFp(k, m, rjb) + flin + fnl);
}

double _mmiDari(double y, (double, double, double, double, double) w) {
  final x = _log10(math.max(y, 1e-6));
  final m = x <= w.$5 ? w.$1 + w.$2 * x : w.$3 + w.$4 * x;
  return m.clamp(1.0, 10.0).toDouble();
}

/// Median PGA (g), PGV (cm/s) dan MMI untuk sesar mendatar, Rjb dalam km.
GerakTanah gerakTanah(double m, double rjbKm, double vs30) {
  final pgaBatuan = math.exp(_feFp(_pga, m, rjbKm));
  final pga = _median(_pga, m, rjbKm, vs30, pgaBatuan);
  final pgv = _median(_pgv, m, rjbKm, vs30, pgaBatuan);
  final mmi = 0.5 * (_mmiDari(pga * 980.665, _wPga) + _mmiDari(pgv, _wPgv));
  return GerakTanah(mmi, pga, pgv);
}
