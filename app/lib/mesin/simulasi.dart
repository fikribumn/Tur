// Simulasi: sumber gempa yang ditaruh pengguna -> guncangan di titik pengguna, plus radius zona MMI.
// Model BSSA14 hanya untuk gempa kerak dangkal; di luar itu hasil sengaja tidak dihitung.
import 'dart:math' as math;

import 'gmpe.dart';

/// Kedalaman maksimum (km) agar BSSA14 (kerak dangkal) masih dipakai.
const kedalamanMaksKm = 30.0;

/// Tingkat MMI yang digambar sebagai cincin di peta.
const tingkatCincin = [6, 7, 8, 9];

/// Jarak permukaan (km) antara dua titik, rumus haversine.
double jarakKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0088;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Arah (derajat dari utara, searah jarum jam) dari titik 1 ke titik 2.
double arahDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

const _mataAngin = ['utara', 'timur laut', 'timur', 'tenggara', 'selatan', 'barat daya', 'barat', 'barat laut'];
String namaArah(double deg) => _mataAngin[((deg + 22.5) % 360 ~/ 45)];

class HasilSimulasi {
  /// False bila sumber terlalu dalam untuk model kerak dangkal; angka tidak dihitung.
  final bool berlaku;
  final double jarakKm, arahDeg;
  final double? mmi, pgaG, pgvCms;
  const HasilSimulasi({
    required this.berlaku,
    required this.jarakKm,
    required this.arahDeg,
    this.mmi,
    this.pgaG,
    this.pgvCms,
  });
}

/// Guncangan di titik pengguna akibat sumber titik. Sumber dianggap titik (jarak episentrum ~ Rjb).
HasilSimulasi simulasikan({
  required double srcLat,
  required double srcLon,
  required double siteLat,
  required double siteLon,
  required double magnitudo,
  required double kedalamanKm,
  required double vs30,
  required Mekanisme mekanisme,
}) {
  final d = jarakKm(srcLat, srcLon, siteLat, siteLon);
  final arah = arahDeg(srcLat, srcLon, siteLat, siteLon);
  if (kedalamanKm > kedalamanMaksKm) {
    return HasilSimulasi(berlaku: false, jarakKm: d, arahDeg: arah);
  }
  final g = gerakTanah(magnitudo, d, vs30, mekanisme);
  return HasilSimulasi(berlaku: true, jarakKm: d, arahDeg: arah, mmi: g.mmi, pgaG: g.pgaG, pgvCms: g.pgvCms);
}

/// Jarak (km) dari sumber di mana MMI turun ke [target], pada tanah acuan [vs30]. Null bila tidak tercapai
/// bahkan di dekat sumber. Dibatasi 600 km.
double? radiusMmiKm(double magnitudo, int target, Mekanisme mekanisme, {double vs30 = 400}) {
  double mmiPada(double r) => gerakTanah(magnitudo, r, vs30, mekanisme).mmi;
  if (mmiPada(0.5) < target) return null;
  var lo = 0.5, hi = 600.0;
  if (mmiPada(hi) >= target) return hi;
  for (var i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2;
    if (mmiPada(mid) >= target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Uraian umum skala MMI (bukan prediksi kerusakan bangunan tertentu).
String uraianMmi(double mmi) {
  final m = mmi.round();
  if (m <= 2) return 'Hampir tidak terasa.';
  if (m <= 4) return 'Terasa ringan; benda gantung bergoyang.';
  if (m == 5) return 'Terasa kuat oleh hampir semua orang; barang kecil bergeser.';
  if (m == 6) return 'Dirasakan semua orang; retak ringan pada bangunan lemah.';
  if (m == 7) return 'Orang sulit berdiri; kerusakan pada bangunan biasa, bangunan lemah rusak berat.';
  if (m == 8) return 'Kerusakan berat pada bangunan lemah, sebagian bisa roboh.';
  return 'Kerusakan sangat berat; banyak bangunan roboh.';
}
