import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../media_credits/media_credit.dart';
import '../../media_credits/media_credit_card.dart';
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

  @override
  void initState() {
    super.initState();
    MediaCreditFeed.changes.addListener(_onCreditsChanged);
    _loadCredits();
  }

  @override
  void dispose() {
    MediaCreditFeed.changes.removeListener(_onCreditsChanged);
    super.dispose();
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

  MediaCredit? _credit(MediaCreditKind kind) =>
      _credits?.where((c) => c.kind == kind && c.isActive).firstOrNull;

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
    final broadcast = _credit(MediaCreditKind.broadcast);
    final photo = _credit(MediaCreditKind.photo);
    final hasCrew = referee.isNotEmpty || broadcast != null || photo != null;

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
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 18, 0, 8),
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
          _Box(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                if (referee.isNotEmpty)
                  _CrewRow(
                    name: referee,
                    badge: const _CrewBadge(
                      color: Color(0xFFFACC15),
                      icon: Icons.sports_rounded,
                      iconColor: Color(0xFF0F172A),
                    ),
                    role: 'Hakem',
                  ),
                if (broadcast != null)
                  _CrewRow(
                    name: broadcast.name,
                    badge: _CrewBadge(
                      color: const Color(0x2EEF4444),
                      icon: Icons.videocam_rounded,
                      iconColor: const Color(0xFFF87171),
                      imageUrl: broadcast.avatarUrl,
                    ),
                    role: 'Yayıncı',
                    onTap: () => showMediaCreditCard(context, broadcast),
                  ),
                if (photo != null)
                  _CrewRow(
                    name: photo.name,
                    badge: _CrewBadge(
                      color: const Color(0x2E38BDF8),
                      icon: Icons.photo_camera_rounded,
                      iconColor: const Color(0xFF38BDF8),
                      imageUrl: photo.avatarUrl,
                    ),
                    role: 'Fotoğrafçı',
                    onTap: () => showMediaCreditCard(context, photo),
                  ),
              ],
            ),
          ),
        ],
      ],
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
