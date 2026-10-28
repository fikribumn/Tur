// Perbandingan model dengan laporan "dirasakan" BMKG: tiap daerah dicari koordinatnya (pusat daerah, perkiraan),
// lalu MMI model dihitung di titik itu dan dibandingkan dengan skala yang dilaporkan BMKG.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gmpe.dart';
import 'katalog_bmkg.dart';
import 'simulasi.dart';

const _agen = 'TERRA-TUR/1.5 (aplikasi riset kerentanan gempa; id.zonaaman.zona_aman_gempa)';

/// Dari hasil pencarian Nominatim, pilih satu titik. Laporan BMKG menyebut kabupaten/kota tanpa provinsi, jadi batas
/// administrasi (kabupaten, kota) didahulukan agar tidak salah ke desa kecil bernama sama; di antara kandidat sejenis
/// dipilih yang paling dekat dengan pusat gempa untuk menyingkirkan nama kembar di pulau lain.
(double, double)? pilihTerdekat(List<Map<String, dynamic>> hasil, double lat, double lon) {
  bool administrasi(Map<String, dynamic> h) => h['category'] == 'boundary' && h['type'] == 'administrative';
  final utama = hasil.where(administrasi).toList();
  final kandidat = utama.isNotEmpty ? utama : hasil;
  (double, double)? terbaik;
  var jarak = double.infinity;
  for (final h in kandidat) {
    final la = double.tryParse('${h['lat']}'), lo = double.tryParse('${h['lon']}');
    if (la == null || lo == null) continue;
    final d = jarakKm(lat, lon, la, lo);
    if (d < jarak) {
      jarak = d;
      terbaik = (la, lo);
    }
  }
  return terbaik;
}

/// Pilih titik dari batas administrasi setingkat kabupaten/kota (addresstype county/regency/city) yang paling dekat
/// dengan (lat, lon). Null bila tidak ada hasil setingkat itu.
(double, double)? pilihAdministrasi(List<Map<String, dynamic>> hasil, double lat, double lon) {
  const tingkat = {'county', 'regency', 'city'};
  final cocok = [
    for (final h in hasil)
      if (h['category'] == 'boundary' && h['type'] == 'administrative' && tingkat.contains(h['addresstype'])) h,
  ];
  return cocok.isEmpty ? null : pilihTerdekat(cocok, lat, lon);
}

/// Pencari koordinat nama daerah lewat Nominatim (OpenStreetMap). Kebijakan pemakaiannya: paling banyak
/// 1 permintaan per detik dan identitas aplikasi yang jelas, jadi permintaan diberi jeda dan hasilnya di-cache.
class Geokoder {
  final http.Client _klien;
  final Duration jeda;
  final _cache = <String, (double, double)?>{};
  DateTime _terakhir = DateTime.fromMillisecondsSinceEpoch(0);

  Geokoder(this._klien, {this.jeda = const Duration(milliseconds: 1100)});

  Future<(double, double)?> cari(String nama, double dekatLat, double dekatLon) async {
    final kunci = '${nama.toLowerCase()}|${dekatLat.toStringAsFixed(1)}|${dekatLon.toStringAsFixed(1)}';
    if (_cache.containsKey(kunci)) return _cache[kunci];
    // BMKG menulis nama kabupaten/kota tanpa awalan, padahal pencarian polos sering hanya memberi desa bernama sama.
    // Coba "Kabupaten X", lalu "Kota X", lalu nama polos; hanya hasil setingkat kabupaten/kota yang langsung diterima.
    (double, double)? cadangan;
    var gagal = false;
    for (final q in ['Kabupaten $nama', 'Kota $nama', nama]) {
      try {
        final hasil = await _cari(q);
        final admin = pilihAdministrasi(hasil, dekatLat, dekatLon);
        if (admin != null) return _cache[kunci] = admin;
        cadangan ??= pilihTerdekat(hasil, dekatLat, dekatLon);
      } catch (_) {
        gagal = true; // jaringan putus: jangan di-cache
        break;
      }
    }
    if (gagal && cadangan == null) return null;
    return _cache[kunci] = cadangan;
  }

  Future<List<Map<String, dynamic>>> _cari(String q) async {
    final tunggu = jeda - DateTime.now().difference(_terakhir);
    if (tunggu > Duration.zero) await Future<void>.delayed(tunggu);
    _terakhir = DateTime.now();
    final r = await _klien
        .get(
          Uri.https('nominatim.openstreetmap.org', '/search',
              {'q': q, 'format': 'jsonv2', 'countrycodes': 'id', 'limit': '5', 'accept-language': 'id'}),
          headers: {'User-Agent': _agen},
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) return const [];
    return (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map<String, dynamic>>();
  }
}

class BarisPerbandingan {
  final LaporanDirasakan laporan;
  final double? lat, lon;

  /// MMI model di titik itu; null bila daerah tidak ditemukan.
  final double? mmiModel;
  const BarisPerbandingan(this.laporan, this.lat, this.lon, this.mmiModel);

  /// Model dikurangi laporan BMKG (positif = model lebih tinggi).
  double? get selisih => mmiModel == null ? null : mmiModel! - laporan.mmi;
}

class RingkasanPerbandingan {
  final int n, tidakDitemukan, dalamSatuSkala;
  final double? rataSelisih, rataMutlak;
  const RingkasanPerbandingan(this.n, this.tidakDitemukan, this.dalamSatuSkala, this.rataSelisih, this.rataMutlak);
}

/// Hitung MMI model di tiap titik laporan. [vs30Di] memberi Vs30 setempat (mis. dari grid geologi).
List<BarisPerbandingan> bandingkan({
  required List<(LaporanDirasakan, (double, double)?)> titik,
  required double srcLat,
  required double srcLon,
  required double magnitudo,
  required double kedalamanKm,
  required double arahSesarDeg,
  required Mekanisme mekanisme,
  required double Function(double lat, double lon) vs30Di,
}) {
  return [
    for (final (lap, p) in titik)
      if (p == null)
        BarisPerbandingan(lap, null, null, null)
      else
        BarisPerbandingan(
          lap,
          p.$1,
          p.$2,
          simulasikan(
            srcLat: srcLat,
            srcLon: srcLon,
            siteLat: p.$1,
            siteLon: p.$2,
            magnitudo: magnitudo,
            kedalamanKm: kedalamanKm,
            vs30: vs30Di(p.$1, p.$2),
            mekanisme: mekanisme,
            arahSesarDeg: arahSesarDeg,
          ).mmi,
        ),
  ];
}

RingkasanPerbandingan ringkas(List<BarisPerbandingan> baris) {
  final ada = baris.where((b) => b.selisih != null).toList();
  if (ada.isEmpty) return RingkasanPerbandingan(0, baris.length, 0, null, null);
  final rata = ada.map((b) => b.selisih!).reduce((a, b) => a + b) / ada.length;
  final mutlak = ada.map((b) => b.selisih!.abs()).reduce((a, b) => a + b) / ada.length;
  return RingkasanPerbandingan(
      ada.length, baris.length - ada.length, ada.where((b) => b.selisih!.abs() <= 1.0).length, rata, mutlak);
}
