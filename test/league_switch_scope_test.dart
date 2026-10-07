import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/widgets/app_name_band.dart';

final _mainTab = ValueNotifier<bool>(true);

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _mainTab,
      builder: (context, main, _) {
        LeagueSwitchScope.setHome(
          ModalRoute.of(context),
          mainTab: main,
          panelTab: !main,
        );
        return const Text('ana');
      },
    );
  }
}

void main() {
  testWidgets('seçici yalnızca ana sekmede ve ana sayfa üstteyken', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [LeagueSwitchScope.observer],
        home: const _Home(),
      ),
    );
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.enabled.value, isTrue);

    // Kadro gibi bir sayfa açılınca gizlenir.
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('kadro')),
    );
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.enabled.value, isFalse);

    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.enabled.value, isTrue);

    // Diyalog sayfa sayılmaz.
    showDialog<void>(
      context: nav.currentContext!,
      builder: (_) => const Text('diyalog'),
    );
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.enabled.value, isTrue);
    nav.currentState!.pop();
    await tester.pumpAndSettle();

    // Profil / yönetim paneli sekmesi.
    _mainTab.value = false;
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.enabled.value, isFalse);
    expect(LeagueSwitchScope.panel.value, isTrue);

    // Panelden açılan yönetim ekranında da turnuva bandı yok.
    nav.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('takım yönetimi')),
    );
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.panel.value, isTrue);
    nav.currentState!.pop();
    await tester.pumpAndSettle();

    _mainTab.value = true;
    await tester.pumpAndSettle();
    expect(LeagueSwitchScope.panel.value, isFalse);
    expect(LeagueSwitchScope.enabled.value, isTrue);
  });
}
