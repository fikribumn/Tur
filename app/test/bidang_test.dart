// Tes peta guncangan: bentuk bergantung pada geologi (Vs30 per sel) dan arah/panjang retakan, bukan lingkaran.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zona_aman_gempa/mesin/bidang_guncangan.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/peta_geologi.dart';
import 'package:zona_aman_gempa/mesin/simulasi.dart';

/// MMI pada sel yang memuat (lat, lon).
double mmiDi(BidangGuncangan b, double lat, double lon) {
  final g = b.grid;
  final i = ((lat - g.lat0) / g.dLat).floor(), j = ((lon - g.lon0) / g.dLon).floor();
  return b.mmi[i * g.nx + j];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('retakan memanjang', () {
    test('panjang retakan membesar dengan magnitudo dan masuk akal (M7 mendatar ~ 60 km)', () {
      expect(panjangRupturKm(7.0, Mekanisme.mendatar), inInclusiveRange(50, 70));
      expect(panjangRupturKm(7.5, Mekanisme.naik), greaterThan(panjangRupturKm(6.5, Mekanisme.naik)));
      expect(panjangRupturKm(5.0, Mekanisme.mendatar), lessThan(5));
    });

    test('segmen: panjang tepat dan searah strike', () {
      final utara = segmenRuptur(-7.9, 110.3, 40, 0);
      expect(jarakKm(utara.lat1, utara.lon1, utara.lat2, utara.lon2), closeTo(40, 0.3));
      expect(utara.lon1, closeTo(utara.lon2, 1e-9)); // strike 0 = utara-selatan
      final timur = segmenRuptur(-7.9, 110.3, 40, 90);
      expect(timur.lat1, closeTo(timur.lat2, 1e-9)); // strike 90 = barat-timur
    });

    test('jarak ke segmen: di ujung dihitung ke ujung, di samping tegak lurus', () {
      final s = segmenRuptur(0, 100, 40, 0);
      expect(jarakKeSegmenKm(0, 100.2, s), closeTo(22.2, 0.5)); // 0,2 derajat ~22,2 km, tegak lurus
      expect(jarakKeSegmenKm(0.4, 100, s), closeTo(0.4 * 110.57 - 20, 0.5)); // 44,2 km dari pusat - 20 = 24,2
      expect(jarakKeSegmenKm(0, 100, s), closeTo(0, 1e-6));
    });
  });

  group('bentuk area terdampak', () {
    test('seragam: lebih kuat searah sesar daripada tegak lurus pada jarak pusat yang sama (memanjang, bukan bulat)', () {
      final g = GridVs30.seragam(0, 100, 150, 110, 400);
      final seg = segmenRuptur(0, 100, panjangRupturKm(7.0, Mekanisme.mendatar), 0); // sesar utara-selatan
      final b = hitungBidang(g, seg: seg, m: 7.0, mek: Mekanisme.mendatar);
      final utara = mmiDi(b, 60 / 110.57, 100); // 60 km searah sesar
      final timur = mmiDi(b, 0, 100 + 60 / 111.32); // 60 km tegak lurus
      expect(utara, greaterThan(timur + 0.3));
    });

    test('bergantung geologi: sisi tanah lunak lebih kuat daripada sisi batuan pada jarak sama', () {
      final g = GridVs30.jendela(0, 100, 100, 100);
      // separuh barat aluvium lunak (Vs30 200), separuh timur batuan keras (Vs30 800)
      isiPoligon(g, [
        [[g.lon0 - 1, g.lat0 - 1], [100.0, g.lat0 - 1], [100.0, g.lat1 + 1], [g.lon0 - 1, g.lat1 + 1]]
      ], 200);
      isiPoligon(g, [
        [[100.0, g.lat0 - 1], [g.lon1 + 1, g.lat0 - 1], [g.lon1 + 1, g.lat1 + 1], [100.0, g.lat1 + 1]]
      ], 800);
      final seg = segmenRuptur(0, 100, 30, 0);
      final b = hitungBidang(g, seg: seg, m: 6.8, mek: Mekanisme.mendatar);
      final lunak = mmiDi(b, 0, 100 - 30 / 111.32);
      final keras = mmiDi(b, 0, 100 + 30 / 111.32);
      expect(lunak, greaterThan(keras + 0.7), reason: 'lunak=$lunak keras=$keras');
    });

    test('sel tanpa data (laut) tidak diwarnai', () {
      final g = GridVs30.jendela(0, 100, 50, 20); // semua NaN
      final b = hitungBidang(g, seg: segmenRuptur(0, 100, 20, 0), m: 6.5, mek: Mekanisme.mendatar);
      expect(b.mmi.every((v) => v.isNaN), isTrue);
      final rgba = warnaRgba(b);
      for (var i = 3; i < rgba.length; i += 4) {
        expect(rgba[i], 0);
      }
    });
  });

  group('rasterisasi poligon', () {
    test('aturan genap-ganjil: lubang tetap kosong', () {
      final g = GridVs30.jendela(0, 100, 50, 40);
      final luar = [[g.lon0 + 0.05, g.lat0 + 0.05], [g.lon1 - 0.05, g.lat0 + 0.05], [g.lon1 - 0.05, g.lat1 - 0.05], [g.lon0 + 0.05, g.lat1 - 0.05]];
      final lubang = [[99.9, -0.1], [100.1, -0.1], [100.1, 0.1], [99.9, 0.1]];
      isiPoligon(g, [luar, lubang], 300);
      expect(g.vs30[(20) * g.nx + 20].isNaN, isTrue); // pusat = lubang
      expect(g.vs30[5 * g.nx + 5], 300); // di dalam poligon luar
      expect(g.jumlahData, greaterThan(100));
    });
  });

  group('celah tertutup', () {
    test('lubang di dalam daratan diisi tetangga terdekat, laut di tepi tetap kosong', () {
      final g = GridVs30(lat0: 0, lon0: 0, dLat: 1, dLon: 1, ny: 12, nx: 12);
      // daratan = kolom 0..8, laut = kolom 9..11 (tersambung ke tepi); lubang 2x2 di tengah daratan
      for (var i = 0; i < 12; i++) {
        for (var j = 0; j <= 8; j++) {
          g.vs30[i * 12 + j] = j < 4 ? 200 : 700;
        }
      }
      for (final (i, j) in [(5, 3), (5, 4), (6, 3), (6, 4)]) {
        g.vs30[i * 12 + j] = double.nan;
      }
      final diisi = isiCelahTertutup(g);
      expect(diisi, 4);
      expect(g.vs30[5 * 12 + 3], anyOf(200, 700)); // terisi nilai tetangga, bukan NaN
      expect(g.vs30[6 * 12 + 4].isNaN, isFalse);
      for (var i = 0; i < 12; i++) {
        expect(g.vs30[i * 12 + 10].isNaN, isTrue); // laut tidak disentuh
      }
    });

    test('celah yang terlalu luas tidak diisi', () {
      final g = GridVs30(lat0: 0, lon0: 0, dLat: 1, dLon: 1, ny: 20, nx: 20);
      for (var i = 0; i < 20; i++) {
        for (var j = 0; j < 20; j++) {
          final tengah = i >= 4 && i <= 15 && j >= 4 && j <= 15;
          final tepi = i == 2 || i == 17 || j == 2 || j == 17;
          if (tengah || tepi || (i > 2 && i < 17 && j > 2 && j < 17)) g.vs30[i * 20 + j] = 300;
        }
      }
      for (var i = 6; i <= 13; i++) {
        for (var j = 6; j <= 13; j++) {
          g.vs30[i * 20 + j] = double.nan; // celah 8x8 = 64 sel
        }
      }
      expect(isiCelahTertutup(g, maksSel: 30), 0);
      expect(g.vs30[8 * 20 + 8].isNaN, isTrue);
      expect(isiCelahTertutup(g, maksSel: 100), 64);
    });
  });

  group('warna', () {
    test('MMI rendah transparan, makin tinggi makin pekat dan menuju merah', () {
      expect(warnaMmi(2.0).$4, 0);
      expect(warnaMmi(double.nan).$4, 0);
      expect(warnaMmi(8.0).$4, greaterThan(warnaMmi(5.0).$4));
      final r8 = warnaMmi(8.0), r5 = warnaMmi(5.0);
      expect(r8.$1, greaterThan(r8.$3)); // merah dominan di MMI 8
      expect(r5.$2, greaterThan(r5.$1)); // hijau dominan di MMI 5
    });
  });

  testWidgets('kePng menghasilkan PNG valid', (t) async {
    await t.runAsync(() async {
      final g = GridVs30.seragam(0, 100, 50, 16, 300);
      final b = hitungBidang(g, seg: segmenRuptur(0, 100, 30, 0), m: 7.0, mek: Mekanisme.mendatar);
      final png = await kePng(warnaRgba(b), g.nx, g.ny);
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group('server Badan Geologi (butuh internet)', () {
    test('geologi sekitar Yogyakarta menghasilkan grid Vs30 yang bervariasi', () async {
      HttpOverrides.global = null;
      final lito = jsonDecode(await File('assets/data/litologi_dampak.json').readAsString()) as Map<String, dynamic>;
      final pemuat = PemuatGeologi(http.Client(), Map<String, dynamic>.from(lito['kelas'] as Map),
          Map<String, dynamic>.from(lito['pemetaan_simobj'] as Map));
      final g = await pemuat.muat(-7.9, 110.35, 40, n: 80);
      final vs = g.vs30.where((v) => !v.isNaN).toList()..sort();
      // ignore: avoid_print
      print('sel berisi ${vs.length}/${g.vs30.length}; Vs30 min ${vs.first} median ${vs[vs.length ~/ 2]} maks ${vs.last}');
      expect(vs.length, greaterThan(g.vs30.length * 0.3)); // sebagian besar daratan
      expect(vs.length, lessThan(g.vs30.length)); // ada laut di selatan
      expect(vs.first, lessThan(300)); // ada tanah lunak (graben/aluvium)
      expect(vs.last, greaterThanOrEqualTo(500)); // ada batuan lebih keras (perbukitan)
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
