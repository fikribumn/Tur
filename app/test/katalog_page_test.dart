// Tes widget: halaman katalog (filter, terdekat dari lokasimu, peringatan sumber) dan simulasi gempa nyata.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_aman_gempa/katalog_page.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/hasil.dart';
import 'package:zona_aman_gempa/mesin/katalog_bmkg.dart';
import 'package:zona_aman_gempa/mesin/peta_geologi.dart';
import 'package:zona_aman_gempa/simulasi_page.dart';

import 'simulasi_page_test.dart' as dasar;

final _sekarang = DateTime.now().toUtc();

GempaBmkg _gempa({
  double m = 5.4,
  double dalam = 10,
  List<LaporanDirasakan> rasa = const [],
  String? potensi,
  int jamLalu = 3,
  double lat = -9.20,
  double lon = 110.39,
  String wilayah = '136 km BaratDaya GUNUNGKIDUL-DIY',
  String sumber = 'BMKG',
  double? magUsgs,
  double? mmiUsgs,
}) =>
    GempaBmkg(
      waktuUtc: _sekarang.subtract(Duration(hours: jamLalu)),
      lat: lat,
      lon: lon,
      magnitudo: m,
      kedalamanKm: dalam,
      wilayah: wilayah,
      potensi: potensi,
      dirasakan: rasa,
      sumber: sumber,
      magnitudoUsgs: magUsgs,
      mmiUsgs: mmiUsgs,
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
    Future<void> buka(
      WidgetTester t,
      List<GempaBmkg> data,
      void Function(GempaBmkg) onSim, {
      HasilLokasi? lokasi,
      bool usgsOk = true,
      bool bmkgOk = true,
    }) async {
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: KatalogPage(
          ambil: () async => HasilKatalog(data, usgsOk: usgsOk, bmkgOk: bmkgOk),
          onSimulasi: onSim,
          lokasiSaya: lokasi,
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
    }

    Future<void> bukaFilter(WidgetTester t) async {
      await t.tap(find.text('Filter'));
      await t.pumpAndSettle();
    }

    testWidgets('menampilkan daftar, jumlah, laporan dirasakan, sumber, dan peringatan tsunami', (t) async {
      await buka(t, [
        _gempa(m: 7.1, rasa: _rasa, potensi: 'Berpotensi tsunami'),
        _gempa(m: 4.8, jamLalu: 30, sumber: 'USGS'),
      ], (_) {});
      expect(find.text('7.1'), findsOneWidget);
      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('2 gempa'), findsOneWidget);
      expect(find.textContaining('Dirasakan di 3 daerah'), findsOneWidget);
      expect(find.textContaining('maks MMI III'), findsOneWidget);
      expect(find.textContaining('BERPOTENSI TSUNAMI'), findsOneWidget);
      expect(find.textContaining('3 jam lalu'), findsOneWidget);
      Finder kartuSumber(String x) => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').endsWith('Sumber: $x'));
      expect(kartuSumber('BMKG'), findsOneWidget);
      expect(kartuSumber('USGS'), findsOneWidget);
    });

    testWidgets('bawaan 7 hari dan M4+: gempa 10 hari lalu tersembunyi, muncul bila 30 hari dipilih', (t) async {
      await buka(t, [_gempa(m: 5.1, jamLalu: 5), _gempa(m: 4.4, jamLalu: 24 * 10)], (_) {});
      expect(find.text('5.1'), findsOneWidget);
      expect(find.text('4.4'), findsNothing);
      await bukaFilter(t);
      await t.tap(find.text('30 hari'));
      await t.pumpAndSettle();
      expect(find.text('4.4'), findsOneWidget);
    });

    testWidgets('filter M5+ menyembunyikan gempa M4', (t) async {
      await buka(t, [_gempa(m: 5.6), _gempa(m: 4.3, jamLalu: 6)], (_) {});
      expect(find.text('4.3'), findsOneWidget);
      await bukaFilter(t);
      await t.tap(find.text('M5+'));
      await t.pumpAndSettle();
      expect(find.text('4.3'), findsNothing);
      expect(find.text('5.6'), findsOneWidget);
    });

    testWidgets('hanya yang dirasakan menyaring daftar', (t) async {
      await buka(t, [_gempa(m: 5.9, rasa: _rasa), _gempa(m: 4.8, jamLalu: 6)], (_) {});
      await bukaFilter(t);
      await t.tap(find.text('Hanya yang dirasakan'));
      await t.pumpAndSettle();
      expect(find.text('5.9'), findsOneWidget);
      expect(find.text('4.8'), findsNothing);
    });

    testWidgets('tanpa lokasi: tidak ada kartu terdekat dan tidak ada filter jarak', (t) async {
      await buka(t, [_gempa()], (_) {});
      expect(find.textContaining('Terdekat dari lokasimu'), findsNothing);
      await bukaFilter(t);
      expect(find.text('Jarak dari lokasimu'), findsNothing);
      expect(find.text('Terdekat'), findsNothing); // opsi urutan jarak butuh lokasi
    });

    testWidgets('dengan lokasi: kartu terdekat, jarak dan arah per gempa, radius menyaring', (t) async {
      // lokasi contoh: Bantul (-7.888, 110.329)
      final dekat = _gempa(m: 4.3, jamLalu: 20, lat: -8.40, lon: 110.40, wilayah: '57 km S of Pundong', sumber: 'USGS'); // ~58 km
      final jauh = _gempa(m: 5.4, jamLalu: 3, lat: -9.20, lon: 110.39); // ~146 km
      await buka(t, [jauh, dekat], (_) {}, lokasi: dasar.contohHasil());
      expect(find.textContaining('Terdekat dari lokasimu: M4.3'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ km ke selatan')), findsWidgets);
      expect(find.text('2 gempa'), findsOneWidget); // bawaan radius 500 km
      await bukaFilter(t);
      await t.tap(find.text('100 km'));
      await t.pumpAndSettle();
      expect(find.text('1 gempa'), findsOneWidget);
      expect(find.text('5.4'), findsNothing); // yang 146 km tersaring
      expect(find.text('4.3'), findsWidgets);
    });

    testWidgets('urutan Terdekat menaruh gempa terdekat di atas', (t) async {
      final dekat = _gempa(m: 4.3, jamLalu: 30, lat: -8.40, lon: 110.40, sumber: 'USGS');
      final jauh = _gempa(m: 5.4, jamLalu: 3, lat: -9.20, lon: 110.39);
      await buka(t, [dekat, jauh], (_) {}, lokasi: dasar.contohHasil());
      final yBaru = t.getTopLeft(find.text('5.4')).dy; // bawaan terbaru: yang 3 jam lalu di atas
      final yLama = t.getTopLeft(find.text('4.3').last).dy;
      expect(yBaru, lessThan(yLama));
      await bukaFilter(t);
      await t.tap(find.text('Terdekat').last);
      await t.pumpAndSettle();
      final y1 = t.getTopLeft(find.text('4.3').last).dy;
      final y2 = t.getTopLeft(find.text('5.4')).dy;
      expect(y1, lessThan(y2));
    });

    testWidgets('tidak ada gempa terdekat -> kartu memberi tahu, bukan kosong', (t) async {
      await buka(t, [], (_) {}, lokasi: dasar.contohHasil());
      expect(find.textContaining('Tidak ada gempa M4+ dalam 7 hari terakhir'), findsOneWidget);
    });

    testWidgets('USGS gagal: peringatan bahwa M4-M5 tidak tersedia; BMKG gagal: peringatan juga', (t) async {
      await buka(t, [_gempa()], (_) {}, usgsOk: false);
      expect(find.textContaining('Gempa M4–M5 tidak tersedia'), findsOneWidget);
    });

    testWidgets('BMKG gagal: peringatan', (t) async {
      await buka(t, [_gempa(sumber: 'USGS')], (_) {}, bmkgOk: false);
      expect(find.textContaining('Server BMKG tidak terjangkau'), findsOneWidget);
    });

    testWidgets('ketuk gempa membuka detail dengan sumber dan magnitudo USGS; tombol Simulasikan memanggil callback', (t) async {
      GempaBmkg? dipilih;
      final g = _gempa(m: 5.4, rasa: _rasa, sumber: 'BMKG+USGS', magUsgs: 5.2, mmiUsgs: 3.2);
      await buka(t, [g], (x) => dipilih = x);
      await t.tap(find.text('5.4'));
      await t.pumpAndSettle();
      expect(find.text('Simulasikan gempa ini'), findsOneWidget);
      expect(find.text('Bantul · II'), findsOneWidget);
      expect(find.textContaining('USGS mencatat M5.2'), findsOneWidget);
      expect(find.textContaining('MMI maksimum perkiraan USGS (ShakeMap): 3.2'), findsOneWidget);
      await t.tap(find.text('Simulasikan gempa ini'));
      await t.pumpAndSettle();
      expect(dipilih, same(g));
    });

    testWidgets('gempa dalam: detail memperingatkan di luar domain model', (t) async {
      await buka(t, [_gempa(m: 6.2, dalam: 120)], (_) {});
      await t.tap(find.text('6.2'));
      await t.pumpAndSettle();
      expect(find.textContaining('melebihi 30 km'), findsOneWidget);
    });

    testWidgets('gagal memuat: pesan dan tombol coba lagi', (t) async {
      var panggilan = 0;
      t.view.physicalSize = const Size(1080, 4000);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: KatalogPage(
          ambil: () async {
            panggilan++;
            if (panggilan == 1) throw Exception('Tidak bisa menghubungi server BMKG maupun USGS.');
            return HasilKatalog([_gempa(m: 5.2)]);
          },
          onSimulasi: (_) {},
        ),
      ));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Tidak bisa menghubungi server BMKG maupun USGS'), findsOneWidget);
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

    testWidgets('spanduk menyebut sumber; sumber, magnitudo, kedalaman dan arah sesar terisi dari gempa', (t) async {
      await buka(t, _gempa(m: 5.4, dalam: 10, rasa: _rasa));
      expect(find.textContaining('Gempa nyata (BMKG)'), findsOneWidget);
      expect(find.textContaining('M5.4 · 10 km'), findsOneWidget);
      expect(find.text('Magnitudo 5.4'), findsOneWidget);
      expect(find.text('Kedalaman 10 km'), findsOneWidget);
      expect(find.textContaining('Arah sesar 40°'), findsOneWidget);
      expect(find.textContaining('diperkirakan dari sesar aktif terdekat'), findsOneWidget);
    });

    testWidgets('gempa dari USGS (tanpa laporan dirasakan): spanduk menyebut USGS, tanpa bagian perbandingan', (t) async {
      await buka(t, _gempa(m: 4.4, sumber: 'USGS'));
      expect(find.textContaining('Gempa nyata (USGS)'), findsOneWidget);
      expect(find.textContaining('Bandingkan dengan laporan BMKG'), findsNothing);
    });

    testWidgets('magnitudo di bawah 4,5 tetap bisa disimulasikan', (t) async {
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
  });
}
