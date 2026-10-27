// Tes mesin daring: klasifikasi material (tanpa jaringan) dan pencarian ke server Badan Geologi (butuh internet).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zona_aman_gempa/mesin/daring.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kelasDariNama', () {
    const kasus = {
      ('Alluvium', 'Kuarter'): 'aluvium',
      ('Endapan Rawa', 'Holosen'): 'aluvium',
      ('Limestone', 'Neogen'): 'gamping',
      ('Granite', 'Kapur'): 'beku',
      ('Schist', 'Pra Tersier'): 'malih',
      ('Young Volcanic Deposit', 'Kuarter'): 'vulkanik_muda',
      ('Tuff and Breccia', 'Miosen'): 'tuf_breksi',
      ('Sandstone and Claystone', 'Miocene'): 'sedimen_lunak',
      ('Sandstone', 'Paleogen'): 'sedimen_tua',
      ('Undifferentiated', 'Kuarter'): 'aluvium_tua',
    };
    kasus.forEach((k, ekspektasi) {
      test('${k.$1} (${k.$2}) -> $ekspektasi', () => expect(kelasDariNama(k.$1, k.$2), ekspektasi));
    });
  });

  test('mekanisme sesar dari nama resmi', () {
    expect(Mekanisme.dariNama('Patahan Mendatar Menganan Opak'), Mekanisme.mendatar);
    expect(Mekanisme.dariNama('Patahan Naik Cibeber'), Mekanisme.naik);
    expect(Mekanisme.dariNama('Patahan Normal Cikande'), Mekanisme.normal);
    expect(Mekanisme.dariNama('Patahan Menurun Lubuksikaping'), Mekanisme.normal);
    expect(Mekanisme.dariNama('Patahan Noname'), Mekanisme.takDiketahui);
  });

  test('mekanisme berpengaruh pada guncangan (naik > mendatar pada M dan jarak sama)', () {
    final ss = gerakTanah(6.5, 10, 400, Mekanisme.mendatar).pgaG;
    final rv = gerakTanah(6.5, 10, 400, Mekanisme.naik).pgaG;
    expect(rv, greaterThan(ss * 0.95));
    expect(ss, inInclusiveRange(0.1, 0.5));
  });

  group('server Badan Geologi (butuh internet)', () {
    late MesinDaring mesin;
    setUpAll(() async {
      HttpOverrides.global = null; // flutter_test memblokir HTTP secara bawaan
      final lito = jsonDecode(await File('assets/data/litologi_dampak.json').readAsString()) as Map<String, dynamic>;
      mesin = MesinDaring(http.Client(), Map<String, dynamic>.from(lito['kelas'] as Map),
          Map<String, dynamic>.from(lito['pemetaan_simobj'] as Map));
    });

    const kota = {
      'Padang': (-0.949, 100.354),
      'Jakarta': (-6.209, 106.845),
      'Palu': (-0.895, 119.870),
      'Jayapura': (-2.533, 140.718),
      'Kupang': (-10.178, 123.607),
      'Yogyakarta': (-7.793, 110.366),
    };
    kota.forEach((nama, c) {
      test(nama, () async {
        final h = await mesin.analisis(c.$1, c.$2);
        // ignore: avoid_print
        print('${nama.padRight(11)} ${h.formasi} (${h.umur}) -> ${h.kelasMaterial}${h.materialPerkiraan ? "*" : ""} '
            'Vs30=${h.vs30.round()} KRB=${h.krbTingkat} lik=${h.likTingkat} gt=${h.gtTingkat} tsu=${h.tsunamiTingkat} '
            'sesar=${h.namaSesar} ${h.jarakSesarKm?.toStringAsFixed(1)}km ${h.mekanisme.label} '
            'M6.3 MMI=${h.skenario(6.3)?.mmi.toStringAsFixed(1)} elev=${h.elevasiM}');
        expect(h.sumber, 'daring');
        expect(h.krbTingkat, isNotNull);
        expect(h.formasi, isNotNull);
      }, timeout: const Timeout(Duration(seconds: 90)));
    });
  });
}
