// Tek bir görseli uygulamanın yükleme sınırlarına küçültür.
// Kullanım: dart run scripts/shrink_image.dart <girdi> <çıktı-öneki> <logo|photo>
// Çıktı: "ok <uzantı>" (küçüldü, dosya <önek>.<uzantı>) ya da "skip".
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final logo = args[2] == 'logo';
  final maxSide = logo ? 384 : 512; // image_upload_service ile aynı
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    print('skip');
    return;
  }
  var im = img.bakeOrientation(decoded);
  if (im.width > maxSide || im.height > maxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
  }
  final png = logo || im.hasAlpha;
  final out = png ? img.encodePng(im, level: 9) : img.encodeJpg(im, quality: 82);
  // %20'den az kazanç varsa dokunma.
  if (out.length > bytes.length * 0.8) {
    print('skip');
    return;
  }
  final ext = png ? 'png' : 'jpg';
  File('${args[1]}.$ext').writeAsBytesSync(out);
  print('ok $ext');
}
