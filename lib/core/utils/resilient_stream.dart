import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_activity.dart';
import 'stream_scope.dart';

/// Arka planda bu süre kalınca canlı bağlantı kapatılır (kısa uygulama
/// geçişlerinde bağlantı kurup kapatmakla uğraşılmasın).
const _backgroundGrace = Duration(seconds: 30);

/// Art arda kopmalarda bekleme en fazla bu kadar uzar.
const _maxRetryDelay = Duration(seconds: 30);

/// Bu süreden uzun ayakta kalan bağlantı sağlıklı sayılır; sonraki kopmada
/// bekleme baştan başlar.
const _healthyAfter = Duration(seconds: 60);

final _random = Random();

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
///
/// Sorgu hatası (PostgrestException: ör. kaldırılmış sütun, yetki) bağlantı
/// kopması değildir; henüz veri yoksa ekrana iletilir ki "yükleniyor"da
/// sonsuza dek takılmasın. Yeniden deneme daha seyrek sürer.
///
/// Kopmadan sonraki bekleme her denemede ikiye katlanır (en fazla
/// [_maxRetryDelay]) ve ±%50 rastgele kaydırılır: maç günü yüzlerce kişi
/// aynı anda koptuğunda hepsi aynı saniyede geri bağlanmaya çalışmasın
/// (2026-10-17 yük testi: sabit 2 sn'lik deneme kanal katılımını tıkıyordu).
Stream<T> resilientStream<T>(
  Stream<T> Function() create, {
  Duration retryDelay = const Duration(seconds: 2),
  Duration queryErrorRetryDelay = const Duration(seconds: 15),
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
  var failures = 0;
  DateTime? connectedAt;

  Duration nextDelay(Duration base) {
    final ms = min(
      base.inMilliseconds * (1 << min(failures, 5)),
      _maxRetryDelay.inMilliseconds,
    );
    failures++;
    return Duration(milliseconds: (ms * (0.5 + _random.nextDouble())).round());
  }

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
    connectedAt = DateTime.now();
    sub = s.run(
      () => create().listen(
        (value) {
          last = value;
          hasLast = true;
          for (final l in [...listeners]) {
            l.add(value);
          }
        },
        onError: (Object e, StackTrace st) {
          if (scope != s) return; // eski bağlantının geç gelen hatası
          final since = connectedAt;
          if (since != null &&
              DateTime.now().difference(since) > _healthyAfter) {
            failures = 0;
          }
          closeConnection();
          if (listeners.isEmpty) return;
          final queryError = e is PostgrestException;
          if (queryError && !hasLast) {
            for (final l in [...listeners]) {
              l.addError(e, st);
            }
          }
          retry?.cancel();
          retry = Timer(
            nextDelay(queryError ? queryErrorRetryDelay : retryDelay),
            connect,
          );
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
        failures = 0;
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
