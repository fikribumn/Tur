import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'mesin/daring.dart';
import 'mesin/hasil.dart';
import 'mesin/kerentanan.dart';
import 'peta_page.dart';
import 'simulasi_page.dart';

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

/// Kota-kota di seluruh Indonesia sebagai alternatif bila GPS tidak dipakai.
const _kota = {
  'Banda Aceh': (5.548, 95.323),
  'Medan': (3.595, 98.672),
  'Padang': (-0.949, 100.354),
  'Jakarta': (-6.209, 106.845),
  'Bandung': (-6.917, 107.619),
  'Semarang': (-6.966, 110.417),
  'Yogyakarta': (-7.793, 110.366),
  'Surabaya': (-7.257, 112.752),
  'Denpasar': (-8.670, 115.217),
  'Mataram': (-8.583, 116.117),
  'Kupang': (-10.178, 123.607),
  'Pontianak': (-0.027, 109.334),
  'Balikpapan': (-1.269, 116.832),
  'Makassar': (-5.147, 119.413),
  'Palu': (-0.895, 119.870),
  'Manado': (1.474, 124.842),
  'Ambon': (-3.696, 128.178),
  'Jayapura': (-2.533, 140.718),
};

const _warna = [Color(0xFF2E9E6B), Color(0xFFD9A21B), Color(0xFFE8702A), Color(0xFFD23B3B)];
const _romawi = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];
String _rom(double m) => _romawi[m.round().clamp(1, 10)];
Color _w(int? t) => t == null ? Colors.grey : _warna[t];
String _n(int? t) => t == null ? 'Belum ada data' : namaTingkat[t];

enum _Fase { mencariLokasi, menganalisis, siap, galat }

class BerandaPage extends StatefulWidget {
  const BerandaPage({super.key});

  @override
  State<BerandaPage> createState() => _BerandaPageState();
}

class _BerandaPageState extends State<BerandaPage> {
  final _klien = http.Client();
  MesinDaring? _daring;
  MesinKerentanan? _offline;

  _Fase _fase = _Fase.mencariLokasi;
  String _pesan = '';
  String _label = '';
  double? _akurasiM;
  String? _kotaDipilih; // nama kota, atau null
  bool _dariPeta = false; // true bila titik dipilih di peta/pencarian
  HasilLokasi? _hasil;
  double _magnitudo = 6.3;

  @override
  void initState() {
    super.initState();
    _pakaiLokasiHp();
  }

  @override
  void dispose() {
    _klien.close();
    super.dispose();
  }

  Future<MesinDaring> _mesinDaring() async {
    if (_daring != null) return _daring!;
    final lito = jsonDecode(await rootBundle.loadString('assets/data/litologi_dampak.json')) as Map<String, dynamic>;
    return _daring = MesinDaring(
        _klien, Map<String, dynamic>.from(lito['kelas'] as Map), Map<String, dynamic>.from(lito['pemetaan_simobj'] as Map));
  }

  Future<void> _pakaiLokasiHp() async {
    setState(() {
      _kotaDipilih = null;
      _dariPeta = false;
      _fase = _Fase.mencariLokasi;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _galat('GPS mati. Nyalakan lokasi di HP, atau pilih kota di bawah.');
      }
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) izin = await Geolocator.requestPermission();
      if (izin == LocationPermission.denied || izin == LocationPermission.deniedForever) {
        return _galat('Izin lokasi ditolak. Izinkan lokasi untuk TERRA TUR di pengaturan, atau pilih kota di bawah.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
      );
      _akurasiM = p.accuracy;
      await _analisis(p.latitude, p.longitude, 'Lokasi HP');
    } catch (e) {
      _galat('Gagal mendapatkan lokasi HP ($e). Coba lagi atau pilih kota di bawah.');
    }
  }

  Future<void> _pakaiKota(String nama) async {
    final (lat, lon) = _kota[nama]!;
    setState(() {
      _kotaDipilih = nama;
      _dariPeta = false;
      _akurasiM = null;
    });
    await _analisis(lat, lon, nama);
  }

  Future<void> _pilihDiPeta() async {
    final awalLat = _hasil?.lat ?? -2.5, awalLon = _hasil?.lon ?? 118.0; // tengah Indonesia bila belum ada lokasi
    final p = await Navigator.of(context).push<LokasiPilihan>(
      MaterialPageRoute(builder: (_) => PetaPage(awalLat: awalLat, awalLon: awalLon)),
    );
    if (p == null || !mounted) return;
    setState(() {
      _kotaDipilih = null;
      _dariPeta = true;
      _akurasiM = null;
    });
    await _analisis(p.lat, p.lon, p.label);
  }

  /// Analisis satu titik (server Badan Geologi; paket offline bila tanpa internet dan titik ada di DIY).
  Future<HasilLokasi> _hitung(double lat, double lon) async {
    try {
      return await (await _mesinDaring()).analisis(lat, lon);
    } on GalatJaringan {
      if (MesinKerentanan.dalamCakupan(lat, lon)) {
        _offline ??= await MesinKerentanan.muat();
        return _offline!.analisis(lat, lon);
      }
      rethrow;
    }
  }

