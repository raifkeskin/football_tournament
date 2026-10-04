import 'package:flutter/material.dart';

import 'league_logo.dart';

const _gold = Color(0xFFE2B845);
const _panel = Color(0xFF152036);
const _accent = Color(0xFF10B981);

/// Fikstür ve puan durumunun üstündeki turnuva kapsülü: logo, turnuva adı ve
/// sezon. Dokununca filtre penceresi açılır; [trailing] (ör. paylaş butonu)
/// sağında durur.
class LeagueFilterCapsule extends StatelessWidget {
  const LeagueFilterCapsule({
    super.key,
    required this.logoUrl,
    required this.leagueName,
    required this.seasonName,
    required this.onTap,
    this.detail,
    this.trailing,
  });

  final String logoUrl;

  /// Sezonun altındaki ince satır (ör. "5. Hafta · Avrupa Yakası").
  final String? detail;
  final String leagueName;
  final String? seasonName;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final season = (seasonName ?? '').trim();
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  LeagueLogo(url: logoUrl, size: 34, fallbackColor: _gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          leagueName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        if (season.isNotEmpty)
                          Text(
                            season,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        if ((detail ?? '').isNotEmpty)
                          Text(
                            detail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// Grup sekmeleri (yalnızca birden fazla grup varsa gösterilir); seçili
/// sekme hafif dolgu ve alt çizgiyle belirtilir.
class GroupSegmentTabs extends StatelessWidget {
  const GroupSegmentTabs({
    super.key,
    required this.groups,
    required this.selectedId,
    required this.onSelect,
  });

  /// (id, ad) sırasıyla.
  final List<({String id, String name})> groups;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final g in groups)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onSelect(g.id),
                child: Container(
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: g.id == selectedId
                        ? Colors.white.withValues(alpha: 0.08)
                        : null,
                    borderRadius: BorderRadius.circular(9),
                    border: g.id == selectedId
                        ? const Border(
                            bottom: BorderSide(color: _accent, width: 2),
                          )
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      g.name,
                      maxLines: 1,
                      style: TextStyle(
                        color: g.id == selectedId
                            ? Colors.white
                            : Colors.white60,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
