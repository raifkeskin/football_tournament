import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

/// Seçilen (henüz yüklenmemiş) resmin önizlemesi. Web'de `XFile.path` bir
/// blob adresidir ve `Image.file` çalışmaz; orada ağ resmi olarak okunur.
ImageProvider pickedImageProvider(XFile file) =>
    kIsWeb ? NetworkImage(file.path) : FileImage(File(file.path));
