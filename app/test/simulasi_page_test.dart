// Tes widget: halaman Simulasi dijalankan sungguhan (peta, tombol, slider, lapisan). Butuh internet untuk ubin peta.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_aman_gempa/mesin/gmpe.dart';
import 'package:zona_aman_gempa/mesin/hasil.dart';
import 'package:zona_aman_gempa/simulasi_page.dart';

HasilLokasi contohHasil({double lat = -7.888, double lon = 110.329, int lik = 2, int gt = 2}) => HasilLokasi(
      lat: lat,
      lon: lon,
      sumber: 'daring',
      kodeFormasi: 'Qa',
      formasi: 'Alluvium',
      umur: 'Kuarter',
      kelasMaterial: 'aluvium',
      namaMaterial: 'Aluvium (endapan sungai/dataran)',
      catatanMaterial: 'Sedimen lunak.',
      materialPerkiraan: false,
      vs30: 200,
      elevasiM: 40,
      kemiringan: null,
      namaSesar: 'Patahan Mendatar Menganan Opak',
      statusSesar: 'Aktif',
      jarakSesarKm: 10.2,
      sesarLat: -7.85,
      sesarLon: 110.42,
      mekanisme: Mekanisme.mendatar,
      krbTingkat: 3,
      krbKelas: 'Kawasan Rawan Bencana Gempabumi Tinggi',
      likTingkat: lik,
      likSumber: 'resmi',
      gtTingkat: gt,
      gtSumber: 'resmi',
      tsunamiTingkat: null,
      tanahLunak: null,
      tingkatKeseluruhan: 3,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  Future<void> buka(WidgetTester t, {HasilLokasi? h, Future<HasilLokasi> Function(double, double)? analisis}) async {
    t.view.physicalSize = const Size(1080, 7000); // tinggi agar seluruh isi panel (ListView lazy) ikut dibangun
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: SimulasiPage(lokasi: h ?? contohHasil(), analisis: analisis ?? (la, lo) async => contohHasil(lat: la, lon: lo))));
    await t.pump(const Duration(milliseconds: 600));
  }

  testWidgets('menampilkan dua titik, hasil MMI, dan cincin legenda', (t) async {
    await buka(t);
    expect(find.text('Simulasi gempa'), findsOneWidget);
    expect(find.textContaining('Titikmu berada'), findsOneWidget);
    expect(find.textContaining('MMI '), findsWidgets);
    expect(find.textContaining('PGA'), findsOneWidget);
    expect(find.byIcon(Icons.crisis_alert), findsWidgets); // penanda sumber
    expect(find.byIcon(Icons.location_on), findsWidgets); // penanda titikku
    expect(tester(t), isNull);
  });

  testWidgets('kedalaman > 30 km: model tidak berlaku, angka tidak ditampilkan', (t) async {
    await buka(t);
    final slider = find.byKey(const Key('slider-kedalaman'));
    await t.drag(slider, const Offset(900, 0)); // geser ke kedalaman maksimum
    await t.pump();
    expect(find.textContaining('melebihi 30 km'), findsOneWidget);
    expect(find.textContaining('PGA'), findsNothing);
    expect(tester(t), isNull);
  });

  testWidgets('magnitudo dan mekanisme mengubah hasil tanpa error', (t) async {
    await buka(t);
    final awal = (t.widget<Text>(find.textContaining('MMI ').first)).data;
    final slider = find.byKey(const Key('slider-magnitudo'));
    await t.drag(slider, const Offset(600, 0));
    await t.pump();
    await t.tap(find.text('naik'));
    await t.pump();
    final akhir = (t.widget<Text>(find.textContaining('MMI ').first)).data;
    expect(awal != null && akhir != null, isTrue);
    expect(tester(t), isNull);
  });

  testWidgets('tombol taruh di sesar terdekat dan lapisan zonasi bisa dinyalakan', (t) async {
    await buka(t);
    final tombol = find.textContaining('Taruh di sesar terdekat');
    await t.tap(tombol);
    await t.pump(const Duration(milliseconds: 300));
    final chip = find.widgetWithText(FilterChip, 'Gerakan tanah');
    await t.tap(chip);
    await t.pump(const Duration(milliseconds: 600));
    expect(t.widget<FilterChip>(chip).selected, isTrue);
    expect(tester(t), isNull);
  });

  testWidgets('mode atur titikku memicu analisis ulang', (t) async {
    var dipanggil = 0;
    await buka(t, analisis: (la, lo) async {
      dipanggil++;
      return contohHasil(lat: la, lon: lo);
    });
    await t.tap(find.text('Atur titikku'));
    await t.pump();
    await t.tapAt(const Offset(200, 300)); // ketuk di area peta (di bawah tombol mode)
    await t.pump(const Duration(milliseconds: 500));
    expect(dipanggil, 1);
    expect(tester(t), isNull);
  });
}

Object? tester(WidgetTester t) => t.takeException();
