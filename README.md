# TERRA TUR

Aplikasi untuk melihat **kerentanan geologi lokasimu saat gempa**: seberapa kuat guncangan diperkuat oleh jenis tanah,
dan apakah ada bahaya turunan seperti likuefaksi dan longsor. Lokasi mengikuti **GPS HP** dan mencakup **seluruh Indonesia** (data dari server Badan Geologi), dengan paket offline cadangan untuk **DIY**.

> **Bukan alat keselamatan resmi.** Ini prototipe riset. Selalu ikuti arahan BMKG dan BPBD.

## Cara kerja

1. **Zonasi resmi Badan Geologi** (Geoportal ESDM): peta geologi 1:100.000, KRB Gempa Bumi 1:50.000, kerentanan likuefaksi,
   zona gerakan tanah 1:50.000, KRB tsunami, dan Sesar Opak.
2. **Kelas material -> Vs30** (digabung proxy kemiringan dari SRTM, Wald & Allen 2007).
3. **Skenario gempa di sesar aktif terdekat** (peta sesar 1:1.000.000; mekanisme mendatar/naik/normal dibaca dari nama sesar): BSSA14 (PGA/PGV) lalu konversi ke MMI (Worden dkk. 2012). Status kerawanan ditentukan **hanya oleh zonasi resmi**, tidak oleh skenario.
4. **Simulasi gempa:** taruh sumber gempa dan titikmu di peta, atur magnitudo, kedalaman, arah sesar, dan mekanisme. Gempa dimodelkan sebagai **retakan memanjang** (panjang dari magnitudo, Wells & Coppersmith 1994) dan area terdampak digambar sebagai **peta guncangan per titik**: tiap sel dihitung dari jarak ke retakan dan Vs30 setempat dari peta geologi resmi, jadi bentuknya mengikuti arah sesar dan jenis tanah (tanah lunak menguat, batuan keras melemah). Sumber lebih dalam dari 30 km sengaja tidak dihitung (model hanya kerak dangkal). Lapisan zonasi resmi Badan Geologi bisa dinyalakan di atas peta.
5. **Gempa terkini BMKG:** katalog gempa nyata (data.bmkg.go.id: terbaru, M5+ terkini, dirasakan). Satu gempa bisa langsung disimulasikan (episentrum, magnitudo, kedalaman asli), dan hasil model **dibandingkan dengan laporan MMI "dirasakan" BMKG** per kabupaten/kota (koordinat daerah dicari lewat Nominatim, titik di pusat daerah).
6. UI berupa kartu ringkas yang bisa dibuka satu per satu (progressive disclosure).

## Struktur

| Folder | Isi |
|---|---|
| `prototype/` | Pipeline Python: unduh data resmi, mesin kerentanan, GMPE, pengemas data offline |
| `data/` | Layer resmi (`data/resmi`), tabel material (`litologi_dampak.json`), hasil contoh |
| `ui/` | Mockup HTML interaktif (buka `ui/index.html`) |
| `app/` | Aplikasi Flutter (offline, Android) |

## Menjalankan

```
python -I prototype/ambil_data_resmi.py   # unduh layer Badan Geologi
python -I prototype/kerentanan.py         # hitung hasil contoh dan buat ui/data.js
python -I prototype/paket_offline.py      # kemas data untuk aplikasi
cd app && flutter test && flutter build apk --release
```

Berkas SRTM (`data/srtm/`) diunduh terpisah dari AWS Terrain Tiles (`S08E110`, `S09E110`) dan tidak ikut di repo.

## Keterbatasan yang perlu diketahui

- **Gempa subduksi/megathrust tidak dimodelkan** (BSSA14 hanya untuk kerak dangkal). Di kota seperti Padang, sesar terdekat bisa puluhan km sehingga skenario jauh lebih kecil daripada bahaya sebenarnya; pegang zonasi resmi.
- Di luar DIY, kelas material **ditebak dari nama dan umur formasi** (ditandai di aplikasi). Kode formasi peta dipakai ulang antar lembar, jadi pemetaan kode hanya dipakai di DIY.
- Peta guncangan dibatasi radius 250 km dari sumber (M7,5+ sebenarnya meluas lebih jauh), retakan dianggap lurus dan vertikal-proyeksi tanpa efek dip/hanging wall/directivity, dan batas antar-formasi tampak tegas karena tiap kelas tanah punya satu nilai Vs30.
- Celah kecil di dalam daratan tanpa data geologi diisi dengan nilai tetangga terdekat; laut dikosongkan.
- Peta memakai ubin OpenStreetMap dan pencarian Nominatim (sesuai kebijakan pemakaian mereka); untuk pemakaian luas perlu penyedia ubin sendiri.
- Perbandingan dengan laporan BMKG: laporan bersifat subjektif per kabupaten/kota, koordinat daerah hanyalah pusat daerah (perkiraan), dan baru diuji pada satu kejadian lemah (M5,4, MMI II); belum bukti akurasi untuk guncangan kuat. Mekanisme dan arah sesar gempa nyata hanya diperkirakan bila sesar terpetakan dalam 50 km.
- Gempa dalam (>30 km) dari katalog hanya ditampilkan lokasinya; guncangannya tidak dihitung.
- Mode daring butuh internet; tanpa internet hanya DIY yang bisa dianalisis.
- Cakupan layer tidak merata: geologi, KRB gempa, dan gerakan tanah ada di seluruh Indonesia; likuefaksi parsial; tsunami dan tanah lunak jarang. "Belum terpetakan" bukan berarti aman.
- Peta geologi 1:100.000 kasar di graben Bantul; zonasi KRB 1:50.000 dipakai sebagai penentu utama.
- BSSA14 tanpa suku cekungan sedimen: MMI skenario di Bantul lebih rendah daripada kejadian 2006.
- Koefisien konversi Worden 2012 belum diverifikasi terhadap makalah aslinya.
- Skor kerentanan per kelas material (`data/litologi_dampak.json`) adalah penilaian awal, belum divalidasi data bor/mikrozonasi.
- Ketentuan lisensi data Badan Geologi belum dikonfirmasi. Periksa sebelum penggunaan publik atau komersial.

## Sumber

- Katalog gempa: BMKG, https://data.bmkg.go.id (DataMKG/TEWS).
- Pencarian nama tempat: Nominatim, OpenStreetMap (dipakai sesuai kebijakan: 1 permintaan per detik, identitas aplikasi, hasil di-cache).
- Badan Geologi, ESDM: https://geoportal.esdm.go.id
- Boore, Stewart, Seyhan, Atkinson (2014), BSSA14. Koefisien dari OpenQuake (gem/oq-engine).
- Worden, Gerstenberger, Rhoades, Wald (2012), BSSA 102(1).
- Wald & Allen (2007), Vs30 dari kemiringan topografi.
- SRTM via AWS Terrain Tiles.