  void _bukaSimulasi() {
    final h = _hasil;
    if (h == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SimulasiPage(lokasi: h, analisis: _hitung)));
  }

  Future<void> _analisis(double lat, double lon, String label) async {
    if (!mounted) return;
    setState(() {
      _fase = _Fase.menganalisis;
      _label = label;
    });
    HasilLokasi? hasil;
    String? catatan;
    try {
      hasil = await (await _mesinDaring()).analisis(lat, lon);
    } on GalatJaringan catch (e) {
      // Cadangan: paket offline hanya mencakup DIY
      if (MesinKerentanan.dalamCakupan(lat, lon)) {
        _offline ??= await MesinKerentanan.muat();
        hasil = _offline!.analisis(lat, lon);
        catatan = 'Tanpa internet: memakai paket offline DIY.';
      } else {
        return _galat('${e.pesan}\nPaket offline saat ini hanya mencakup DIY.');
      }
    } catch (e) {
      return _galat('Terjadi kesalahan saat menganalisis: $e');
    }
    if (!mounted) return;
    setState(() {
      _hasil = hasil;
      _pesan = catatan ?? '';
      _fase = _Fase.siap;
    });
  }

  void _galat(String pesan) {
    if (!mounted) return;
    setState(() {
      _pesan = pesan;
      _fase = _Fase.galat;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TERRA TUR'),
        actions: [
          IconButton(
            tooltip: 'Simulasi gempa',
            icon: const Icon(Icons.crisis_alert),
            onPressed: _hasil == null ? null : _bukaSimulasi,
          ),
          IconButton(tooltip: 'Pilih di peta', icon: const Icon(Icons.map_outlined), onPressed: _pilihDiPeta),
          IconButton(
            tooltip: 'Pakai lokasi HP',
            icon: const Icon(Icons.my_location),
            onPressed: _pakaiLokasiHp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.my_location, size: 16),
                    label: const Text('Lokasi HP'),
                    selected: _kotaDipilih == null && !_dariPeta,
                    onSelected: (_) => _pakaiLokasiHp(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Pilih di peta'),
                    backgroundColor: _dariPeta ? Theme.of(context).colorScheme.primaryContainer : null,
                    onPressed: _pilihDiPeta,
                  ),
                ),
                for (final k in _kota.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(k), selected: k == _kotaDipilih, onSelected: (_) => _pakaiKota(k)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._badan(context),
        ],
      ),
    );
  }

  List<Widget> _badan(BuildContext context) {
    switch (_fase) {
      case _Fase.mencariLokasi:
        return const [_Memuat('Mencari lokasi HP...')];
      case _Fase.menganalisis:
        return [_Memuat('Menganalisis $_label dari data Badan Geologi...')];
      case _Fase.galat:
        return [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(padding: const EdgeInsets.all(16), child: Text(_pesan)),
          ),
        ];
      case _Fase.siap:
        return _tampilHasil(context, _hasil!);
    }
  }

  List<Widget> _tampilHasil(BuildContext context, HasilLokasi h) {
    final gt = h.skenario(_magnitudo);
    // Status murni dari zonasi resmi. Skenario sesar terdekat TIDAK menurunkannya: sumber gempa lain
    // (mis. subduksi) tidak dimodelkan, sehingga skenario bisa jauh lebih kecil daripada bahaya sebenarnya.
    final lv = h.tingkatKeseluruhan ?? 1;
    final kecil = Theme.of(context).textTheme.bodySmall;

    return [
      Card(
        child: ListTile(
          leading: Icon(_dariPeta ? Icons.place : (_kotaDipilih == null ? Icons.my_location : Icons.location_city)),
          title: Text(_label),
          subtitle: Text(
              '${h.lat.toStringAsFixed(4)}, ${h.lon.toStringAsFixed(4)}${_akurasiM != null ? ' · akurasi ±${_akurasiM!.round()} m' : ''}\n'
              'Data: ${h.sumber == 'daring' ? 'server Badan Geologi' : 'paket offline DIY'}'),
          isThreeLine: true,
        ),
      ),
      if (_pesan.isNotEmpty)
        Card(color: Theme.of(context).colorScheme.tertiaryContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_pesan))),
      const SizedBox(height: 4),
      _KartuStatus(level: lv, mmi: gt?.mmi, formasi: h.formasi, umur: h.umur),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.crisis_alert, color: Color(0xFFD23B3B)),
          title: const Text('Simulasi gempa', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Taruh sumber gempa di peta dan lihat dampaknya ke titikmu'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _bukaSimulasi,
        ),
      ),
      const SizedBox(height: 12),
      if (gt != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Skenario: gempa di ${h.namaSesar} (${h.mekanisme.label}), ${h.jarakSesarKm!.toStringAsFixed(1)} km, '
                    'magnitudo ${_magnitudo.toStringAsFixed(1)}',
                    style: kecil),
                Slider(
                  min: 5.0,
                  max: 7.5,
                  divisions: 25,
                  value: _magnitudo,
                  label: _magnitudo.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _magnitudo = v),
                ),
                if (h.jarakSesarKm! > 30)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                        'Sesar terdekat yang terpetakan cukup jauh. Gempa dari sumber lain (mis. zona subduksi) bisa '
                        'jauh lebih kuat; itu tidak dimodelkan di sini. Pegang zonasi resmi.',
                        style: kecil?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Letak sesar dari peta 1:1.000.000 (kasar, bisa meleset beberapa km). Status sesar: ${h.statusSesar}.',
                      style: kecil),
                ),
              ],
            ),
          ),
        )
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
                'Tidak ada sesar aktif terpetakan dalam $radiusSesarKm km, jadi skenario guncangan tidak tersedia. '
                'Zonasi resmi di bawah tetap berlaku. Gempa subduksi/megathrust tidak dimodelkan di aplikasi ini.',
                style: kecil),
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
                if (gt != null)
                  'Skenario M${_magnitudo.toStringAsFixed(1)} di ${h.namaSesar}: sekitar ${_rom(gt.mmi)} MMI '
                      '(jarak ${h.jarakSesarKm!.toStringAsFixed(1)} km, Vs30 ~${h.vs30.round()} m/s).',
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
            if (h.tsunamiTingkat != null)
              _Topik(
                judul: 'Tsunami',
                nilai: 'Zona ${_n(h.tsunamiTingkat)}',
                tingkat: h.tsunamiTingkat,
                isi: const [
                  'Titik ini berada dalam kawasan rawan tsunami resmi. Bila guncangan kuat dan lama, segera ke tempat tinggi.'
                ],
              )
            else if ((h.elevasiM ?? 99) < 15)
              _Topik(
                judul: 'Tsunami',
                nilai: 'Belum terpetakan',
                tingkat: null,
                isi: [
                  'Lokasi pesisir rendah (${h.elevasiM?.round() ?? '?'} m). Data kawasan rawan tsunami resmi belum mencakup titik ini. '
                      'Belum terpetakan bukan berarti aman.'
                ],
              ),
            _Topik(
              judul: 'Jenis tanah di sini',
              nilai: h.formasi ?? '-',
              tingkat: null,
              isi: [
                h.catatanMaterial ?? 'Belum ada keterangan.',
                '${h.namaMaterial ?? ''}${h.tanahLunak != null ? ' · tanah lunak terpetakan: ${h.tanahLunak}' : ''}',
                if (h.materialPerkiraan)
                  'Kelas material ditebak dari nama dan umur formasi, belum ditinjau ahli geologi. Anggap perkiraan kasar.',
              ],
            ),
            _Topik(
              judul: 'Detail teknis',
              nilai: 'untuk yang penasaran',
              tingkat: null,
              isi: [
                'Vs30 ~ ${h.vs30.round()} m/s'
                    '${h.elevasiM != null ? ' · elevasi ${h.elevasiM!.round()} m' : ''}'
                    '${h.kemiringan != null ? ' · lereng ${(h.kemiringan! * 100).toStringAsFixed(1)}%' : ''}',
                'Kode formasi: ${h.kodeFormasi ?? '-'}'
                    '${gt != null ? ' · PGA ${gt.pgaG.toStringAsFixed(2)} g · PGV ${gt.pgvCms.round()} cm/s' : ''}',
                if (h.namaSesar != null)
                  'Sesar terdekat: ${h.namaSesar} (${h.statusSesar}), peta 1:1.000.000.',
                'Zonasi: Badan Geologi (Geoportal ESDM). MMI skenario: BSSA14 + Worden 2012 untuk gempa kerak dangkal, '
                    'median tanpa kalibrasi lokal.',
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _KartuTindakan(h: h),
      const SizedBox(height: 12),
      Text('Bukan alat keselamatan resmi. Ikuti arahan BMKG/BPBD.',
          textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
    ];
  }
}

class _Memuat extends StatelessWidget {
  final String teks;
  const _Memuat(this.teks);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(teks, textAlign: TextAlign.center)]),
      );
}

class _KartuStatus extends StatelessWidget {
  final int level;
  final double? mmi;
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
            Text(mmi != null
                ? 'Zonasi resmi Badan Geologi. Skenario di sesar terdekat: sekitar ${_rom(mmi!)} MMI.'
                : 'Berdasarkan zonasi resmi Badan Geologi.'),
            if (formasi != null) Text('$formasi (${umur ?? ''})', style: Theme.of(context).textTheme.bodySmall),
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
    if (h.tsunami || (h.elevasiM ?? 99) < 15) {
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
            Text('Apa yang harus dilakukan', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700)),
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
