import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/error_reporter.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../auth/widgets/phone_input.dart';
import 'tournament_request.dart';

// "Turnuvanı Kur": tanıtım + talep formu. Uygulamada fiyat ve ödeme bilgisi
// yok (mağaza kuralı); teklif telefon / WhatsApp ile iletilir.

const _kinds = <(String, String)>[
  ('halisaha', 'Halı saha'),
  ('okul', 'Okul'),
  ('sirket', 'Şirket'),
  ('dernek', 'Dernek'),
  ('master', 'Master'),
  ('diger', 'Diğer'),
];

const _extras = <(String, IconData, String, String)>[
  (
    'setup',
    Icons.upload_file_rounded,
    'Kurulumu siz yapın',
    'Takım ve oyuncu listelerini biz gireriz',
  ),
  (
    'live_draw',
    Icons.casino_outlined,
    'Canlı kura',
    'Grupları uygulamada canlı çekeriz',
  ),
  (
    'instagram',
    Icons.photo_camera_outlined,
    'Instagram paylaşımları',
    'Maç günü ve skor görselleri',
  ),
];

/// Tahmini maç sayısı: gruplar tek / çift devre; eleme varsa takımların
/// yarısına kadar en büyük 2'nin kuvveti kadar takımla tek maç eleme.
int estimateMatches({
  required int teams,
  required int groups,
  required bool doubleRound,
  required bool knockout,
}) {
  final g = groups.clamp(1, teams);
  var total = 0;
  for (var i = 0; i < g; i++) {
    final size = teams ~/ g + (i < teams % g ? 1 : 0);
    total += size * (size - 1) ~/ 2;
  }
  if (doubleRound) total *= 2;
  if (knockout && teams >= 4) {
    var bracket = 2;
    while (bracket * 2 <= teams ~/ 2) {
      bracket *= 2;
    }
    total += bracket - 1;
  }
  return total;
}

class TournamentRequestIntroScreen extends StatelessWidget {
  const TournamentRequestIntroScreen({super.key, this.bandBack = true});

  final bool bandBack;

