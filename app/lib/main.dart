import 'package:flutter/material.dart';

import 'mesin/kerentanan.dart';

void main() => runApp(const ZonaAmanApp());

class ZonaAmanApp extends StatelessWidget {
  const ZonaAmanApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData tema(Brightness b) => ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F5FD0), brightness: b),
        );
    return MaterialApp(
      title: 'TERRA TUR',
      theme: tema(Brightness.light),
      darkTheme: tema(Brightness.dark),
      home: const BerandaPage(),
    );
  }
}

const _tempat = {
  'Malioboro': (-7.793, 110.366),
  'Bantul kota': (-7.888, 110.329),
  'Parangtritis': (-8.025, 110.332),
  'Imogiri': (-7.930, 110.390),
  'Prambanan': (-7.752, 110.491),
  'Sleman': (-7.716, 110.355),
  'Kaliurang': (-7.600, 110.427),
  'Wates': (-7.862, 110.158),
  'Wonosari': (-7.965, 110.600),
};

const _warna = [Color(0xFF2E9E6B), Color(0xFFD9A21B), Color(0xFFE8702A), Color(0xFFD23B3B)];
const _romawi = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
String _rom(double m) => _romawi[m.round().clamp(1, 10)];
Color _w(int? t) => t == null ? Colors.grey : _warna[t];
String _n(int? t) => t == null ? 'Belum ada data' : namaTingkat[t];

class BerandaPage extends StatefulWidget {
  const BerandaPage({super.key});

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  MesinKerentanan? _mesin;
  String? _galat;
  String _tempatDipilih = 'Bantul kota';
  double _magnitudo = 6.3;

