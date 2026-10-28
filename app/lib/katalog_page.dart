// Katalog gempa terkini: BMKG (M5+, dirasakan) dan USGS (M4+). Disaring menurut periode, magnitudo, dan jarak dari
// lokasimu. Ketuk gempa untuk detail, lalu "Simulasikan gempa ini" memindahkannya ke menu Simulasi.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'mesin/gempa_dekat.dart';
import 'mesin/hasil.dart';
import 'mesin/katalog_bmkg.dart';
import 'mesin/simulasi.dart';

String _rom(double m) => const ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'][m.round().clamp(1, 12)];

Color _warnaMagnitudo(double m) {
  if (m >= 7) return const Color(0xFFD23B3B);
  if (m >= 6) return const Color(0xFFE8702A);
  if (m >= 5) return const Color(0xFFD9A21B);
  if (m >= 4.5) return const Color(0xFF8FB339);
  return const Color(0xFF2E9E6B);
}

/// "110 km ke selatan" dari lokasi pengguna.
String _jarakArah(GempaDekat d) => '${d.jarakKm.round()} km ke ${namaArah(d.arahDeg)}';

class KatalogPage extends StatefulWidget {
  /// Lokasi yang sedang dianalisis; dipakai untuk jarak, radius, dan kartu "terdekat". Boleh null.
  final HasilLokasi? lokasiSaya;
  final void Function(GempaBmkg gempa) onSimulasi;

  /// Pengambil katalog; bisa diganti pada tes.
  final Future<HasilKatalog> Function()? ambil;

  const KatalogPage({super.key, required this.onSimulasi, this.lokasiSaya, this.ambil});

  @override
  State<KatalogPage> createState() => _KatalogPageState();
}

class _KatalogPageState extends State<KatalogPage> {
  final _klien = http.Client();
  late Future<HasilKatalog> _data;

  int _hari = 7;
  double _magMin = 4;
  double? _radius; // km; null = tanpa batas
  bool _urutJarak = false;
  bool _dirasakanSaja = false;

  @override
  void initState() {
    super.initState();
    _radius = widget.lokasiSaya != null ? 500 : null; // bawaan: yang dekat denganmu dulu
    _data = _muat();
  }

  @override
  void dispose() {
    _klien.close();
    super.dispose();
  }

  Future<HasilKatalog> _muat() => (widget.ambil ?? KatalogBmkg(_klien).ambilLengkap)();

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

  String get _ringkasFilter =>
      '$_hari hari · M${_magMin.toStringAsFixed(0)}+${widget.lokasiSaya != null ? ' · ${_radius == null ? 'semua jarak' : '${_radius!.round()} km'}' : ''}'
      ' · ${_urutJarak ? 'terdekat' : 'terbaru'}${_dirasakanSaja ? ' · dirasakan' : ''}';