  static const _features = <(IconData, String, String)>[
    (
      Icons.account_tree_outlined,
      'Fikstür ve Kura',
      'Lig, sezon, grup, playoff ve takımlar; tek ya da çift devre',
    ),
    (
      Icons.bolt_rounded,
      'Canlı Skor',
      'Anlık maç detayı: gol, asist, kart ve canlı yayın takibi',
    ),
    (
      Icons.leaderboard_outlined,
      'Puan Durumu ve İstatistik',
      'Maç sırasında canlı puan durumu; gol krallığı, asist ve kart '
          'listeleri anında güncellenir',
    ),
    (
      Icons.badge_outlined,
      'Takım ve Oyuncu Profilleri',
      'Kadro ve forma numaraları; oyuncu bilgileri, geçmişi ve '
          'istatistikleri',
    ),
    (
      Icons.fact_check_outlined,
      'Esame ve Kart Cezaları',
      'Maç kadrosu telefondan girilir; cezalı oyuncu esamede işaretli',
    ),
    (
      Icons.document_scanner_outlined,
      'Kâğıttan Esame',
      'Kadroyu tek tek eklemeye uğraşma, esamenin fotoğrafını çek; kadro '
          'otomatik maç detayına eklensin',
    ),
    (
      Icons.live_tv_rounded,
      'Canlı Yayın',
      'Maçın canlı yayını uygulamadan izlenir; maç bitiminde gol '
          'kesitleri kısa sürede maç detayına eklenir',
    ),
    (
      Icons.notifications_active_outlined,
      'Bildirimler ve Haberler',
      'Maç saati, gol ve sonuç bildirimleri; maç günü ve sonuç haberleri',
    ),
    (
      Icons.campaign_outlined,
      'Sponsor Alanı ve Paylaşım Görselleri',
      'Sponsor şeridi, maç afişleri ve skor kartları',
    ),
    (
      Icons.groups_outlined,
      'Roller ve Yetkiler',
      'Turnuva, bölge ve takım sorumluları kendi işini kendisi yapar',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Turnuvanı Kur',
      bandBack: bandBack,
      bottomBar: AdminPrimaryButton(
        label: 'TALEP OLUŞTUR',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'TournamentRequestFormScreen'),
            builder: (_) => TournamentRequestFormScreen(bandBack: bandBack),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Icon(Icons.emoji_events_rounded, size: 44, color: kRequestGold),
          const SizedBox(height: 10),
          const Text(
            'Turnuvan artık çok profesyonel',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Canlı skor, puan durumu, oyuncu profilleri ve maç '
            'bildirimleriyle turnuvan bir lig gibi yönetilsin, herkes anında '
            'takip etsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 14),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(Icons.handshake_outlined, 'Kurulumu birlikte yapıyoruz'),
              _Pill(Icons.schedule_rounded, '24 saat içinde dönüş'),
            ],
          ),
          const SizedBox(height: 20),
          AdminFormSection(
            title: 'Turnuvanda neler var?',
            child: AdminFieldGroup(
              children: [
                for (final f in _features)
                  AdminFieldRow(
                    icon: f.$1,
                    label: f.$2,
                    child: Text(
                      f.$3,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const AdminFormSection(
            title: 'Nasıl işliyor?',
            child: AdminFieldGroup(
              children: [
                AdminFieldRow(
                  icon: Icons.edit_note_rounded,
                  label: '1 · Talep',
                  child: _RowText('Turnuvanı birkaç soruda anlat (~2 dk).'),
                ),
                AdminFieldRow(
                  icon: Icons.phone_in_talk_outlined,
                  label: '2 · Görüşme',
                  child: _RowText(
                    'Telefon ya da WhatsApp ile dönüp sana özel teklif '
                    'iletiriz.',
                  ),
                ),
                AdminFieldRow(
                  icon: Icons.rocket_launch_outlined,
                  label: '3 · Yayın',
                  child: _RowText(
                    'Turnuvanı kurarız; kurucu başkan olarak sen yönetirsin.',
                  ),
                ),
              ],
            ),
          ),
          const _Footnote([
            'Destek taleplerine çok hızlı dönüş sağlanır.',
            'Kurulumdan ilk maç gününe kadar adım adım yanındayız.',
            'Takım ve oyuncu listelerini istersen biz gireriz.',
          ]),
        ],
      ),
    );
  }
}

/// Sayfa sonundaki küçük notlar.
class _Footnote extends StatelessWidget {
  const _Footnote(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 14,
                    color: kAdminAccent,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: kAdminAccent),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _RowText extends StatelessWidget {
  const _RowText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// Seçenek düğmeleri (tek seçim).
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in options)
        _Chip(
          label: o.$2,
          selected: o.$1 == value,
          onTap: () => onChanged(o.$1),
        ),
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? kAdminAccent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? kAdminAccent
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ),
  );
}

class TournamentRequestFormScreen extends StatefulWidget {
  const TournamentRequestFormScreen({super.key, this.bandBack = true});

  final bool bandBack;

  @override
  State<TournamentRequestFormScreen> createState() =>
      _TournamentRequestFormScreenState();
}

