// Menu Simulasi: taruh sumber gempa (merah) dan titikmu (biru) di peta, atur magnitudo/kedalaman,
// lihat cincin zona guncangan dan dampak di titikmu. Lapisan zonasi resmi Badan Geologi bisa dinyalakan.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'mesin/gmpe.dart';
import 'mesin/hasil.dart';
import 'mesin/simulasi.dart';

const _romawi = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
String _rom(double m) => _romawi[m.round().clamp(1, 10)];

const _warnaCincin = {
  6: Color(0xFFE0B020),
  7: Color(0xFFE8902A),
  8: Color(0xFFE05030),
  9: Color(0xFFA01820),
};

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
      : super(silenceExceptions: true, headers: {'User-Agent': 'TERRA-TUR/1.3 (riset kerentanan gempa)'}); // bukan const: TileLayer menambah header

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
  const SimulasiPage({super.key, required this.lokasi, required this.analisis});

  @override
  State<SimulasiPage> createState() => _SimulasiPageState();
}

class _SimulasiPageState extends State<SimulasiPage> {
  late HasilLokasi _site = widget.lokasi;
  late LatLng _src;
  double _m = 6.5, _dalam = 10;
  Mekanisme _mek = Mekanisme.takDiketahui;
  _Mode _mode = _Mode.sumber;
  final _aktif = <String>{};
  bool _menganalisis = false;
  final _peta = MapController();

  @override
  void initState() {
    super.initState();
    _src = _awalSumber(widget.lokasi);
    if (widget.lokasi.jarakSesarKm != null && widget.lokasi.mekanisme != Mekanisme.takDiketahui) {
      _mek = widget.lokasi.mekanisme;
    }
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
    });
    _peta.move(_src, math.max(_peta.camera.zoom, 9));
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
    } else {
      _aturTitikku(p);
    }
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
      );

  @override
  Widget build(BuildContext context) {
    final sim = _sim;
    final site = LatLng(_site.lat, _site.lon);
    final tengah = LatLng((site.latitude + _src.latitude) / 2, (site.longitude + _src.longitude) / 2);

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
                    minZoom: 3,
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
                    if (sim.berlaku) CircleLayer(circles: _cincin()),
                    PolylineLayer(polylines: [
                      Polyline(
                        points: [_src, site],
                        strokeWidth: 2.5,
                        color: Colors.black87,
                        pattern: StrokePattern.dashed(segments: const [10, 8]),
                      ),
                    ]),
                    MarkerLayer(markers: [
                      Marker(
                        point: tengah,
                        width: 110,
                        height: 28,
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black26)),
                          child: Text('${sim.jarakKm.toStringAsFixed(1)} km',
                              style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      Marker(
                        point: _src,
                        width: 44,
                        height: 44,
                        child: const Icon(Icons.crisis_alert, size: 40, color: Color(0xFFD23B3B)),
                      ),
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
                        TextSourceAttribution('Zonasi: Badan Geologi (ESDM)'),
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
                      child: SegmentedButton<_Mode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: _Mode.sumber, icon: Icon(Icons.crisis_alert), label: Text('Atur sumber')),
                          ButtonSegment(value: _Mode.titikku, icon: Icon(Icons.location_on), label: Text('Atur titikku')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (s) => setState(() => _mode = s.first),
                      ),
                    ),
                  ),
                ),
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

  List<CircleMarker> _cincin() {
    final out = <CircleMarker>[];
    for (final t in tingkatCincin) {
      final r = radiusMmiKm(_m, t, _mek);
      if (r == null) continue;
      final w = _warnaCincin[t]!;
      out.add(CircleMarker(
        point: _src,
        radius: r * 1000,
        useRadiusInMeter: true,
        color: w.withValues(alpha: 0.18),
        borderColor: w,
        borderStrokeWidth: 1.5,
      ));
    }
    // cincin terbesar digambar lebih dulu agar yang kecil tidak tertutup
    return out;
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
        Text('Titikmu berada ${sim.jarakKm.toStringAsFixed(1)} km di arah ${namaArah(sim.arahDeg)} dari sumber.',
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
        Slider(key: const Key('slider-magnitudo'), min: 4.5, max: 8.5, divisions: 40, value: _m, label: _m.toStringAsFixed(1), onChanged: (v) => setState(() => _m = v)),
        Text('Kedalaman ${_dalam.round()} km', style: tema.textTheme.labelLarge),
        Slider(key: const Key('slider-kedalaman'), min: 5, max: 100, divisions: 19, value: _dalam, label: '${_dalam.round()} km', onChanged: (v) => setState(() => _dalam = v)),
        Wrap(spacing: 8, children: [
          for (final m in Mekanisme.values)
            ChoiceChip(label: Text(m.label), selected: _mek == m, onSelected: (_) => setState(() => _mek = m)),
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
        Text('Zona guncangan (cincin) untuk tanah sedang, Vs30 400 m/s:', style: tema.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final t in tingkatCincin)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: _warnaCincin[t], shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(
                  () {
                    final r = radiusMmiKm(_m, t, _mek);
                    return r == null ? 'MMI ${_romawi[t]}: tidak tercapai' : 'MMI ${_romawi[t]}: ≤ ${r.toStringAsFixed(r < 10 ? 1 : 0)} km';
                  }(),
                  style: kecil),
            ]),
        ]),
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
        Text(
            'Warna lapisan mengikuti legenda resmi Badan Geologi; ubin dimuat dari server dan bisa lambat. '
            'Area tanpa warna belum tentu aman: bisa berarti belum terpetakan.',
            style: kecil),
        const SizedBox(height: 12),
        Text(
            'Perkiraan model median (BSSA14 + Worden 2012) untuk sumber titik di kerak dangkal; gempa besar yang pecahannya panjang '
            'akan lebih dekat daripada yang dihitung. Bukan alat keselamatan resmi.',
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
