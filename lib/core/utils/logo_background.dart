import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Beyaza uzaklık bundan küçükse kesin arka plan.
const _hard = 40;

/// [_hard] ile bu değer arası, arka plana komşu kenarlarda kısmi şeffaflık.
const _soft = 110;

/// Logolar en fazla bu kenar uzunluğunda saklanır.
const _maxSide = 512;

/// Logonun kenarlarındaki beyaz/açık arka planı şeffaf yapar ve PNG döner.
///
/// Kenardan başlayan dolgu yalnızca kenara bağlı açık pikselleri siler;
/// logonun içindeki beyazlar korunur. Silinecek arka plan yoksa (zaten
/// şeffaf ya da koyu zeminli logo) `null` döner, resim olduğu gibi yüklenir.
/// Ağır iş; `compute` ile ayrı isolate'te çağrılmalı.
Uint8List? removeLogoBackground(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var src = decoded.convert(numChannels: 4);
  if (math.max(src.width, src.height) > _maxSide * 2) {
    src = src.width >= src.height
        ? img.copyResize(src, width: _maxSide * 2)
        : img.copyResize(src, height: _maxSide * 2);
  }
  src = _trimEdgeStripes(src);
  final w = src.width, h = src.height;

  int dist(img.Pixel p) {
    // Zaten şeffaf piksel arka plan sayılır.
    if (p.a < 128) return 0;
    return math.max(
      255 - p.r.toInt(),
      math.max(255 - p.g.toInt(), 255 - p.b.toInt()),
    );
  }

  final bg = Uint8List(w * h);
  final queue = Queue<int>();
  void seed(int x, int y) => queue.add(y * w + x);
  for (var x = 0; x < w; x++) {
    seed(x, 0);
    seed(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    seed(0, y);
    seed(w - 1, y);
  }
  var removed = 0;
  while (queue.isNotEmpty) {
    final i = queue.removeFirst();
    if (bg[i] == 1) continue;
    final x = i % w, y = i ~/ w;
    if (dist(src.getPixel(x, y)) > _hard) continue;
    bg[i] = 1;
    removed++;
    if (x > 0) queue.add(i - 1);
    if (x < w - 1) queue.add(i + 1);
    if (y > 0) queue.add(i - w);
    if (y < h - 1) queue.add(i + w);
  }
  // Silinecek kayda değer arka plan yok.
  if (removed < w * h * 0.02) return null;

  bool nearBg(int x, int y) {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && nx < w && ny >= 0 && ny < h && bg[ny * w + nx] == 1) {
          return true;
        }
      }
    }
    return false;
  }

  final out = img.Image(width: w, height: h, numChannels: 4);
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (bg[y * w + x] == 1) {
        out.setPixelRgba(x, y, 255, 255, 255, 0);
        continue;
      }
      final p = src.getPixel(x, y);
      var a = p.a.toInt();
      final d = dist(p);
      if (d < _soft && nearBg(x, y)) {
        a = math.min(a, (255 * (d - _hard) / (_soft - _hard)).round());
        a = a.clamp(0, 255);
      }
      out.setPixelRgba(x, y, p.r, p.g, p.b, a);
      if (a > 0) {
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
  }
  if (maxX < 0) return null;

  // Boş kenarları kırp, kare tuvale ortala.
  final cw = maxX - minX + 1, ch = maxY - minY + 1;
  final cropped = img.copyCrop(out, x: minX, y: minY, width: cw, height: ch);
  final side = math.max(cw, ch);
  var square = img.Image(width: side, height: side, numChannels: 4);
  img.compositeImage(
    square,
    cropped,
    dstX: (side - cw) ~/ 2,
    dstY: (side - ch) ~/ 2,
  );
  if (side > _maxSide) {
    square = img.copyResize(
      square,
      width: _maxSide,
      height: _maxSide,
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodePng(square);
}

/// Kenarlardaki ince, tek renk koyu şeritleri (ör. kare yapmak için eklenmiş
/// siyah satırlar) kırpar; yoksa dolgu kenardan başlayamaz. Her kenarda en
/// fazla boyun %3'ü kırpılır.
img.Image _trimEdgeStripes(img.Image src) {
  bool uniformDark(Iterable<img.Pixel> line) {
    img.Pixel? first;
    for (final p in line) {
      if (p.a < 128) return false;
      if (math.max(p.r, math.max(p.g, p.b)) > 200) return false;
      first ??= p;
      if ((p.r - first.r).abs() > 24 ||
          (p.g - first.g).abs() > 24 ||
          (p.b - first.b).abs() > 24) {
        return false;
      }
    }
    return first != null;
  }

  Iterable<img.Pixel> row(int y) sync* {
    for (var x = 0; x < src.width; x++) {
      yield src.getPixel(x, y);
    }
  }

  Iterable<img.Pixel> col(int x) sync* {
    for (var y = 0; y < src.height; y++) {
      yield src.getPixel(x, y);
    }
  }

  final maxY = (src.height * 0.03).ceil(), maxX = (src.width * 0.03).ceil();
  var top = 0, bottom = 0, left = 0, right = 0;
  while (top < maxY && uniformDark(row(top))) {
    top++;
  }
  while (bottom < maxY && uniformDark(row(src.height - 1 - bottom))) {
    bottom++;
  }
  while (left < maxX && uniformDark(col(left))) {
    left++;
  }
  while (right < maxX && uniformDark(col(src.width - 1 - right))) {
    right++;
  }
  // Şerit sınırı aşıyorsa koyu zeminli logodur; dokunma.
  if (top == maxY || bottom == maxY || left == maxX || right == maxX) {
    return src;
  }
  if (top + bottom + left + right == 0) return src;
  return img.copyCrop(
    src,
    x: left,
    y: top,
    width: src.width - left - right,
    height: src.height - top - bottom,
  );
}
