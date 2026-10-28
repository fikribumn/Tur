// Pengaturan peta yang dipakai bersama halaman Pilih lokasi dan Simulasi.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Gestur yang tidak "liar": rotasi dimatikan (cubit dua jari tidak lagi memutar peta), zoom dan geser berlomba
/// sehingga hanya satu yang menang per gestur, dan ambangnya dinaikkan agar goyangan kecil jari diabaikan.
const opsiInteraksi = InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
  enableMultiFingerGestureRace: true,
  pinchZoomThreshold: 0.8,
  pinchMoveThreshold: 60,
);

const zoomMin = 4.0, zoomMaks = 15.0;

/// Tombol +/- sebagai alternatif cubit.
class TombolZoom extends StatelessWidget {
  final MapController kontrol;
  const TombolZoom({super.key, required this.kontrol});

  void _ubah(double delta) {
    final c = kontrol.camera;
    kontrol.move(c.center, (c.zoom + delta).clamp(zoomMin, zoomMaks));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(heroTag: null, tooltip: 'Perbesar', onPressed: () => _ubah(1), child: const Icon(Icons.add)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: null, tooltip: 'Perkecil', onPressed: () => _ubah(-1), child: const Icon(Icons.remove)),
      ],
    );
  }
}
