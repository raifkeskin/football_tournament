// Web dışı platformlar: Web Push yok (mağaza sürümünde yerel bildirim
// altyapısı eklenecek).
String pushState() => 'unsupported';
Future<String> pushSubscribe(String vapidKey) async =>
    throw UnsupportedError('push');
Future<String> pushCurrent() async => '';
Future<String> pushUnsubscribe() async => '';
bool pushIsIos() => false;
void pushOnOpen(void Function(String url) onOpen) {}
