import 'dart:async';

import 'app_activity.dart';
import 'stream_scope.dart';

/// Arka planda bu süre kalınca canlı bağlantı kapatılır (kısa uygulama
/// geçişlerinde bağlantı kurup kapatmakla uğraşılmasın).
const _backgroundGrace = Duration(seconds: 30);

/// Supabase realtime akışlarını kopmalara karşı dayanıklı hale getirir.
///
/// Uygulama arka plana alınınca işletim sistemi websocket bağlantısını
/// kapatır; Supabase akışı `RealtimeSubscribeException (code 1006)` hatasıyla
/// sonlanır ve bir daha veri göndermez. Bu sarmalayıcı hatayı ekrana iletmek
/// yerine kısa bir beklemeden sonra akışı [create] ile yeniden kurar; ekran
/// son veriyi göstermeye devam eder.
///
/// Uygulama arka planda kalınca akış (ve realtime kanalı) kendiliğinden
/// kapatılır; ön plana dönünce yeniden kurulur ve taze veri okunur. Ekran bu
/// sırada son veriyi göstermeye devam eder.
///
/// Birden fazla dinleyiciyi destekler ve sonradan bağlanan dinleyiciye son
/// değeri hemen iletir (ekran yeniden kurulsa da yükleniyor'da takılmaz).
Stream<T> resilientStream<T>(
  Stream<T> Function() create, {
  Duration retryDelay = const Duration(seconds: 2),
}) {
  final listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? sub;
  // Geçerli bağlantının kapsamı: içinde açılan realtime kanalları bağlantı
  // kapanınca doğrudan kapatılır (bkz. StreamScope).
  StreamScope? scope;
  Timer? retry;
  Timer? sleep;
  late T last;
  var hasLast = false;

  void closeConnection() {
    scope?.cancel();
    scope = null;
    sub?.cancel();
    sub = null;
  }

  void connect() {
    retry = null;
    if (listeners.isEmpty || !AppActivity.foreground.value) return;
    final s = scope = StreamScope();
    sub = s.run(
      () => create().listen(
        (value) {
          last = value;
          hasLast = true;
          for (final l in [...listeners]) {
            l.add(value);
          }
        },
        onError: (Object _, StackTrace _) {
          if (scope != s) return; // eski bağlantının geç gelen hatası
          closeConnection();
          if (listeners.isEmpty) return;
          retry?.cancel();
          retry = Timer(retryDelay, connect);
        },
      ),
    );
  }

  void disconnect() {
    retry?.cancel();
    retry = null;
    closeConnection();
  }

  void onActivity() {
    if (AppActivity.foreground.value) {
      sleep?.cancel();
      sleep = null;
      if (listeners.isNotEmpty && sub == null && retry == null) connect();
    } else {
      sleep ??= Timer(_backgroundGrace, () {
        sleep = null;
        disconnect();
      });
    }
  }

  return Stream<T>.multi((controller) {
    if (listeners.isEmpty) AppActivity.foreground.addListener(onActivity);
    listeners.add(controller);
    if (hasLast) controller.add(last);
    if (sub == null && retry == null) connect();
    void detach() {
      if (!listeners.remove(controller)) return;
      if (listeners.isEmpty) {
        AppActivity.foreground.removeListener(onActivity);
        sleep?.cancel();
        sleep = null;
        disconnect();
        hasLast = false;
      }
    }

    // Bu akışı başka bir akışın gövdesi dinliyorsa (iç içe akış), o akış
    // kapanınca bu dinleyici de bırakılır; aksi halde paylaşılan akışın
    // kanalı hiç kapanmaz.
    final unregister = StreamScope.current?.add(() {
      detach();
      controller.closeSync();
    });
    controller.onCancel = () {
      unregister?.call();
      detach();
    };
  });
}
