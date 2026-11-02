import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart' show BuildContext;

import '../../services/app_session.dart';
import '../../services/app_settings.dart';
import 'face_detect_stub.dart'
    if (dart.library.io) 'face_detect_io.dart'
    as detect;

/// Profil fotoğrafı standardı: yüz ve omuzlar görünen, ortalı, düz bakan
/// tek kişi. Kadraj ekranı kılavuz çizer; telefonda kayıttan önce yüz bulunup
/// kurallara bakılır (web'de yalnız kılavuz).
class PhotoStandard {
  PhotoStandard._();

  /// Yeni özellik: admin her zaman, diğerleri ayar açıksa görür.
  static bool visible(BuildContext context) {
    try {
      if (AppSession.of(context).value.isAdmin) return true;
    } catch (_) {}
    return AppSettings.photoStandardEnabled.value;
  }

  /// Kesilmiş fotoğrafın standarda uymayan yanları (boşsa uygun). Yüz
  /// bulma bu cihazda yoksa ya da hata verirse boş döner: kullanıcı
  /// engellenmez.
  static Future<List<String>> check(Uint8List jpeg, Size size) async {
    try {
      final faces = await detect.detectFaces(jpeg);
      if (faces == null) return const [];
      return portraitIssues(faces, size);
    } catch (_) {
      return const [];
    }
  }
}

/// Bulunan yüz: kutu piksel cinsinden; açılar derece, gözler 0–1 olasılık.
class PhotoFace {
  const PhotoFace(
    this.box, {
    this.roll,
    this.yaw,
    this.leftEyeOpen,
    this.rightEyeOpen,
  });

  final Rect box;
  final double? roll;
  final double? yaw;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
}

/// Kurallar. Yüz kutusu kaşlardan çeneye kadardır: başın üstü kutunun
/// yaklaşık üçte biri kadar yukarıda, omuzlar çenenin bir yüz boyu altında.
List<String> portraitIssues(List<PhotoFace> all, Size size) {
  final w = size.width, h = size.height;
  // Arkadaki küçük yüzler sayılmaz.
  final faces = all.where((f) => f.box.width >= w * 0.12).toList();
  if (faces.isEmpty) {
    return const ['Yüz bulunamadı. Yüzünüz net ve önden görünsün.'];
  }
  if (faces.length > 1) {
    return const ['Fotoğrafta yalnız siz olmalısınız.'];
  }
  final f = faces.first;
  final b = f.box;
  final out = <String>[];
  final ratio = b.width / w;
  if (ratio < 0.28) {
    out.add('Çok uzaktan çekilmiş; fotoğrafı büyütün.');
  } else if (ratio > 0.62) {
    out.add('Çok yakın; omuzlarınız da görünsün.');
  } else if ((h - b.bottom) < b.height * 0.8) {
    out.add('Omuzlarınız görünmüyor; fotoğrafı yukarı kaydırın.');
  }
  if (b.top < b.height * 0.25) {
    out.add('Başınızın üstü kesiliyor; fotoğrafı aşağı kaydırın.');
  }
  final cx = b.center.dx / w;
  if (cx < 0.38 || cx > 0.62) out.add('Yüzünüzü ortalayın.');
  if ((f.roll ?? 0).abs() > 15 || (f.yaw ?? 0).abs() > 20) {
    out.add('Kameraya düz bakın.');
  }
  if (b.width < 150) {
    out.add('Fotoğraf çok küçük; daha net bir fotoğraf seçin.');
  }
  final l = f.leftEyeOpen, r = f.rightEyeOpen;
  if (l != null && r != null && l < 0.25 && r < 0.25) {
    out.add('Gözleriniz kapalı görünüyor.');
  }
  return out;
}
