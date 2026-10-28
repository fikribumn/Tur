// Menu Simulasi: taruh sumber gempa (merah) dan titikmu (biru) di peta, atur magnitudo/kedalaman/arah sesar.
// Area terdampak digambar sebagai peta guncangan per titik: tiap sel dihitung dari jarak ke retakan memanjang
// dan Vs30 setempat (peta geologi resmi), jadi bentuknya mengikuti sesar dan jenis tanah, bukan lingkaran.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'mesin/bidang_guncangan.dart';
import 'mesin/gmpe.dart';
import 'mesin/hasil.dart';
import 'mesin/peta_geologi.dart';
import 'mesin/simulasi.dart';
import 'peta_umum.dart';

const _romawi = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
String _rom(double m) => _romawi[m.round().clamp(1, 10)];

/// Lapisan zonasi resmi (ArcGIS MapServer) yang bisa ditampilkan sebagai ubin.
const _lapisan = {
  'KRB gempa': 'BGV_GT/KRB_Gempa_Bumi',
  'Likuefaksi': 'BGE_GT/Kerentanan_Likuefaksi',
  'Gerakan tanah': 'BGV_GT/Zona_Kerentanan_Gerakan_Tanah',
  'Tsunami': 'BGV_GT/KRB_Tsunami',
};

/// Ubin dari endpoint `export` ArcGIS MapServer: bbox dihitung dari koordinat ubin (EPSG:3857).
class _ZonasiTileProvider extends NetworkTileProvider {
  final String layanan;
  _ZonasiTileProvider(this.layanan)
      : super(silenceExceptions: true, headers: {'User-Agent': 'TERRA-TUR/1.4 (riset kerentanan gempa)'}); // bukan const: TileLayer menambah header

  @override
  String getTileUrl(TileCoordinates c, TileLayer options) {
    const w = 20037508.342789244;
    final n = 1 << c.z;
    final s = 2 * w / n;
    final minX = -w + c.x * s, maxY = w - c.y * s;
    return 'https://geoportal.esdm.go.id/gis4/rest/services/$layanan/MapServer/export'
        '?bbox=$minX,${maxY - s},${minX + s},$maxY&bboxSR=3857&imageSR=3857&size=256,256'
        '&format=png32&transparent=true&f=image';
  }
}

enum _Mode { sumber, titikku }

class SimulasiPage extends StatefulWidget {
  final HasilLokasi lokasi;

  /// Menganalisis ulang bila pengguna memindahkan titiknya (data zonasi dan jenis tanah ikut berubah).
  final Future<HasilLokasi> Function(double lat, double lon) analisis;

  /// Pengambil grid geologi dan pengubah piksel ke PNG; bisa diganti pada tes.
  final Future<GridVs30> Function(double lat, double lon, double radiusKm)? muatGeologi;
  final Future<Uint8List> Function(Uint8List rgba, int lebar, int tinggi)? enkode;

  const SimulasiPage({super.key, required this.lokasi, required this.analisis, this.muatGeologi, this.enkode});

  @override
  State<SimulasiPage> createState() => _SimulasiPageState();
}

class _SimulasiPageState extends State<SimulasiPage> {
  late HasilLokasi _site = widget.lokasi;
  late LatLng _src;
  late double _strike;
  double _m = 6.5, _dalam = 10;
  Mekanisme _mek = Mekanisme.takDiketahui;
  _Mode _mode = _Mode.sumber;
  final _aktif = <String>{};
  bool _menganalisis = false;
  final _peta = MapController();

  // peta guncangan
  final _klien = http.Client();
  PemuatGeologi? _pemuat;
  GridVs30? _geo;
  double _geoJendela = 0;
  LatLng? _geoPusat;
  bool _geoCadangan = false; // true bila geologi gagal diambil dan grid seragam dipakai
  bool _memuatGeo = false;
  Uint8List? _png;
  GridVs30? _gridTampil;
  Timer? _tunda;
  int _versi = 0;

