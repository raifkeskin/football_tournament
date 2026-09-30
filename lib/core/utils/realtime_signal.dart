import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Bir tablodaki `column = value` satırları değiştiğinde (ekleme, güncelleme,
/// silme) boş bir sinyal yayar. Veri taşımaz; dinleyen taraf listeyi kendi
/// filtreli sorgusuyla yeniden okur.
///
/// `.stream()` aksine tabloyu indirmez. Filtreli realtime aboneliğinde silme
/// olayları gelmediği için (silinen satırda yalnızca birincil anahtar olur)
/// silmeler ayrıca filtresiz dinlenir; bu olaylar yalnızca id taşır.
///
/// [column] verilmezse tablodaki her değişiklik sinyal üretir (ör. sezon
/// sütunu olmayan match_events için sezon istatistikleri).
///
/// Kanal hata verirse akış hata ile biter; `resilientStream` ile sarılırsa
/// otomatik yeniden bağlanır.
Stream<void> realtimeChangeSignal(
  SupabaseClient client, {
  required String table,
  String? column,
  String? value,
}) {
  late StreamController<void> controller;
  RealtimeChannel? channel;

  controller = StreamController<void>(
    onListen: () {
      void signal(PostgresChangePayload _) {
        if (!controller.isClosed) controller.add(null);
      }

      final name =
          'sig:$table:$column=$value:${DateTime.now().microsecondsSinceEpoch}';
      final base = client.channel(name);
      final RealtimeChannel configured;
      if (column == null || value == null) {
        configured = base.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: signal,
        );
      } else {
        configured = base
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: table,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: column,
                value: value,
              ),
              callback: signal,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: table,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: column,
                value: value,
              ),
              callback: signal,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: table,
              callback: signal,
            );
      }
      channel = configured.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!controller.isClosed) {
            controller.addError(error ?? 'realtime $status');
          }
        }
      });
    },
    onCancel: () async {
      final c = channel;
      channel = null;
      if (c != null) await client.removeChannel(c);
    },
  );
  return controller.stream;
}
