import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:football_tournament/services/supabase/supabase_team_service.dart';

void main() {
  test('upsertRosterEntry writes league_team_players with league_id, team_id, player_id', () async {
    final requests = <http.Request>[];

    String dumpReq(http.Request r) =>
        '${r.method} ${r.url}\naccept=${r.headers['accept']}\nprefer=${r.headers['prefer']}';

    final mock = MockClient((req) async {
      requests.add(req);

      final path = req.url.path;
      if (path.endsWith('/rest/v1/players') && req.method == 'GET') {
        final accept = req.headers['accept'] ?? '';
        final body = accept.contains('vnd.pgrst.object')
            ? jsonEncode({'id': 'player-1'})
            : jsonEncode([{'id': 'player-1'}]);
        return http.Response(body, 200, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      if (path.endsWith('/rest/v1/players') && req.method == 'POST') {
        return http.Response('[]', 201, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      if (path.endsWith('/rest/v1/league_team_players') && req.method == 'POST') {
        return http.Response('[]', 201, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      if (path.endsWith('/rest/v1/transfers') && req.method == 'POST') {
        return http.Response('[]', 201, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      return http.Response('[]', 200, request: req, headers: {
        'content-type': 'application/json',
        'content-range': '*/0',
      });
    });

    final client = SupabaseClient(
      'http://localhost:54321',
      'anon',
      httpClient: mock,
    );
    final service = SupabaseTeamService(client: client);

    final lookup = await client
        .from('players')
        .select('id')
        .or('id.eq.5550000000,phone.eq.5550000000,phone_raw10.eq.5550000000')
        .limit(1);
    expect(lookup, isA<List>());
    expect((lookup as List).isNotEmpty, true);

    await service.upsertRosterEntry(
      tournamentId: 'league-1',
      teamId: 'team-1',
      playerPhone: '5550000000',
      playerName: 'Test Player',
      jerseyNumber: '10',
      role: 'Futbolcu',
      caller: 'test',
    );

    final write = requests.where((r) => r.url.path.endsWith('/rest/v1/league_team_players')).toList();
    expect(
      write.length,
      1,
      reason: requests.map(dumpReq).join('\n\n'),
    );
    expect(write.single.method, anyOf('POST', 'PUT', 'PATCH'));

    final decoded = jsonDecode(write.single.body);
    final row = (decoded is List ? decoded.single : decoded as Map).cast<String, dynamic>();
    expect(row['league_id'], 'league-1');
    expect(row['team_id'], 'team-1');
    expect(row['player_id'], 'player-1');
    expect(row['jersey_number'], '10');
    expect(row['role'], 'Futbolcu');
  });

  test('deleteRosterEntry deletes from league_team_players with league_id, team_id, player_id', () async {
    final requests = <http.Request>[];

    String dumpReq(http.Request r) =>
        '${r.method} ${r.url}\naccept=${r.headers['accept']}\nprefer=${r.headers['prefer']}';

    final mock = MockClient((req) async {
      requests.add(req);

      final path = req.url.path;
      if (path.endsWith('/rest/v1/players') && req.method == 'GET') {
        final accept = req.headers['accept'] ?? '';
        final body = accept.contains('vnd.pgrst.object')
            ? jsonEncode({'id': 'player-1'})
            : jsonEncode([{'id': 'player-1'}]);
        return http.Response(body, 200, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      if (path.endsWith('/rest/v1/league_team_players') && req.method == 'DELETE') {
        return http.Response('[]', 200, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '*/0',
        });
      }

      if (path.endsWith('/rest/v1/transfers') && req.method == 'POST') {
        return http.Response('[]', 201, request: req, headers: {
          'content-type': 'application/json',
          'content-range': '0-0/1',
        });
      }

      return http.Response('[]', 200, request: req, headers: {
        'content-type': 'application/json',
        'content-range': '*/0',
      });
    });

    final client = SupabaseClient(
      'http://localhost:54321',
      'anon',
      httpClient: mock,
    );
    final service = SupabaseTeamService(client: client);

    final lookup = await client
        .from('players')
        .select('id')
        .or('id.eq.5550000000,phone.eq.5550000000,phone_raw10.eq.5550000000')
        .limit(1);
    expect(lookup, isA<List>());
    expect((lookup as List).isNotEmpty, true);

    await service.deleteRosterEntry(
      tournamentId: 'league-1',
      teamId: 'team-1',
      playerPhone: '5550000000',
      caller: 'test',
    );

    final del = requests.where((r) => r.url.path.endsWith('/rest/v1/league_team_players')).toList();
    expect(
      del.length,
      1,
      reason: requests.map(dumpReq).join('\n\n'),
    );
    expect(del.single.method, 'DELETE');
    expect(del.single.url.queryParameters['league_id'], 'eq.league-1');
    expect(del.single.url.queryParameters['team_id'], 'eq.team-1');
    expect(del.single.url.queryParameters['player_id'], 'eq.player-1');
  });
}
