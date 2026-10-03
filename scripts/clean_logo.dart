// Tek bir logonun açık arka planını temizler (uygulamadaki algoritma).
// Kullanım: dart run scripts/clean_logo.dart <girdi> <çıktı.png> <önizleme.png>
// Çıktı: "clean" (temizlendi), "skip" (köşeler açık/opak değil, gerek yok).
import 'dart:io';

import 'package:football_tournament/core/utils/logo_background.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final src = img.decodeImage(bytes);
  if (src == null) {
    print('skip');
    return;
  }
  // Köşelerden en az ikisi opak ve beyaza yakınsa logo beyaz zeminlidir.
  bool lightOpaque(int x, int y) {
    final p = src.getPixel(x, y);
    final dark = [255 - p.r, 255 - p.g, 255 - p.b].reduce((a, b) => a > b ? a : b);
    return p.a > 200 && dark <= 40;
  }

  // Kenardaki ince çizgiler yanıltmasın diye köşelerin biraz içine bakılır.
  final ix = (src.width * 0.04).ceil(), iy = (src.height * 0.04).ceil();
  final w = src.width - 1 - ix, h = src.height - 1 - iy;
  final corners = [
    lightOpaque(ix, iy),
    lightOpaque(w, iy),
    lightOpaque(ix, h),
    lightOpaque(w, h),
  ].where((c) => c).length;
  if (corners < 2) {
    print('skip');
    return;
  }
  final out = removeLogoBackground(bytes);
  if (out == null) {
    print('skip');
    return;
  }
  File(args[1]).writeAsBytesSync(out);
  final im = img.decodePng(out)!;
  final bg = img.Image(width: im.width + 40, height: im.height + 40)
    ..clear(img.ColorRgb8(6, 78, 59));
  img.compositeImage(bg, im, dstX: 20, dstY: 20);
  File(args[2]).writeAsBytesSync(img.encodePng(bg));
  print('clean');
}
