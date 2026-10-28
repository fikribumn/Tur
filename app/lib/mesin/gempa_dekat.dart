// Menyaring katalog gempa menurut kedekatan dengan lokasi pengguna, periode, dan magnitudo minimum.
import 'katalog_bmkg.dart';
import 'simulasi.dart' as sim;

class GempaDekat {
  final GempaBmkg gempa;

  /// Jarak dari titik pengguna ke episentrum (km) dan arah dari pengguna ke episentrum (derajat dari utara).
  final double jarakKm, arahDeg;
  const GempaDekat(this.gempa, this.jarakKm, this.arahDeg);
}

/// Gempa dengan umur paling lama [hari], magnitudo minimal [magMin], dan (bila [radiusKm] diberikan) jarak paling jauh
/// [radiusKm] dari (lat, lon). Urutan: terbaru dulu, atau terdekat dulu bila [urutJarak].
List<GempaDekat> gempaDekat(
  List<GempaBmkg> semua,
  double lat,
  double lon, {
  double? radiusKm,
  int hari = 30,
  double magMin = 4,
  bool urutJarak = false,
  DateTime? sekarangUtc,
}) {
  final batas = (sekarangUtc ?? DateTime.now().toUtc()).subtract(Duration(days: hari));
  final out = <GempaDekat>[];
  for (final g in semua) {
    if (g.waktuUtc.isBefore(batas) || g.magnitudo < magMin) continue;
    final d = sim.jarakKm(g.lat, g.lon, lat, lon);
    if (radiusKm != null && d > radiusKm) continue;
    out.add(GempaDekat(g, d, sim.arahDeg(lat, lon, g.lat, g.lon)));
  }
  out.sort(urutJarak ? (a, b) => a.jarakKm.compareTo(b.jarakKm) : (a, b) => b.gempa.waktuUtc.compareTo(a.gempa.waktuUtc));
  return out;
}
