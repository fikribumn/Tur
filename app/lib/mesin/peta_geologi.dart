// Grid Vs30 dari peta geologi resmi (Badan Geologi) di sekitar sumber gempa.
// Poligon formasi diambil dari server untuk satu jendela, diklasifikasi ke kelas material, lalu dirasterisasi.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'daring.dart' show GalatJaringan, kelasDariNama;

const _host = 'geoportal.esdm.go.id';
const _layer = '/gis4/rest/services/BGS_PM/Geologi_Litologi/MapServer/0/query';
const _batas = Duration(seconds: 40);

/// Grid persegi panjang sel Vs30. Sel (i, j): i dari selatan, j dari barat. NaN = tidak ada data (laut dsb.).
class GridVs30 {
  final double lat0, lon0, dLat, dLon;
  final int ny, nx;
  final Float32List vs30;

  GridVs30({required this.lat0, required this.lon0, required this.dLat, required this.dLon, required this.ny, required this.nx})
      : vs30 = Float32List(ny * nx)..fillRange(0, ny * nx, double.nan);

  double get lat1 => lat0 + ny * dLat;
  double get lon1 => lon0 + nx * dLon;
  double latPusat(int i) => lat0 + (i + 0.5) * dLat;
  double lonPusat(int j) => lon0 + (j + 0.5) * dLon;
  int get jumlahData => vs30.where((v) => !v.isNaN).length;

  /// Grid persegi berukuran 2*radiusKm berpusat di (lat, lon), n x n sel.
  factory GridVs30.jendela(double lat, double lon, double radiusKm, int n) {
    final dLat = radiusKm / 110.57, dLon = radiusKm / (111.32 * math.cos(lat * math.pi / 180));
    return GridVs30(lat0: lat - dLat, lon0: lon - dLon, dLat: 2 * dLat / n, dLon: 2 * dLon / n, ny: n, nx: n);
  }

  /// Grid seragam (cadangan bila geologi tidak bisa diambil): semua sel bernilai [vs].
  factory GridVs30.seragam(double lat, double lon, double radiusKm, int n, double vs) {
    final g = GridVs30.jendela(lat, lon, radiusKm, n);
    g.vs30.fillRange(0, g.vs30.length, vs);
    return g;
  }
}

bool _dalamCincin(double x, double y, List<List<double>> r) {
  var masuk = false;
  var j = r.length - 1;
  for (var i = 0; i < r.length; i++) {
    final xi = r[i][0], yi = r[i][1], xj = r[j][0], yj = r[j][1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) masuk = !masuk;
    j = i;
  }
  return masuk;
}

/// Isi sel yang pusatnya berada di dalam poligon (aturan genap-ganjil antar-cincin, jadi lubang ikut benar).
void isiPoligon(GridVs30 g, List<List<List<double>>> cincin, double vs) {
  if (cincin.isEmpty) return;
  var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
  for (final r in cincin) {
    for (final p in r) {
      minX = math.min(minX, p[0]);
      maxX = math.max(maxX, p[0]);
      minY = math.min(minY, p[1]);
      maxY = math.max(maxY, p[1]);
    }
  }
  final j0 = math.max(0, ((minX - g.lon0) / g.dLon - 0.5).floor());
  final j1 = math.min(g.nx - 1, ((maxX - g.lon0) / g.dLon + 0.5).ceil());
  final i0 = math.max(0, ((minY - g.lat0) / g.dLat - 0.5).floor());
  final i1 = math.min(g.ny - 1, ((maxY - g.lat0) / g.dLat + 0.5).ceil());
  for (var i = i0; i <= i1; i++) {
    final y = g.latPusat(i);
    for (var j = j0; j <= j1; j++) {
      final x = g.lonPusat(j);
      var hitung = 0;
      for (final r in cincin) {
        if (_dalamCincin(x, y, r)) hitung++;
      }
      if (hitung.isOdd) g.vs30[i * g.nx + j] = vs;
    }
  }
}

