import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/services/error_reporter.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  static int created = 0;
  @override
  State<_Counter> createState() {
    created++;
    return _CounterState();
  }
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const Text('içerik');
}

void main() {
  testWidgets('gevşek genişlikte (bantlı sütun) tüm alanı kaplar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            SizedBox(height: 50),
            Expanded(
              child: ErrorRecoveryOverlay(child: ColoredBox(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    final size = tester.getSize(find.byType(ColoredBox).last);
    expect(size.width, 800);
    expect(size.height, 550);
  });

  testWidgets('kart açılır, Yenile başlangıç sayfasını açar', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    ErrorReporter.restartHandler = () => nav.currentState!.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const Text('yeni ana sayfa')),
      (_) => false,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => ErrorRecoveryOverlay(child: child!),
        home: const _Counter(),
      ),
    );
    expect(find.text('içerik'), findsOneWidget);
    expect(find.text('Bir sorun oluştu'), findsNothing);

    ErrorReporter.broken.value = true;
    await tester.pump();
    expect(find.text('Bir sorun oluştu'), findsOneWidget);

    await tester.tap(find.text('YENİLE'));
    await tester.pumpAndSettle();
    expect(find.text('Bir sorun oluştu'), findsNothing);
    expect(find.text('yeni ana sayfa'), findsOneWidget);
    expect(find.text('içerik'), findsNothing);
    expect(tester.takeException(), isNull);

    ErrorReporter.broken.value = true;
    await tester.pump();
    await tester.tap(find.text('Kapat'));
    await tester.pump();
    expect(find.text('Bir sorun oluştu'), findsNothing);
    expect(find.text('yeni ana sayfa'), findsOneWidget);
  });
}
