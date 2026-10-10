import 'package:flutter/material.dart';

import '../../../core/push/push_card.dart';

import '../../notifications/notification_settings_screen.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../auth/widgets/phone_input.dart';
import '../../home/screens/home_screen.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../match/widgets/match_score_line.dart';
import '../consent/consent_screen.dart';
import '../consent/consent_service.dart';
import '../services/player_profile_service.dart';
import '../widgets/player_card.dart';
import 'edit_my_profile_screen.dart';

const _surface = Color(0xFF1E293B);
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Ör. "22 Eylül 2026".
String _dayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _dateTime(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

BoxDecoration _card({Color? border}) => BoxDecoration(
  color: _surface.withValues(alpha: 0.92),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: border ?? Colors.white.withValues(alpha: 0.08)),
);

/// Giriş yapmış futbolcunun profili: takım seçici, oyuncu kartı, bekleyen
/// profil talebi, sıradaki maç, takımın maçları ve geçmiş talepler.
class MyProfileView extends StatefulWidget {
  const MyProfileView({
    super.key,
    required this.playerId,
    required this.displayName,
    required this.phone,
    this.roleLabels = const [],
    this.onSignOut,
  });

  /// Sayfanın en altındaki "Çıkış yap / Hesabı sil" bağlantısı (yönetim
  /// panelinde çıkış bantta olduğundan verilmez).
  final VoidCallback? onSignOut;

  /// Kartta adın altında gösterilen roller (ör. Futbolcu, Takım Sorumlusu).
  final List<String> roleLabels;

  /// Hesaba bağlı oyuncu kaydı; yoksa "eşleşmedi" görünümü açılır.
  final String? playerId;
  final String? displayName;
  final String phone;

  @override
  State<MyProfileView> createState() => _MyProfileViewState();
}

class _MyProfileViewState extends State<MyProfileView> {
  final _service = PlayerProfileService();
  final _consentService = ConsentService();

