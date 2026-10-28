// Tes katalog M4+: pengurai USGS, penggabungan dengan BMKG, penyaringan gempa terdekat, dan pengambilan langsung.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zona_aman_gempa/mesin/gempa_dekat.dart';
import 'package:zona_aman_gempa/mesin/katalog_bmkg.dart';
import 'package:zona_aman_gempa/mesin/simulasi.dart' show jarakKm;

// Bentuk nyata respons USGS (disingkat): dua gempa 27 Okt, satu ledakan tambang, satu tanpa magnitudo.
const _usgs = '{"type":"FeatureCollection","metadata":{"count":4,"status":200},"features":['
    '{"type":"Feature","properties":{"mag":5.4,"place":"128 km S of Pundong, Indonesia","time":1793112240933,"mmi":3.228,"tsunami":0,"type":"earthquake"},'
    '"geometry":{"type":"Point","coordinates":[110.3305,-9.1162,10]},"id":"us7000ttgf"},'
    '{"type":"Feature","properties":{"mag":4.9,"place":"156 km S of Pundong, Indonesia","time":1793112236000,"mmi":null,"tsunami":0,"type":"earthquake"},'
    '"geometry":{"type":"Point","coordinates":[110.30,-9.37,21]},"id":"us7000ttgg"},'
    '{"type":"Feature","properties":{"mag":4.1,"place":"quarry","time":1793100000000,"type":"quarry blast"},'
    '"geometry":{"type":"Point","coordinates":[110.0,-7.0,0]},"id":"x1"},'
    '{"type":"Feature","properties":{"mag":null,"place":"?","time":1793100000000,"type":"earthquake"},'
    '"geometry":{"type":"Point","coordinates":[110.0,-7.0,0]},"id":"x2"}]}';

GempaBmkg _b({required DateTime t, double lat = -9.20, double lon = 110.39, double m = 5.4, double dalam = 10, String w = 'BMKG'}) =>
    GempaBmkg(waktuUtc: t, lat: lat, lon: lon, magnitudo: m, kedalamanKm: dalam, wilayah: w);

