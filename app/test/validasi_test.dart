// Tes perbandingan model dengan laporan dirasakan BMKG.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/katalog_bmkg.dart';
import 'package:zona_aman_gempa/mesin/validasi_bmkg.dart';

void main() {
  test('pilihTerdekat memilih hasil yang paling dekat dengan pusat gempa (menyingkirkan nama kembar)', () {
    final hasil = [
      {'lat': '-6.2', 'lon': '106.8'}, // Jakarta
      {'lat': '-7.89', 'lon': '110.33'}, // Yogyakarta
      {'lat': 'x', 'lon': 'y'}, // rusak, dilewati
    ];
    expect(pilihTerdekat(hasil, -9.2, 110.39), (-7.89, 110.33));
    expect(pilihTerdekat([], 0, 0), isNull);
  });

  test('pilihTerdekat mendahulukan batas administrasi daripada desa bernama sama yang lebih dekat', () {
    final hasil = [
      {'lat': '-7.70', 'lon': '109.91', 'category': 'place', 'type': 'village'}, // desa, sedikit lebih dekat
      {'lat': '-7.68', 'lon': '110.84', 'category': 'boundary', 'type': 'administrative'}, // kabupaten
    ];
    expect(pilihTerdekat(hasil, -9.2, 110.39), (-7.68, 110.84));
    // tanpa batas administrasi, kembali ke yang terdekat
    expect(pilihTerdekat([hasil[0]], -9.2, 110.39), (-7.70, 109.91));
  });

  test('pilihAdministrasi hanya menerima kabupaten/kota', () {
    final desa = {'lat': '-7.70', 'lon': '109.91', 'category': 'boundary', 'type': 'administrative', 'addresstype': 'village'};
    final kab = {'lat': '-7.68', 'lon': '110.87', 'category': 'boundary', 'type': 'administrative', 'addresstype': 'county'};
    expect(pilihAdministrasi([desa], -9.2, 110.39), isNull);
    expect(pilihAdministrasi([desa, kab], -9.2, 110.39), (-7.68, 110.87));
  });

  group('bandingkan dan ringkas', () {
    const lap = LaporanDirasakan('III', 3, 'A');
    test('model dikurangi BMKG; tanah lunak memberi MMI lebih tinggi; titik tak ditemukan dilewati', () {
      final baris = bandingkan(
        titik: [
          (lap, (-7.9, 110.4)),
          (lap, (-7.9, 110.4)),
          (const LaporanDirasakan('II', 2, 'B'), null),
        ],
        srcLat: -7.9,
        srcLon: 110.3,
        magnitudo: 6.0,
        kedalamanKm: 10,
        arahSesarDeg: 30,
        mekanisme: Mekanisme.mendatar,
        vs30Di: (la, lo) => 300,
      );
      expect(baris.length, 3);
      expect(baris[2].mmiModel, isNull);
      expect(baris[0].selisih, closeTo(baris[0].mmiModel! - 3, 1e-9));
      final r = ringkas(baris);
      expect(r.n, 2);
      expect(r.tidakDitemukan, 1);
      expect(r.rataMutlak, greaterThanOrEqualTo(0));
    });

    test('ringkas semua tak ditemukan -> n=0 tanpa rata-rata', () {
      final r = ringkas([const BarisPerbandingan(lap, null, null, null)]);
      expect(r.n, 0);
      expect(r.rataSelisih, isNull);
    });
  });

  group('Geokoder', () {
    test('hasil di-cache: permintaan kedua untuk nama sama tidak memanggil server lagi', () async {
      var panggilan = 0;
      final klien = MockClient((req) async {
        panggilan++;
        expect(req.headers['User-Agent'], contains('TERRA-TUR'));
        return http.Response(
            '[{"lat":"-7.89","lon":"110.33","category":"boundary","type":"administrative","addresstype":"county"}]', 200);
      });
      final g = Geokoder(klien, jeda: Duration.zero);
      final a = await g.cari('Bantul', -9.2, 110.39);
      final b = await g.cari('Bantul', -9.2, 110.39);
      expect(a, (-7.89, 110.33));
      expect(b, a);
      expect(panggilan, 1);
    });

    test('mencoba "Kabupaten X" dulu dan berhenti begitu dapat batas kabupaten (nama polos hanya memberi desa)', () async {
      final kueri = <String>[];
      final g = Geokoder(MockClient((req) async {
        final q = req.url.queryParameters['q']!;
        kueri.add(q);
        if (q == 'Kabupaten Sukoharjo') {
          return http.Response(
              '[{"lat":"-7.68","lon":"110.87","category":"boundary","type":"administrative","addresstype":"county"}]', 200);
        }
        return http.Response('[{"lat":"-7.70","lon":"109.91","category":"place","type":"village","addresstype":"village"}]', 200);
      }), jeda: Duration.zero);
      expect(await g.cari('Sukoharjo', -9.2, 110.39), (-7.68, 110.87));
      expect(kueri, ['Kabupaten Sukoharjo']);
    });

    test('bila kabupaten tak ada, jatuh ke Kota lalu nama polos; hasil terakhir dipakai sebagai cadangan', () async {
      final kueri = <String>[];
      final g = Geokoder(MockClient((req) async {
        kueri.add(req.url.queryParameters['q']!);
        return http.Response('[{"lat":"-7.70","lon":"109.91","category":"place","type":"village","addresstype":"village"}]', 200);
      }), jeda: Duration.zero);
      expect(await g.cari('Antah', -9.2, 110.39), (-7.70, 109.91));
      expect(kueri, ['Kabupaten Antah', 'Kota Antah', 'Antah']);
    });

    test('kegagalan jaringan -> null dan tidak di-cache', () async {
      var panggilan = 0;
      final g = Geokoder(MockClient((req) async {
        panggilan++;
        throw const SocketException('putus');
      }), jeda: Duration.zero);
      expect(await g.cari('Bantul', 0, 0), isNull);
      expect(await g.cari('Bantul', 0, 0), isNull);
      expect(panggilan, 2);
    });

    test('permintaan diberi jeda sesuai aturan layanan', () async {
      final waktu = <DateTime>[];
      final g = Geokoder(MockClient((req) async {
        waktu.add(DateTime.now());
        return http.Response('[]', 200);
      }), jeda: const Duration(milliseconds: 300));
      await g.cari('A', 0, 0);
      await g.cari('B', 0, 0);
      expect(waktu[1].difference(waktu[0]).inMilliseconds, greaterThanOrEqualTo(280));
    });
  });

  test('NYATA: gempa dirasakan BMKG terbaru vs model (butuh internet)', () async {
    HttpOverrides.global = null;
    final klien = http.Client();
    final daftar = (await KatalogBmkg(klien).ambil()).where((g) => g.dirasakan.length >= 3).toList();
    expect(daftar, isNotEmpty);
    final g = daftar.first;
    final geo = Geokoder(klien);
    final titik = <(LaporanDirasakan, (double, double)?)>[];
    for (final l in g.dirasakan.take(8)) {
      titik.add((l, await geo.cari(l.tempat, g.lat, g.lon)));
    }
    final baris = bandingkan(
      titik: titik,
      srcLat: g.lat,
      srcLon: g.lon,
      magnitudo: g.magnitudo,
      kedalamanKm: g.kedalamanKm,
      arahSesarDeg: 0,
      mekanisme: Mekanisme.takDiketahui,
      vs30Di: (la, lo) => 400,
    );
    // ignore: avoid_print
    print('GEMPA M${g.magnitudo} ${g.waktuWib} ${g.wilayah} dalam ${g.kedalamanKm} km');
    for (final b in baris) {
      // ignore: avoid_print
      print('  ${b.laporan.tempat.padRight(16)} BMKG ${b.laporan.skala.padRight(6)} model ${b.mmiModel?.toStringAsFixed(1) ?? '-'} '
          'selisih ${b.selisih?.toStringAsFixed(1) ?? '-'}  (${b.lat?.toStringAsFixed(2)}, ${b.lon?.toStringAsFixed(2)})');
    }
    final r = ringkas(baris);
    // ignore: avoid_print
    print('RINGKASAN n=${r.n} tak ditemukan=${r.tidakDitemukan} dalam ±1=${r.dalamSatuSkala} rata selisih=${r.rataSelisih?.toStringAsFixed(2)}');
    expect(r.n, greaterThan(titik.length ~/ 2)); // sebagian besar daerah berhasil dicari koordinatnya
  }, timeout: const Timeout(Duration(minutes: 4)));
}
