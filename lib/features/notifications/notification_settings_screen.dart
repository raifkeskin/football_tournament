import 'package:flutter/material.dart';

import '../../core/push/notification_prefs.dart';
import '../../core/push/push_card.dart';
import '../../core/services/app_session.dart';
import '../../core/services/service_locator.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';
import '../tournament/models/league.dart';

/// Bildirim ayarları. Giriş yapmış kişi: hangi maçlar, bildirim türleri,
/// haberler, cezalar (yöneticiye yönetim bildirimleri). Misafir: takip
/// ettiği turnuvalar ve bu turnuvalarda hangi bildirimler. Kapatılan tür
/// telefona gitmez, uygulama içi bildirimlerde yine görünür.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const NotificationSettingsScreen()),
  );

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationPrefs? _prefs;
  List<({String leagueId, String league, String team})> _teams = const [];
  Set<String> _leagues = const {};
  late final Stream<List<League>> _allLeagues = ServiceLocator.leagueService
      .watchLeagues();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<Object>([
        NotificationPrefsService.load(),
        NotificationPrefsService.followedTeams(),
        NotificationPrefsService.followedLeagues(),
      ]);
      if (!mounted) return;
      setState(() {
        _prefs = r[0] as NotificationPrefs;
        _teams = r[1] as List<({String leagueId, String league, String team})>;
        _leagues = r[2] as Set<String>;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _prefs = NotificationPrefsService.isGuest
              ? NotificationPrefs.guest
              : const NotificationPrefs(),
        );
      }
    }
  }

  /// İyimser güncelleme: anahtar hemen döner, kayıt arkadan yapılır.
  Future<void> _update(NotificationPrefs next) async {
    final before = _prefs;
    setState(() => _prefs = next);
    try {
      await NotificationPrefsService.save(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = before);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Future<void> _toggleLeague(String id, bool follow) async {
    final before = _leagues;
    setState(() => _leagues = {...before}..toggle(id, follow));
    try {
      await NotificationPrefsService.setFollowedLeague(id, follow);
      // İlk takipte misafir varsayılanları kaydedilir.
      final p = _prefs;
      if (follow && p != null) await NotificationPrefsService.save(p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _leagues = before);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Widget _switchRow({
    required IconData icon,
    required String label,
    required String text,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      onTap: () => onChanged(!value),
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: kAdminAccent,
        onChanged: onChanged,
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final p = _prefs;
    final guest = NotificationPrefsService.isGuest;
    final manager = session.isAdmin || session.ownedLeagueIds.isNotEmpty;
    return AdminPageScaffold(
      title: 'Bildirimler',
      body: p == null
          ? const Center(child: CircularProgressIndicator(color: kAdminAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                const PushCard(showSettingsLink: false),
                const SizedBox(height: 14),
                if (guest) ..._guest(p) else ..._member(p, manager),
                const SizedBox(height: 10),
                const Text(
                  'Kapattığınız bildirimler telefona gelmez; uygulama içi '
                  'bildirimlerde 14 gün durur.',
                  style: TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
    );
  }

  List<Widget> _member(NotificationPrefs p, bool manager) {
    final followed = _teams.isEmpty
        ? 'Ana sayfadan "Takımımı takip et" ile seçilir'
        : _teams.map((t) => t.team).join(', ');
    return [
      AdminFormSection(
        title: 'Hangi maçlar',
        child: AdminFieldGroup(
          children: [
            _switchRow(
              icon: Icons.sports_soccer_rounded,
              label: 'Takımımın maçları',
              text: 'Oyuncusu ya da sorumlusu olduğum takım',
              value: p.scopeMyTeam,
              onChanged: (v) => _update(p.copyWith(scopeMyTeam: v)),
            ),
            _switchRow(
              icon: Icons.star_rounded,
              label: 'Takip ettiğim takımlar',
              text: followed,
              value: p.scopeFollowed,
              onChanged: (v) => _update(p.copyWith(scopeFollowed: v)),
            ),
            _switchRow(
              icon: Icons.radio_button_checked_rounded,
              label: 'Grubumdaki tüm maçlar',
              text: 'Takımımın grubundaki diğer maçlar',
              value: p.scopeGroup,
              onChanged: (v) => _update(p.copyWith(scopeGroup: v)),
            ),
            _switchRow(
              icon: Icons.emoji_events_rounded,
              label: 'Turnuvanın tüm maçları',
              text: 'Turnuvamdaki bütün maçlar',
              value: p.scopeLeague,
              onChanged: (v) => _update(p.copyWith(scopeLeague: v)),
            ),
          ],
        ),
      ),
      ..._matchKinds(p, withReminder: true),
      AdminFormSection(
        title: 'Turnuva',
        child: AdminFieldGroup(
          children: [
            AdminFieldRow(
              icon: Icons.article_rounded,
              label: 'Haberler',
              child: _NewsChoice(
                value: p.news,
                onChanged: (v) => _update(p.copyWith(news: v)),
              ),
            ),
            _switchRow(
              icon: Icons.gavel_rounded,
              label: 'Cezalarım',
              text: 'Onaylanan ceza ve maç sayısı',
              value: p.penalty,
              onChanged: (v) => _update(p.copyWith(penalty: v)),
            ),
          ],
        ),
      ),
      if (manager)
        AdminFormSection(
          title: 'Yönetim',
          child: AdminFieldGroup(
            children: [
              _switchRow(
                icon: Icons.balance_rounded,
                label: 'Onay bekleyen cezalar',
                text: 'Kart cezası girildiğinde',
                value: p.adminPenalty,
                onChanged: (v) => _update(p.copyWith(adminPenalty: v)),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _matchKinds(NotificationPrefs p, {required bool withReminder}) {
    return [
      AdminFormSection(
        title: withReminder ? 'Maç bildirimleri' : 'Takip ettiğim turnuvalarda',
        child: AdminFieldGroup(
          children: [
            _switchRow(
              icon: Icons.event_rounded,
              label: 'Maç planlandı / saat değişti',
              text: 'Tarih ve saat',
              value: p.schedule,
              onChanged: (v) => _update(p.copyWith(schedule: v)),
            ),
            if (withReminder)
              const AdminFieldRow(
                icon: Icons.alarm_rounded,
                label: 'Maç hatırlatma',
                trailing: Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    '2 saat önce',
                    style: TextStyle(
                      color: kAdminMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                child: Text(
                  'Takımımın maçından önce',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            _switchRow(
              icon: Icons.play_circle_outline_rounded,
              label: 'Maç başladı / ilk yarı',
              text: 'Başlama ve ilk yarı skoru',
              value: p.live,
              onChanged: (v) => _update(p.copyWith(live: v)),
            ),
            _switchRow(
              icon: Icons.bolt_rounded,
              label: 'Canlı gol',
              text: 'Skor, dakika, golcü ve asist',
              value: p.goal,
              onChanged: (v) => _update(p.copyWith(goal: v)),
            ),
            _switchRow(
              icon: Icons.sports_score_rounded,
              label: 'Maç sonucu',
              text: 'Maç bitince skor',
              value: p.result,
              onChanged: (v) => _update(p.copyWith(result: v)),
            ),
            if (!withReminder)
              _switchRow(
                icon: Icons.article_rounded,
                label: 'Haberler',
                text: 'Turnuva haberleri',
                value: p.news != 'off',
                onChanged: (v) =>
                    _update(p.copyWith(news: v ? 'league' : 'off')),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _guest(NotificationPrefs p) {
    return [
      AdminFormSection(
        title: 'Takip ettiğim turnuvalar',
        child: StreamBuilder<List<League>>(
          stream: _allLeagues,
          builder: (context, snap) {
            final leagues = snap.data;
            if (leagues == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: kAdminAccent),
                ),
              );
            }
            return AdminFieldGroup(
              children: [
                for (final l in leagues)
                  AdminFieldRow(
                    icon: Icons.emoji_events_rounded,
                    label: _leagues.contains(l.id)
                        ? 'Takip ediliyor'
                        : 'Takip edilmiyor',
                    onTap: () => _toggleLeague(l.id, !_leagues.contains(l.id)),
                    trailing: Switch.adaptive(
                      value: _leagues.contains(l.id),
                      activeTrackColor: kAdminAccent,
                      onChanged: (v) => _toggleLeague(l.id, v),
                    ),
                    child: Row(
                      children: [
                        if (l.logoUrl.isNotEmpty) ...[
                          WebSafeImage(
                            url: l.logoUrl,
                            width: 26,
                            height: 26,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            l.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      ..._matchKinds(p, withReminder: false),
    ];
  }
}

/// Haberler: Kapalı · Bölgem · Tüm turnuva.
class _NewsChoice extends StatelessWidget {
  const _NewsChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('off', 'Kapalı'),
      ('region', 'Bölgem'),
      ('league', 'Tüm turnuva'),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (key, text) in options)
          ChoiceChip(
            label: Text(text),
            selected: value == key,
            onSelected: (_) => onChanged(key),
            showCheckmark: false,
            labelStyle: TextStyle(
              color: value == key ? Colors.white : kAdminMuted,
              fontWeight: FontWeight.w700,
            ),
            selectedColor: kAdminAccent.withValues(alpha: 0.25),
            backgroundColor: Colors.black.withValues(alpha: 0.3),
            side: BorderSide(
              color: value == key
                  ? kAdminAccent.withValues(alpha: 0.6)
                  : Colors.white12,
            ),
          ),
      ],
    );
  }
}

extension on Set<String> {
  void toggle(String id, bool on) => on ? add(id) : remove(id);
}