  @override
  void initState() {
    super.initState();
    MesinKerentanan.muat().then((m) {
      if (mounted) setState(() => _mesin = m);
    }).catchError((Object e) {
      if (mounted) setState(() => _galat = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final mesin = _mesin;
    return Scaffold(
      appBar: AppBar(title: const Text('TERRA TUR')),
      body: _galat != null
          ? Center(child: Text('Gagal memuat data: $_galat'))
          : mesin == null
              ? const Center(child: CircularProgressIndicator())
              : _isi(context, mesin),
    );
  }

  Widget _isi(BuildContext context, MesinKerentanan mesin) {
    final (lat, lon) = _tempat[_tempatDipilih]!;
    final h = mesin.analisis(lat, lon);
    final gt = h.skenario(_magnitudo);
    final batas = gt.mmi < 6 ? 1 : (gt.mmi < 7 ? 2 : 3);
    final lv = (h.tingkatKeseluruhan ?? 1) < batas ? (h.tingkatKeseluruhan ?? 1) : batas;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final k in _tempat.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(k),
                    selected: k == _tempatDipilih,
                    onSelected: (_) => setState(() => _tempatDipilih = k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _KartuStatus(level: lv, mmi: gt.mmi, formasi: h.formasi, umur: h.umur),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Skenario: gempa di Sesar Opak, magnitudo ${_magnitudo.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.bodySmall),
                Slider(
                  min: 5.0,
                  max: 7.5,
                  divisions: 25,
                  value: _magnitudo,
                  label: _magnitudo.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _magnitudo = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _Topik(
                judul: 'Guncangan',
                nilai: h.krbKelas == null ? 'Belum ada data' : 'Zona ${_n(h.krbTingkat)}',
                tingkat: h.krbTingkat,
                isi: [
                  'Zonasi resmi: ${h.krbKelas?.replaceFirst('Kawasan Rawan Bencana ', '') ?? 'belum ada data'}.',
                  'Skenario M${_magnitudo.toStringAsFixed(1)}: sekitar ${_rom(gt.mmi)} MMI '
                      '(jarak ke Sesar Opak ${h.jarakOpakKm.toStringAsFixed(1)} km, Vs30 ~${h.vs30.round()} m/s).',
                  'Tanah lunak memperbesar dan memperpanjang guncangan dibanding batuan keras.',
                ],
              ),
              _Topik(
                judul: 'Likuefaksi',
                nilai: _n(h.likTingkat),
                tingkat: h.likTingkat,
                isi: [
                  (h.likTingkat ?? 0) >= 2
                      ? 'Pasir lepas jenuh air bisa berubah seperti cairan saat diguncang kuat. '
                          'Tanah dapat amblas, bergeser, atau menyemburkan pasir.'
                      : 'Material di sini kecil kemungkinannya mengalami likuefaksi.',
                  'Sumber: ${h.likSumber}.',
                ],
              ),
              _Topik(
                judul: 'Gerakan tanah / longsor',
                nilai: _n(h.gtTingkat),
                tingkat: h.gtTingkat,
                isi: [
                  (h.gtTingkat ?? 0) >= 2
                      ? 'Lereng di sekitar sini bisa bergerak saat gempa, terutama setelah hujan.'
                      : 'Kemungkinan gerakan tanah di sekitar sini kecil.',
                  'Sumber: ${h.gtSumber}.',
                ],
              ),
              _Topik(
                judul: 'Jenis tanah di sini',
                nilai: h.formasi ?? '-',
                tingkat: null,
                isi: [
                  h.catatanMaterial ?? 'Belum ada keterangan.',
                  '${h.namaMaterial ?? ''}${h.tanahLunak != null ? ' · tanah lunak terpetakan: ${h.tanahLunak}' : ''}',
                ],
              ),
              if (h.tsunami)
                const _Topik(
                  judul: 'Tsunami',
                  nilai: 'Masuk zona rawan',
                  tingkat: 3,
                  isi: ['Titik ini berada dalam kawasan rawan tsunami resmi. Bila guncangan kuat dan lama, segera ke tempat tinggi.'],
                )
              else if (h.elevasiM < 15)
                _Topik(
                  judul: 'Tsunami',
                  nilai: 'Belum terpetakan',
                  tingkat: null,
                  isi: [
                    'Lokasi pesisir rendah (${h.elevasiM.round()} m). Data kawasan rawan tsunami resmi belum mencakup titik ini. '
                        'Belum terpetakan bukan berarti aman.'
                  ],
                ),
              _Topik(
                judul: 'Detail teknis',
                nilai: 'untuk yang penasaran',
                tingkat: null,
                isi: [
                  'Vs30 ~ ${h.vs30.round()} m/s · elevasi ${h.elevasiM.round()} m · lereng ${(h.kemiringan * 100).toStringAsFixed(1)}%',
                  'Kode formasi: ${h.kodeFormasi ?? '-'} · PGA ${gt.pgaG.toStringAsFixed(2)} g · PGV ${gt.pgvCms.round()} cm/s',
                  'Zonasi: Badan Geologi (Geoportal ESDM). MMI skenario: BSSA14 + Worden 2012, median tanpa kalibrasi lokal.',
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _KartuTindakan(h: h),
        const SizedBox(height: 12),
        Text(
          'Bukan alat keselamatan resmi. Ikuti arahan BMKG/BPBD.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _KartuStatus extends StatelessWidget {
  final int level;
  final double mmi;
  final String? formasi, umur;
  const _KartuStatus({required this.level, required this.mmi, this.formasi, this.umur});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: _warna[level], width: 8))),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kerawanan ${namaTingkat[level]}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _warna[level], fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Di skenario ini guncangan sekitar ${_rom(mmi)} MMI.'),
            if (formasi != null)
              Text('$formasi (${umur ?? ''})', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Topik extends StatelessWidget {
  final String judul, nilai;
  final int? tingkat;
  final List<String> isi;
  const _Topik({required this.judul, required this.nilai, required this.tingkat, required this.isi});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: CircleAvatar(radius: 6, backgroundColor: _w(tingkat)),
      title: Text(judul, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(nilai, textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall),
        ),
        const Icon(Icons.chevron_right),
      ]),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final s in isi) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(s))],
    );
  }
}

class _KartuTindakan extends StatelessWidget {
  final HasilLokasi h;
  const _KartuTindakan({required this.h});

  @override
  Widget build(BuildContext context) {
    final tips = <String>['Lindungi kepala, jauhi kaca dan benda jatuh.'];
    if ((h.likTingkat ?? 0) >= 2) tips.add('Setelah guncangan, menjauh dari tanah yang retak atau berair.');
    if ((h.gtTingkat ?? 0) >= 2) tips.add('Jauhi lereng dan tebing, waspada longsor susulan.');
    if (h.tsunami || h.elevasiM < 15) {
      tips.add('Di pesisir: bila guncangan kuat atau lama, segera ke tempat tinggi tanpa menunggu peringatan.');
    }
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primary,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Apa yang harus dilakukan',
                style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final t in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $t', style: TextStyle(color: cs.onPrimary)),
              ),
          ],
        ),
      ),
    );
  }
}
