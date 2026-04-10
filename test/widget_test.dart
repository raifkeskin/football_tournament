import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:football_tournament/main.dart';

void main() {
  testWidgets('Uygulama açılır ve alt menü görünür', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Ana Sayfa'), findsWidgets);
  }, skip: true);
}
