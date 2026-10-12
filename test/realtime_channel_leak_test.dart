import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/utils/realtime_signal.dart';
import 'package:football_tournament/core/utils/resilient_stream.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `async*` + `await for` içindeki realtime kanalı, akış iptal edilince
/// kapanmalı (yoksa ekrandan çıkıldıkça kanallar birikir ve sunucu 100
/// kanalda "Too many channels" ile reddeder).
void main() {
  late SupabaseClient client;
  late HttpServer server;

  setUp(() async {
    // Bağlantıyı kabul edip hiç yanıt vermeyen sahte realtime sunucusu:
    // kanal ne hata verir ne olay alır (olay gelmeyen gerçek kanal gibi).
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {});
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'anon');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('ekrana girip çıkmak kanal bırakmaz', () async {
    Stream<int> feed(String id) => resilientStream(() async* {
      yield 0;
      await for (final _ in realtimeChangeSignal(
        client,
        table: 'match_events',
        column: 'match_id',
        value: id,
      )) {
        yield 1;
      }
    });

    for (var i = 0; i < 50; i++) {
      final sub = feed('m$i').listen((_) {});
      await settle();
      expect(client.getChannels(), hasLength(1));
      await sub.cancel();
      await settle();
    }
    expect(client.getChannels(), isEmpty);
  });

  test('iç içe paylaşılan akış da bırakılır', () async {
    final shared = resilientStream(() async* {
      yield 0;
      await for (final _ in realtimeRowChanges(client, table: 'matches')) {
        yield 1;
      }
    });
    Stream<int> outer() => resilientStream(() async* {
      await for (final v in shared) {
        yield v;
      }
    });

    for (var i = 0; i < 20; i++) {
      final sub = outer().listen((_) {});
      await settle();
      expect(client.getChannels(), hasLength(1));
      await sub.cancel();
      await settle();
    }
    expect(client.getChannels(), isEmpty);
  });

  const m1 = '11111111-1111-4111-8111-111111111111';
  const s1 = '22222222-2222-4222-8222-222222222222';

  test('canlı maç tablolarının broadcast konusu', () {
    expect(broadcastTopicFor('matches', 'id', m1), 'match:$m1');
    expect(broadcastTopicFor('match_events', 'match_id', m1), 'match:$m1');
    expect(broadcastTopicFor('match_rosters', 'match_id', m1), 'match:$m1');
    expect(broadcastTopicFor('matches', 'season_id', s1), 'season:$s1');
    expect(broadcastTopicFor('match_events', 'season_id', s1), 'season:$s1');
    expect(broadcastTopicFor('matches', 'league_id', s1), 'league:$s1');
    // Esame sezona yayınlanmaz; başka tablolar ve uuid olmayan değerler
    // postgres_changes'te kalır.
    expect(broadcastTopicFor('match_rosters', 'season_id', s1), isNull);
    expect(broadcastTopicFor('news', 'season_id', s1), isNull);
    expect(broadcastTopicFor('matches', 'id', 'abc'), isNull);
  });

  test(
    'aynı konuyu dinleyen akışlar tek kanalı paylaşır, sonra kapanır',
    () async {
      Stream<int> feed(String table) => resilientStream(() async* {
        yield 0;
        await for (final _ in realtimeRowChanges(
          client,
          table: table,
          column: 'match_id',
          value: m1,
        )) {
          yield 1;
        }
      });

      for (var i = 0; i < 20; i++) {
        final a = feed('match_events').listen((_) {});
        final b = feed('match_rosters').listen((_) {});
        await settle();
        // İki akış da match:<id> konusunda: tek kanal.
        expect(client.getChannels(), hasLength(1));
        // ignore: invalid_use_of_internal_member
        expect(client.getChannels().single.topic, 'realtime:match:$m1');
        await a.cancel();
        await settle();
        expect(client.getChannels(), hasLength(1));
        await b.cancel();
        await settle();
        expect(client.getChannels(), isEmpty);
      }
    },
  );
}