  @override
  void initState() {
    super.initState();
    _src = _awalSumber(widget.lokasi);
    _strike = widget.lokasi.sesarArahDeg ?? 0;
    if (widget.lokasi.jarakSesarKm != null && widget.lokasi.mekanisme != Mekanisme.takDiketahui) {
      _mek = widget.lokasi.mekanisme;
    }
    _jadwalkan();
  }

  @override
  void dispose() {
    _tunda?.cancel();
    _klien.close();
    super.dispose();
  }

  /// Sumber awal: titik sesar terdekat bila ada, jika tidak 30 km ke timur titikmu.
  LatLng _awalSumber(HasilLokasi h) {
    if (h.sesarLat != null && h.sesarLon != null && (h.jarakSesarKm ?? 999) > 1.0) {
      return LatLng(h.sesarLat!, h.sesarLon!);
    }
    return LatLng(h.lat, h.lon + 30 / (111.32 * math.cos(h.lat * math.pi / 180)));
  }

  void _taruhDiSesar() {
    final s = _site;
    if (s.sesarLat == null || s.sesarLon == null) return;
    setState(() {
      _src = LatLng(s.sesarLat!, s.sesarLon!);
      if (s.mekanisme != Mekanisme.takDiketahui) _mek = s.mekanisme;
      if (s.sesarArahDeg != null) _strike = s.sesarArahDeg!;
    });
    _peta.move(_src, math.max(_peta.camera.zoom, 9));
    _jadwalkan();
  }

  Future<void> _aturTitikku(LatLng p) async {
    setState(() => _menganalisis = true);
    try {
      final h = await widget.analisis(p.latitude, p.longitude);
      if (mounted) setState(() => _site = h);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menganalisis titik: $e')));
    } finally {
      if (mounted) setState(() => _menganalisis = false);
    }
  }

  void _ketuk(LatLng p) {
    if (_menganalisis) return;
    if (_mode == _Mode.sumber) {
      setState(() => _src = p);
      _jadwalkan();
    } else {
      _aturTitikku(p);
    }
  }

  /// Hitung ulang peta guncangan setelah jeda singkat, agar geseran slider tidak memicu hitungan di tiap piksel.
  void _jadwalkan() {
    _tunda?.cancel();
    _tunda = Timer(const Duration(milliseconds: 180), _perbarui);
  }

  Future<GridVs30> _ambilGeologi(double lat, double lon, double radiusKm) async {
    if (widget.muatGeologi != null) return widget.muatGeologi!(lat, lon, radiusKm);
    if (_pemuat == null) {
      final lito = jsonDecode(await rootBundle.loadString('assets/data/litologi_dampak.json')) as Map<String, dynamic>;
      _pemuat = PemuatGeologi(
          _klien, Map<String, dynamic>.from(lito['kelas'] as Map), Map<String, dynamic>.from(lito['pemetaan_simobj'] as Map));
    }
    return _pemuat!.muat(lat, lon, radiusKm);
  }

  Future<void> _perbarui() async {
    final versi = ++_versi;
    if (_dalam > kedalamanMaksKm) {
      if (mounted) {
        setState(() {
          _png = null;
          _memuatGeo = false;
        });
      }
      return;
    }
    final m = _m, mek = _mek, strike = _strike, src = _src;
    final jendela = pilihJendelaKm(radiusJangkauanKm(m, mek));
    final perluMuat = _geo == null ||
        _geoJendela != jendela ||
        jarakKm(src.latitude, src.longitude, _geoPusat!.latitude, _geoPusat!.longitude) > jendela * 0.25;

    if (perluMuat) {
      if (mounted) setState(() => _memuatGeo = true);
      try {
        _geo = await _ambilGeologi(src.latitude, src.longitude, jendela);
        _geoCadangan = false;
      } catch (_) {
        _geo = GridVs30.seragam(src.latitude, src.longitude, jendela, 110, _site.vs30);
        _geoCadangan = true;
      }
      _geoJendela = jendela;
      _geoPusat = src;
    }
    if (versi != _versi || !mounted) return; // ada pembaruan yang lebih baru

    final seg = segmenRuptur(src.latitude, src.longitude, panjangRupturKm(m, mek), strike);
    final bidang = hitungBidang(_geo!, seg: seg, m: m, mek: mek);
    final enkode = widget.enkode ?? kePng;
    final png = await enkode(warnaRgba(bidang), _geo!.nx, _geo!.ny);
    if (versi != _versi || !mounted) return;
    setState(() {
      _png = png;
      _gridTampil = _geo;
      _memuatGeo = false;
    });
  }