class _TournamentRequestFormScreenState
    extends State<TournamentRequestFormScreen> {
  static const _steps = ['Turnuva', 'Format', 'Ek istek', 'İletişim'];

  int _step = 0;
  bool _busy = false;
  String? _error;

  bool _infoOnly = false;
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _start = TextEditingController();
  String? _kind;

  int _teams = 8;
  int _groups = 1;
  bool _double = false;
  bool _knockout = false;
  String _format = '7+1';

  final Set<String> _extrasOn = {};

  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _city, _start, _contact, _phone, _org, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _est => estimateMatches(
    teams: _teams,
    groups: _groups,
    doubleRound: _double,
    knockout: _knockout,
  );

  String? _validateStep() {
    if (_step == 0 && _kind == null) return 'Turnuva türünü seçin.';
    if (_step == 3) {
      if (_contact.text.trim().length < 3) return 'Ad soyad gerekli.';
      final raw = normalizePhoneToRaw10(_phone.text);
      if (!RegExp(r'^5\d{9}$').hasMatch(raw)) {
        return 'Geçerli bir cep telefonu girin.';
      }
    }
    return null;
  }

  void _next() {
    final e = _validateStep();
    setState(() => _error = e);
    if (e != null) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _step--;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await Supabase.instance.client.rpc(
        'submit_tournament_request',
        params: {
          'p_info_only': _infoOnly,
          'p_name': _infoOnly ? null : _name.text,
          'p_city': _infoOnly ? null : _city.text,
          'p_start_hint': _infoOnly ? null : _start.text,
          'p_kind': _kind,
          'p_team_count': _teams,
          'p_group_count': _groups,
          'p_double_round': _double,
          'p_knockout': _knockout,
          'p_players_format': _format,
          'p_est_matches': _est,
          'p_extras': _extrasOn.toList(),
          'p_contact_name': _contact.text,
          'p_phone': normalizePhoneToRaw10(_phone.text),
          'p_organization': _org.text,
          'p_note': _note.text,
          'p_platform': ErrorReporter.platform,
          'p_app_version': ErrorReporter.version,
        },
      );
      if (!mounted) return;
      await showAdminInfoDialog(
        context: context,
        icon: Icons.check_circle_rounded,
        iconColor: kAdminAccent,
        title: 'Talebin alındı',
        message:
            'Talep kodun: $code\n24 saat içinde telefon ya da WhatsApp '
            'ile sana dönüş yapacağız.',
      );
      if (!mounted) return;
      // Tanıtım ve form kapanır.
      Navigator.of(context)
        ..pop()
        ..maybePop();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Gönderilemedi, bağlantını kontrol et.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _step == _steps.length - 1;
    return AdminPageScaffold(
      title: 'Turnuva Talebi',
      bandBack: widget.bandBack,
      bottomBar: Row(
        children: [
          Expanded(
            child: AdminSecondaryButton(
              label: _step == 0 ? 'VAZGEÇ' : 'GERİ',
              onPressed: _busy ? null : _back,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AdminPrimaryButton(
              label: last ? 'GÖNDER' : 'İLERİ',
              icon: last ? Icons.send_rounded : Icons.arrow_forward_rounded,
              busy: _busy,
              onPressed: _next,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _stepper(),
          const SizedBox(height: 18),
          ...switch (_step) {
            0 => _stepTournament(),
            1 => _stepFormat(),
            2 => _stepExtras(),
            _ => _stepContact(),
          },
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kAdminDanger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepper() => Row(
    children: [
      for (var i = 0; i < _steps.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _steps.length - 1 ? 6 : 0),
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? kAdminAccent
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _steps[i],
                  style: TextStyle(
                    color: i == _step ? Colors.white : Colors.white54,
                    fontSize: 11.5,
                    fontWeight: i == _step ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _textRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int maxLength = 120,
    int maxLines = 1,
  }) => AdminFieldRow(
    icon: icon,
    label: label,
    child: TextField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      minLines: maxLines > 1 ? 3 : 1,
      maxLines: maxLines,
      textCapitalization: keyboard == null
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: adminInlineInputDecoration(
        hint: hint,
      ).copyWith(counterText: ''),
    ),
  );

  List<Widget> _stepTournament() => [
    AdminFieldGroup(
      children: [
        SwitchListTile.adaptive(
          value: _infoOnly,
          onChanged: (v) => setState(() => _infoOnly = v),
          activeTrackColor: kAdminAccent,
          secondary: const Icon(
            Icons.info_outline_rounded,
            color: kRequestGold,
          ),
          title: const Text(
            'Bilgi almak istiyorum',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          subtitle: const Text(
            'Turnuvam henüz hazır değil.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    if (!_infoOnly)
      AdminFormSection(
        title: 'Turnuva',
        child: AdminFieldGroup(
          children: [
            _textRow(
              icon: Icons.emoji_events_outlined,
              label: 'Turnuva adı · isteğe bağlı',
              controller: _name,
              hint: 'Örn. Kadıköy Masterlar Kupası',
            ),
            _textRow(
              icon: Icons.place_outlined,
              label: 'Şehir / ilçe · isteğe bağlı',
              controller: _city,
              maxLength: 80,
            ),
            _textRow(
              icon: Icons.event_outlined,
              label: 'Tahmini başlangıç · isteğe bağlı',
              controller: _start,
              hint: 'Örn. Kasım başı',
              maxLength: 60,
            ),
          ],
        ),
      ),
    AdminFormSection(
      title: 'Turnuva türü',
      child: _Choices<String>(
        options: _kinds,
        value: _kind,
        onChanged: (v) => setState(() {
          _kind = v;
          _error = null;
        }),
      ),
    ),
  ];

  List<Widget> _stepFormat() => [
    AdminFormSection(
      title: 'Takım sayısı',
      child: _Choices<int>(
        options: [
          for (final n in const [8, 12, 16, 24, 32]) (n, '$n'),
        ],
        value: _teams,
        onChanged: (v) => setState(() {
          _teams = v;
          if (_groups > v ~/ 2) _groups = 1;
        }),
      ),
    ),
    AdminFormSection(
      title: 'Grup sayısı',
      child: _Choices<int>(
        options: [
          (1, 'Tek lig'),
          for (final g in const [2, 4, 8])
            if (g <= _teams ~/ 2) (g, '$g grup'),
        ],
        value: _groups,
        onChanged: (v) => setState(() => _groups = v),
      ),
    ),
    AdminFormSection(
      title: 'Devre',
      child: _Choices<bool>(
        options: const [(false, 'Tek devre'), (true, 'Çift devre')],
        value: _double,
        onChanged: (v) => setState(() => _double = v),
      ),
    ),
    AdminFormSection(
      title: 'Lig sonrası eleme / kupa',
      child: _Choices<bool>(
        options: const [(false, 'Yok'), (true, 'Var')],
        value: _knockout,
        onChanged: (v) => setState(() => _knockout = v),
      ),
    ),
    AdminFormSection(
      title: 'Kaç kişilik',
      child: _Choices<String>(
        options: const [
          ('5+1', '5+1'),
          ('6+1', '6+1'),
          ('7+1', '7+1'),
          ('11', '11'),
        ],
        value: _format,
        onChanged: (v) => setState(() => _format = v),
      ),
    ),
    AdminFieldGroup(
      children: [
        AdminFieldRow(
          icon: Icons.calculate_outlined,
          label: 'Tahmini maç sayısı',
          child: Text(
            '$_est maç',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
  ];

  List<Widget> _stepExtras() => [
    AdminFormSection(
      title: 'Ek istekler · isteğe bağlı',
      child: AdminFieldGroup(
        children: [
          for (final e in _extras)
            CheckboxListTile(
              value: _extrasOn.contains(e.$1),
              onChanged: (v) => setState(
                () => v == true ? _extrasOn.add(e.$1) : _extrasOn.remove(e.$1),
              ),
              activeColor: kAdminAccent,
              secondary: Icon(e.$2, color: kAdminAccent),
              title: Text(
                e.$3,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                e.$4,
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
        ],
      ),
    ),
    const Text(
      'Uygulamadaki her şey zaten dahil. Buradaki istekleri görüşmede '
      'konuşuruz.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white54, fontSize: 12.5),
    ),
    const SizedBox(height: 14),
  ];

  List<Widget> _stepContact() => [
    AdminFormSection(
      title: 'İletişim',
      child: AdminFieldGroup(
        children: [
          _textRow(
            icon: Icons.person_outline_rounded,
            label: 'Ad soyad',
            controller: _contact,
            maxLength: 80,
          ),
          _textRow(
            icon: Icons.phone_outlined,
            label: 'Telefon (zorunlu)',
            controller: _phone,
            hint: '(5XX) XXX XX XX',
            keyboard: TextInputType.phone,
            formatters: [PhoneMaskFormatter()],
            maxLength: 20,
          ),
          _textRow(
            icon: Icons.apartment_outlined,
            label: 'Kurum / dernek · isteğe bağlı',
            controller: _org,
          ),
        ],
      ),
    ),
    AdminFormSection(
      title: 'Açıklama · isteğe bağlı',
      child: AdminFieldGroup(
        children: [
          _textRow(
            icon: Icons.edit_note_rounded,
            label: 'Turnuvanı kısaca anlat',
            controller: _note,
            hint:
                'Örn. Maçlar cumartesi akşamları, kart cezalarını '
                'uygulamadan takip etmek istiyoruz.',
            maxLength: 2000,
            maxLines: 6,
          ),
        ],
      ),
    ),
    const Text(
      'Giriş yapmadan da gönderebilirsin; sana telefon ya da WhatsApp ile '
      'dönüş yaparız.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white54, fontSize: 12.5),
    ),
    const SizedBox(height: 14),
  ];
}
