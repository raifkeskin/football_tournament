/// Kimlik kartı okuyucu: uygulamada NFC + kamera, web'de boş.
library;

export 'id_card.dart';
export 'id_card_reader_stub.dart' if (dart.library.io) 'id_card_reader_io.dart';
