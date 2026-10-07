import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/sponsors/sponsor_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _s(String id, String tier, String name, int order) => {
  'id': id,
  'league_id': 'L',
  'tier': tier,
  'name': name,
  'logo_url': '',
  'sort_order': order,
  'is_active': true,
};

void main() {
  testWidgets('önce ana sponsorlar kendi süreleriyle, sonra alt sponsor', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sponsor_feed_L': jsonEncode({
        'main': 5,
        'sub': 2,
        'items': [
          _s('1', 'main', 'Ana Bir', 10),
          _s('2', 'main', 'Ana İki', 20),
          _s('3', 'sub', 'Alt Bir', 10),
        ],
      }),
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SponsorStrip(leagueId: 'L')),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Ana Bir'), findsOneWidget);
    expect(find.text('ANA\nSPONSOR'), findsOneWidget);

    // Ana sponsor 5 sn kalır.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Ana İki'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ana İki'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alt Bir'), findsOneWidget);
    expect(find.text('SPONSOR'), findsOneWidget);

    // Alt sponsor 2 sn sonra başa döner.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ana Bir'), findsOneWidget);
  });

  testWidgets('sponsor yoksa şerit çizilmez', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SponsorStrip(leagueId: 'L')),
      ),
    );
    await tester.pump();
    expect(find.byType(GestureDetector), findsNothing);
  });
}
