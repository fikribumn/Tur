// Katalog gempa terbuka BMKG (data.bmkg.go.id): gempa terbaru, M5+ terkini, dan gempa yang dirasakan.
// Pengurai dibuat terpisah dari jaringan agar bisa diuji dengan contoh data.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'daring.dart' show GalatJaringan;

const _dasar = 'https://data.bmkg.go.id/DataMKG/TEWS/';
const _batas = Duration(seconds: 25);

const _romawi = {
  'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12,
};

/// Satu laporan "dirasakan" BMKG: skala MMI (angka Romawi, bisa rentang "II-III") dan nama daerah.
class LaporanDirasakan {
  final String skala;
  final double mmi;
  final String tempat;
  const LaporanDirasakan(this.skala, this.mmi, this.tempat);
}

class GempaBmkg {
  final DateTime waktuUtc;
  final double lat, lon, magnitudo, kedalamanKm;
  final String wilayah;
  final String? potensi;
  final List<LaporanDirasakan> dirasakan;

  const GempaBmkg({
    required this.waktuUtc,
    required this.lat,
    required this.lon,
    required this.magnitudo,
    required this.kedalamanKm,
    required this.wilayah,
    this.potensi,
    this.dirasakan = const [],
  });

  String get kunci => waktuUtc.toIso8601String();

  /// Waktu dalam WIB (UTC+7), mis. "28 Okt 2026 08:11 WIB".
  String get waktuWib {
    final w = waktuUtc.add(const Duration(hours: 7));
    const bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    String d2(int x) => x.toString().padLeft(2, '0');
    return '${w.day} ${bulan[w.month - 1]} ${w.year} ${d2(w.hour)}:${d2(w.minute)} WIB';
  }

