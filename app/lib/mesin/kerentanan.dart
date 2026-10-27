// Mesin kerentanan geologi offline. Port dari prototype/data_resmi.py dan prototype/kerentanan.py.
// Zonasi: Badan Geologi (Geoportal ESDM). Bukan alat keselamatan resmi.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'gmpe.dart';
import 'hasil.dart';

// Batas area data (DIY dan sekitarnya)
const batasLat0 = -8.2, batasLat1 = -7.5, batasLon0 = 110.0, batasLon1 = 110.7;

class _Poligon {
  final List<List<List<double>>> cincin; // [0] luar, sisanya lubang
  final double minX, minY, maxX, maxY;
  _Poligon(this.cincin, this.minX, this.minY, this.maxX, this.maxY);

  bool memuat(double x, double y) {
    if (x < minX || x > maxX || y < minY || y > maxY) return false;
    if (!_dalam(x, y, cincin[0])) return false;
    for (var i = 1; i < cincin.length; i++) {
      if (_dalam(x, y, cincin[i])) return false;
    }
    return true;
  }

  static bool _dalam(double x, double y, List<List<double>> r) {
    var masuk = false;
    var j = r.length - 1;
    for (var i = 0; i < r.length; i++) {
      final xi = r[i][0], yi = r[i][1], xj = r[j][0], yj = r[j][1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) masuk = !masuk;
      j = i;
    }
    return masuk;
  }
}

class _Fitur {
  final Map<String, dynamic> atribut;
  final List<_Poligon> poligon;
  final double luasBbox;
  _Fitur(this.atribut, this.poligon, this.luasBbox);
}

class _Lapisan {
  final List<_Fitur> fitur;
  _Lapisan(this.fitur);

  static _Lapisan dari(List<dynamic> json) {
    final out = <_Fitur>[];
    for (final f in json) {
      final polys = <_Poligon>[];
      double luas = double.infinity;
      for (final p in f['g'] as List) {
        final cincin = [
          for (final r in p as List)
            [for (final c in r as List) [(c[0] as num).toDouble(), (c[1] as num).toDouble()]]
        ];
        var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
        for (final c in cincin[0]) {
          minX = math.min(minX, c[0]);
          maxX = math.max(maxX, c[0]);
          minY = math.min(minY, c[1]);
          maxY = math.max(maxY, c[1]);
        }
        polys.add(_Poligon(cincin, minX, minY, maxX, maxY));
        luas = math.min(luas, (maxX - minX) * (maxY - minY));
      }
      out.add(_Fitur(Map<String, dynamic>.from(f['p'] as Map), polys, luas));
    }
    return _Lapisan(out);
  }

  /// Atribut semua fitur yang memuat titik, dari yang bbox-nya paling kecil (paling spesifik).
  List<Map<String, dynamic>> cari(double lon, double lat) {
    final hit = <_Fitur>[];
    for (final f in fitur) {
      if (f.poligon.any((p) => p.memuat(lon, lat))) hit.add(f);
    }
    hit.sort((a, b) => a.luasBbox.compareTo(b.luasBbox));
    return [for (final f in hit) f.atribut];
  }
}

class MesinKerentanan {
  final _Lapisan _litologi, _krb, _l50, _l100, _gt, _tsunami, _lunak;
  final List<List<List<double>>> _opak;
  final Map<String, dynamic> _kelas, _pemetaan;
  final List<double> _elev;
  final double _lat0, _lon0, _step;
  final int _nlat, _nlon;

  MesinKerentanan._(this._litologi, this._krb, this._l50, this._l100, this._gt, this._tsunami, this._lunak,
      this._opak, this._kelas, this._pemetaan, this._elev, this._lat0, this._lon0, this._step, this._nlat, this._nlon);

  static Future<dynamic> _json(String nama) async =>
      jsonDecode(await rootBundle.loadString('assets/data/$nama.json'));