void main() {
  final t0 = DateTime.utc(2026, 10, 27, 14, 43, 13);

  group('pengurai USGS', () {
    test('hanya gempa bermagnitudo; ledakan tambang dan magnitudo kosong dibuang; koordinat lon,lat,kedalaman benar', () {
      final g = uraiUsgs(_usgs);
      expect(g.length, 2);
      expect(g.first.magnitudo, 5.4);
      expect(g.first.lat, -9.1162);
      expect(g.first.lon, 110.3305);
      expect(g.first.kedalamanKm, 10);
      expect(g.first.sumber, 'USGS');
      expect(g.first.mmiUsgs, closeTo(3.228, 1e-9));
      expect(g[1].mmiUsgs, isNull);
      expect(g.first.waktuUtc, DateTime.fromMillisecondsSinceEpoch(1793112240933, isUtc: true));
      expect(g.first.waktuUtc.isUtc, isTrue);
    });
  });

  group('gabung BMKG dan USGS', () {
    test('gempa yang sama tidak ganda: memakai data BMKG, menambah magnitudo dan MMI USGS', () {
      final usgs = uraiUsgs(_usgs);
      final bmkg = [_b(t: DateTime.fromMillisecondsSinceEpoch(1793112240933 - 48000, isUtc: true))]; // M5,4 BMKG, 48 detik lebih awal
      final hasil = gabungSumber(bmkg, usgs);
      expect(hasil.length, 2); // M5,4 digabung; M4,9 tetap kejadian terpisah
      final gabung = hasil.firstWhere((e) => e.sumber == 'BMKG+USGS');
      expect(gabung.lat, -9.20); // koordinat BMKG dipertahankan
      expect(gabung.magnitudoUsgs, 5.4);
      expect(gabung.mmiUsgs, closeTo(3.228, 1e-9));
      final sisa = hasil.firstWhere((e) => e.sumber == 'USGS');
      expect(sisa.magnitudo, 4.9); // pasangan terbaik (magnitudo mirip) yang dipakai; yang lain tidak ikut tergabung
    });

    test('REGRESI kejadian nyata 27 Okt: USGS M4,9 hanya 4 detik sebelum BMKG, M5,4 USGS 48 detik sesudahnya; M5,4 yang dipasangkan', () {
      final bmkg = [_b(t: t0)]; // BMKG M5,4, 21:43:13 WIB
      final usgs = [
        _b(t: t0.add(const Duration(seconds: 48)), lat: -9.1162, lon: 110.3305, m: 5.4).dengan(sumber: 'USGS', magnitudoUsgs: 5.4, mmiUsgs: 3.2),
        _b(t: t0.subtract(const Duration(seconds: 4)), lat: -9.37, lon: 110.30, m: 4.9, dalam: 21).dengan(sumber: 'USGS', magnitudoUsgs: 4.9),
      ];
      final hasil = gabungSumber(bmkg, usgs);
      expect(hasil.length, 2);
      final gabung = hasil.firstWhere((e) => e.sumber == 'BMKG+USGS');
      expect(gabung.magnitudoUsgs, 5.4, reason: 'harus berpasangan dengan USGS M5,4, bukan M4,9');
      expect(hasil.firstWhere((e) => e.sumber == 'USGS').magnitudo, 4.9);
    });

    test('selisih magnitudo lebih dari 0,8 tidak dianggap gempa yang sama', () {
      final u = _b(t: t0, m: 4.4).dengan(sumber: 'USGS'); // BMKG M5,4 vs USGS M4,4
      expect(gabungSumber([_b(t: t0)], [u]).length, 2);
    });

    test('kejadian USGS yang tidak ada di BMKG (M4) tetap muncul; BMKG tanpa pasangan USGS tetap muncul', () {
      final usgsSaja = _b(t: t0.subtract(const Duration(days: 2)), m: 4.3, w: 'x').dengan(sumber: 'USGS');
      final bmkgSaja = _b(t: t0.subtract(const Duration(days: 5)), lat: 5.0, lon: 125.0, m: 5.6);
      final hasil = gabungSumber([bmkgSaja], [usgsSaja]);
      expect(hasil.length, 2);
      expect(hasil.map((e) => e.sumber).toSet(), {'BMKG', 'USGS'});
    });

    test('jauh dalam waktu atau jarak tidak dianggap sama', () {
      final u = _b(t: t0.add(const Duration(minutes: 10))).dengan(sumber: 'USGS');
      expect(gabungSumber([_b(t: t0)], [u]).length, 2);
      final u2 = _b(t: t0, lat: -5.0, lon: 106.0).dengan(sumber: 'USGS'); // lebih dari 150 km
      expect(gabungSumber([_b(t: t0)], [u2]).length, 2);
    });

    test('hasil urut terbaru dulu', () {
      final h = gabungSumber([_b(t: t0)], [_b(t: t0.subtract(const Duration(days: 1)), lat: 0, lon: 100).dengan(sumber: 'USGS')]);
      expect(h.first.waktuUtc.isAfter(h.last.waktuUtc), isTrue);
    });
  });

  group('gempaDekat', () {
    final sekarang = DateTime.utc(2026, 10, 28, 4);
    // lokasi pengguna: Yogyakarta
    const lat = -7.80, lon = 110.37;
    final semua = [
      _b(t: sekarang.subtract(const Duration(hours: 5)), lat: -9.20, lon: 110.39, m: 5.4), // ~155 km selatan
      _b(t: sekarang.subtract(const Duration(days: 3)), lat: -8.40, lon: 110.40, m: 4.3), // ~67 km
      _b(t: sekarang.subtract(const Duration(days: 20)), lat: -8.00, lon: 110.30, m: 4.1), // ~24 km, tapi 20 hari lalu
      _b(t: sekarang.subtract(const Duration(days: 1)), lat: 5.5, lon: 125.3, m: 5.4), // jauh (Sulawesi utara)
      _b(t: sekarang.subtract(const Duration(days: 1)), lat: -8.0, lon: 110.3, m: 3.8), // terlalu kecil
    ];

    test('radius, periode, dan magnitudo minimum', () {
      final r = gempaDekat(semua, lat, lon, radiusKm: 300, hari: 7, magMin: 4, sekarangUtc: sekarang);
      expect(r.map((e) => e.gempa.magnitudo).toSet(), {5.4, 4.3}); // 20 hari lalu, M3,8 dan yang jauh tersaring
      expect(gempaDekat(semua, lat, lon, radiusKm: 300, hari: 30, magMin: 4, sekarangUtc: sekarang).length, 3);
      expect(gempaDekat(semua, lat, lon, radiusKm: 300, hari: 30, magMin: 5, sekarangUtc: sekarang).length, 1);
      expect(gempaDekat(semua, lat, lon, hari: 30, magMin: 4, sekarangUtc: sekarang).length, 4); // tanpa radius
    });

    test('urutan: terbaru dulu atau terdekat dulu; jarak dan arah benar', () {
      final baru = gempaDekat(semua, lat, lon, radiusKm: 500, hari: 30, sekarangUtc: sekarang);
      expect(baru.first.gempa.magnitudo, 5.4);
      final dekat = gempaDekat(semua, lat, lon, radiusKm: 500, hari: 30, urutJarak: true, sekarangUtc: sekarang);
      expect(dekat.first.gempa.magnitudo, 4.1); // 24 km
      for (var i = 0; i < dekat.length - 1; i++) {
        expect(dekat[i].jarakKm, lessThanOrEqualTo(dekat[i + 1].jarakKm));
      }
      final selatan = baru.firstWhere((e) => e.gempa.lat == -9.20);
      expect(selatan.jarakKm, inInclusiveRange(150, 160));
      expect(selatan.arahDeg, anyOf(inInclusiveRange(175, 185)));
    });

    test('tidak ada yang cocok -> daftar kosong', () {
      expect(gempaDekat(semua, lat, lon, radiusKm: 10, hari: 30, sekarangUtc: sekarang), isEmpty);
    });
  });

  test('NYATA: katalog gabungan BMKG+USGS (butuh internet) dan gempa M4+ terdekat dari Yogyakarta', () async {
    HttpOverrides.global = null;
    final h = await KatalogBmkg(http.Client()).ambilLengkap();
    final berasal = <String, int>{};
    for (final g in h.gempa) {
      berasal[g.sumber] = (berasal[g.sumber] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('gabungan ${h.gempa.length} gempa; per sumber: $berasal; bmkgOk=${h.bmkgOk} usgsOk=${h.usgsOk}');
    expect(h.bmkgOk && h.usgsOk, isTrue);
    expect(h.gempa.where((g) => g.magnitudo < 5).length, greaterThan(10), reason: 'M4-M5 harus muncul dari USGS');
    expect(h.gempa.where((g) => g.sumber == 'BMKG+USGS').length, greaterThan(0), reason: 'sebagian besar M5+ tercatat di keduanya');
    final d = gempaDekat(h.gempa, -7.80, 110.37, radiusKm: 500, hari: 30, urutJarak: true);
    // ignore: avoid_print
    print('terdekat dari Yogyakarta (500 km, 30 hari): ${d.length} gempa; ${d.take(3).map((e) => 'M${e.gempa.magnitudo} ${e.jarakKm.round()} km ${e.gempa.sumber}').join(' | ')}');
    expect(d, isNotEmpty);
    // tidak ada kejadian ganda pada menit dan tempat yang sama
    final kunci = h.gempa.map((g) => '${g.waktuUtc.millisecondsSinceEpoch ~/ 60000}|${g.lat.toStringAsFixed(1)}|${g.lon.toStringAsFixed(1)}').toList();
    expect(kunci.toSet().length, kunci.length);
    // tiap gempa gabungan: magnitudo BMKG dan USGS harus berdekatan (pasangan sebenarnya)
    for (final g in h.gempa.where((e) => e.sumber == 'BMKG+USGS')) {
      expect((g.magnitudo - g.magnitudoUsgs!).abs(), lessThanOrEqualTo(0.8), reason: '${g.wilayah} M${g.magnitudo} vs USGS M${g.magnitudoUsgs}');
    }
    // tidak boleh ada gempa USGS-saja yang sebenarnya kembaran gempa BMKG (waktu, jarak, magnitudo hampir sama)
    for (final u in h.gempa.where((e) => e.sumber == 'USGS')) {
      for (final b in h.gempa.where((e) => e.sumber != 'USGS')) {
        final dt = u.waktuUtc.difference(b.waktuUtc).inSeconds.abs();
        final dm = (u.magnitudo - b.magnitudo).abs();
        final dk = jarakKm(u.lat, u.lon, b.lat, b.lon);
        expect(dt <= 120 && dk <= 150 && dm <= 0.3, isFalse,
            reason: 'kembaran tak tergabung: USGS M${u.magnitudo} ${u.wilayah} dan ${b.sumber} M${b.magnitudo} ${b.wilayah} (dt=${dt}s dk=${dk.round()}km)');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