  /// Selang waktu yang ramah dibaca, mis. "3 jam lalu".
  String selang(DateTime sekarangUtc) {
    final d = sekarangUtc.difference(waktuUtc);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
    if (d.inHours < 48) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  bool get berpotensiTsunami => (potensi ?? '').toLowerCase().contains('berpotensi tsunami') &&
      !(potensi ?? '').toLowerCase().contains('tidak berpotensi');

  /// MMI tertinggi di antara laporan dirasakan (null bila tidak ada).
  double? get mmiDirasakanMaks => dirasakan.isEmpty ? null : dirasakan.map((e) => e.mmi).reduce((a, b) => a > b ? a : b);

  GempaBmkg dengan({List<LaporanDirasakan>? dirasakan, String? potensi}) => GempaBmkg(
        waktuUtc: waktuUtc,
        lat: lat,
        lon: lon,
        magnitudo: magnitudo,
        kedalamanKm: kedalamanKm,
        wilayah: wilayah,
        potensi: potensi ?? this.potensi,
        dirasakan: dirasakan ?? this.dirasakan,
      );
}

/// "-9.20,110.39" -> (lat, lon). Null bila tidak terbaca.
(double, double)? uraiKoordinat(String? s) {
  if (s == null) return null;
  final p = s.split(',');
  if (p.length != 2) return null;
  final lat = double.tryParse(p[0].trim()), lon = double.tryParse(p[1].trim());
  return (lat == null || lon == null) ? null : (lat, lon);
}

/// "10 km" -> 10.0
double? uraiKedalaman(String? s) {
  if (s == null) return null;
  final m = RegExp(r'[\d.]+').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// "II-III" -> 2.5, "IV" -> 4. Null bila bukan angka Romawi yang dikenal.
double? uraiSkala(String s) {
  final bagian = s.trim().toUpperCase().split('-');
  final nilai = [for (final b in bagian) _romawi[b.trim()]];
  if (nilai.isEmpty || nilai.contains(null)) return null;
  return nilai.cast<int>().reduce((a, b) => a + b) / nilai.length;
}

/// "II Bantul, II-III Sleman" -> daftar laporan. Butir yang tidak terbaca dilewati.
List<LaporanDirasakan> uraiDirasakan(String? s) {
  if (s == null || s.trim().isEmpty || s.trim() == '-') return const [];
  final out = <LaporanDirasakan>[];
  final pola = RegExp(r'^([IVX]+(?:\s*-\s*[IVX]+)?)\s+(.+)$', caseSensitive: false);
  for (final butir in s.split(',')) {
    final m = pola.firstMatch(butir.trim());
    if (m == null) continue;
    final skala = m.group(1)!.replaceAll(' ', '').toUpperCase();
    final mmi = uraiSkala(skala);
    if (mmi != null) out.add(LaporanDirasakan(skala, mmi, m.group(2)!.trim()));
  }
  return out;
}

GempaBmkg? _uraiSatu(Map<String, dynamic> j) {
  final waktu = DateTime.tryParse('${j['DateTime'] ?? ''}');
  final koor = uraiKoordinat(j['Coordinates'] as String?);
  final mag = double.tryParse('${j['Magnitude'] ?? ''}');
  final dalam = uraiKedalaman(j['Kedalaman'] as String?);
  if (waktu == null || koor == null || mag == null || dalam == null) return null;
  return GempaBmkg(
    waktuUtc: waktu.toUtc(),
    lat: koor.$1,
    lon: koor.$2,
    magnitudo: mag,
    kedalamanKm: dalam,
    wilayah: '${j['Wilayah'] ?? ''}'.trim(),
    potensi: j['Potensi'] as String?,
    dirasakan: uraiDirasakan(j['Dirasakan'] as String?),
  );
}

/// Urai berkas BMKG: `Infogempa.gempa` bisa berupa satu objek (autogempa) atau daftar.
List<GempaBmkg> uraiBerkas(String isiJson) {
  final d = jsonDecode(isiJson) as Map<String, dynamic>;
  final g = (d['Infogempa'] as Map<String, dynamic>)['gempa'];
  final daftar = g is List ? g : [g];
  return [
    for (final e in daftar)
      if (e is Map<String, dynamic>) ?_uraiSatu(e),
  ];
}

/// Gabung beberapa sumber: kunci = waktu kejadian. Laporan dirasakan dan potensi tsunami dilengkapi dari yang tersedia.
List<GempaBmkg> gabungkan(Iterable<List<GempaBmkg>> sumber) {
  final peta = <String, GempaBmkg>{};
  for (final daftar in sumber) {
    for (final g in daftar) {
      final ada = peta[g.kunci];
      if (ada == null) {
        peta[g.kunci] = g;
      } else {
        peta[g.kunci] = ada.dengan(
          dirasakan: ada.dirasakan.isNotEmpty ? ada.dirasakan : g.dirasakan,
          potensi: ada.potensi ?? g.potensi,
        );
      }
    }
  }
  final hasil = peta.values.toList()..sort((a, b) => b.waktuUtc.compareTo(a.waktuUtc));
  return hasil;
}

class KatalogBmkg {
  final http.Client _klien;
  KatalogBmkg(this._klien);

  Future<List<GempaBmkg>?> _ambil(String berkas) async {
    try {
      final r = await _klien.get(Uri.parse('$_dasar$berkas')).timeout(_batas);
      if (r.statusCode != 200) return null;
      return uraiBerkas(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// Ambil dan gabungkan tiga berkas BMKG. Gagal total (tanpa satu pun berkas) -> [GalatJaringan].
  Future<List<GempaBmkg>> ambil() async {
    final hasil = await Future.wait([_ambil('autogempa.json'), _ambil('gempaterkini.json'), _ambil('gempadirasakan.json')]);
    final ada = hasil.whereType<List<GempaBmkg>>().toList();
    if (ada.isEmpty) throw GalatJaringan('Tidak bisa menghubungi server BMKG. Periksa koneksi internet.');
    return gabungkan(ada);
  }
}
