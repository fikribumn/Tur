// Bentuk hasil analisis lokasi, dipakai bersama oleh mesin offline (DIY) dan mesin daring (seluruh Indonesia).
import 'gmpe.dart';

const namaTingkat = ['Sangat rendah', 'Rendah', 'Menengah', 'Tinggi'];

// Kelas resmi Badan Geologi -> tingkat 0-3
const kKrb = {'Sangat Rendah': 0, 'Rendah': 1, 'Menengah': 2, 'Tinggi': 3};
const kLik50 = {
  'Zona Tidak Rentan Likuefaksi': 0,
  'Zona Kerentanan Likuefaksi Rendah': 1,
  'Zona Kerentanan Likuefaksi Sedang': 2,
  'Zona Kerentanan Likuefaksi Tinggi': 3,
};
// 1 = merata/rusak parah, 2 = tidak merata, 3 = jarang terjadi (keterangan resmi)
const kLik100 = {'1': 3, '2': 2, '3': 1};
const kGt = {'Sangat Rendah': 0, 'Rendah': 1, 'Menengah': 2, 'Tinggi': 3};
const kTsunami = {'Rendah': 1, 'Menengah': 2, 'Tinggi': 3};

class HasilLokasi {
  final double lat, lon;

  /// 'offline' (paket DIY di dalam aplikasi) atau 'daring' (server Badan Geologi).
  final String sumber;
  final String? kodeFormasi, formasi, umur, kelasMaterial, namaMaterial, catatanMaterial;

  /// True bila kelas material ditebak dari nama/umur formasi (bukan dari pemetaan kode yang sudah ditinjau).
  final bool materialPerkiraan;
  final double vs30;
  final double? elevasiM, kemiringan;

  /// Sesar aktif terdekat (peta 1:1.000.000) dan jaraknya ke jejak sesar.
  final String? namaSesar, statusSesar;
  final double? jarakSesarKm;
  final Mekanisme mekanisme;
  final int? krbTingkat, likTingkat, gtTingkat, tsunamiTingkat, tingkatKeseluruhan;
  final String? krbKelas, tanahLunak;
  final String likSumber, gtSumber;

  const HasilLokasi({
    required this.lat,
    required this.lon,
    required this.sumber,
    required this.kodeFormasi,
    required this.formasi,
    required this.umur,
    required this.kelasMaterial,
    required this.namaMaterial,
    required this.catatanMaterial,
    required this.materialPerkiraan,
    required this.vs30,
    required this.elevasiM,
    required this.kemiringan,
    required this.namaSesar,
    required this.statusSesar,
    required this.jarakSesarKm,
    required this.mekanisme,
    required this.krbTingkat,
    required this.krbKelas,
    required this.likTingkat,
    required this.likSumber,
    required this.gtTingkat,
    required this.gtSumber,
    required this.tsunamiTingkat,
    required this.tanahLunak,
    required this.tingkatKeseluruhan,
  });

  bool get adaSkenario => jarakSesarKm != null;
  bool get tsunami => tsunamiTingkat != null;

  /// Skenario gempa di sesar terdekat dengan magnitudo [m]; Rjb ~ jarak ke jejak sesar.
  /// Null bila tidak ada sesar terpetakan di sekitar titik.
  GerakTanah? skenario(double m) => jarakSesarKm == null ? null : gerakTanah(m, jarakSesarKm!, vs30, mekanisme);
}
