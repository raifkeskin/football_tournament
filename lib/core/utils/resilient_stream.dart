import 'dart:async';

/// Supabase realtime akışlarını kopmalara karşı dayanıklı hale getirir.
///
/// Uygulama arka plana alınınca işletim sistemi websocket bağlantısını
/// kapatır; Supabase akışı `RealtimeSubscribeException (code 1006)` hatasıyla
/// sonlanır ve bir daha veri göndermez. Bu sarmalayıcı hatayı ekrana iletmek
/// yerine kısa bir beklemeden sonra akışı [create] ile yeniden kurar; ekran
/// son veriyi göstermeye devam eder.
///
/// Birden fazla dinleyiciyi destekler ve sonradan bağlanan dinleyiciye son
/// değeri hemen iletir (ekran yeniden kurulsa da yükleniyor'da takılmaz).
Stream<T> resilientStream<T>(
  Stream<T> Function() create, {
  Duration retryDelay = const Duration(seconds: 2),
}) {
  final listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? sub;
  Timer? retry;
  late T last;
  var hasLast = false;

  void connect() {
    retry = null;
    if (listeners.isEmpty) return;
    sub = create().listen(
      (value) {
        last = value;
        hasLast = true;
        for (final l in [...listeners]) {
          l.add(value);
        }
      },
      onError: (Object _, StackTrace _) {
        sub?.cancel();
        sub = null;
        if (listeners.isEmpty) return;
        retry?.cancel();
        retry = Timer(retryDelay, connect);
      },
    );
  }

  return Stream<T>.multi((controller) {
    listeners.add(controller);
    if (hasLast) controller.add(last);
    if (sub == null && retry == null) connect();
    controller.onCancel = () {
      listeners.remove(controller);
      if (listeners.isEmpty) {
        retry?.cancel();
        retry = null;
        sub?.cancel();
        sub = null;
        hasLast = false;
      }
    };
  });
}
