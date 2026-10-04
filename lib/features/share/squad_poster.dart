import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/utils/string_utils.dart';
import '../../core/utils/team_colors.dart';
import 'poster_share.dart';

/// Afişteki oyuncu.
class PosterPlayer {
  const PosterPlayer({
    required this.firstName,
    required this.lastName,
    this.number,
    this.isCaptain = false,
  });

  final String firstName;
  final String lastName;
  final String? number;
  final bool isCaptain;

  /// "Ad Soyad" → ad / soyad (soyad son kelime).
  factory PosterPlayer.fromFullName(
    String name, {
    String? number,
    bool isCaptain = false,
  }) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return PosterPlayer(
      firstName: parts.length > 1
          ? parts.sublist(0, parts.length - 1).join(' ')
          : parts.first,
      lastName: parts.length > 1 ? parts.last : '',
      number: number,
      isCaptain: isCaptain,
    );
  }
}

/// Takım kadrosu afişi: renkler takımın ana / ikinci renginden türetilir
/// ([TeamPalette]); oyuncular mevkiye göre iki sütunlu listede.
class SquadPoster extends StatelessWidget {
  const SquadPoster({
    super.key,
    required this.teamName,
    required this.teamLogo,
    required this.leagueName,
    required this.leagueLogo,
    required this.seasonName,
    required this.palette,
    required this.groups,
  });

  final String teamName;
  final String teamLogo;
  final String leagueName;
  final String leagueLogo;
  final String seasonName;
  final TeamPalette palette;

  /// Mevki adı → oyuncular (sıra korunur).
  final Map<String, List<PosterPlayer>> groups;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final cond = GoogleFonts.barlowCondensed;

    Widget group(String title, List<PosterPlayer> players) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.trUpper,
                  style: cond(
                    color: p.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: p.accent.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${players.length}',
                  style: cond(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              runSpacing: 5,
              children: [
                for (final pl in players)
                  SizedBox(
                    width: (kPosterSize.width - 32) / 2,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            (pl.number ?? '').isEmpty ? '–' : pl.number!,
                            style: cond(
                              color: p.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              text: '${pl.firstName} ',
                              children: [
                                TextSpan(
                                  text: pl.lastName.trUpper,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF1F5F9),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.background, p.backgroundDeep],
        ),
      ),
      child: Stack(
        children: [
          // Sağ üstte takımın ikinci renginde hafif ışıma.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1, -1),
                  radius: 0.9,
                  colors: [
                    p.secondary.withValues(alpha: 0.22),
                    p.secondary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  PosterLogo(
                    url: teamLogo,
                    name: teamName,
                    size: 64,
                    badgeColor: p.primary,
                    badgeTextColor: Colors.white,
                    shadow: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TAKIM KADROSU',
                          style: cond(
                            color: p.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          teamName.trUpper,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: cond(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (leagueLogo.isNotEmpty) ...[
                              PosterLogo(
                                url: leagueLogo,
                                name: leagueName,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                [
                                  leagueName,
                                  seasonName,
                                ].where((e) => e.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              // Kalabalık kadrolarda liste afişe sığacak şekilde küçülür.
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: kPosterSize.width - 32,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final e in groups.entries)
                            if (e.value.isNotEmpty) group(e.key, e.value),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
