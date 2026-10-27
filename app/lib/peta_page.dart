// Pemilih lokasi bebas: ketuk titik mana pun di peta, atau cari nama tempat (Nominatim/OpenStreetMap).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Hasil pemilihan: koordinat dan label yang ditampilkan di kartu lokasi.
class LokasiPilihan {
  final double lat, lon;
  final String label;
  const LokasiPilihan(this.lat, this.lon, this.label);
}

const _agen = 'TERRA-TUR/1.1 (aplikasi riset kerentanan gempa; id.zonaaman.zona_aman_gempa)';

class PetaPage extends StatefulWidget {
  final double awalLat, awalLon;
  const PetaPage({super.key, required this.awalLat, required this.awalLon});

  @override
  State<PetaPage> createState() => _PetaPageState();
}

class _PetaPageState extends State<PetaPage> {
  final _peta = MapController();
  final _cari = TextEditingController();
  final _klien = http.Client();
  LatLng? _titik;
  String? _nama; // nama tempat bila dari pencarian
  bool _mencari = false;
  String? _pesan;

  @override
  void dispose() {
    _klien.close();
    _cari.dispose();
    super.dispose();
  }

  // Nominatim: hanya dipanggil saat pengguna menekan cari (bukan per ketikan), sesuai kebijakan pemakaian mereka.
  Future<void> _cariTempat() async {
    final q = _cari.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mencari = true;
      _pesan = null;
    });
    try {
      final r = await _klien
          .get(
            Uri.https('nominatim.openstreetmap.org', '/search',
                {'q': q, 'format': 'jsonv2', 'countrycodes': 'id', 'limit': '5', 'accept-language': 'id'}),
            headers: {'User-Agent': _agen},
          )
          .timeout(const Duration(seconds: 20));
      final hasil = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (hasil.isEmpty) {
        setState(() => _pesan = 'Tempat "$q" tidak ditemukan di Indonesia.');
      } else if (hasil.length == 1) {
        _pilihHasil(hasil.first);
      } else {
        await _tampilkanDaftar(hasil);
      }
    } catch (_) {
      if (mounted) setState(() => _pesan = 'Pencarian gagal. Periksa internet, atau ketuk langsung di peta.');
    } finally {
      if (mounted) setState(() => _mencari = false);
    }
  }

  Future<void> _tampilkanDaftar(List<Map<String, dynamic>> hasil) async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final h in hasil)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(h['display_name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(c, h),
              ),
          ],
        ),
      ),
    );
    if (dipilih != null) _pilihHasil(dipilih);
  }

  void _pilihHasil(Map<String, dynamic> h) {
    final p = LatLng(double.parse(h['lat'] as String), double.parse(h['lon'] as String));
    setState(() {
      _titik = p;
      _nama = (h['display_name'] as String).split(',').take(2).join(',').trim();
    });
    _peta.move(p, 13);
  }

  @override
  Widget build(BuildContext context) {
    final awal = LatLng(widget.awalLat, widget.awalLon);
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih lokasi')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _peta,
            options: MapOptions(
              initialCenter: awal,
              initialZoom: 9,
              minZoom: 3,
              onTap: (_, p) => setState(() {
                _titik = p;
                _nama = null;
                _pesan = null;
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'id.zonaaman.zona_aman_gempa',
                maxZoom: 18,
              ),
              if (_titik != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _titik!,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, size: 48, color: Color(0xFFD23B3B)),
                  ),
                ]),
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('© kontributor OpenStreetMap')],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(28),
              child: TextField(
                controller: _cari,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _cariTempat(),
                decoration: InputDecoration(
                  hintText: 'Cari tempat (mis. Parangtritis, Palu)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _mencari
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cariTempat),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          ),
          if (_pesan != null)
            Positioned(
              left: 12,
              right: 12,
              top: 72,
              child: Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(10), child: Text(_pesan!))),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            onPressed: _titik == null
                ? null
                : () => Navigator.pop(
                    context,
                    LokasiPilihan(_titik!.latitude, _titik!.longitude,
                        _nama ?? 'Titik di peta')),
            label: Text(_titik == null
                ? 'Ketuk peta untuk memilih titik'
                : 'Analisis titik ini (${_titik!.latitude.toStringAsFixed(4)}, ${_titik!.longitude.toStringAsFixed(4)})'),
          ),
        ),
      ),
    );
  }
}
