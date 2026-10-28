// Simulasi: sumber gempa yang ditaruh pengguna -> guncangan di titik pengguna dan di seluruh peta.
// Sumber dimodelkan sebagai retakan memanjang (segmen garis) sepanjang sesar, bukan titik.
// Model BSSA14 hanya untuk gempa kerak dangkal; di luar itu hasil sengaja tidak dihitung.
import 'dart:math' as math;

import 'gmpe.dart';

/// Kedalaman maksimum (km) agar BSSA14 (kerak dangkal) masih dipakai.
const kedalamanMaksKm = 30.0;

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

/// Panjang retakan permukaan (km) dari magnitudo, regresi SRL Wells & Coppersmith (1994) per mekanisme.
double panjangRupturKm(double magnitudo, Mekanisme mek) {
  final (a, b) = switch (mek) {
    Mekanisme.mendatar => (-2.57, 0.62),
    Mekanisme.naik => (-2.42, 0.58),
    Mekanisme.normal => (-1.88, 0.50),
    Mekanisme.takDiketahui => (-2.44, 0.59),
  };
  return math.pow(10, a + b * magnitudo).toDouble();
}

/// Segmen retakan di permukaan (dua ujung).
class Segmen {
  final double lat1, lon1, lat2, lon2;
  const Segmen(this.lat1, this.lon1, this.lat2, this.lon2);
}

/// Segmen sepanjang [panjangKm] berpusat di (lat, lon), searah [arah] (derajat dari utara).
Segmen segmenRuptur(double lat, double lon, double panjangKm, double arah) {
  final kx = 111.32 * math.cos(lat * math.pi / 180), ky = 110.57;
  final az = arah * math.pi / 180;
  final dx = math.sin(az) * panjangKm / 2, dy = math.cos(az) * panjangKm / 2;
  return Segmen(lat - dy / ky, lon - dx / kx, lat + dy / ky, lon + dx / kx);
}

/// Jarak permukaan terdekat (km) dari sebuah titik ke segmen; ini yang dipakai sebagai Rjb.
double jarakKeSegmenKm(double lat, double lon, Segmen s) {
  final kx = 111.32 * math.cos(lat * math.pi / 180), ky = 110.57;
  final ax = (s.lon1 - lon) * kx, ay = (s.lat1 - lat) * ky;
  final bx = (s.lon2 - lon) * kx, by = (s.lat2 - lat) * ky;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
  return math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
}

class HasilSimulasi {
  /// False bila sumber terlalu dalam untuk model kerak dangkal; angka tidak dihitung.
  final bool berlaku;

  /// Jarak dan arah dari pusat sumber ke titik pengguna; rjbKm = jarak ke retakan (dipakai model).
  final double jarakKm, arahDeg, rjbKm, panjangKm;
  final Segmen segmen;
  final double? mmi, pgaG, pgvCms;
  const HasilSimulasi({
    required this.berlaku,
    required this.jarakKm,
    required this.arahDeg,
    required this.rjbKm,
    required this.panjangKm,
    required this.segmen,
    this.mmi,
    this.pgaG,
    this.pgvCms,
  });
}

/// Guncangan di titik pengguna. Retakan berpusat di sumber, memanjang searah [arahSesarDeg].
HasilSimulasi simulasikan({
  required double srcLat,
  required double srcLon,
  required double siteLat,
  required double siteLon,
  required double magnitudo,
  required double kedalamanKm,
  required double vs30,
  required Mekanisme mekanisme,
  double arahSesarDeg = 0,
}) {
  final panjang = panjangRupturKm(magnitudo, mekanisme);
  final seg = segmenRuptur(srcLat, srcLon, panjang, arahSesarDeg);
  final d = jarakKm(srcLat, srcLon, siteLat, siteLon);
  final arah = arahDeg(srcLat, srcLon, siteLat, siteLon);
  final rjb = jarakKeSegmenKm(siteLat, siteLon, seg);
  if (kedalamanKm > kedalamanMaksKm) {
    return HasilSimulasi(berlaku: false, jarakKm: d, arahDeg: arah, rjbKm: rjb, panjangKm: panjang, segmen: seg);
  }
  final g = gerakTanah(magnitudo, rjb, vs30, mekanisme);
  return HasilSimulasi(
      berlaku: true, jarakKm: d, arahDeg: arah, rjbKm: rjb, panjangKm: panjang, segmen: seg, mmi: g.mmi, pgaG: g.pgaG, pgvCms: g.pgvCms);
}

/// Jarak (km) dari retakan di mana MMI turun ke [target], pada tanah acuan [vs30]. Null bila tidak tercapai
/// bahkan di dekat retakan. Dibatasi 600 km.
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

/// Radius jendela peta guncangan yang diperlukan (km): sampai MMI ~III-IV di tanah lunak, ditambah setengah retakan.
double radiusJangkauanKm(double magnitudo, Mekanisme mek) {
  final r = radiusMmiKm(magnitudo, 4, mek, vs30: 200) ?? 20.0;
  return r + panjangRupturKm(magnitudo, mek) / 2;
}

/// Jendela diambil bertingkat supaya data geologi tidak diunduh ulang tiap slider bergeser sedikit.
const tingkatJendelaKm = [40.0, 80.0, 160.0, 250.0];
double pilihJendelaKm(double butuhKm) {
  for (final t in tingkatJendelaKm) {
    if (butuhKm <= t) return t;
  }
  return tingkatJendelaKm.last;
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
