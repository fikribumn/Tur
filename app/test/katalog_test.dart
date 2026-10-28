// Tes katalog BMKG: pengurai (dengan format nyata data.bmkg.go.id), penggabungan, dan pengambilan langsung.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zona_aman_gempa/mesin/katalog_bmkg.dart';

const _auto = '{"Infogempa":{"gempa":{"Tanggal":"28 Okt 2026","Jam":"08:11:54 WIB","DateTime":"2026-10-28T01:11:54+00:00",'
    '"Coordinates":"5.59,125.27","Lintang":"5.59 LU","Bujur":"125.27 BT","Magnitude":"5.4","Kedalaman":"10 km",'
    '"Wilayah":"221 km BaratLaut PULAUKARATUNG-SULUT","Potensi":"Tidak berpotensi tsunami","Dirasakan":"-","Shakemap":"x.mmi.jpg"}}}';

const _kini = '{"Infogempa":{"gempa":['
    '{"Tanggal":"28 Okt 2026","Jam":"08:11:54 WIB","DateTime":"2026-10-28T01:11:54+00:00","Coordinates":"5.59,125.27","Magnitude":"5.4","Kedalaman":"10 km","Wilayah":"221 km BaratLaut PULAUKARATUNG-SULUT","Potensi":"Tidak berpotensi tsunami"},'
    '{"Tanggal":"27 Okt 2026","Jam":"21:43:13 WIB","DateTime":"2026-10-27T14:43:13+00:00","Coordinates":"-9.20,110.39","Magnitude":"5.4","Kedalaman":"10 km","Wilayah":"136 km BaratDaya GUNUNGKIDUL-DIY","Potensi":"Tidak berpotensi tsunami"}]}}';

const _rasa = '{"Infogempa":{"gempa":['
    '{"Tanggal":"27 Okt 2026","Jam":"21:43:13 WIB","DateTime":"2026-10-27T14:43:13+00:00","Coordinates":"-9.20,110.39","Magnitude":"5.4","Kedalaman":"10 km",'
    '"Wilayah":"Pusat gempa berada di laut 137 km Selatan Gunungkidul","Dirasakan":"II Bantul, II Sleman, II Wonogiri, II Kulon Progo, II Sukoharjo, II Trenggalek, II Nganjuk, II Pacitan, II Klaten, II Kediri, II Ponorogo, II Banjarnegara, II Lumajang, II Blitar"},'
    '{"Tanggal":"26 Okt 2026","Jam":"11:53:42 WIB","DateTime":"2026-10-26T04:53:42+00:00","Coordinates":"-8.45,121.45","Magnitude":"4.9","Kedalaman":"13 km","Wilayah":"Pusat gempa berada di darat","Dirasakan":"III-IV Ende, IV Sikka"}]}}';

