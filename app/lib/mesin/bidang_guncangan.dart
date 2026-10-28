// Peta guncangan: MMI per sel grid, dihitung dari jarak ke retakan dan Vs30 setempat (geologi), lalu diwarnai.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'gmpe.dart';
import 'peta_geologi.dart';
import 'simulasi.dart';

class BidangGuncangan {
  final GridVs30 grid;

  /// MMI per sel (NaN = tanpa data). Indeks sama dengan [GridVs30.vs30].
  final Float32List mmi;
  final double mmiMaks;
  const BidangGuncangan(this.grid, this.mmi, this.mmiMaks);
}

/// Hitung MMI di tiap sel: Rjb = jarak ke segmen retakan, Vs30 = nilai sel dari peta geologi.
BidangGuncangan hitungBidang(GridVs30 g, {required Segmen seg, required double m, required Mekanisme mek}) {
  final out = Float32List(g.vs30.length);
  var maks = 0.0;
  for (var i = 0; i < g.ny; i++) {
    final lat = g.latPusat(i);
    for (var j = 0; j < g.nx; j++) {
      final k = i * g.nx + j;
      final vs = g.vs30[k];
      if (vs.isNaN) {
        out[k] = double.nan;
        continue;
      }
      final v = gerakTanah(m, jarakKeSegmenKm(lat, g.lonPusat(j), seg), vs.toDouble(), mek).mmi;
      out[k] = v;
      if (v > maks) maks = v;
    }
  }
  return BidangGuncangan(g, out, maks);
}

// Pita warna MMI: (mmi, r, g, b, alpha)
const _pita = [
  (3.0, 150, 200, 255, 0),
  (4.0, 150, 200, 255, 90),
  (5.0, 110, 200, 120, 130),
  (6.0, 245, 225, 70, 155),
  (7.0, 245, 150, 40, 170),
  (8.0, 225, 60, 40, 185),
  (9.0, 140, 20, 60, 200),
  (10.0, 80, 0, 60, 215),
];

/// Warna (r, g, b, a) untuk MMI tertentu; terinterpolasi halus di antara tingkat.
(int, int, int, int) warnaMmi(double mmi) {
  if (mmi.isNaN || mmi <= _pita.first.$1) return (0, 0, 0, 0);
  if (mmi >= _pita.last.$1) return (_pita.last.$2, _pita.last.$3, _pita.last.$4, _pita.last.$5);
  for (var k = 0; k < _pita.length - 1; k++) {
    final a = _pita[k], b = _pita[k + 1];
    if (mmi <= b.$1) {
      final t = (mmi - a.$1) / (b.$1 - a.$1);
      int mix(int x, int y) => (x + (y - x) * t).round();
      return (mix(a.$2, b.$2), mix(a.$3, b.$3), mix(a.$4, b.$4), mix(a.$5, b.$5));
    }
  }
  return (0, 0, 0, 0);
}

/// Piksel RGBA (baris pertama = utara). Ukuran grid.nx x grid.ny.
Uint8List warnaRgba(BidangGuncangan b) {
  final g = b.grid;
  final out = Uint8List(g.nx * g.ny * 4);
  for (var i = 0; i < g.ny; i++) {
    final baris = g.ny - 1 - i; // balik: i=0 adalah paling selatan
    for (var j = 0; j < g.nx; j++) {
      final (r, gg, bb, a) = warnaMmi(b.mmi[i * g.nx + j]);
      final o = (baris * g.nx + j) * 4;
      out[o] = r;
      out[o + 1] = gg;
      out[o + 2] = bb;
      out[o + 3] = a;
    }
  }
  return out;
}

/// Ubah piksel RGBA menjadi PNG (dipakai sebagai gambar yang ditempel di peta).
Future<Uint8List> kePng(Uint8List rgba, int lebar, int tinggi) async {
  final selesai = await _dekode(rgba, lebar, tinggi);
  final data = await selesai.toByteData(format: ui.ImageByteFormat.png);
  selesai.dispose();
  return data!.buffer.asUint8List();
}

Future<ui.Image> _dekode(Uint8List rgba, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}
