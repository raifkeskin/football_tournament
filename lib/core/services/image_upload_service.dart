import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Resim yükleme işlemleri için soyut arayüz.
/// Bu sayede ileride ImgBB'den Firebase Storage'a veya başka bir servise kolayca geçilebilir.
abstract class ImageUploadService {
  Future<String?> uploadImage(File image);
}

/// ImgBB API kullanarak resim yükleme servisi.
class ImgBBUploadService implements ImageUploadService {
  final String _apiKey = '227aa94606b89561c4818dc797a7e07b';
  final String _uploadUrl = 'https://api.imgbb.com/1/upload';

  @override
  Future<String?> uploadImage(File image) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      request.fields['key'] = _apiKey;
      request.files.add(await http.MultipartFile.fromPath('image', image.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonResponse = json.decode(responseData);

      if (response.statusCode == 200 && jsonResponse['success'] == true) {
        return jsonResponse['data']['url'] as String?;
      } else {
        print(
          'ImgBB Upload Hatası: ${jsonResponse['error']?['message'] ?? 'Bilinmeyen hata'}',
        );
        return null;
      }
    } catch (e) {
      print('ImgBB Servis Hatası: $e');
      return null;
    }
  }
}