  bool _loading = true;
  String? _error;
  MyPlayer? _player;
  List<MyTeam> _teams = const [];
  List<ProfileChangeRequest> _requests = const [];
  MyConsents? _consents;
  int _selected = 0;
  bool _showPlayed = false;
  final _matches = <String, Future<List<TeamMatch>>>{};
  final _stats = <String, Future<MySeasonStats>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MyProfileView old) {
    super.didUpdateWidget(old);
    if (old.playerId != widget.playerId) _load();
  }

  Future<void> _load() async {
    final id = widget.playerId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.loadPlayer(id),
        _service.loadTeams(id),
        _service.listRequests(onlyPending: false, playerId: id),
        _consentService
            .loadMine(id)
            .then<MyConsents?>((c) => c)
            .catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _player = results[0] as MyPlayer?;
        _teams = results[1] as List<MyTeam>;
        _requests = results[2] as List<ProfileChangeRequest>;
        _consents = results[3] as MyConsents?;
        if (_selected >= _teams.length) _selected = 0;
        _matches.clear();
        _stats.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Profil yüklenemedi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Yalnızca taleplerin yenilenmesi (geri çekme / yeni talep sonrası).
  Future<void> _reloadRequests() async {
    final id = widget.playerId;
    if (id == null) return;
    try {
      final r = await _service.listRequests(onlyPending: false, playerId: id);
      if (mounted) setState(() => _requests = r);
    } catch (_) {}
  }

  MyTeam? get _team => _teams.isEmpty ? null : _teams[_selected];

  List<ProfileChangeRequest> get _pending =>
      _requests.where((r) => r.status == ProfileChangeStatus.pending).toList();

  Future<void> _openEdit() async {
    final p = _player;
    if (p == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'EditMyProfileScreen'),
        builder: (_) => EditMyProfileScreen(
          player: p,
          pending: _pending,
          service: _service,
        ),
      ),
    );
    if (saved == true) _reloadRequests();
  }

  Future<void> _withdraw(ProfileChangeRequest r) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Talebi Geri Çek',
      message:
          '${r.fieldLabels.join(', ')} değişikliği geri çekilecek. '
          'Profilin olduğu gibi kalır.',
      confirmLabel: 'GERİ ÇEK',
      icon: Icons.undo_rounded,
    );
    if (!ok) return;
    try {
      await _service.withdraw(r.id);
      await _reloadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Talep geri çekilemedi.')));
    }
  }

  // --- Görünüm ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.playerId == null) {
      return _UnmatchedView(name: widget.displayName, phone: widget.phone);
    }
    if (_loading && _player == null) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    final player = _player;
    if (player == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _error ?? 'Oyuncu kaydı bulunamadı.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          AdminPrimaryButton(label: 'TEKRAR DENE', onPressed: _load),
        ],
      );
    }

    final team = _team;
    final history = _requests
        .where((r) => r.status != ProfileChangeStatus.pending)
        .toList();

    return RefreshIndicator(
      color: kAdminAccent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (_teams.length > 1) ...[
            _teamSwitcher(),
            const SizedBox(height: 14),
          ],
          _playerCard(player, team),
          for (final r in _pending) ...[
            const SizedBox(height: 14),
            _pendingCard(r),
          ],
          const SizedBox(height: 14),
          if (team == null)
            _infoCard(
              Icons.groups_outlined,
              'Henüz aktif bir takım kadrosunda değilsin. Kadroya '
              'eklendiğinde takımının maçları burada görünecek.',
            )
          else
            _matchesSection(team),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 18),
            _historyButton(history),
          ],
          if (widget.onSignOut != null) ...[
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: widget.onSignOut,
                style: TextButton.styleFrom(foregroundColor: kAdminMuted),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Çıkış yap / Hesabı sil'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: kAdminAccent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _teamSwitcher() {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _teams.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = _teams[i];
          final sel = i == _selected;
          return Material(
            color: sel ? kAdminAccent.withValues(alpha: 0.12) : _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: sel
                    ? kAdminAccent.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                _selected = i;
                _showPlayed = false;
              }),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _teamLogo(t.logoUrl, t.color, 28),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shortTeamName(t.teamName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              t.leagueName.isEmpty
                                  ? t.seasonName
                                  : t.leagueName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: kAdminMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _teamLogo(String? url, String? color, double size) {
    final u = (url ?? '').trim();
    if (u.isNotEmpty) {
      return WebSafeImage(
        url: u,
        width: size,
        height: size,
        fit: BoxFit.contain,
        fallbackIconSize: size * 0.7,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: parseHexColor(color) ?? const Color(0xFF334155),
      ),
      child: Icon(
        Icons.shield_outlined,
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }

  Widget _playerCard(MyPlayer p, MyTeam? team) {
    final teamColor = parseHexColor(team?.color) ?? kAdminAccent;
    final position = [
      p.mainPosition,
      p.subPosition,
    ].whereType<String>().where((e) => e.isNotEmpty).toSet().join(' · ');
    final details = [
      if (team?.jerseyNumber != null) '#${team!.jerseyNumber}',
      if (position.isNotEmpty) position,
      if (p.age != null) '${p.age} yaş',
    ].join(' · ');
    final photo = (p.photoUrl ?? '').trim();
    final statsFuture = team == null
        ? null
        : _stats.putIfAbsent(
            team.key,
            () => _service.loadStats(p.id, team.seasonId),
          );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 6, color: teamColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: teamColor, width: 3),
                  ),
                  child: ClipOval(
                    child: photo.isEmpty
                        ? Container(
                            color: const Color(0xFF334155),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white54,
                              size: 44,
                            ),
                          )
                        : WebSafeImage(url: photo, width: 82, height: 82),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isEmpty ? (widget.displayName ?? '-') : p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: const TextStyle(
                            color: kAdminMuted,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (widget.roleLabels.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final r in widget.roleLabels)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: kAdminAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: kAdminAccent.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  r,
                                  style: const TextStyle(
                                    color: kAdminAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (team != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _teamLogo(team.logoUrl, team.color, 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                team.teamName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (statsFuture != null)
            FutureBuilder<MySeasonStats>(
              future: statsFuture,
              builder: (context, snap) {
                final s = snap.data;
                String v(int Function(MySeasonStats) f) =>
                    s == null ? '-' : '${f(s)}';
                return Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      _stat(v((s) => s.matches), 'Maç'),
                      _stat(v((s) => s.goals), 'Gol', kAdminAccent),
                      _stat(v((s) => s.assists), 'Asist'),
                      _stat(v((s) => s.yellow), 'Sarı kart', kAdminAmber),
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _cardButton(
                    icon: Icons.badge_outlined,
                    label: 'Oyuncu kartım',
                    color: kAdminAccent,
                    onTap: () => showPlayerCard(
                      context,
                      playerKey: p.id,
                      number: team?.jerseyNumber?.toString() ?? '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _cardButton(
                    icon: Icons.edit_outlined,
                    label: 'Bilgilerim',
                    color: Colors.white,
                    onTap: _openEdit,
                  ),
                ),
              ],
            ),
          ),
          // İzinler (eksikse sarı) ve bildirim ayarları: aynı düğme dili.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: _consents == null
                      ? const SizedBox.shrink()
                      : _cardButton(
                          icon: _consents!.complete
                              ? Icons.verified_user_outlined
                              : Icons.privacy_tip_outlined,
                          label: _consents!.complete
                              ? 'İzinlerim'
                              : 'Onay eksik',
                          color: _consents!.complete
                              ? Colors.white
                              : kAdminAmber,
                          onTap: _openConsents,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _cardButton(
                    icon: Icons.notifications_none_rounded,
                    label: 'Bildirimler',
                    color: Colors.white,
                    onTap: () => NotificationSettingsScreen.open(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, [Color color = Colors.white]) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: kAdminMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  // --- Bekleyen talep ---------------------------------------------------------

  Widget _pendingCard(ProfileChangeRequest r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(border: kAdminAmber.withValues(alpha: 0.45)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bilgi değişikliği talebin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _chip('Onay bekliyor', kAdminAmber),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_dateTime(r.createdAt)} · turnuva sorumlusuna gönderildi',
            style: const TextStyle(color: kAdminMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          ProfileChangeDiff(request: r),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminDanger,
                side: BorderSide(color: kAdminDanger.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _withdraw(r),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text(
                'Talebi geri çek',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Maçlar ------------------------------------------------------------------

  Widget _matchesSection(MyTeam team) {
    final future = _matches.putIfAbsent(
      team.key,
      () => _service.loadTeamMatches(team),
    );
    return FutureBuilder<List<TeamMatch>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            ),
          );
        }
        if (snap.hasError) {
          return _infoCard(Icons.error_outline, 'Maçlar yüklenemedi.');
        }
        final all = snap.data ?? const <TeamMatch>[];
        final upcoming = all.where((m) => !m.isPlayed).toList()
          ..sort((a, b) {
            final weekA = a.match.week;
            final weekB = b.match.week;
            if (weekA != null && weekB != null && weekA != weekB) {
              return weekA.compareTo(weekB);
            }
            if (weekA != null && weekB == null) return -1;
            if (weekA == null && weekB != null) return 1;
            final x = a.startsAt, y = b.startsAt;
            if (x == null) return 1;
            if (y == null) return -1;
            return x.compareTo(y);
          });
        final played = all.where((m) => m.isPlayed).toList().reversed.toList();
        final next = upcoming.isEmpty ? null : upcoming.first;
        final rest = upcoming.skip(1).toList();
        final list = _showPlayed ? played : rest;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (next != null) ...[
              _nextMatchCard(next),
              const SizedBox(height: 18),
            ],
            _sectionTitle('TAKIMIMIN MAÇLARI'),
            _segmented(rest.length, played.length),
            const SizedBox(height: 10),
            if (list.isEmpty)
              _infoCard(
                Icons.event_busy_outlined,
                _showPlayed
                    ? 'Henüz oynanmış maç yok.'
                    : next == null
                    ? 'Planlanmış maç yok.'
                    : 'Sıradaki maçtan sonra planlanmış maç yok.',
              )
            else
              for (final m in list) _matchRow(m),
          ],
        );
      },
    );
  }

  Widget _segmented(int upcoming, int played) {
    Widget seg(String label, bool sel, VoidCallback onTap) => Expanded(
      child: Material(
        color: sel ? kAdminAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: sel ? const Color(0xFF04120D) : kAdminMuted,
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          seg(
            'Oynanacak ($upcoming)',
            !_showPlayed,
            () => setState(() => _showPlayed = false),
          ),
          const SizedBox(width: 4),
          seg(
            'Oynanan ($played)',
            _showPlayed,
            () => setState(() => _showPlayed = true),
          ),
        ],
      ),
    );
  }

  void _openMatch(MatchModel m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'MatchDetailsScreen'),
        builder: (_) => MatchDetailsScreen(match: m),
      ),
    );
  }

  Widget _nextMatchCard(TeamMatch m) {
    final at = m.startsAt;
    final live =
        m.match.status == MatchStatus.live ||
        m.match.status == MatchStatus.halftime;
    String badge;
    if (live) {
      badge = 'Canlı';
    } else if (at == null) {
      badge = 'Tarih bekleniyor';
    } else {
      final today = DateTime.now();
      final days = DateTime(
        at.year,
        at.month,
        at.day,
      ).difference(DateTime(today.year, today.month, today.day)).inDays;
      badge = days <= 0
          ? 'Bugün'
          : days == 1
          ? 'Yarın'
          : '$days gün kaldı';
    }
    final time = (m.match.matchTime ?? '').trim();

    Widget side(String name, String logo, String? color) => Expanded(
      child: Column(
        children: [
          _teamLogo(logo, color, 52),
          const SizedBox(height: 8),
          Text(
            shortTeamName(name),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openMatch(m.match),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(border: kAdminAccent.withValues(alpha: 0.35)),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'SIRADAKİ MAÇ',
                      style: TextStyle(
                        color: kAdminAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  _chip(badge, live ? kAdminDanger : kAdminAccent),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  side(m.homeName, m.homeLogo, m.homeColor),
                  SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          live
                              ? '${m.match.homeScore} - ${m.match.awayScore}'
                              : (time.length >= 5
                                    ? time.substring(0, 5)
                                    : '--:--'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (at != null)
                          Text(
                            _dayLabel(at),
                            style: const TextStyle(
                              color: kAdminMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  side(m.awayName, m.awayLogo, m.awayColor),
                ],
              ),
              if ((m.pitchName ?? '').isNotEmpty || m.match.week != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: kAdminMuted,
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [
                          if ((m.pitchName ?? '').isNotEmpty) m.pitchName!,
                          if (m.match.week != null) '${m.match.week}. hafta',
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchRow(TeamMatch m) {
    final at = m.startsAt;
    final top = [
      if (at != null) _dayLabel(at),
      if ((m.pitchName ?? '').isNotEmpty) m.pitchName!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openMatch(m.match),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            decoration: _card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (top.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text(
                      top,
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                MatchScoreLine(
                  match: m.match,
                  homeName: m.homeName,
                  awayName: m.awayName,
                  homeLogo: m.homeLogo,
                  awayLogo: m.awayLogo,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Geçmiş --------------------------------------------------------------------

  Widget _historyButton(List<ProfileChangeRequest> items) {
    return Material(
      color: _surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'RequestHistoryScreen'),
            builder: (_) => _RequestHistoryScreen(items: items),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: kAdminAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Geçmiş Taleplerim (${items.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openConsents() async {
    final id = widget.playerId;
    final current = _consents;
    if (id == null || current == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'ConsentScreen'),
        builder: (_) => ConsentScreen(playerId: id, initial: current.granted),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final c = await _consentService.loadMine(id);
      if (mounted) setState(() => _consents = c);
    } catch (_) {}
  }

  /// Onay eksikse uyarı; tamamsa sade bir "onaylandı" satırı (geri almak
  /// ya da metinleri tekrar okumak için).
  Widget _infoCard(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Row(
        children: [
          Icon(icon, color: kAdminMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _chip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

/// Talepteki değişikliklerin eski → yeni listesi (futbolcu ve onay ekranı).
/// Mevki ile alt mevki tek satırda gösterilir.
class ProfileChangeDiff extends StatelessWidget {
  const ProfileChangeDiff({
    super.key,
    required this.request,
    this.showPhoto = true,
  });

  final ProfileChangeRequest request;

  /// Onay ekranı fotoğrafı büyük gösterdiği için satırı gizleyebilir.
  final bool showPhoto;

  @override
  Widget build(BuildContext context) {
    final c = request.changes;
    final p = request.previous;
    final rows = <Widget>[];

    if (showPhoto && c.containsKey(ProfileField.photoUrl)) {
      Widget thumb(String? url, Color border) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2),
        ),
        child: ClipOval(
          child: (url ?? '').isEmpty
              ? Container(
                  color: const Color(0xFF334155),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                )
              : WebSafeImage(url: url!, width: 32, height: 32),
        ),
      );
      rows.add(
        _row(
          ProfileField.label(ProfileField.photoUrl),
          Row(
            children: [
              thumb(p[ProfileField.photoUrl]?.toString(), Colors.white24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: kAdminMuted,
                  size: 16,
                ),
              ),
              thumb(c[ProfileField.photoUrl]?.toString(), kAdminAmber),
            ],
          ),
        ),
      );
    }

    String pos(Map<String, dynamic> m, {Map<String, dynamic>? fallback}) {
      String? v(String k) {
        final x = (m.containsKey(k) ? m[k] : fallback?[k])?.toString().trim();
        return (x ?? '').isEmpty ? null : x;
      }

      return [
        v(ProfileField.mainPosition),
        v(ProfileField.subPosition),
      ].whereType<String>().toSet().join(' · ');
    }

    var positionDone = false;
    for (final k in c.keys) {
      if (k == ProfileField.photoUrl) continue;
      if (k == ProfileField.mainPosition || k == ProfileField.subPosition) {
        if (positionDone) continue;
        positionDone = true;
        rows.add(
          _textRow(
            ProfileField.label(ProfileField.mainPosition),
            pos(p),
            pos(c, fallback: p),
          ),
        );
        continue;
      }
      rows.add(
        _textRow(
          ProfileField.label(k),
          ProfileField.display(k, p[k]),
          ProfileField.display(k, c[k]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            rows[i],
          ],
        ],
      ),
    );
  }

  static Widget _row(String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              color: kAdminMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: value),
      ],
    ),
  );

  static Widget _textRow(String label, String before, String after) => _row(
    label,
    Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: before.isEmpty ? '-' : before,
            style: const TextStyle(
              color: kAdminMuted,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const TextSpan(text: '  →  '),
          TextSpan(text: after.isEmpty ? '-' : after),
        ],
      ),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

/// Hesaba bağlı oyuncu kaydı yoksa.
class _UnmatchedView extends StatelessWidget {
  const _UnmatchedView({required this.name, required this.phone});

  final String? name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAdminAccent.withValues(alpha: 0.15),
            ),
            child: Text(
              n,
              style: const TextStyle(
                color: kAdminAccent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const PushCard(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: _card(),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 42,
                backgroundColor: Color(0xFF334155),
                child: Icon(
                  Icons.person_rounded,
                  color: Colors.white54,
                  size: 44,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                (name ?? '').isEmpty ? 'Futbolcu' : name!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  formatPhoneRaw10(phone),
                  style: const TextStyle(color: kAdminMuted, fontSize: 14),
                ),
              ],
              const SizedBox(height: 10),
              _chip('Oyuncu kaydı eşleşmedi', kAdminAmber),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _card(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kartın ve maçların burada görünecek',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Telefon numaran henüz hiçbir takım kadrosunda yok. Numaran '
                'kadroya eklendiğinde hesabın otomatik eşleşir.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              step(
                '1',
                'Takım sorumluna bu numarayı kadroya eklemesini söyle.',
              ),
              step(
                '2',
                'Turnuva sorumlusu onayladığında oyuncu kartın ve takımının '
                    'maçları bu ekrana gelir.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: kAdminAccent,
              side: BorderSide(color: kAdminAccent.withValues(alpha: 0.6)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'HomeScreen'),
                builder: (_) => const HomeScreen(showCalendar: true),
              ),
            ),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text(
              'Takvime göz at',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

/// Futbolcunun sonuçlanmış profil talepleri: ne değişti, kim ne zaman karar
/// verdi, red sebebi.
class _RequestHistoryScreen extends StatelessWidget {
  const _RequestHistoryScreen({required this.items});

  final List<ProfileChangeRequest> items;

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Geçmiş Taleplerim',
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final r = items[i];
          final (label, color) = switch (r.status) {
            ProfileChangeStatus.approved => ('Onaylandı', kAdminAccent),
            ProfileChangeStatus.rejected => ('Reddedildi', kAdminDanger),
            ProfileChangeStatus.withdrawn => ('Geri çekildi', kAdminMuted),
            ProfileChangeStatus.pending => ('Bekliyor', kAdminAmber),
          };
          final who = r.status == ProfileChangeStatus.withdrawn
              ? 'Senin tarafından geri çekildi'
              : 'Karar: ${r.reviewerName ?? 'turnuva sorumlusu'}';
          final note = (r.reviewNote ?? '').trim();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Talep: ${_dateTime(r.createdAt)}',
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    _chip(label, color),
                  ],
                ),
                const SizedBox(height: 10),
                ProfileChangeDiff(request: r),
                const SizedBox(height: 10),
                Text(
                  [
                    who,
                    _dateTime(r.reviewedAt),
                    if (note.isNotEmpty) 'Not: $note',
                  ].join(' · '),
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
