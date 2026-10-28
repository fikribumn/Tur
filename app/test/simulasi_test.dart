import 'package:flutter_test/flutter_test.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/simulasi.dart';

void main() {
  test('jarak haversine Jakarta-Bandung sekitar 116 km', () {
    expect(jarakKm(-6.209, 106.845, -6.917, 107.619), inInclusiveRange(110, 122));
  });

  test('arah: Bandung ada di tenggara Jakarta, Jakarta di barat laut Bandung', () {
    expect(namaArah(arahDeg(-6.209, 106.845, -6.917, 107.619)), 'tenggara');
    expect(namaArah(arahDeg(-6.917, 107.619, -6.209, 106.845)), 'barat laut');
    expect(namaArah(arahDeg(0, 100, 5, 100)), 'utara');
    expect(namaArah(arahDeg(0, 100, 0, 105)), 'timur');
  });

  test('radius zona: MMI lebih tinggi -> radius lebih kecil; magnitudo lebih besar -> radius lebih besar', () {
    final r = [for (final t in [6, 7, 8, 9]) radiusMmiKm(7.0, t, Mekanisme.mendatar)];
    for (var i = 0; i < r.length - 1; i++) {
      if (r[i] != null && r[i + 1] != null) expect(r[i]!, greaterThan(r[i + 1]!));
    }
    expect(radiusMmiKm(7.5, 7, Mekanisme.naik)!, greaterThan(radiusMmiKm(6.0, 7, Mekanisme.naik)!));
  });

  test('gempa kecil tidak mencapai MMI IX; gempa besar menjangkau puluhan km pada MMI VI', () {
    expect(radiusMmiKm(5.0, 9, Mekanisme.mendatar), isNull);
    expect(radiusMmiKm(7.5, 6, Mekanisme.mendatar)!, greaterThan(50));
  });

  test('simulasi: titik di atas sumber paling kuat, makin jauh makin lemah', () {
    HasilSimulasi s(double lonSite) => simulasikan(
        srcLat: -7.9, srcLon: 110.3, siteLat: -7.9, siteLon: lonSite, magnitudo: 6.5, kedalamanKm: 10, vs30: 300, mekanisme: Mekanisme.mendatar);
    final dekat = s(110.31), jauh = s(110.9);
    expect(dekat.mmi!, greaterThan(jauh.mmi!));
    expect(dekat.jarakKm, lessThan(jauh.jarakKm));
    expect(dekat.berlaku, isTrue);
  });

  test('sumber dalam (subduksi/intraslab) tidak dihitung', () {
    final h = simulasikan(
        srcLat: -7.9, srcLon: 110.3, siteLat: -7.8, siteLon: 110.4, magnitudo: 7.0, kedalamanKm: 80, vs30: 300, mekanisme: Mekanisme.naik);
    expect(h.berlaku, isFalse);
    expect(h.mmi, isNull);
    expect(h.jarakKm, greaterThan(0));
  });

  test('tanah lunak mengguncang lebih kuat daripada batuan pada skenario yang sama', () {
    double mmiPada(double vs) => simulasikan(
            srcLat: -7.9, srcLon: 110.3, siteLat: -7.9, siteLon: 110.5, magnitudo: 6.5, kedalamanKm: 10, vs30: vs, mekanisme: Mekanisme.mendatar)
        .mmi!;
    expect(mmiPada(200), greaterThan(mmiPada(800)));
  });
}
