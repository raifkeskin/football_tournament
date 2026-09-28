import 'dart:async';

/// Supabase realtime akışlarını kopmalara karşı dayanıklı hale getirir.
///
/// Uygulama arka plana alınınca işletim sistemi websocket bağlantısını
/// kapatır; Supabase akışı `RealtimeSubscribeException (code 1006)` hatasıyla
/// sonlanır ve bir daha veri göndermez. Bu sarmalayıcı hatayı ekrana iletmek
/// yerine kısa bir beklemeden sonra akışı [create] ile yeniden kurar; ekran
/// son veriyi göstermeye devam eder.
Stream<T> resilientStream<T>(
  Stream<T> Function() create, {
  Duration retryDelay = const Duration(seconds: 2),
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? retry;
  var cancelled = false;

  void connect() {
    if (cancelled) return;
    sub = create().listen(
      controller.add,
      onError: (Object _, StackTrace _) {
        sub?.cancel();
        sub = null;
        if (cancelled) return;
        retry?.cancel();
        retry = Timer(retryDelay, connect);
      },
    );
  }

  controller = StreamController<T>.broadcast(
    onListen: () {
      cancelled = false;
      connect();
    },
    onCancel: () {
      cancelled = true;
      retry?.cancel();
      sub?.cancel();
    },
  );
  return controller.stream;
}
