// Tes widget: halaman katalog BMKG dan simulasi gempa nyata (spanduk, perbandingan dengan laporan dirasakan).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_aman_gempa/katalog_page.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/katalog_bmkg.dart';
import 'package:zona_aman_gempa/mesin/peta_geologi.dart';
import 'package:zona_aman_gempa/simulasi_page.dart';

import 'simulasi_page_test.dart' as dasar;

final _sekarang = DateTime.now().toUtc();

GempaBmkg _gempa({double m = 5.4, double dalam = 10, List<LaporanDirasakan> rasa = const [], String? potensi, int jamLalu = 3}) => GempaBmkg(
      waktuUtc: _sekarang.subtract(Duration(hours: jamLalu)),
      lat: -9.20,
      lon: 110.39,
      magnitudo: m,
      kedalamanKm: dalam,
      wilayah: '136 km BaratDaya GUNUNGKIDUL-DIY',
      potensi: potensi,
      dirasakan: rasa,
    );

final _rasa = [
  const LaporanDirasakan('II', 2, 'Bantul'),
  const LaporanDirasakan('II-III', 2.5, 'Sleman'),
  const LaporanDirasakan('III', 3, 'Klaten'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png1x1 = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

  group('halaman katalog', () {
    Future<void> buka(WidgetTester t, Future<List<GempaBmkg>> Function() ambil, void Function(GempaBmkg) onSim) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: KatalogPage(ambil: ambil, onSimulasi: onSim)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('menampilkan daftar gempa, laporan dirasakan, dan peringatan tsunami', (t) async {
      await buka(t, () async => [
            _gempa(m: 7.1, rasa: _rasa, potensi: 'Berpotensi tsunami'),
            _gempa(m: 4.8, jamLalu: 30),
          ], (_) {});
      expect(find.text('7.1'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.textContaining('Dirasakan di 3 daerah'), findsOneWidget);
      expect(find.textContaining('maks MMI III'), findsOneWidget);
      expect(find.textContaining('BERPOTENSI TSUNAMI'), findsOneWidget);
      expect(find.textContaining('3 jam lalu'), findsOneWidget);
      expect(find.text('Semua (2)'), findsOneWidget);
      expect(find.text('Dirasakan (1)'), findsOneWidget);
    });

    testWidgets('filter Dirasakan menyaring daftar', (t) async {
      await buka(t, () async => [_gempa(m: 5.9, rasa: _rasa), _gempa(m: 4.8)], (_) {});
      await t.tap(find.text('Dirasakan (1)'));
      await t.pump();
      expect(find.text('5.9'), findsOneWidget);
      expect(find.text('4.8'), findsNothing);
    });

    testWidgets('ketuk gempa membuka detail; tombol Simulasikan memanggil callback dengan gempa itu', (t) async {
      GempaBmkg? dipilih;
      final g = _gempa(m: 5.9, rasa: _rasa);
      await buka(t, () async => [g], (x) => dipilih = x);
      await t.tap(find.text('5.9'));
      await t.pumpAndSettle();
      expect(find.text('Simulasikan gempa ini'), findsOneWidget);
      expect(find.text('Bantul · II'), findsOneWidget);
      await t.tap(find.text('Simulasikan gempa ini'));
      await t.pumpAndSettle();
      expect(dipilih, same(g));
    });

    testWidgets('gempa dalam: detail memperingatkan di luar domain model', (t) async {
      await buka(t, () async => [_gempa(m: 6.2, dalam: 120)], (_) {});
      await t.tap(find.text('6.2'));
      await t.pumpAndSettle();
      expect(find.textContaining('melebihi 30 km'), findsOneWidget);
    });

    testWidgets('gagal memuat: pesan dan tombol coba lagi', (t) async {
      var panggilan = 0;
      await buka(t, () async {
        panggilan++;
        if (panggilan == 1) throw Exception('Tidak bisa menghubungi server BMKG.');
        return [_gempa(m: 5.2)];
      }, (_) {});
      expect(find.textContaining('Tidak bisa menghubungi server BMKG'), findsOneWidget);
      await t.tap(find.text('Coba lagi'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('5.2'), findsOneWidget);
      expect(panggilan, 2);
    });
  });

  group('simulasi gempa nyata', () {
    var kueri = <String>[];
    Future<void> buka(WidgetTester t, GempaBmkg g, {Future<(double, double)?> Function(String, double, double)? geokode}) async {
      kueri = [];
      t.view.physicalSize = const Size(1080, 9000);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: SimulasiPage(
          lokasi: dasar.contohHasil(),
          analisis: (la, lo) async => dasar.contohHasil(lat: la, lon: lo),
          muatGeologi: (la, lo, r) async => GridVs30.seragam(la, lo, r, 30, 300),
          enkode: (rgba, w, h) async => png1x1,
          gempa: g,
          awalStrike: 40,
          awalMek: Mekanisme.mendatar,
          geokode: geokode ??
              (nama, la, lo) async {
                kueri.add(nama);
                return nama == 'Klaten' ? null : (-7.9, 110.4);
              },
        ),
      ));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('spanduk gempa BMKG; sumber, magnitudo, kedalaman dan arah sesar terisi dari gempa', (t) async {
      await buka(t, _gempa(m: 5.4, dalam: 10, rasa: _rasa));
      expect(find.textContaining('Gempa nyata BMKG'), findsOneWidget);
      expect(find.textContaining('M5.4 · 10 km'), findsOneWidget);
      expect(find.text('Magnitudo 5.4'), findsOneWidget);
      expect(find.text('Kedalaman 10 km'), findsOneWidget);
      expect(find.textContaining('Arah sesar 40°'), findsOneWidget);
      expect(find.textContaining('diperkirakan dari sesar aktif terdekat'), findsOneWidget);
    });

    testWidgets('magnitudo di bawah 4,5 (laporan dirasakan BMKG kecil) tetap bisa disimulasikan', (t) async {
      await buka(t, _gempa(m: 3.9, rasa: _rasa));
      expect(find.text('Magnitudo 3.9'), findsOneWidget);
    });

    testWidgets('perbandingan: geokode tiap daerah, tabel, ringkasan, daerah tak ditemukan ditandai', (t) async {
      await buka(t, _gempa(m: 5.9, rasa: _rasa));
      expect(find.textContaining('Bandingkan dengan laporan BMKG (3 daerah)'), findsOneWidget);
      await t.tap(find.byKey(const Key('tombol-banding')));
      await t.pump(const Duration(milliseconds: 300));
      expect(kueri, ['Bantul', 'Sleman', 'Klaten']);
      expect(find.text('Bantul'), findsOneWidget);
      expect(find.text('II-III'), findsOneWidget);
      expect(find.textContaining('Rata-rata selisih model−BMKG'), findsOneWidget);
      expect(find.textContaining('1 daerah tidak ditemukan'), findsOneWidget); // Klaten
      expect(find.textContaining('dari 2 daerah dalam ±1 skala'), findsOneWidget);
    });

    testWidgets('mengubah pengaturan menghapus hasil perbandingan lama; hitung ulang memakai koordinat yang sudah dicari', (t) async {
      await buka(t, _gempa(m: 5.9, rasa: _rasa));
      await t.tap(find.byKey(const Key('tombol-banding')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Rata-rata selisih'), findsOneWidget);
      await t.drag(find.byKey(const Key('slider-magnitudo')), const Offset(150, 0));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Rata-rata selisih'), findsNothing);
      expect(find.text('Hitung ulang dengan pengaturan sekarang'), findsOneWidget);
      await t.tap(find.byKey(const Key('tombol-banding')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Rata-rata selisih'), findsOneWidget);
      expect(kueri.length, 3, reason: 'koordinat daerah tidak dicari ulang');
    });

    testWidgets('gempa dalam: perbandingan tidak tersedia dan tidak ada tombol', (t) async {
      await buka(t, _gempa(m: 6.5, dalam: 90, rasa: _rasa));
      expect(find.textContaining('Tidak tersedia: kedalaman melebihi 30 km'), findsOneWidget);
      expect(find.byKey(const Key('tombol-banding')), findsNothing);
    });

    testWidgets('tanpa laporan dirasakan: bagian perbandingan tidak muncul', (t) async {
      await buka(t, _gempa(m: 5.0));
      expect(find.textContaining('Bandingkan dengan laporan BMKG'), findsNothing);
    });
  });
}