/// Isi celah kosong yang seluruhnya dikelilingi daratan (celah antarpoligon, badan air kecil) dengan nilai sel
/// daratan terdekat. Sel kosong yang tersambung ke tepi grid (laut) tetap kosong, begitu pula celah yang
/// luasnya lebih dari [maksSel] sel (bukan celah, mungkin wilayah luas tanpa data). Mengembalikan jumlah sel diisi.
int isiCelahTertutup(GridVs30 g, {int maksSel = 800}) {
  final n = g.ny * g.nx;
  final v = g.vs30;
  const arah = [(-1, 0), (1, 0), (0, -1), (0, 1)];
  Iterable<int> tetangga(int k) sync* {
    final i = k ~/ g.nx, j = k % g.nx;
    for (final (di, dj) in arah) {
      final a = i + di, b = j + dj;
      if (a >= 0 && a < g.ny && b >= 0 && b < g.nx) yield a * g.nx + b;
    }
  }

  // 1) tandai sel kosong yang tersambung ke tepi grid (laut/luar)
  final luar = List<bool>.filled(n, false);
  final antrean = <int>[];
  for (var k = 0; k < n; k++) {
    final i = k ~/ g.nx, j = k % g.nx;
    if (v[k].isNaN && (i == 0 || j == 0 || i == g.ny - 1 || j == g.nx - 1)) {
      luar[k] = true;
      antrean.add(k);
    }
  }
  for (var h = 0; h < antrean.length; h++) {
    for (final nb in tetangga(antrean[h])) {
      if (v[nb].isNaN && !luar[nb]) {
        luar[nb] = true;
        antrean.add(nb);
      }
    }
  }

  // 2) komponen kosong tertutup: isi bila cukup kecil, dengan nilai daratan tetangga terdekat (rambat dari tepi)
  final dikunjungi = List<bool>.filled(n, false);
  var diisi = 0;
  for (var k = 0; k < n; k++) {
    if (!v[k].isNaN || luar[k] || dikunjungi[k]) continue;
    if (!(v[k].isNaN && !luar[k])) continue;
    final komp = <int>[k];
    dikunjungi[k] = true;
    for (var h = 0; h < komp.length; h++) {
      for (final nb in tetangga(komp[h])) {
        if (v[nb].isNaN && !luar[nb] && !dikunjungi[nb]) {
          dikunjungi[nb] = true;
          komp.add(nb);
        }
      }
    }
    if (komp.length > maksSel) continue;
    final anggota = komp.toSet();
    final front = <int>[];
    final nilai = <int, double>{};
    for (final c in komp) {
      for (final nb in tetangga(c)) {
        if (!anggota.contains(nb) && !v[nb].isNaN && !nilai.containsKey(c)) {
          nilai[c] = v[nb];
          front.add(c);
        }
      }
    }
    for (var h = 0; h < front.length; h++) {
      final c = front[h];
      for (final nb in tetangga(c)) {
        if (anggota.contains(nb) && !nilai.containsKey(nb)) {
          nilai[nb] = nilai[c]!;
          front.add(nb);
        }
      }
    }
    nilai.forEach((c, x) => v[c] = x);
    diisi += nilai.length;
  }
  return diisi;
}

class PemuatGeologi {
  final http.Client _klien;
  final Map<String, dynamic> _kelas, _pemetaanDiy;
  PemuatGeologi(this._klien, this._kelas, this._pemetaanDiy);

  static bool _diDiy(double lat, double lon) => lat >= -8.2 && lat <= -7.5 && lon >= 110.0 && lon <= 110.7;

  Future<Map<String, dynamic>> _get(Map<String, String> param) async {
    try {
      final r = await _klien.get(Uri.https(_host, _layer, {...param, 'f': 'json'})).timeout(_batas);
      if (r.statusCode != 200) throw GalatJaringan('Server Badan Geologi membalas ${r.statusCode}.');
      final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if (d.containsKey('error')) throw GalatJaringan('Server Badan Geologi menolak permintaan.');
      return d;
    } on GalatJaringan {
      rethrow;
    } catch (e) {
      throw GalatJaringan('Tidak bisa menghubungi server Badan Geologi.');
    }
  }

  /// Ambil formasi di jendela berpusat (lat, lon) radius [radiusKm], lalu rasterisasi ke grid n x n berisi Vs30.
  Future<GridVs30> muat(double lat, double lon, double radiusKm, {int n = 110}) async {
    final g = GridVs30.jendela(lat, lon, radiusKm, n);
    final bbox = '${g.lon0},${g.lat0},${g.lon1},${g.lat1}';
    final dasar = {
      'geometry': bbox,
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
    };
    final ids = ((await _get({...dasar, 'returnIdsOnly': 'true'}))['objectIds'] as List?)?.cast<int>() ?? const <int>[];
    if (ids.isEmpty) return g;

    final sederhana = (g.dLat < g.dLon ? g.dLat : g.dLon).toString(); // disederhanakan ke ukuran satu sel
    final kelompok = <List<int>>[for (var k = 0; k < ids.length; k += 80) ids.sublist(k, math.min(k + 80, ids.length))];
    const paralel = 4;
    final fitur = <Map<String, dynamic>>[];
    for (var k = 0; k < kelompok.length; k += paralel) {
      final hasil = await Future.wait([
        for (final ids in kelompok.skip(k).take(paralel))
          _get({
            'objectIds': ids.join(','),
            'outFields': 'simobj,namobj,umurobj,remark',
            'returnGeometry': 'true',
            'outSR': '4326',
            'maxAllowableOffset': sederhana,
            'geometryPrecision': '4',
          })
      ]);
      for (final d in hasil) {
        fitur.addAll(((d['features'] as List?) ?? const []).cast<Map<String, dynamic>>());
      }
    }

    for (final f in fitur) {
      final a = (f['attributes'] as Map).cast<String, dynamic>();
      final rings = (f['geometry']?['rings'] as List?);
      if (rings == null) continue;
      final cincin = [
        for (final r in rings)
          [for (final p in r as List) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]]
      ];
      final simobj = a['simobj'] as String?;
      final kode = (_diDiy(lat, lon) && simobj != null && _pemetaanDiy.containsKey(simobj))
          ? _pemetaanDiy[simobj] as String
          : kelasDariNama('${a['namobj'] ?? ''} ${a['remark'] ?? ''}', '${a['umurobj'] ?? ''}');
      final vs = (_kelas[kode]?['vs30'] as num?)?.toDouble() ?? 400.0;
      isiPoligon(g, cincin, vs);
    }
    isiCelahTertutup(g);
    return g;
  }
}
