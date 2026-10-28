// Katalog gempa: BMKG (data.bmkg.go.id: terbaru, M5+ terkini, dirasakan) dilengkapi USGS untuk M4+ di Indonesia dan sekitarnya.
// Pengurai dibuat terpisah dari jaringan agar bisa diuji dengan contoh data.
import 'dart:convert';
import 'dart:math' as math;

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

  /// 'BMKG', 'USGS', atau 'BMKG+USGS' (gempa yang sama tercatat di keduanya).
  final String sumber;

  /// Magnitudo dan MMI maksimum (ShakeMap) menurut USGS bila ada; lembaga berbeda sering memberi angka sedikit berbeda.
  final double? magnitudoUsgs, mmiUsgs;

  const GempaBmkg({
    required this.waktuUtc,
    required this.lat,
    required this.lon,
    required this.magnitudo,
    required this.kedalamanKm,
    required this.wilayah,
    this.potensi,
    this.dirasakan = const [],
    this.sumber = 'BMKG',
    this.magnitudoUsgs,
    this.mmiUsgs,
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

  GempaBmkg dengan({
    List<LaporanDirasakan>? dirasakan,
    String? potensi,
    String? sumber,
    double? magnitudoUsgs,
    double? mmiUsgs,
  }) =>
      GempaBmkg(
        waktuUtc: waktuUtc,
        lat: lat,
        lon: lon,
        magnitudo: magnitudo,
        kedalamanKm: kedalamanKm,
        wilayah: wilayah,
        potensi: potensi ?? this.potensi,
        dirasakan: dirasakan ?? this.dirasakan,
        sumber: sumber ?? this.sumber,
        magnitudoUsgs: magnitudoUsgs ?? this.magnitudoUsgs,
        mmiUsgs: mmiUsgs ?? this.mmiUsgs,
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

/// Urai GeoJSON USGS (FDSN event). Hanya `type == earthquake` bermagnitudo yang diambil.
List<GempaBmkg> uraiUsgs(String isiJson) {
  final d = jsonDecode(isiJson) as Map<String, dynamic>;
  final out = <GempaBmkg>[];
  for (final f in (d['features'] as List? ?? const [])) {
    if (f is! Map<String, dynamic>) continue;
    final p = f['properties'];
    final g = f['geometry'];
    if (p is! Map<String, dynamic> || g is! Map<String, dynamic>) continue;
    if (p['type'] != 'earthquake') continue;
    final mag = (p['mag'] as num?)?.toDouble();
    final waktu = p['time'] as num?;
    final koor = g['coordinates'] as List?;
    if (mag == null || waktu == null || koor == null || koor.length < 2) continue;
    out.add(GempaBmkg(
      waktuUtc: DateTime.fromMillisecondsSinceEpoch(waktu.toInt(), isUtc: true),
      lat: (koor[1] as num).toDouble(),
      lon: (koor[0] as num).toDouble(),
      magnitudo: mag,
      kedalamanKm: koor.length > 2 ? (koor[2] as num).toDouble().clamp(0, 800).toDouble() : 10,
      wilayah: '${p['place'] ?? ''}'.trim(),
      potensi: p['tsunami'] == 1 ? 'Berpotensi tsunami (menurut USGS)' : null,
      sumber: 'USGS',
      magnitudoUsgs: mag,
      mmiUsgs: (p['mmi'] as num?)?.toDouble(),
    ));
  }
  return out;
}

/// Gabungkan BMKG dan USGS. Satu gempa USGS dianggap sama dengan satu gempa BMKG bila selisih waktunya paling lama
/// [jendelaDetik] dan jaraknya paling jauh [jendelaKm]; tiap gempa BMKG dicocokkan paling banyak dengan satu gempa USGS
/// (yang paling mirip menurut waktu, jarak, dan magnitudo), sisanya tetap sebagai kejadian terpisah.
/// Yang cocok memakai data BMKG dan menambahkan magnitudo/MMI USGS sebagai pembanding.
List<GempaBmkg> gabungSumber(List<GempaBmkg> bmkg, List<GempaBmkg> usgs, {int jendelaDetik = 120, double jendelaKm = 150}) {
  double skor(GempaBmkg a, GempaBmkg b) {
    final dt = a.waktuUtc.difference(b.waktuUtc).inSeconds.abs();
    final dk = _jarakKm(a.lat, a.lon, b.lat, b.lon);
    final dm = (a.magnitudo - b.magnitudo).abs();
    if (dt > jendelaDetik || dk > jendelaKm || dm > 0.8) return double.infinity;
    // Magnitudo berbobot besar: gempa utama dan susulan/pendahulunya bisa hanya berselang beberapa detik di tempat yang
    // hampir sama, dan yang magnitudonya cocoklah pasangan sebenarnya.
    return dt / 30 + dk / 25 + dm * 8;
  }

  final pasangan = <(double, int, int)>[];
  for (var i = 0; i < bmkg.length; i++) {
    for (var j = 0; j < usgs.length; j++) {
      final k = skor(bmkg[i], usgs[j]);
      if (k.isFinite) pasangan.add((k, i, j));
    }
  }
  pasangan.sort((a, b) => a.$1.compareTo(b.$1));
  final bmkgTerpakai = <int, int>{}, usgsTerpakai = <int>{};
  for (final (_, i, j) in pasangan) {
    if (bmkgTerpakai.containsKey(i) || usgsTerpakai.contains(j)) continue;
    bmkgTerpakai[i] = j;
    usgsTerpakai.add(j);
  }
  final hasil = <GempaBmkg>[];
  for (var i = 0; i < bmkg.length; i++) {
    final j = bmkgTerpakai[i];
    hasil.add(j == null
        ? bmkg[i]
        : bmkg[i].dengan(sumber: 'BMKG+USGS', magnitudoUsgs: usgs[j].magnitudoUsgs, mmiUsgs: usgs[j].mmiUsgs));
  }
  for (var j = 0; j < usgs.length; j++) {
    if (!usgsTerpakai.contains(j)) hasil.add(usgs[j]);
  }
  hasil.sort((a, b) => b.waktuUtc.compareTo(a.waktuUtc));
  return hasil;
}

double _jarakKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0088;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Hasil pengambilan katalog gabungan beserta status tiap sumber.
class HasilKatalog {
  final List<GempaBmkg> gempa;
  final bool bmkgOk, usgsOk;
  const HasilKatalog(this.gempa, {this.bmkgOk = true, this.usgsOk = true});
}

class KatalogBmkg {
  final http.Client _klien;
  KatalogBmkg(this._klien);

  Future<List<GempaBmkg>?> _ambilUsgs(int hari) async {
    try {
      final mulai = DateTime.now().toUtc().subtract(Duration(days: hari)).toIso8601String().split('.').first;
      final uri = Uri.https('earthquake.usgs.gov', '/fdsnws/event/1/query', {
        'format': 'geojson',
        'starttime': mulai,
        'minmagnitude': '4',
        'orderby': 'time',
        'minlatitude': '-12',
        'maxlatitude': '7',
        'minlongitude': '94',
        'maxlongitude': '142',
      });
      final r = await _klien.get(uri).timeout(_batas);
      if (r.statusCode != 200) return null;
      return uraiUsgs(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  /// BMKG (M5+, dirasakan) digabung USGS (M4+). Gagal total dari kedua sumber -> [GalatJaringan]; bila hanya satu
  /// sumber gagal, yang lain tetap ditampilkan dan statusnya dicatat di [HasilKatalog].
  Future<HasilKatalog> ambilLengkap({int hari = 30}) async {
    final hasil = await Future.wait<List<GempaBmkg>?>([_ambilBmkg(), _ambilUsgs(hari)]);
    final b = hasil[0], u = hasil[1];
    if (b == null && u == null) throw GalatJaringan('Tidak bisa menghubungi server BMKG maupun USGS. Periksa koneksi internet.');
    return HasilKatalog(gabungSumber(b ?? const [], u ?? const []), bmkgOk: b != null, usgsOk: u != null);
  }

  Future<List<GempaBmkg>?> _ambilBmkg() async {
    final hasil = await Future.wait([_ambil('autogempa.json'), _ambil('gempaterkini.json'), _ambil('gempadirasakan.json')]);
    final ada = hasil.whereType<List<GempaBmkg>>().toList();
    return ada.isEmpty ? null : gabungkan(ada);
  }

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