  static Future<MesinKerentanan> muat() async {
    final lito = await _json('litologi_dampak');
    final e = await _json('elevasi');
    final opak = await _json('sesar_opak') as List;
    return MesinKerentanan._(
      _Lapisan.dari(await _json('litologi')),
      _Lapisan.dari(await _json('krb_gempa')),
      _Lapisan.dari(await _json('likuefaksi_50k')),
      _Lapisan.dari(await _json('likuefaksi_100k')),
      _Lapisan.dari(await _json('gerakan_tanah')),
      _Lapisan.dari(await _json('tsunami')),
      _Lapisan.dari(await _json('tanah_lunak')),
      [
        for (final g in opak)
          [for (final c in g as List) [(c[0] as num).toDouble(), (c[1] as num).toDouble()]]
      ],
      Map<String, dynamic>.from(lito['kelas'] as Map),
      Map<String, dynamic>.from(lito['pemetaan_simobj'] as Map),
      [for (final v in e['elev'] as List) (v as num).toDouble()],
      (e['lat0'] as num).toDouble(),
      (e['lon0'] as num).toDouble(),
      (e['step'] as num).toDouble(),
      e['nlat'] as int,
      e['nlon'] as int,
    );
  }

  static bool dalamCakupan(double lat, double lon) =>
      lat >= batasLat0 && lat <= batasLat1 && lon >= batasLon0 && lon <= batasLon1;

  // ---- elevasi, kemiringan, Vs30 proxy ----
  double _e(int i, int j) => _elev[i * _nlon + j];

  (double, double) _elevasiLereng(double lat, double lon) {
    // sel terdekat; jarak tepat 0,5 sel dibulatkan ke atas (disamakan dengan prototype/kerentanan.py)
    final i = ((lat - _lat0) / _step + 0.5 + 1e-9).floor().clamp(0, _nlat - 1);
    final j = ((lon - _lon0) / _step + 0.5 + 1e-9).floor().clamp(0, _nlon - 1);
    final d = _step * 111000.0;
    final i0 = math.max(i - 1, 0), i1 = math.min(i + 1, _nlat - 1);
    final j0 = math.max(j - 1, 0), j1 = math.min(j + 1, _nlon - 1);
    final gy = (_e(i1, j) - _e(i0, j)) / ((i1 - i0) * d);
    final gx = (_e(i, j1) - _e(i, j0)) / ((j1 - j0) * d * math.cos(-7.8 * math.pi / 180));
    return (_e(i, j), math.sqrt(gx * gx + gy * gy));
  }

  // Titik jangkar slope -> Vs30 (aproksimasi Wald & Allen 2007, tektonik aktif)
  static const _anchor = [(1e-4, 180.0), (2.2e-3, 360.0), (0.138, 760.0), (0.3, 1000.0)];

  static double _vs30DariSlope(double s) {
    if (s <= _anchor[0].$1) return _anchor[0].$2;
    for (var k = 0; k < _anchor.length - 1; k++) {
      final (s0, v0) = _anchor[k];
      final (s1, v1) = _anchor[k + 1];
      if (s <= s1) {
        final t = (math.log(s) - math.log(s0)) / (math.log(s1) - math.log(s0));
        return v0 + t * (v1 - v0);
      }
    }
    return _anchor.last.$2;
  }

