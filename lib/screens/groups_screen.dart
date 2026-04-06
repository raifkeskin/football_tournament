import 'package:flutter/material.dart';

class _GrupTakimi {
  const _GrupTakimi({
    required this.takimAdi,
    required this.puan,
    required this.logoUrl,
  });

  final String takimAdi;
  final int puan;
  final String logoUrl;
}

/// Gruplar ekranı — takım amblemleriyle örnek tablo görünümü.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const takimlar = <_GrupTakimi>[
      _GrupTakimi(takimAdi: 'Galaktikler', puan: 9, logoUrl: ''),
      _GrupTakimi(takimAdi: 'Meteor FC', puan: 6, logoUrl: ''),
      _GrupTakimi(takimAdi: 'Yeşil Vadi', puan: 3, logoUrl: ''),
      _GrupTakimi(takimAdi: 'Kırmızı Şimşek', puan: 1, logoUrl: ''),
    ];

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Gruplar')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: takimlar.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final takim = takimlar[index];
          return Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: ListTile(
              leading: _TakimAmblemi(
                logoUrl: takim.logoUrl,
                takimAdi: takim.takimAdi,
              ),
              title: Text(takim.takimAdi),
              subtitle: const Text('A Grubu'),
              trailing: Text(
                '${takim.puan} P',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TakimAmblemi extends StatelessWidget {
  const _TakimAmblemi({required this.logoUrl, required this.takimAdi});

  final String logoUrl;
  final String takimAdi;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = takimAdi.isNotEmpty ? takimAdi[0].toUpperCase() : '?';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.14),
      ),
      alignment: Alignment.center,
      child: logoUrl.isNotEmpty
          ? ClipOval(
              child: Image.network(
                logoUrl,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            )
          : Text(
              initial,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
    );
  }
}