  Widget _kelompok(String judul, List<Widget> chip) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(judul, style: Theme.of(context).textTheme.labelSmall),
          Wrap(spacing: 8, children: chip),
        ]),
      );

  Widget _filter() {
    ChoiceChip pilih(String label, bool aktif, VoidCallback f) => ChoiceChip(label: Text(label), selected: aktif, onSelected: (_) => setState(f));
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.tune),
        title: const Text('Filter'),
        subtitle: Text(_ringkasFilter),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kelompok('Periode', [
            pilih('7 hari', _hari == 7, () => _hari = 7),
            pilih('30 hari', _hari == 30, () => _hari = 30),
          ]),
          _kelompok('Magnitudo', [
            pilih('M4+', _magMin == 4, () => _magMin = 4),
            pilih('M5+', _magMin == 5, () => _magMin = 5),
          ]),
          if (widget.lokasiSaya != null)
            _kelompok('Jarak dari lokasimu', [
              pilih('100 km', _radius == 100, () => _radius = 100),
              pilih('250 km', _radius == 250, () => _radius = 250),
              pilih('500 km', _radius == 500, () => _radius = 500),
              pilih('Semua', _radius == null, () => _radius = null),
            ]),
          _kelompok('Urutan', [
            pilih('Terbaru', !_urutJarak, () => _urutJarak = false),
            if (widget.lokasiSaya != null) pilih('Terdekat', _urutJarak, () => _urutJarak = true),
          ]),
          _kelompok('Lainnya', [
            FilterChip(
              label: const Text('Hanya yang dirasakan'),
              selected: _dirasakanSaja,
              onSelected: (v) => setState(() => _dirasakanSaja = v),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gempa terkini'),
        actions: [IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh), onPressed: _segarkan)],
      ),
      body: FutureBuilder<HasilKatalog>(
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
          return _isi(context, snap.data!);
        },
      ),
    );
  }

  Widget _isi(BuildContext context, HasilKatalog h) {
    final tema = Theme.of(context);
    final lok = widget.lokasiSaya;
    final sekarang = DateTime.now().toUtc();

    // daftar yang tampil
    final tampil = lok != null
        ? gempaDekat(h.gempa, lok.lat, lok.lon, radiusKm: _radius, hari: _hari, magMin: _magMin, urutJarak: _urutJarak, sekarangUtc: sekarang)
        : [
            for (final g in h.gempa)
              if (g.magnitudo >= _magMin && !g.waktuUtc.isBefore(sekarang.subtract(Duration(days: _hari)))) GempaDekat(g, 0, 0),
          ];
    final daftar = _dirasakanSaja ? tampil.where((d) => d.gempa.dirasakan.isNotEmpty).toList() : tampil;

    // terdekat: pada periode dan magnitudo terpilih (tanpa batas radius agar selalu ada jawaban bila ada data)
    final terdekat = lok == null
        ? null
        : gempaDekat(h.gempa, lok.lat, lok.lon, hari: _hari, magMin: _magMin, urutJarak: true, sekarangUtc: sekarang).firstOrNull;

    return RefreshIndicator(
      onRefresh: _segarkan,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!h.usgsOk)
            _Peringatan('Gempa M4–M5 tidak tersedia karena server USGS tidak terjangkau. Yang tampil hanya data BMKG (M5+ dan dirasakan).'),
          if (!h.bmkgOk) _Peringatan('Server BMKG tidak terjangkau. Yang tampil hanya data USGS (M4+).'),
          if (lok != null)
            Card(
              color: tema.colorScheme.primaryContainer,
              child: ListTile(
                onTap: terdekat == null ? null : () => _detail(terdekat.gempa),
                leading: const Icon(Icons.near_me),
                title: terdekat == null
                    ? Text('Tidak ada gempa M${_magMin.toStringAsFixed(0)}+ dalam $_hari hari terakhir di wilayah ini.')
                    : Text('Terdekat dari lokasimu: M${terdekat.gempa.magnitudo.toStringAsFixed(1)} · ${_jarakArah(terdekat)}'),
                subtitle: terdekat == null
                    ? null
                    : Text('${terdekat.gempa.waktuWib} · ${terdekat.gempa.selang(sekarang)} · ${terdekat.gempa.kedalamanKm.round()} km dalam\n${terdekat.gempa.wilayah}'),
                isThreeLine: terdekat != null,
              ),
            ),
          _filter(),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${daftar.length} gempa', style: tema.textTheme.labelLarge),
          ),
          for (final d in daftar)
            Card(
              child: ListTile(
                onTap: () => _detail(d.gempa),
                leading: CircleAvatar(
                  backgroundColor: _warnaMagnitudo(d.gempa.magnitudo),
                  child: Text(d.gempa.magnitudo.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                title: Text(d.gempa.wilayah, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${d.gempa.waktuWib} · ${d.gempa.selang(sekarang)} · ${d.gempa.kedalamanKm.round()} km'
                    '${lok != null ? '\n${_jarakArah(d)} dari lokasimu' : ''}'
                    '${d.gempa.dirasakan.isNotEmpty ? '\nDirasakan di ${d.gempa.dirasakan.length} daerah (maks MMI ${_rom(d.gempa.mmiDirasakanMaks!)})' : ''}'
                    '${d.gempa.berpotensiTsunami ? '\nBERPOTENSI TSUNAMI' : ''}'
                    '\nSumber: ${d.gempa.sumber}'),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          if (daftar.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Tidak ada gempa pada filter ini. Coba perluas jarak atau periode.'))),
          const SizedBox(height: 8),
          Text(
              'Sumber: BMKG (M5+, dirasakan) dan USGS (M4+). Magnitudo dan lokasi antar-lembaga bisa berbeda sedikit. '
              'Bukan peringatan dini; ikuti informasi resmi BMKG/BPBD.',
              textAlign: TextAlign.center,
              style: tema.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _Peringatan extends StatelessWidget {
  final String teks;
  const _Peringatan(this.teks);

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(teks)),
      );
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
    final ada = g.magnitudoUsgs != null && g.sumber == 'BMKG+USGS';
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
            Text('Sumber: ${g.sumber}', style: tema.textTheme.bodySmall),
            if (ada) Text('USGS mencatat M${g.magnitudoUsgs!.toStringAsFixed(1)} (BMKG M${g.magnitudo.toStringAsFixed(1)}); selisih kecil antar-lembaga wajar.', style: tema.textTheme.bodySmall),
            if (g.mmiUsgs != null) Text('MMI maksimum perkiraan USGS (ShakeMap): ${g.mmiUsgs!.toStringAsFixed(1)}', style: tema.textTheme.bodySmall),
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
