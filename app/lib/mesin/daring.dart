// Mesin daring: menanyakan layer resmi Badan Geologi (Geoportal ESDM) untuk titik mana pun di Indonesia.
// Zonasi (KRB gempa, gerakan tanah, likuefaksi, tsunami) memakai kelas resmi; skenario guncangan memakai
// sesar aktif terdekat (peta 1:1.000.000) dan BSSA14, yang hanya berlaku untuk gempa kerak dangkal.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'gmpe.dart';
import 'hasil.dart';

const _host = 'geoportal.esdm.go.id';
const _dasar = '/gis4/rest/services/';
const _batasWaktu = Duration(seconds: 25);
const radiusSesarKm = 150;

/// Kelas material dari nama/umur formasi untuk wilayah yang kode petanya belum ditinjau.
/// Mengembalikan kunci pada tabel `kelas` di litologi_dampak.json.
String kelasDariNama(String nama, String umur) {
  final t = nama.toLowerCase();
  final u = umur.toLowerCase();
  final kuarter = u.contains('kuarter') || u.contains('holosen') || u.contains('plistosen') || u.contains('quarter');
  final neogen = u.contains('neogen') || u.contains('miosen') || u.contains('miocene') || u.contains('plio') || u.contains('tersier');

  bool ada(List<String> k) => k.any(t.contains);
  if (ada(['colluvium', 'koluvium'])) return 'koluvium';
  if (ada(['terrace', 'teras', 'older alluvium', 'older aluvium'])) return 'aluvium_tua';
  if (ada(['alluvium', 'aluvium', 'alluvial', 'swamp', 'rawa', 'delta', 'beach', 'pantai', 'tidal', 'mangrove', 'flood', 'dataran banjir'])) {
    return 'aluvium';
  }
  if (ada(['limestone', 'batugamping', 'karst', 'reef', 'terumbu', 'coral', 'koral'])) return 'gamping';
  if (ada(['granit', 'diorit', 'dioryte', 'basalt', 'gabbro', 'dacite', 'dasit', 'intrusi', 'intrusive', 'ultramafic', 'peridotit', 'serpentin', 'andesite', 'andesit'])) {
    if (!ada(['lava', 'breccia', 'breksi', 'tuff', 'tuf']) || ada(['intrusi', 'intrusive', 'granit', 'diorit'])) return 'beku';
  }
  if (ada(['metamorf', 'schist', 'sekis', 'gneiss', 'slate', 'filit', 'phyllite', 'marble', 'marmer', 'kuarsit', 'quartzite', 'malih'])) {
    return 'malih';
  }
  if (ada(['volcanic', 'vulkanik', 'gunungapi', 'gunung api', 'lava', 'lahar', 'tuff', 'tuf', 'breccia', 'breksi', 'pyroclastic', 'piroklastik', 'ignimbrite'])) {
    if (kuarter) return ada(['old', 'tua', 'older']) ? 'vulkanik_tua' : 'vulkanik_muda';
    return 'tuf_breksi';
  }
  // Batuan sedimen atau tak diketahui: tebak dari umur
  if (kuarter) return 'aluvium_tua';
  if (neogen) return 'sedimen_lunak';
  return 'sedimen_tua';
}

class GalatJaringan implements Exception {
  final String pesan;
  GalatJaringan(this.pesan);
  @override
  String toString() => pesan;
}

class _Sesar {
  final String nama, status;
  final double jarakKm;
  const _Sesar(this.nama, this.status, this.jarakKm);
}

class MesinDaring {
  final http.Client _klien;
  final Map<String, dynamic> _kelas, _pemetaanDiy;

  MesinDaring(this._klien, this._kelas, this._pemetaanDiy);

  /// Pemetaan kode formasi hanya sah untuk DIY (kode peta dipakai ulang di lembar lain).
  static bool _diDiy(double lat, double lon) => lat >= -8.2 && lat <= -7.5 && lon >= 110.0 && lon <= 110.7;

  Future<Map<String, dynamic>?> _ambil(String svc, Map<String, String> param) async {
    try {
      final uri = Uri.https(_host, '$_dasar$svc/MapServer/0/query', {...param, 'f': 'json'});
      final r = await _klien.get(uri).timeout(_batasWaktu);
      if (r.statusCode != 200) return null;
      final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return d.containsKey('error') ? null : d;
    } catch (_) {
      return null; // jaringan putus atau waktu habis: ditangani pemanggil sebagai data tidak tersedia
    }
  }

