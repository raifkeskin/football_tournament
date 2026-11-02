import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'photo_standard.dart';

/// Cihazda yüz bulma (ML Kit); fotoğraf telefondan çıkmaz. Android ve iOS
/// dışında null.
Future<List<PhotoFace>?> detectFaces(Uint8List jpeg) async {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/face_check_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(jpeg, flush: true);
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  try {
    final faces = await detector.processImage(
      InputImage.fromFilePath(file.path),
    );
    return [
      for (final f in faces)
        PhotoFace(
          f.boundingBox,
          roll: f.headEulerAngleZ,
          yaw: f.headEulerAngleY,
          leftEyeOpen: f.leftEyeOpenProbability,
          rightEyeOpen: f.rightEyeOpenProbability,
        ),
    ];
  } finally {
    await detector.close();
    try {
      await file.delete();
    } catch (_) {}
  }
}