  /// Jarak (km) ke jejak Sesar Opak beserta titik terdekatnya (lat, lon).
  (double, double, double) _jarakOpak(double lon, double lat) {
    final kx = 111.32 * math.cos(lat * math.pi / 180), ky = 110.57;
    var terbaik = double.infinity, tLat = lat, tLon = lon;
    for (final ln in _opak) {
      for (var k = 0; k < ln.length - 1; k++) {
        final ax = (ln[k][0] - lon) * kx, ay = (ln[k][1] - lat) * ky;
        final bx = (ln[k + 1][0] - lon) * kx, by = (ln[k + 1][1] - lat) * ky;
        final dx = bx - ax, dy = by - ay;
        final t = (dx == 0 && dy == 0) ? 0.0 : (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
        final d = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
        if (d < terbaik) {
          terbaik = d;
          tLat = lat + (ay + t * dy) / ky;
          tLon = lon + (ax + t * dx) / kx;
        }
      }
    }
    return (terbaik, tLat, tLon);
  }

  HasilLokasi analisis(double lat, double lon) {
    final (elev, slope) = _elevasiLereng(lat, lon);
    final gs = _litologi.cari(lon, lat);
    final g = gs.isEmpty ? null : gs.first;
    final kode = g == null ? null : _pemetaan[g['simobj']] as String?;
    final mat = kode == null ? null : Map<String, dynamic>.from(_kelas[kode] as Map);

    final vsProxy = _vs30DariSlope(slope);
    final vs30 = mat != null ? 0.3 * vsProxy + 0.7 * (mat['vs30'] as num) : vsProxy;
    final (dOpak, opakLat, opakLon) = _jarakOpak(lon, lat);

    final krb = _krb.cari(lon, lat);
    final krbKelas = krb.isEmpty ? null : krb.first['kelas'] as String;
    final krbLv = krbKelas == null ? null : kKrb[krbKelas.replaceFirst('Kawasan Rawan Bencana Gempabumi ', '')];

    final l50 = _l50.cari(lon, lat), l100 = _l100.cari(lon, lat);
    int? likLv;
    String likSrc;
    if (l50.isNotEmpty) {
      likLv = kLik50[(l50.first['kerentanan'] as String).trim()];
      likSrc = 'resmi 1:50.000';
    } else if (l100.isNotEmpty) {
      final lv = kLik100[l100.first['kerentanan'].toString().trim()];
      likLv = (lv != null && mat != null) ? math.min(lv, 1 + (mat['likuefaksi'] as int)) : lv;
      likSrc = 'resmi 1:100.000 (poligon kasar, dibatasi oleh material)';
    } else {
      likLv = mat?['likuefaksi'] as int?;
      likSrc = 'perkiraan dari material';
    }

    final gt = _gt.cari(lon, lat).where((p) => kGt.containsKey(p['unsur'])).toList();
    int? gtLv;
    String gtSrc;
    if (gt.isNotEmpty) {
      gtLv = kGt[gt.first['unsur']];
      gtSrc = 'resmi 1:50.000';
    } else {
      gtLv = mat == null ? null : ((mat['longsor'] as int) * math.min(1.0, 0.4 + slope * 6)).round();
      gtSrc = 'perkiraan dari material dan lereng';
    }

    final lunak = _lunak.cari(lon, lat);
    final level = [krbLv, likLv, gtLv].whereType<int>();
    final tsu = _tsunami.cari(lon, lat);
    return HasilLokasi(
      lat: lat,
      lon: lon,
      sumber: 'offline',
      kodeFormasi: g?['simobj'] as String?,
      formasi: g?['namobj'] as String?,
      umur: g?['umurobj'] as String?,
      kelasMaterial: kode,
      namaMaterial: mat?['nama'] as String?,
      catatanMaterial: mat?['catatan'] as String?,
      materialPerkiraan: false,
      vs30: vs30,
      elevasiM: elev,
      kemiringan: slope,
      namaSesar: 'Sesar Opak',
      statusSesar: 'Aktif',
      jarakSesarKm: dOpak,
      sesarLat: opakLat,
      sesarLon: opakLon,
      mekanisme: Mekanisme.mendatar,
      krbTingkat: krbLv,
      krbKelas: krbKelas,
      likTingkat: likLv,
      likSumber: likSrc,
      gtTingkat: gtLv,
      gtSumber: gtSrc,
      tsunamiTingkat: tsu.isEmpty ? null : (kTsunami[tsu.first['unsur']] ?? 3),
      tanahLunak: lunak.isEmpty ? null : lunak.first['jenis_tana'] as String?,
      tingkatKeseluruhan: level.isEmpty ? null : level.reduce(math.max),
    );
  }
}
