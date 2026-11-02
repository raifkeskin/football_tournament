import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_session.dart';
import '../../media_credits/match_crew_sheet.dart';
import '../../media_credits/media_credit.dart';
import '../../media_credits/media_credit_card.dart';
import '../../referees/referee_service.dart';
import '../models/match.dart';
import 'match_weather.dart';

const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFF34D399);

/// Maç detayı › Bilgi sekmesi (Detay'ın solundaki kâğıt ikonu): tarih ve
/// saha, maç saatinin havası, maçın ekibi (hakem, yayıncı, fotoğrafçı).
/// Girilmemiş bilgi gösterilmez.
class MatchInfoTab extends StatefulWidget {
  const MatchInfoTab({
    super.key,
    required this.match,
    this.pitchName,
    this.onDirections,
  });

  final MatchModel match;

  /// Sahalar listesinden çözülmüş ad (yoksa maçtaki ad).
  final String? pitchName;

  /// Sahanın konum linki varsa "Yol tarifi".
  final VoidCallback? onDirections;

  @override
  State<MatchInfoTab> createState() => _MatchInfoTabState();
}

class _MatchInfoTabState extends State<MatchInfoTab>
    with AutomaticKeepAliveClientMixin {
  late List<MediaCredit>? _credits = MediaCreditFeed.memory(
    widget.match.leagueId,
  );

  @override
  bool get wantKeepAlive => true;

  /// Maça özel medya ekibi (yoksa turnuvanın varsayılanları).
  late MatchCrew? _crew = MatchMediaCrew.memory(widget.match.id);

  @override
  void initState() {
    super.initState();
    MediaCreditFeed.changes.addListener(_onCreditsChanged);
    MatchMediaCrew.changes.addListener(_onCrewChanged);
    _loadCredits();
    _loadCrew();
  }

  @override
  void dispose() {
    MediaCreditFeed.changes.removeListener(_onCreditsChanged);
    MatchMediaCrew.changes.removeListener(_onCrewChanged);
    super.dispose();
  }

  void _onCrewChanged() {
    if (MatchMediaCrew.changes.value == widget.match.id) {
      setState(() => _crew = MatchMediaCrew.memory(widget.match.id));
    }
  }

  Future<void> _loadCrew() async {
    try {
      final c = await MatchMediaCrew.fetch(widget.match.id);
      if (mounted) setState(() => _crew = c);
    } catch (_) {
      // Ağ hatasında varsayılanlar görünür.
    }
  }

  void _onCreditsChanged() {
    if (MediaCreditFeed.changes.value == widget.match.leagueId) {
      _loadCredits(fresh: true);
    }
  }

  Future<void> _loadCredits({bool fresh = false}) async {
    final leagueId = widget.match.leagueId;
    if (!fresh && _credits == null) {
      final c = await MediaCreditFeed.cached(leagueId);
      if (mounted && c != null) setState(() => _credits = c);
    }
    try {
      final c = await MediaCreditFeed.fetch(leagueId);
      if (mounted) setState(() => _credits = c);
    } catch (_) {
      // Ağ hatasında eldeki hâl kalır.
    }
  }

  List<MediaCredit> _crewOf(MediaCreditKind kind) =>
      MatchMediaCrew.resolve(_credits, _crew, kind);

  String? get _when {
    final m = widget.match;
    final d = DateTime.tryParse((m.matchDate ?? '').trim());
    final t = (m.matchTime ?? '').trim();
    final time = t.length >= 5 ? t.substring(0, 5) : t;
    final parts = [
      if (d != null) DateFormat('d MMMM y EEEE', 'tr_TR').format(d),
      if (time.isNotEmpty && time != 'null') time,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final when = _when;
    final pitch = (widget.pitchName ?? widget.match.pitchName ?? '').trim();
    final referee = (widget.match.refereeName ?? '').trim();
    final broadcasts = _crewOf(MediaCreditKind.broadcast);
    final photos = _crewOf(MediaCreditKind.photo);
    final m = widget.match;
    // Admin, kurucu başkan ve bölge sorumlusu maçın ekibini düzenler
    // (sunucu maçın bölgesini ayrıca denetler).
    final session = AppSession.of(context).value;
    final canEditCrew =
        session.canManageLeague(m.leagueId) ||
        session.regionsInSeason(m.seasonId).isNotEmpty;
    final hasReferees =
        referee.isNotEmpty ||
        m.refereeId != null ||
        m.assistantReferee1Id != null ||
        m.assistantReferee2Id != null;
    final hasMedia = broadcasts.isNotEmpty || photos.isNotEmpty;
    final hasCrew = hasReferees || hasMedia || canEditCrew;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      children: [
        if (when != null || pitch.isNotEmpty)
          _Box(
            child: Column(
              children: [
                if (when != null)
                  _IconRow(
                    icon: Icons.calendar_month_rounded,
                    label: 'TARİH',
                    value: when,
                  ),
                if (when != null && pitch.isNotEmpty)
                  const SizedBox(height: 12),
                if (pitch.isNotEmpty)
                  _IconRow(
                    icon: Icons.location_on_outlined,
                    label: 'SAHA',
                    value: pitch,
                    trailing: widget.onDirections == null
                        ? null
                        : FilledButton(
                            onPressed: widget.onDirections,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: const Color(0xFF04150F),
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: const Text('Yol tarifi'),
                          ),
                  ),
              ],
            ),
          ),
        ValueListenableBuilder<MatchWeather?>(
          valueListenable: MatchWeatherService.of(widget.match.id),
          builder: (context, w, _) => w == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _WeatherBox(weather: w, match: widget.match),
                ),
        ),
        if (hasCrew) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(2, canEditCrew ? 8 : 18, 0, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'MAÇIN EKİBİ',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                if (canEditCrew)
                  TextButton.icon(
                    onPressed: () => showMatchCrewSheet(context, m),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Düzenle'),
                    style: TextButton.styleFrom(
                      foregroundColor: _accent,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          if (hasReferees) _RefereesBox(match: m),
          if (hasReferees && hasMedia) const SizedBox(height: 10),
          if (hasMedia)
            _Box(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final b in broadcasts)
                    _CrewRow(
                      name: b.name,
                      badge: _CrewBadge(
                        color: const Color(0x2EEF4444),
                        icon: Icons.videocam_rounded,
                        iconColor: const Color(0xFFF87171),
                        imageUrl: b.avatarUrl,
                      ),
                      role: 'Yayıncı',
                      onTap: () => showMediaCreditCard(context, b),
                    ),
                  for (final p in photos)
                    _CrewRow(
                      name: p.name,
                      badge: _CrewBadge(
                        color: const Color(0x2E38BDF8),
                        icon: Icons.photo_camera_rounded,
                        iconColor: const Color(0xFF38BDF8),
                        imageUrl: p.avatarUrl,
                      ),
                      role: 'Fotoğrafçı',
                      onTap: () => showMediaCreditCard(context, p),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Maçın hakemleri: düdükle orta hakem ortada, altında bayraklarla iki
/// yardımcı hakem aynı satırda (seçilmeyen gösterilmez).
class _RefereesBox extends StatefulWidget {
  const _RefereesBox({required this.match});

  final MatchModel match;

  @override
  State<_RefereesBox> createState() => _RefereesBoxState();
}

class _RefereesBoxState extends State<_RefereesBox> {
  Map<String, Referee> _refs = const {};

  List<String> get _ids => [
    ?widget.match.refereeId,
    ?widget.match.assistantReferee1Id,
    ?widget.match.assistantReferee2Id,
  ];

  @override
  void initState() {
    super.initState();
    _refs = {
      for (final id in _ids)
        if (RefereeService.cached(id) != null) id: RefereeService.cached(id)!,
    };
    _load();
  }

  @override
  void didUpdateWidget(covariant _RefereesBox old) {
    super.didUpdateWidget(old);
    if (old.match.refereeId != widget.match.refereeId ||
        old.match.assistantReferee1Id != widget.match.assistantReferee1Id ||
        old.match.assistantReferee2Id != widget.match.assistantReferee2Id) {
      _load();
    }
  }

  Future<void> _load() async {
    final ids = _ids;
    if (ids.isEmpty || ids.every(_refs.containsKey)) return;
    try {
      final r = await RefereeService.byIds(ids);
      if (mounted) setState(() => _refs = r);
    } catch (_) {
      // Ad okunamazsa eski hakem adı (referee_name) gösterilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final center = _refs[m.refereeId]?.name ?? (m.refereeName ?? '').trim();
    final a1 = _refs[m.assistantReferee1Id]?.name;
    final a2 = _refs[m.assistantReferee2Id]?.name;
    Widget assistant(String name) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flag_outlined, size: 17, color: Color(0xFF38BDF8)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    return _Box(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        children: [
          if (center.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFFFACC15),
                  child: Icon(
                    Icons.sports_rounded,
                    size: 17,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          if (a1 != null || a2 != null) ...[
            if (center.isNotEmpty) const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (a1 != null) Flexible(child: assistant(a1)),
                if (a1 != null && a2 != null) const SizedBox(width: 22),
                if (a2 != null) Flexible(child: assistant(a2)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: child,
  );
}

class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x2410B981),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20, color: _accent),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing!],
    ],
  );
}

class _WeatherBox extends StatelessWidget {
  const _WeatherBox({required this.weather, required this.match});

  final MatchWeather weather;
  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final played =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime ||
        match.status == MatchStatus.finished;
    final sub = [
      played ? 'Maç oynanırken' : 'Maç saatinde',
      if (w.feelsLike != null) 'hissedilen ${w.feelsLike!.round()}°',
    ].join(' · ');
    return _Box(
      child: Column(
        children: [
          Row(
            children: [
              WeatherGlyph(code: w.code, isDay: w.isDay, size: 40),
              const SizedBox(width: 12),
              Text(
                w.tempLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (w.description.isNotEmpty)
                      Text(
                        w.description,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      sub,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WeatherTile(value: '%${w.pop}', label: 'Yağış'),
              const SizedBox(width: 8),
              _WeatherTile(
                value: w.windKmh == null ? '–' : '${w.windKmh!.round()} km/s',
                label: 'Rüzgâr',
              ),
              const SizedBox(width: 8),
              _WeatherTile(
                value: w.humidity == null ? '–' : '%${w.humidity}',
                label: 'Nem',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeatherTile extends StatelessWidget {
  const _WeatherTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: const TextStyle(color: _muted, fontSize: 10.5)),
        ],
      ),
    ),
  );
}

class _CrewBadge extends StatelessWidget {
  const _CrewBadge({
    required this.color,
    required this.icon,
    required this.iconColor,
    this.imageUrl,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    return CircleAvatar(
      radius: 19,
      backgroundColor: color,
      foregroundImage: url.isEmpty ? null : NetworkImage(url),
      child: Icon(icon, size: 18, color: iconColor),
    );
  }
}

class _CrewRow extends StatelessWidget {
  const _CrewRow({
    required this.badge,
    required this.role,
    required this.name,
    this.onTap,
  });

  final Widget badge;
  final String role;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          badge,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(role, style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.white38,
            ),
        ],
      ),
    ),
  );
}
