import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/services/notification_center.dart';
import 'package:football_tournament/core/widgets/notification_bell.dart';

void main() {
  testWidgets('zil: misafirde yok, okunmamış sayısı ve 9+', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NotificationBell())),
    );
    expect(find.byType(Icon), findsNothing);

    NotificationCenter.enabled.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

    NotificationCenter.unread.value = 2;
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);

    NotificationCenter.unread.value = 14;
    await tester.pump();
    expect(find.text('9+'), findsOneWidget);
  });
}
