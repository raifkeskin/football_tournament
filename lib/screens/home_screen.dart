import 'package:flutter/material.dart';
import '../models/league.dart';

/// Ana sayfa — günün maçları, tarih şeridi ve örnek maç kartları.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Örnek maç verisi (dummy).
class _OrnekMac {
  const _OrnekMac({
    required this.grupAdi,
    required this.evSahibi,
    required this.deplasman,
    required this.evLogoUrl,
    required this.depLogoUrl,
    this.evSkor,
    this.depSkor,
    required this.durumMetni,
    this.canli = false,
    this.basladi = true,
  });

  final String grupAdi;
  final String evSahibi;
  final String deplasman;
  final String evLogoUrl;
  final String depLogoUrl;
  final int? evSkor;
  final int? depSkor;

  /// Üst satırda gösterilecek durum: saat, canlı dakika veya MS.
  final String durumMetni;
  final bool canli;

  /// false ise skor yerine "V" (henüz başlamamış).
  final bool basladi;
}

/// Örnek son dakika haberi.
class _SonDakikaHaber {
  const _SonDakikaHaber({required this.baslik, required this.kaynak});

  final String baslik;
  final String kaynak;
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _gunYaricap = 10;

  static const List<String> _haftaKisa = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  static const List<String> _ayKisa = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];

  /// Koyu yeşil vurgu (tema ile uyumlu sabit ton).
  static const Color _koyuYesil = Color(0xFF1B5E20);

  late final List<DateTime> _tarihler;
  late final ScrollController _tarihScrollController;
  int _seciliIndeks = _gunYaricap;

  /// Seçilen tarihe göre gösterilecek örnek maçlar (sadece demo).
  late final List<_OrnekMac> _ornekMaclar;
  late final List<_SonDakikaHaber> _haberler;
  late final List<League> _turnuvalar;

  @override
  void initState() {
    super.initState();
    final bugun = DateTime.now();
    final gun0 = DateTime(bugun.year, bugun.month, bugun.day);
    _tarihler = List.generate(
      _gunYaricap * 2 + 1,
      (i) => gun0.add(Duration(days: i - _gunYaricap)),
    );
    _tarihScrollController = ScrollController();
    _ornekMaclar = _demoMaclariOlustur();
    _haberler = _demoHaberleriOlustur();
    _turnuvalar = _demoTurnuvalar();
  }

  @override
  void dispose() {
    _tarihScrollController.dispose();
    super.dispose();
  }

  /// Bugün mü (takvim günü).
  bool _bugunMu(DateTime t) {
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  /// Seçilen gün değişince örnek listeyi yenile (demo çeşitliliği).
  List<_OrnekMac> _demoMaclariOlustur() {
    final secilen = _tarihler[_seciliIndeks];
    if (!_bugunMu(secilen)) {
      return [
        _OrnekMac(
          grupAdi: 'B Grubu',
          evSahibi: 'Kartal SK',
          deplasman: 'Sahil FK',
          evLogoUrl: '',
          depLogoUrl: '',
          durumMetni: '20:00',
          basladi: false,
        ),
        _OrnekMac(
          grupAdi: 'A Grubu',
          evSahibi: 'Yıldız',
          deplasman: 'Rüzgar',
          evLogoUrl: '',
          depLogoUrl: '',
          evSkor: 1,
          depSkor: 0,
          durumMetni: 'MS',
        ),
      ];
    }
    return [
      _OrnekMac(
        grupAdi: 'A Grubu',
        evSahibi: 'Galaktikler',
        deplasman: 'Meteor FC',
        evLogoUrl: '',
        depLogoUrl: '',
        durumMetni: '14:00',
        basladi: false,
      ),
      _OrnekMac(
        grupAdi: 'A Grubu',
        evSahibi: 'Yeşil Vadi',
        deplasman: 'Kırmızı Şimşek',
        evLogoUrl: '',
        depLogoUrl: '',
        evSkor: 2,
        depSkor: 1,
        durumMetni: "45' Canlı",
        canli: true,
      ),
      _OrnekMac(
        grupAdi: 'B Grubu',
        evSahibi: 'Sahilspor',
        deplasman: 'Dağcılar',
        evLogoUrl: '',
        depLogoUrl: '',
        evSkor: 3,
        depSkor: 1,
        durumMetni: 'MS',
      ),
    ];
  }

  List<League> _demoTurnuvalar() {
    final now = DateTime.now();
    return [
      League(
        id: 'sl-2026',
        name: 'Süper Lig Turnuvası',
        logoUrl: '',
        country: 'Türkiye',
        startDate: DateTime(now.year, 1, 10),
        endDate: DateTime(now.year, 12, 25),
      ),
      League(
        id: 'cl-2026',
        name: 'Champions Cup',
        logoUrl: '',
        country: 'Avrupa',
        startDate: DateTime(now.year, 2, 5),
        endDate: DateTime(now.year, 11, 15),
      ),
      League(
        id: 'ts-2024',
        name: 'Turnuva Serisi 2024',
        logoUrl: '',
        country: 'Türkiye',
        startDate: DateTime(now.year - 2, 2, 1),
        endDate: DateTime(now.year - 2, 11, 28),
      ),
    ];
  }

  List<League> _aktifTurnuvalar(DateTime now) {
    final gunBasi = DateTime(now.year, now.month, now.day);
    return _turnuvalar
        .where((l) => l.endDate == null || !l.endDate!.isBefore(gunBasi))
        .toList();
  }

  List<League> _gecmisTurnuvalar(DateTime now) {
    final gunBasi = DateTime(now.year, now.month, now.day);
    return _turnuvalar
        .where((l) => l.endDate != null && l.endDate!.isBefore(gunBasi))
        .toList();
  }

  List<_SonDakikaHaber> _demoHaberleriOlustur() {
    return const [
      _SonDakikaHaber(
        baslik: 'Galaktikler, final maçı öncesi son antrenmanını tamamladı.',
        kaynak: 'Turnuva Merkezi',
      ),
      _SonDakikaHaber(
        baslik: 'Yeşil Vadi teknik ekibi sakatlık raporunu açıkladı.',
        kaynak: 'Saha Kenarı',
      ),
      _SonDakikaHaber(
        baslik: 'A Grubu puan durumunda liderlik yarışı kızışıyor.',
        kaynak: 'Spor Bülteni',
      ),
      _SonDakikaHaber(
        baslik: 'Kritik derbi için biletlerin tamamı tükendi.',
        kaynak: 'Kulüp Duyuru',
      ),
    ];
  }

  void _tarihSec(int index) {
    setState(() {
      _seciliIndeks = index;
      _ornekMaclar.clear();
      _ornekMaclar.addAll(_demoMaclariOlustur());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final aktif = _aktifTurnuvalar(now);
    final gecmis = _gecmisTurnuvalar(now);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Günün Maçları')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TarihSeridi(
            tarihler: _tarihler,
            seciliIndeks: _seciliIndeks,
            scrollController: _tarihScrollController,
            bugunMu: _bugunMu,
            onSec: _tarihSec,
            koyuYesil: _koyuYesil,
            haftaKisa: _haftaKisa,
            ayKisa: _ayKisa,
          ),
          _SonDakikaBandi(haberler: _haberler, koyuYesil: _koyuYesil),
          _TurnuvaSatiri(
            baslik: 'Aktif Turnuvalar',
            turnuvalar: aktif,
            vurguRenk: _koyuYesil,
          ),
          if (gecmis.isNotEmpty)
            _TurnuvaSatiri(
              baslik: 'Geçmiş Sezonlar',
              turnuvalar: gecmis,
              vurguRenk: cs.onSurfaceVariant,
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _ornekMaclar.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < _ornekMaclar.length - 1 ? 12 : 0,
                  ),
                  child: _MacKarti(
                    mac: _ornekMaclar[index],
                    koyuYesil: _koyuYesil,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarih şeridinin altında yatay kayan son dakika haber bandı.
class _SonDakikaBandi extends StatelessWidget {
  const _SonDakikaBandi({required this.haberler, required this.koyuYesil});

  final List<_SonDakikaHaber> haberler;
  final Color koyuYesil;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        itemCount: haberler.length,
        itemBuilder: (context, index) {
          final haber = haberler[index];
          return Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: koyuYesil.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Son Dakika',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: koyuYesil,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  haber.baslik,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '• ${haber.kaynak}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TurnuvaSatiri extends StatelessWidget {
  const _TurnuvaSatiri({
    required this.baslik,
    required this.turnuvalar,
    required this.vurguRenk,
  });

  final String baslik;
  final List<League> turnuvalar;
  final Color vurguRenk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            baslik,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(
          height: 74,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: turnuvalar.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final league = turnuvalar[index];
              return Container(
                width: 210,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    _LogoKutusu(
                      isim: league.name,
                      logoUrl: league.logoUrl,
                      kare: true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            league.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            league.country,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: vurguRenk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Üstte yatay kaydırmalı tarih seçici — ortada Bugün koyu yeşil.
class _TarihSeridi extends StatelessWidget {
  const _TarihSeridi({
    required this.tarihler,
    required this.seciliIndeks,
    required this.scrollController,
    required this.bugunMu,
    required this.onSec,
    required this.koyuYesil,
    required this.haftaKisa,
    required this.ayKisa,
  });

  final List<DateTime> tarihler;
  final int seciliIndeks;
  final ScrollController scrollController;
  final bool Function(DateTime) bugunMu;
  final ValueChanged<int> onSec;
  final Color koyuYesil;
  final List<String> haftaKisa;
  final List<String> ayKisa;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          // Yeterli iç yükseklik — küçük ekran / test ortamında taşmayı önler.
          height: 112,
          child: ListView.separated(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            itemCount: tarihler.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final tarih = tarihler[index];
              final secili = index == seciliIndeks;
              final bugun = bugunMu(tarih);

              // Bugün + seçili: koyu yeşil dolgu; diğer seçili günler: pastel vurgu.
              final Color arkaPlan;
              final Color yaziRengi;
              final Color ikincilYazi;
              if (bugun && secili) {
                arkaPlan = koyuYesil;
                yaziRengi = Colors.white;
                ikincilYazi = Colors.white.withValues(alpha: 0.85);
              } else if (secili) {
                arkaPlan = koyuYesil.withValues(alpha: 0.12);
                yaziRengi = koyuYesil;
                ikincilYazi = cs.onSurfaceVariant;
              } else {
                arkaPlan = cs.surfaceContainerHighest.withValues(alpha: 0.65);
                yaziRengi = cs.onSurface;
                ikincilYazi = cs.onSurfaceVariant;
              }

              final ustEtiket = bugun ? 'Bugün' : haftaKisa[tarih.weekday - 1];
              final altEtiket = bugun
                  ? '${tarih.day} ${ayKisa[tarih.month - 1]}'
                  : '${tarih.day} ${ayKisa[tarih.month - 1]}';

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSec(index),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    width: bugun ? 88 : 72,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: arkaPlan,
                      borderRadius: BorderRadius.circular(16),
                      border: secili && !bugun
                          ? Border.all(color: koyuYesil.withValues(alpha: 0.35))
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ustEtiket,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: yaziRengi,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (!bugun) ...[
                          Text(
                            '${tarih.day}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: yaziRengi,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          Text(
                            ayKisa[tarih.month - 1],
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: ikincilYazi,
                              height: 1.1,
                            ),
                          ),
                        ] else
                          Text(
                            altEtiket,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: ikincilYazi,
                              fontWeight: FontWeight.w500,
                              height: 1.1,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Tek maç kartı — M3, düşük yükseltme, pastel yüzey.
class _MacKarti extends StatelessWidget {
  const _MacKarti({required this.mac, required this.koyuYesil});

  final _OrnekMac mac;
  final Color koyuYesil;

  static const Color _canliKirmizi = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lig / grup ve durum satırı
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: koyuYesil.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    mac.grupAdi,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: koyuYesil,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (mac.canli) ...[
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: const BoxDecoration(
                      color: _canliKirmizi,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    mac.durumMetni,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _canliKirmizi,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else
                  Text(
                    mac.durumMetni,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Takımlar ve skor / V
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LogoKutusu(isim: mac.evSahibi, logoUrl: mac.evLogoUrl),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Text(
                    mac.evSahibi,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: mac.basladi
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${mac.evSkor}',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '-',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                '${mac.depSkor}',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'V',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    mac.deplasman,
                    textAlign: TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _LogoKutusu(isim: mac.deplasman, logoUrl: mac.depLogoUrl),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoKutusu extends StatelessWidget {
  const _LogoKutusu({
    required this.isim,
    required this.logoUrl,
    this.kare = false,
  });

  final String isim;
  final String logoUrl;
  final bool kare;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initial = isim.isNotEmpty ? isim[0].toUpperCase() : '?';
    final radius = kare
        ? BorderRadius.circular(10)
        : BorderRadius.circular(999);

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: logoUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: radius,
              child: Image.network(
                logoUrl,
                width: 36,
                height: 36,
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
