import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Arka plan rengine uzaklık bundan küçükse kesin arka plan.
const _hard = 40;

/// [_hard] ile bu değer arası, arka plana komşu kenarlarda kısmi şeffaflık.
const _soft = 110;

/// Logolar en fazla bu kenar uzunluğunda saklanır.
const _maxSide = 384;

/// Logonun kenarlarındaki tek renk arka planı (beyaz, siyah, renkli kare)
/// şeffaf yapar, boş kenarları kırpar ve PNG döner.
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

  final bgColor = _edgeBackground(src);
  if (bgColor == null) return null;

  int dist(img.Pixel p) {
    // Zaten şeffaf piksel arka plan sayılır.
    if (p.a < 128) return 0;
    if (bgColor.transparent) return 255;
    return math.max(
      (bgColor.r - p.r.toInt()).abs(),
      math.max(
        (bgColor.g - p.g.toInt()).abs(),
        (bgColor.b - p.b.toInt()).abs(),
      ),
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

/// Kenar piksellerinden arka planı bulur: çoğu şeffafsa şeffaf zemin, çoğu
/// aynı renkse o renk. Kenarlar karışıksa (logo resmin kenarına taşıyor)
/// `null` döner; o zaman arka plan silinmez.
({int r, int g, int b, bool transparent})? _edgeBackground(img.Image src) {
  final w = src.width, h = src.height;
  final rs = <int>[], gs = <int>[], bs = <int>[];
  var total = 0, transparent = 0;
  void add(int x, int y) {
    final p = src.getPixel(x, y);
    total++;
    if (p.a < 128) {
      transparent++;
      return;
    }
    rs.add(p.r.toInt());
    gs.add(p.g.toInt());
    bs.add(p.b.toInt());
  }

  for (var x = 0; x < w; x++) {
    add(x, 0);
    add(x, h - 1);
  }
  for (var y = 1; y < h - 1; y++) {
    add(0, y);
    add(w - 1, y);
  }
  if (transparent >= total * 0.5) {
    return (r: 0, g: 0, b: 0, transparent: true);
  }
  int median(List<int> v) => (v..sort())[v.length ~/ 2];
  final r = median(List.of(rs)),
      g = median(List.of(gs)),
      b = median(List.of(bs));
  var close = 0;
  for (var i = 0; i < rs.length; i++) {
    final d = math.max(
      (rs[i] - r).abs(),
      math.max((gs[i] - g).abs(), (bs[i] - b).abs()),
    );
    if (d <= _hard) close++;
  }
  if (close < total * 0.6) return null;
  return (r: r, g: g, b: b, transparent: false);
}

/// Kenarlardaki tek renk koyu şeritleri kırpar; yoksa dolgu kenardan
/// başlayamaz. İnce şeritler (ör. kare yapmak için eklenmiş siyah satırlar,
/// boyun en fazla %3'ü) her zaman kırpılır. Kalın şeritler (ör. ekran
/// görüntüsündeki siyah bantlar) ancak arkalarında açık zemin varsa kırpılır;
/// yoksa koyu zeminli logodur.
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

  bool mostlyLight(Iterable<img.Pixel> line) {
    var light = 0, total = 0;
    for (final p in line) {
      total++;
      if (p.a < 128 || math.min(p.r, math.min(p.g, p.b)) > 200) light++;
    }
    return total > 0 && light >= total * 0.9;
  }

  // Bant en fazla boyun %45'i olabilir; ortada içerik kalmalı.
  final limY = (src.height * 0.45).floor(), limX = (src.width * 0.45).floor();
  var top = 0, bottom = 0, left = 0, right = 0;
  while (top < limY && uniformDark(row(top))) {
    top++;
  }
  while (bottom < limY && uniformDark(row(src.height - 1 - bottom))) {
    bottom++;
  }
  while (left < limX && uniformDark(col(left))) {
    left++;
  }
  while (right < limX && uniformDark(col(src.width - 1 - right))) {
    right++;
  }
  if (top == limY || bottom == limY || left == limX || right == limX) {
    return src;
  }
  final thinY = (src.height * 0.03).ceil(), thinX = (src.width * 0.03).ceil();
  final thin = top < thinY && bottom < thinY && left < thinX && right < thinX;
  if (!thin) {
    // Kalın bandın hemen içi (geçiş pikselleri atlanarak) açık zemin olmalı.
    bool lightNear(int start, int step, Iterable<img.Pixel> Function(int) at) {
      for (var k = 0; k < 6; k++) {
        if (mostlyLight(at(start + k * step))) return true;
      }
      return false;
    }

    final light =
        (top == 0 || lightNear(top, 1, row)) &&
        (bottom == 0 || lightNear(src.height - 1 - bottom, -1, row)) &&
        (left == 0 || lightNear(left, 1, col)) &&
        (right == 0 || lightNear(src.width - 1 - right, -1, col));
    if (!light) return src;
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

/// Sponsor logoları bu yükseklikte saklanır (şeritte 32 px; 6× yoğunluk),
/// genişlik logonun kendi oranıyla (en fazla [_sponsorMaxWidth]).
const sponsorLogoHeight = 192;
const _sponsorMaxWidth = 1080;

/// Sponsor logosunu standarda getirir: kenarlardaki düz renkli bantlar
/// (ekran görüntüsündeki siyah/beyaz boşluklar, şeffaf kenar, geçiş
/// çizgileri) katman katman kırpılır; logo kendi oranında 192 px yüksekliğe
/// ölçeklenir. Zemin opaksa (ör. siyah kutulu logo) kenarda o renkten ince
/// pay bırakılır. Ağır iş; `compute` ile ayrı isolate'te çağrılmalı.
Uint8List? fitSponsorLogo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var src = decoded.convert(numChannels: 4);
  if (math.max(src.width, src.height) > 1600) {
    src = src.width >= src.height
        ? img.copyResize(src, width: 1600)
        : img.copyResize(src, height: 1600);
  }

  // Katman katman: önce dış bant (ör. siyah), sonra içteki zemin (beyaz).
  // Bulunan tüm zemin renkleri birlikte sayılır; aradaki geçiş satırları
  // kırpmayı durdurmaz.
  final bgs = <({int r, int g, int b, bool transparent})>[];
  for (var pass = 0; pass < 3; pass++) {
    final c = _cornerColor(src);
    if (c == null) break;
    if (!bgs.contains(c)) bgs.add(c);
    final cropped = _trimUniform(src, bgs);
    if (cropped == null) break;
    src = cropped;
  }
  final bg = bgs.isEmpty ? null : bgs.last;

  // Opak zeminde logo kutunun kenarına yapışmasın: zemin renginden ince pay.
  if (bg != null && !bg.transparent) {
    final pad = math.max(2, (math.min(src.width, src.height) * 0.06).round());
    final framed = img.Image(
      width: src.width + pad * 2,
      height: src.height + pad * 2,
      numChannels: 4,
    );
    img.fill(framed, color: img.ColorRgba8(bg.r, bg.g, bg.b, 255));
    img.compositeImage(framed, src, dstX: pad, dstY: pad);
    src = framed;
  }

  var scale = sponsorLogoHeight / src.height;
  if (src.width * scale > _sponsorMaxWidth) {
    scale = _sponsorMaxWidth / src.width;
  }
  final out = img.copyResize(
    src,
    width: math.max(1, (src.width * scale).round()),
    height: math.max(1, (src.height * scale).round()),
    interpolation: img.Interpolation.cubic,
  );
  return img.encodePng(out, level: 6);
}

/// PNG başlığından en/boy oranı (genişlik / yükseklik); okunamazsa null.
double? pngAspect(Uint8List png) {
  if (png.length < 24) return null;
  final d = ByteData.sublistView(png);
  final w = d.getUint32(16), h = d.getUint32(20);
  return w > 0 && h > 0 ? w / h : null;
}

/// Dört köşe aynı renkteyse (ya da şeffafsa) o renk; değilse null.
({int r, int g, int b, bool transparent})? _cornerColor(img.Image src) {
  // Köşeden biraz içeri bakılır: kenardaki tek piksellik geçiş yanıltmasın.
  final i = math.min(2, math.min(src.width, src.height) ~/ 4);
  final corners = [
    src.getPixel(i, i),
    src.getPixel(src.width - 1 - i, i),
    src.getPixel(i, src.height - 1 - i),
    src.getPixel(src.width - 1 - i, src.height - 1 - i),
  ];
  if (corners.every((p) => p.a < 32)) {
    return (r: 0, g: 0, b: 0, transparent: true);
  }
  final f = corners.first;
  for (final p in corners) {
    if (p.a < 200 ||
        (p.r - f.r).abs() > 30 ||
        (p.g - f.g).abs() > 30 ||
        (p.b - f.b).abs() > 30) {
      return null;
    }
  }
  return (r: f.r.toInt(), g: f.g.toInt(), b: f.b.toInt(), transparent: false);
}

/// Zemin renklerinden ([bgs]) birinde olan (en az %96'sı) kenar
/// satır/sütunlarını kırpar. Kırpacak bir şey yoksa ya da geriye neredeyse
/// hiçbir şey kalmıyorsa null.
img.Image? _trimUniform(
  img.Image src,
  List<({int r, int g, int b, bool transparent})> bgs,
) {
  bool isBg(img.Pixel p) {
    for (final bg in bgs) {
      if (bg.transparent) {
        if (p.a < 32) return true;
      } else if (p.a >= 200 &&
          (p.r - bg.r).abs() <= 40 &&
          (p.g - bg.g).abs() <= 40 &&
          (p.b - bg.b).abs() <= 40) {
        return true;
      }
    }
    return false;
  }

  /// Satır/sütun zemin mi: büyük kısmı zemin renginde ya da baştan sona tek
  /// renk (bantlar arasındaki gri geçiş çizgisi gibi).
  bool lineBg(Iterable<img.Pixel> line, int length) {
    var n = 0, same = 0;
    img.Pixel? first;
    for (final p in line) {
      if (isBg(p)) n++;
      first ??= p;
      if ((p.r - first.r).abs() <= 24 &&
          (p.g - first.g).abs() <= 24 &&
          (p.b - first.b).abs() <= 24 &&
          (p.a - first.a).abs() <= 24) {
        same++;
      }
    }
    return n >= length * 0.96 || same >= length * 0.98;
  }

  bool rowBg(int y) => lineBg([
    for (var x = 0; x < src.width; x++) src.getPixel(x, y),
  ], src.width);

  bool colBg(int x, int top, int bottom) => lineBg([
    for (var y = top; y <= bottom; y++) src.getPixel(x, y),
  ], bottom - top + 1);

  var top = 0, bottom = src.height - 1;
  while (top < bottom && rowBg(top)) {
    top++;
  }
  while (bottom > top && rowBg(bottom)) {
    bottom--;
  }
  var left = 0, right = src.width - 1;
  while (left < right && colBg(left, top, bottom)) {
    left++;
  }
  while (right > left && colBg(right, top, bottom)) {
    right--;
  }
  final w = right - left + 1, h = bottom - top + 1;
  if (w == src.width && h == src.height) return null;
  if (w < 8 || h < 8) return null;
  return img.copyCrop(src, x: left, y: top, width: w, height: h);
}