void main() {
  group('pengurai', () {
    test('koordinat dan kedalaman', () {
      expect(uraiKoordinat('-9.20,110.39'), (-9.20, 110.39));
      expect(uraiKoordinat('5.59,125.27'), (5.59, 125.27));
      expect(uraiKoordinat('rusak'), isNull);
      expect(uraiKoordinat(null), isNull);
      expect(uraiKedalaman('10 km'), 10);
      expect(uraiKedalaman('13.5 km'), 13.5);
      expect(uraiKedalaman('?'), isNull);
    });

    test('skala MMI Romawi dan rentang', () {
      expect(uraiSkala('II'), 2);
      expect(uraiSkala('IV'), 4);
      expect(uraiSkala('II-III'), 2.5);
      expect(uraiSkala('III-IV'), 3.5);
      expect(uraiSkala('XYZ'), isNull);
    });

    test('laporan dirasakan: 14 kota MMI II dari data nyata; "-" kosong; rentang dibaca', () {
      final l = uraiDirasakan(
          'II Bantul, II Sleman, II Wonogiri, II Kulon Progo, II Sukoharjo, II Trenggalek, II Nganjuk, II Pacitan, II Klaten, II Kediri, II Ponorogo, II Banjarnegara, II Lumajang, II Blitar');
      expect(l.length, 14);
      expect(l.first.tempat, 'Bantul');
      expect(l.every((e) => e.mmi == 2), isTrue);
      expect(l[3].tempat, 'Kulon Progo'); // nama dua kata utuh
      expect(uraiDirasakan('-'), isEmpty);
      expect(uraiDirasakan(null), isEmpty);
      final r = uraiDirasakan('III-IV Ende, V Donggala, rusak');
      expect(r.map((e) => e.mmi), [3.5, 5]);
      expect(r.map((e) => e.skala), ['III-IV', 'V']);
    });

    test('berkas: objek tunggal (autogempa) dan daftar', () {
      final a = uraiBerkas(_auto);
      expect(a.length, 1);
      expect(a.first.magnitudo, 5.4);
      expect(a.first.lat, 5.59);
      expect(a.first.potensi, 'Tidak berpotensi tsunami');
      expect(a.first.berpotensiTsunami, isFalse);
      expect(uraiBerkas(_kini).length, 2);
    });
  });

  group('gabungan', () {
    test('menghapus duplikat, melengkapi laporan dirasakan, urut terbaru dulu', () {
      final semua = gabungkan([uraiBerkas(_auto), uraiBerkas(_kini), uraiBerkas(_rasa)]);
      expect(semua.length, 3); // 28 Okt, 27 Okt, 26 Okt (duplikat 28 dan 27 digabung)
      expect(semua.map((e) => e.waktuUtc).toList(), [...semua.map((e) => e.waktuUtc)]..sort((a, b) => b.compareTo(a)));
      final gunungkidul = semua.firstWhere((e) => e.wilayah.contains('GUNUNGKIDUL') || e.wilayah.contains('Gunungkidul'));
      expect(gunungkidul.dirasakan.length, 14); // dilengkapi dari gempadirasakan
      expect(gunungkidul.potensi, 'Tidak berpotensi tsunami'); // dilengkapi dari gempaterkini
      expect(gunungkidul.mmiDirasakanMaks, 2);
    });
  });

  group('tampilan waktu', () {
    final g = uraiBerkas(_kini)[1]; // 2026-10-27T14:43:13Z
    test('WIB = UTC+7', () => expect(g.waktuWib, '27 Okt 2026 21:43 WIB'));
    test('selang waktu', () {
      expect(g.selang(g.waktuUtc.add(const Duration(seconds: 20))), 'baru saja');
      expect(g.selang(g.waktuUtc.add(const Duration(minutes: 25))), '25 menit lalu');
      expect(g.selang(g.waktuUtc.add(const Duration(hours: 5))), '5 jam lalu');
      expect(g.selang(g.waktuUtc.add(const Duration(days: 4))), '4 hari lalu');
    });
  });

  test('server BMKG (butuh internet): katalog terisi dan bidang wajib valid', () async {
    HttpOverrides.global = null;
    final daftar = await KatalogBmkg(http.Client()).ambil();
    // ignore: avoid_print
    print('katalog ${daftar.length} gempa; terbaru: M${daftar.first.magnitudo} ${daftar.first.waktuWib} ${daftar.first.wilayah}; '
        'dengan laporan dirasakan: ${daftar.where((e) => e.dirasakan.isNotEmpty).length}');
    expect(daftar, isNotEmpty);
    for (final g in daftar) {
      expect(g.magnitudo, inInclusiveRange(1, 10));
      expect(g.lat, inInclusiveRange(-15, 12));
      expect(g.lon, inInclusiveRange(90, 145));
      expect(g.kedalamanKm, greaterThanOrEqualTo(0));
      expect(g.wilayah, isNotEmpty);
    }
    expect(daftar.first.waktuUtc.isAfter(daftar.last.waktuUtc) || daftar.length == 1, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