  Future<Map<String, dynamic>?> _titik(String svc, double lat, double lon) async {
    final d = await _ambil(svc, {
      'geometry': '$lon,$lat',
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': '*',
      'returnGeometry': 'false',
    });
    if (d == null) return null; // gagal
    final fs = (d['features'] as List?) ?? const [];
    return fs.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(fs.first['attributes'] as Map);
  }

  /// Semua fitur yang memuat titik (untuk layer dengan poligon bertumpuk, mis. gerakan tanah).
  Future<List<Map<String, dynamic>>?> _titikSemua(String svc, double lat, double lon) async {
    final d = await _ambil(svc, {
      'geometry': '$lon,$lat',
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'outFields': '*',
      'returnGeometry': 'false',
    });
    if (d == null) return null;
    return [for (final f in (d['features'] as List?) ?? const []) Map<String, dynamic>.from(f['attributes'] as Map)];
  }

  Future<_Sesar?> _sesarTerdekat(double lat, double lon) async {
    final d = await _ambil('BGS_PM/Patahan_Aktif_Skala_Besar', {
      'geometry': '$lon,$lat',
      'geometryType': 'esriGeometryPoint',
      'inSR': '4326',
      'outSR': '4326',
      'spatialRel': 'esriSpatialRelIntersects',
      'distance': '${radiusSesarKm * 1000}',
      'units': 'esriSRUnit_Meter',
      'outFields': 'namobj,klspthn',
      'returnGeometry': 'true',
      'maxAllowableOffset': '0.005',
    });
    if (d == null) return null;
    final kx = 111.32 * math.cos(lat * math.pi / 180), ky = 110.57;
    _Sesar? terbaik;
    for (final f in (d['features'] as List?) ?? const []) {
      final paths = (f['geometry']?['paths'] as List?) ?? const [];
      for (final ln in paths) {
        final p = ln as List;
        for (var k = 0; k < p.length - 1; k++) {
          final ax = ((p[k][0] as num) - lon) * kx, ay = ((p[k][1] as num) - lat) * ky;
          final bx = ((p[k + 1][0] as num) - lon) * kx, by = ((p[k + 1][1] as num) - lat) * ky;
          final dx = bx - ax, dy = by - ay;
          final t = (dx == 0 && dy == 0) ? 0.0 : (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
          final jarak = math.sqrt(math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2));
          if (terbaik == null || jarak < terbaik.jarakKm) {
            final a = f['attributes'] as Map;
            terbaik = _Sesar((a['namobj'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? 'Sesar tanpa nama',
                (a['klspthn'] as String?) ?? '-', jarak);
          }
        }
      }
    }
    return terbaik;
  }

  Future<double?> _elevasi(double lat, double lon) async {
    try {
      final r = await _klien
          .get(Uri.https('api.open-meteo.com', '/v1/elevation', {'latitude': '$lat', 'longitude': '$lon'}))
          .timeout(_batasWaktu);
      if (r.statusCode != 200) return null;
      final e = (jsonDecode(r.body)['elevation'] as List).first;
      return (e as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<HasilLokasi> analisis(double lat, double lon) async {
    final h = await Future.wait<Object?>([
      _titik('BGS_PM/Geologi_Litologi', lat, lon),
      _titik('BGV_GT/KRB_Gempa_Bumi', lat, lon),
      _titik('BGE_GT/Kerentanan_Likuefaksi_Skala_1_50000', lat, lon),
      _titik('BGE_GT/Kerentanan_Likuefaksi', lat, lon),
      _titikSemua('BGV_GT/Zona_Kerentanan_Gerakan_Tanah', lat, lon),
      _titik('BGV_GT/KRB_Tsunami', lat, lon),
      _titik('BGE_GT/Sebaran_Tanah_Lunak_Indonesia', lat, lon),
      _sesarTerdekat(lat, lon),
      _elevasi(lat, lon),
    ]);
    final geo = h[0] as Map<String, dynamic>?;
    final krb = h[1] as Map<String, dynamic>?;
    final l50 = h[2] as Map<String, dynamic>?;
    final l100 = h[3] as Map<String, dynamic>?;
    final gtSemua = h[4] as List<Map<String, dynamic>>?;
    final tsu = h[5] as Map<String, dynamic>?;
    final lunak = h[6] as Map<String, dynamic>?;
    final sesar = h[7] as _Sesar?;
    final elev = h[8] as double?;

    // Tanpa geologi maupun zonasi gempa, tidak ada yang bisa disimpulkan (kemungkinan besar tidak ada koneksi).
    if (geo == null && krb == null) {
      throw GalatJaringan('Tidak bisa menghubungi server Badan Geologi. Periksa koneksi internet.');
    }

    // material
    String? kode;
    var perkiraan = false;
    if (geo != null && geo.isNotEmpty) {
      final simobj = geo['simobj'] as String?;
      if (_diDiy(lat, lon) && simobj != null && _pemetaanDiy.containsKey(simobj)) {
        kode = _pemetaanDiy[simobj] as String;
      } else {
        kode = kelasDariNama('${geo['namobj'] ?? ''} ${geo['remark'] ?? ''}', '${geo['umurobj'] ?? ''}');
        perkiraan = true;
      }
    }
    final mat = kode == null ? null : Map<String, dynamic>.from(_kelas[kode] as Map);
    final vs30 = (mat?['vs30'] as num?)?.toDouble() ?? 400.0;

    // zonasi resmi
    final krbKelas = (krb != null && krb.isNotEmpty) ? krb['kelas'] as String? : null;
    final krbLv = krbKelas == null ? null : kKrb[krbKelas.replaceFirst('Kawasan Rawan Bencana Gempabumi ', '')];

    int? likLv;
    String likSrc;
    if (l50 != null && l50.isNotEmpty) {
      likLv = kLik50[(l50['kerentanan'] as String).trim()];
      likSrc = 'resmi 1:50.000';
    } else if (l100 != null && l100.isNotEmpty) {
      final lv = kLik100[l100['kerentanan'].toString().trim()];
      likLv = (lv != null && mat != null) ? math.min(lv, 1 + (mat['likuefaksi'] as int)) : lv;
      likSrc = 'resmi 1:100.000 (poligon kasar, dibatasi oleh material)';
    } else {
      likLv = mat?['likuefaksi'] as int?;
      likSrc = 'perkiraan dari material';
    }

    final gt = (gtSemua ?? const []).where((p) => kGt.containsKey(p['unsur'])).toList();
    int? gtLv;
    String gtSrc;
    if (gt.isNotEmpty) {
      gtLv = kGt[gt.first['unsur']];
      gtSrc = 'resmi 1:50.000';
    } else {
      gtLv = mat == null ? null : ((mat['longsor'] as int) * 0.7).round();
      gtSrc = 'perkiraan dari material (lereng tidak diketahui)';
    }

    final tsunamiLv = (tsu != null && tsu.isNotEmpty)
        ? (kTsunami[(tsu['unsur'] as String? ?? '').replaceFirst('Kawasan Rawan Bencana Tsunami ', '')] ?? 3)
        : null;
    final level = [krbLv, likLv, gtLv].whereType<int>();

    return HasilLokasi(
      lat: lat,
      lon: lon,
      sumber: 'daring',
      kodeFormasi: geo?['simobj'] as String?,
      formasi: geo?['namobj'] as String?,
      umur: geo?['umurobj'] as String?,
      kelasMaterial: kode,
      namaMaterial: mat?['nama'] as String?,
      catatanMaterial: mat?['catatan'] as String?,
      materialPerkiraan: perkiraan,
      vs30: vs30,
      elevasiM: elev,
      kemiringan: null,
      namaSesar: sesar?.nama,
      statusSesar: sesar?.status,
      jarakSesarKm: sesar?.jarakKm,
      mekanisme: sesar == null ? Mekanisme.takDiketahui : Mekanisme.dariNama(sesar.nama),
      krbTingkat: krbLv,
      krbKelas: krbKelas,
      likTingkat: likLv,
      likSumber: likSrc,
      gtTingkat: gtLv,
      gtSumber: gtSrc,
      tsunamiTingkat: tsunamiLv,
      tanahLunak: (lunak != null && lunak.isNotEmpty) ? lunak['jenis_tana'] as String? : null,
      tingkatKeseluruhan: level.isEmpty ? null : level.reduce(math.max),
    );
  }
}
