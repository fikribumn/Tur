// Katalog gempa terkini BMKG. Ketuk gempa untuk detail, lalu "Simulasikan gempa ini" memindahkannya ke menu Simulasi.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mesin/hasil.dart';
import 'mesin/katalog_bmkg.dart';
import 'mesin/simulasi.dart';

String _rom(double m) => const ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'][m.round().clamp(1, 12)];

Color _warnaMagnitudo(double m) {
  if (m >= 7) return const Color(0xFFD23B3B);
  if (m >= 6) return const Color(0xFFE8702A);
  if (m >= 5) return const Color(0xFFD9A21B);
  return const Color(0xFF2E9E6B);
}

enum _Saring { semua, dirasakan }

class KatalogPage extends StatefulWidget {
  /// Lokasi yang sedang dianalisis (untuk menampilkan jarak ke tiap gempa); boleh null.
  final HasilLokasi? lokasiSaya;
  final void Function(GempaBmkg gempa) onSimulasi;

  /// Pengambil katalog; bisa diganti pada tes.
  final Future<List<GempaBmkg>> Function()? ambil;

  const KatalogPage({super.key, required this.onSimulasi, this.lokasiSaya, this.ambil});

  @override
  State<KatalogPage> createState() => _KatalogPageState();
}

class _KatalogPageState extends State<KatalogPage> {
  final _klien = http.Client();
  late Future<List<GempaBmkg>> _data;
  _Saring _saring = _Saring.semua;

  @override
  void initState() {
    super.initState();
    _data = _muat();
  }

  @override
  void dispose() {
    _klien.close();
    super.dispose();
  }

  Future<List<GempaBmkg>> _muat() => (widget.ambil ?? KatalogBmkg(_klien).ambil)();

  Future<void> _segarkan() async {
    final baru = _muat();
    setState(() {
      _data = baru;
    });
    try {
      await baru;
    } catch (_) {/* ditampilkan oleh FutureBuilder */}
  }

  void _detail(GempaBmkg g) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _Detail(
        gempa: g,
        lokasiSaya: widget.lokasiSaya,
        onSimulasi: () {
          Navigator.pop(c);
          widget.onSimulasi(g);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gempa terkini BMKG'),
        actions: [IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh), onPressed: _segarkan)],
      ),
      body: FutureBuilder<List<GempaBmkg>>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(onPressed: _segarkan, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
                ]),
              ),
            );
          }
          final semua = snap.data!;
          final daftar = _saring == _Saring.semua ? semua : semua.where((g) => g.dirasakan.isNotEmpty).toList();
          final sekarang = DateTime.now().toUtc();
          return RefreshIndicator(
            onRefresh: _segarkan,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: Text('Semua (${semua.length})'),
                      selected: _saring == _Saring.semua,
                      onSelected: (_) => setState(() => _saring = _Saring.semua)),
                  ChoiceChip(
                      label: Text('Dirasakan (${semua.where((g) => g.dirasakan.isNotEmpty).length})'),
                      selected: _saring == _Saring.dirasakan,
                      onSelected: (_) => setState(() => _saring = _Saring.dirasakan)),
                ]),
                const SizedBox(height: 8),
                for (final g in daftar)
                  Card(
                    child: ListTile(
                      onTap: () => _detail(g),
                      leading: CircleAvatar(
                        backgroundColor: _warnaMagnitudo(g.magnitudo),
                        child: Text(g.magnitudo.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      title: Text(g.wilayah, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${g.waktuWib} · ${g.selang(sekarang)} · ${g.kedalamanKm.round()} km'
                          '${g.dirasakan.isNotEmpty ? '\nDirasakan di ${g.dirasakan.length} daerah (maks MMI ${_rom(g.mmiDirasakanMaks!)})' : ''}'
                          '${g.berpotensiTsunami ? '\nBERPOTENSI TSUNAMI' : ''}'),
                      isThreeLine: g.dirasakan.isNotEmpty || g.berpotensiTsunami,
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
                if (daftar.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Tidak ada gempa pada filter ini.'))),
                const SizedBox(height: 8),
                Text('Sumber: BMKG (data.bmkg.go.id). Bukan peringatan dini; ikuti informasi resmi BMKG/BPBD.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final GempaBmkg gempa;
  final HasilLokasi? lokasiSaya;
  final VoidCallback onSimulasi;
  const _Detail({required this.gempa, required this.lokasiSaya, required this.onSimulasi});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final g = gempa;
    final dalam = g.kedalamanKm > kedalamanMaksKm;
    String? jarak;
    if (lokasiSaya != null) {
      final d = jarakKm(g.lat, g.lon, lokasiSaya!.lat, lokasiSaya!.lon);
      jarak = '${d.round()} km di arah ${namaArah(arahDeg(g.lat, g.lon, lokasiSaya!.lat, lokasiSaya!.lon))} dari pusat gempa';
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('M${g.magnitudo.toStringAsFixed(1)} · ${g.kedalamanKm.round()} km', style: tema.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(g.wilayah, style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('${g.waktuWib} · ${g.lat.toStringAsFixed(2)}, ${g.lon.toStringAsFixed(2)}', style: tema.textTheme.bodySmall),
            if (jarak != null) Text('Titikmu: $jarak', style: tema.textTheme.bodySmall),
            if (g.potensi != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(g.potensi!, style: TextStyle(color: g.berpotensiTsunami ? tema.colorScheme.error : null, fontWeight: FontWeight.w600)),
              ),
            if (g.dirasakan.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Dirasakan (laporan BMKG)', style: tema.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final l in g.dirasakan) Chip(visualDensity: VisualDensity.compact, label: Text('${l.tempat} · ${l.skala}')),
              ]),
            ],
            const SizedBox(height: 12),
            if (dalam)
              Card(
                color: tema.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                      'Kedalaman ${g.kedalamanKm.round()} km melebihi ${kedalamanMaksKm.round()} km. Gempa sedalam ini (subduksi/intraslab) '
                      'di luar domain model aplikasi, jadi simulasi akan menampilkan lokasi tetapi tidak menghitung guncangan.'),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(onPressed: onSimulasi, icon: const Icon(Icons.crisis_alert), label: const Text('Simulasikan gempa ini')),
            ),
          ],
        ),
      ),
    );
  }
}
