# TERRA TUR

Aplikasi untuk melihat **kerentanan geologi lokasimu saat gempa**: seberapa kuat guncangan diperkuat oleh jenis tanah,
dan apakah ada bahaya turunan seperti likuefaksi dan longsor. Prototipe saat ini mencakup **Daerah Istimewa Yogyakarta**.

> **Bukan alat keselamatan resmi.** Ini prototipe riset. Selalu ikuti arahan BMKG dan BPBD.

## Cara kerja

1. **Zonasi resmi Badan Geologi** (Geoportal ESDM): peta geologi 1:100.000, KRB Gempa Bumi 1:50.000, kerentanan likuefaksi,
   zona gerakan tanah 1:50.000, KRB tsunami, dan Sesar Opak.
2. **Kelas material -> Vs30** (digabung proxy kemiringan dari SRTM, Wald & Allen 2007).
3. **Skenario gempa di Sesar Opak:** BSSA14 (PGA/PGV) lalu konversi ke MMI (Worden dkk. 2012).
4. UI berupa kartu ringkas yang bisa dibuka satu per satu (progressive disclosure).

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

- Peta geologi 1:100.000 kasar di graben Bantul; zonasi KRB 1:50.000 dipakai sebagai penentu utama.
- BSSA14 tanpa suku cekungan sedimen: MMI skenario di Bantul lebih rendah daripada kejadian 2006.
- Koefisien konversi Worden 2012 belum diverifikasi terhadap makalah aslinya.
- Skor kerentanan per kelas material (`data/litologi_dampak.json`) adalah penilaian awal, belum divalidasi data bor/mikrozonasi.
- Ketentuan lisensi data Badan Geologi belum dikonfirmasi. Periksa sebelum penggunaan publik atau komersial.

## Sumber

- Badan Geologi, ESDM: https://geoportal.esdm.go.id
- Boore, Stewart, Seyhan, Atkinson (2014), BSSA14. Koefisien dari OpenQuake (gem/oq-engine).
- Worden, Gerstenberger, Rhoades, Wald (2012), BSSA 102(1).
- Wald & Allen (2007), Vs30 dari kemiringan topografi.
- SRTM via AWS Terrain Tiles.