  HasilSimulasi get _sim => simulasikan(
        srcLat: _src.latitude,
        srcLon: _src.longitude,
        siteLat: _site.lat,
        siteLon: _site.lon,
        magnitudo: _m,
        kedalamanKm: _dalam,
        vs30: _site.vs30,
        mekanisme: _mek,
        arahSesarDeg: _strike,
      );

  @override
  Widget build(BuildContext context) {
    final sim = _sim;
    final site = LatLng(_site.lat, _site.lon);
    final seg = sim.segmen;

    return Scaffold(
      appBar: AppBar(title: const Text('Simulasi gempa')),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _peta,
                  options: MapOptions(
                    initialCameraFit: CameraFit.coordinates(
                        coordinates: [site, _src], padding: const EdgeInsets.all(70), maxZoom: 10),
                    minZoom: zoomMin,
                    maxZoom: zoomMaks,
                    interactionOptions: opsiInteraksi,
                    onTap: (_, p) => _ketuk(p),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'id.zonaaman.zona_aman_gempa',
                      maxZoom: 18,
                    ),
                    for (final e in _lapisan.entries)
                      if (_aktif.contains(e.key))
                        Opacity(
                          opacity: 0.6,
                          child: TileLayer(
                            urlTemplate: 'zonasi/{z}/{x}/{y}', // diabaikan; URL dibuat oleh _ZonasiTileProvider
                            tileProvider: _ZonasiTileProvider(e.value),
                            maxNativeZoom: 16,
                          ),
                        ),
                    if (sim.berlaku && _png != null && _gridTampil != null)
                      OverlayImageLayer(overlayImages: [
                        OverlayImage(
                          bounds: LatLngBounds(LatLng(_gridTampil!.lat0, _gridTampil!.lon0), LatLng(_gridTampil!.lat1, _gridTampil!.lon1)),
                          imageProvider: MemoryImage(_png!),
                          opacity: 0.9,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ]),
                    PolylineLayer(polylines: [
                      Polyline(points: [_src, site], strokeWidth: 2.5, color: Colors.black87, pattern: StrokePattern.dashed(segments: const [10, 8])),
                      Polyline(
                        points: [LatLng(seg.lat1, seg.lon1), LatLng(seg.lat2, seg.lon2)],
                        strokeWidth: 5,
                        color: const Color(0xFFD23B3B),
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng((site.latitude + _src.latitude) / 2, (site.longitude + _src.longitude) / 2),
                        width: 110,
                        height: 28,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black26)),
                          child: Text('${sim.jarakKm.toStringAsFixed(1)} km',
                              style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      Marker(point: _src, width: 44, height: 44, child: const Icon(Icons.crisis_alert, size: 40, color: Color(0xFFD23B3B))),
                      Marker(
                        point: site,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: const Icon(Icons.location_on, size: 46, color: Color(0xFF2F5FD0)),
                      ),
                    ]),
                    const RichAttributionWidget(
                      alignment: AttributionAlignment.bottomLeft,
                      attributions: [
                        TextSourceAttribution('© kontributor OpenStreetMap'),
                        TextSourceAttribution('Geologi & zonasi: Badan Geologi (ESDM)'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SegmentedButton<_Mode>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: _Mode.sumber, icon: Icon(Icons.crisis_alert), label: Text('Atur sumber')),
                              ButtonSegment(value: _Mode.titikku, icon: Icon(Icons.location_on), label: Text('Atur titikku')),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) => setState(() => _mode = s.first),
                          ),
                          if (_memuatGeo)
                            const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 3)),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(right: 8, bottom: 28, child: TombolZoom(kontrol: _peta)),
                if (_menganalisis)
                  const Positioned.fill(child: ColoredBox(color: Color(0x55000000), child: Center(child: CircularProgressIndicator()))),
              ],
            ),
          ),
          Expanded(flex: 6, child: _panel(context, sim)),
        ],
      ),
    );
  }

  Widget _legenda(BuildContext context) {
    final kecil = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        for (final t in [4, 5, 6, 7, 8, 9])
          Expanded(
            child: Column(children: [
              Container(
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                color: () {
                  final (r, g, b, a) = warnaMmi(t.toDouble());
                  return Color.fromARGB(255, r, g, b).withValues(alpha: (a / 255).clamp(0.45, 1.0));
                }(),
              ),
              Text(_romawi[t], style: kecil),
            ]),
          ),
      ],
    );
  }

  Widget _panel(BuildContext context, HasilSimulasi sim) {
    final tema = Theme.of(context);
    final kecil = tema.textTheme.bodySmall;
    final h = _site;
    final mmi = sim.mmi;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ringkasan hasil di paling atas agar langsung terlihat saat slider digeser
        Text('Titikmu berada ${sim.jarakKm.toStringAsFixed(1)} km di arah ${namaArah(sim.arahDeg)} dari pusat sumber '
            '(${sim.rjbKm.toStringAsFixed(1)} km dari retakan sepanjang ±${sim.panjangKm.round()} km).',
            style: tema.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (!sim.berlaku)
          Card(
            color: tema.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  'Kedalaman ${_dalam.round()} km melebihi ${kedalamanMaksKm.round()} km. Itu gempa dalam (subduksi/intraslab), '
                  'dan model aplikasi ini hanya untuk gempa kerak dangkal, jadi angka sengaja tidak dihitung. '
                  'Kurangi kedalaman untuk mensimulasikan gempa kerak.'),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MMI ${_rom(mmi!)}', style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(uraianMmi(mmi)),
                  const SizedBox(height: 6),
                  Text(
                      'PGA ${sim.pgaG!.toStringAsFixed(2)} g · PGV ${sim.pgvCms!.round()} cm/s · Vs30 ~${h.vs30.round()} m/s '
                      '(${h.namaMaterial ?? 'jenis tanah tidak diketahui'})',
                      style: kecil),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        // kontrol
        Text('Magnitudo ${_m.toStringAsFixed(1)}', style: tema.textTheme.labelLarge),
        Slider(
          key: const Key('slider-magnitudo'),
          min: 4.5,
          max: 8.5,
          divisions: 40,
          value: _m,
          label: _m.toStringAsFixed(1),
          onChanged: (v) {
            setState(() => _m = v);
            _jadwalkan();
          },
        ),
        Text('Kedalaman ${_dalam.round()} km', style: tema.textTheme.labelLarge),
        Slider(
          key: const Key('slider-kedalaman'),
          min: 5,
          max: 100,
          divisions: 19,
          value: _dalam,
          label: '${_dalam.round()} km',
          onChanged: (v) {
            setState(() => _dalam = v);
            _jadwalkan();
          },
        ),
        Text('Arah sesar ${_strike.round()}° (0° = utara–selatan, 90° = barat–timur)', style: tema.textTheme.labelLarge),
        Slider(
          key: const Key('slider-strike'),
          min: 0,
          max: 180,
          divisions: 36,
          value: _strike.clamp(0, 180).toDouble(),
          label: '${_strike.round()}°',
          onChanged: (v) {
            setState(() => _strike = v);
            _jadwalkan();
          },
        ),
        Wrap(spacing: 8, children: [
          for (final m in Mekanisme.values)
            ChoiceChip(
              label: Text(m.label),
              selected: _mek == m,
              onSelected: (_) {
                setState(() => _mek = m);
                _jadwalkan();
              },
            ),
        ]),
        if (h.sesarLat != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _taruhDiSesar,
              icon: const Icon(Icons.polyline_outlined),
              label: Text('Taruh di sesar terdekat (${h.namaSesar ?? ''})'),
            ),
          ),
        const Divider(),
        if (sim.berlaku) ..._dampakTurunan(context, mmi!),
        const SizedBox(height: 8),
        Text('Peta guncangan (MMI)', style: tema.textTheme.labelLarge),
        const SizedBox(height: 4),
        _legenda(context),
        const SizedBox(height: 4),
        Text(
            _geoCadangan
                ? 'Geologi sekitar sumber tidak bisa diambil (periksa internet). Peta memakai Vs30 titikmu untuk semua area, '
                    'jadi bentuknya hanya mengikuti sesar, bukan jenis tanah.'
                : 'Tiap titik dihitung dari jarak ke retakan dan jenis tanah setempat (peta geologi Badan Geologi): tanah lunak '
                    'menguat, batuan keras melemah. Laut dan area tanpa data tidak diwarnai. Peta dibatasi ±250 km dari sumber; '
                    'pada magnitudo besar (M7,5+) guncangan sebenarnya meluas melampaui batas itu.',
            style: kecil),
        const SizedBox(height: 12),
        Text('Lapisan zonasi resmi (Badan Geologi)', style: tema.textTheme.labelLarge),
        Wrap(spacing: 8, children: [
          for (final k in _lapisan.keys)
            FilterChip(
              label: Text(k),
              selected: _aktif.contains(k),
              onSelected: (v) => setState(() => v ? _aktif.add(k) : _aktif.remove(k)),
            ),
        ]),
        const SizedBox(height: 4),
        Text('Warna lapisan mengikuti legenda resmi Badan Geologi; ubin dimuat dari server dan bisa lambat. '
            'Area tanpa warna belum tentu aman: bisa berarti belum terpetakan.',
            style: kecil),
        const SizedBox(height: 12),
        Text(
            'Perkiraan model median (BSSA14 + Worden 2012) untuk retakan lurus di kerak dangkal; kelas tanah di luar DIY ditebak '
            'dari nama dan umur formasi. Bukan alat keselamatan resmi.',
            style: kecil),
      ],
    );
  }

  List<Widget> _dampakTurunan(BuildContext context, double mmi) {
    final h = _site;
    final baris = <String>[];
    if ((h.likTingkat ?? 0) >= 2) {
      baris.add(mmi >= 7
          ? 'Likuefaksi mungkin terjadi: titikmu berada di zona rawan (${namaTingkat[h.likTingkat!]}) dan guncangan cukup kuat.'
          : 'Titikmu di zona rawan likuefaksi (${namaTingkat[h.likTingkat!]}), tetapi guncangan skenario ini belum cukup kuat untuk memicunya.');
    }
    if ((h.gtTingkat ?? 0) >= 2) {
      baris.add(mmi >= 6.5
          ? 'Gerakan tanah/longsor mungkin terjadi: zona ${namaTingkat[h.gtTingkat!]}, terutama bila baru hujan.'
          : 'Titikmu di zona rawan gerakan tanah (${namaTingkat[h.gtTingkat!]}); guncangan skenario ini relatif lemah.');
    }
    if (_m >= 7.0 && _dalam <= 60) {
      baris.add('Gempa M${_m.toStringAsFixed(1)} dangkal yang pusatnya di laut berpotensi memicu tsunami. Ikuti peringatan BMKG.');
    }
    if (baris.isEmpty) baris.add('Tidak ada bahaya turunan menonjol di titikmu pada skenario ini.');
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dampak turunan di titikmu', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final b in baris) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $b')),
            ],
          ),
        ),
      ),
    ];
  }
}
