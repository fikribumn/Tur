// Mencocokkan mesin Dart dengan keluaran referensi Python (data/hasil_contoh.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zona_aman_gempa/mesin/kerentanan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hasil Dart sama dengan referensi Python', () async {
    final ref = jsonDecode(await File('../data/hasil_contoh.json').readAsString()) as Map<String, dynamic>;
    final mesin = await MesinKerentanan.muat();
    final sb = StringBuffer();
    var beda = 0;
    for (final e in ref.entries) {
      final r = e.value as Map<String, dynamic>;
      final h = mesin.analisis((r['lat'] as num).toDouble(), (r['lon'] as num).toDouble());
      final mmi = h.skenario(6.3)!.mmi;
      final cek = <String, bool>{
        'formasi': h.kodeFormasi == (r['geologi']?['kode']),
        'vs30': (h.vs30.round() - (r['vs30'] as num)).abs() <= 1,
        'opak': (h.jarakSesarKm! - (r['jarak_sesar_opak_km'] as num)).abs() < 0.11,
        'mmi': (mmi - (r['skenario']['mmi'] as num)).abs() < 0.11,
        'krb': h.krbTingkat == r['krb_gempa']['tingkat'],
        'lik': h.likTingkat == r['likuefaksi']['tingkat'],
        'gt': h.gtTingkat == r['gerakan_tanah']['tingkat'],
        'tsunami': (h.tsunamiTingkat != null) == r['tsunami'],
        'total': h.tingkatKeseluruhan == r['tingkat_keseluruhan'],
      };
      final salah = cek.entries.where((c) => !c.value).map((c) => c.key).toList();
      beda += salah.length;
      sb.writeln('${e.key.padRight(13)} mmi=${mmi.toStringAsFixed(1)} vs30=${h.vs30.round()} '
          'opak=${h.jarakSesarKm!.toStringAsFixed(1)} -> ${salah.isEmpty ? "OK" : "BEDA: $salah"}');
    }
    // ignore: avoid_print
    print(sb);
    expect(beda, 0);
  });
}
