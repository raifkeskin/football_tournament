import 'dart:async';

/// Bir akış bağlantısının ömrü boyunca açılan iç akışları (realtime
/// kanalları, paylaşılan akışlara bağlanan dinleyiciler) kaydeder ve
/// bağlantı kapanınca hepsini kapatır.
///
/// Neden gerekli: `async*` gövdesi bir `await for` içinde beklerken dış
/// abonelik iptal edilirse Dart içteki aboneliği iptal etmez; gövde ancak
/// bir sonraki `yield`'da sonlanır. Olay gelmeyen bir realtime kanalında bu
/// hiç olmaz ve kanal açık kalır (ekrandan çıkıldıkça kanallar birikir,
/// sunucu 100 kanalda "Too many channels" ile reddeder). Kapsam iç akışları
/// doğrudan kapatır; `await for` biter ve gövde sonlanır.
class StreamScope {
  static const _key = #streamScope;

  final _closers = <void Function()>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Şu an çalışan kod bir kapsam içindeyse o kapsam.
  static StreamScope? get current => Zone.current[_key] as StreamScope?;

  /// [body] bu kapsamın içinde çalışır; içinde (ve devamındaki asenkron
  /// adımlarda) açılan iç akışlar bu kapsama kaydolur.
  R run<R>(R Function() body) => runZoned(body, zoneValues: {_key: this});

  /// Kapsam kapanınca çağrılacak kapatıcıyı ekler; kaldırmak için dönen
  /// fonksiyon çağrılır. Kapsam zaten kapandıysa kapatıcı hemen çalışır.
  void Function() add(void Function() closer) {
    if (_cancelled) {
      closer();
      return () {};
    }
    _closers.add(closer);
    return () => _closers.remove(closer);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final all = [..._closers];
    _closers.clear();
    for (final c in all) {
      c();
    }
  }
}
