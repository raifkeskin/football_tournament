import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/utils/friendly_error.dart';
import '../../player/consent/consent_service.dart';
import '../../player/consent/consent_texts.dart';
import '../../player/consent/consent_widgets.dart';

/// Ana sayfa: futbolcunun beyan bekleyen sezonları için sağlık beyanı kartı.
/// Kadrosunda olduğu her aktif sezon için bir kez "oynamama engel bir sağlık
/// durumum yok" beyanı alınır (my_pending_health_seasons). Beyan rapor
/// değildir; yalnız beyan, tarih ve metin sürümü kaydedilir.
/// Yeni özellik: admin her zaman, diğerleri season_health_enabled açıksa.
class SeasonHealthCard extends StatefulWidget {
  const SeasonHealthCard({super.key});

  static bool enabledFor(AppSessionState s) =>
      s.isAdmin || AppSettings.seasonHealthEnabled.value;

  @override
  State<SeasonHealthCard> createState() => _SeasonHealthCardState();
}

class _PendingSeason {
  const _PendingSeason({
    required this.seasonId,
    required this.label,
    required this.team,
  });

  final String seasonId;
  final String label;
  final String team;
}

class _SeasonHealthCardState extends State<SeasonHealthCard> {
  final _sb = Supabase.instance.client;
  List<_PendingSeason> _pending = const [];
  ConsentDoc? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = _sb.auth.currentUser;
    if (u == null || u.isAnonymous) return;
    try {
      final rows = await _sb.rpc('my_pending_health_seasons') as List;
      if (rows.isEmpty) return;
      final doc = await ConsentService().loadDoc();
      final list = [
        for (final r in rows.cast<Map>())
          _PendingSeason(
            seasonId: r['season_id'].toString(),
            label: [
              (r['league_name'] ?? '').toString().trim(),
              (r['season_name'] ?? '').toString().trim(),
            ].where((s) => s.isNotEmpty).join(' · '),
            team: (r['team_name'] ?? '').toString().trim(),
          ),
      ];
      if (mounted) {
        setState(() {
          _pending = list;
          _doc = doc;
        });
      }
    } catch (_) {
      // Okunamazsa kart çıkmaz.
    }
  }

  Future<void> _open() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF16213A),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DeclarationSheet(seasons: _pending, doc: _doc),
    );
    if (done == true && mounted) {
      setState(() => _pending = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sağlık beyanın kaydedildi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pending.isEmpty) return const SizedBox.shrink();
    final names = _pending.map((p) => p.label).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF3A2A0E),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _open,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF92650F)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF78520C),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.health_and_safety_outlined,
                    color: Color(0xFFFDE68A),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sağlık beyanı bekliyor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        names,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFFDE68A),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeclarationSheet extends StatefulWidget {
  const _DeclarationSheet({required this.seasons, required this.doc});

  final List<_PendingSeason> seasons;

  /// Yürürlükteki metinler; beyan metni health_declaration kutusundan gelir.
  final ConsentDoc? doc;

  @override
  State<_DeclarationSheet> createState() => _DeclarationSheetState();
}

class _DeclarationSheetState extends State<_DeclarationSheet> {
  static const _fallbackBody =
      'Katılacağım maçların fiziksel efor gerektirdiğini ve yaralanma, '
      'sakatlanma, düşme, çarpışma gibi riskler barındırabileceğini biliyorum. '
      'Bilgim dâhilinde futbol oynamama engel bir hastalık, sakatlık, sağlık '
      'sorunu veya fiziksel kısıtlılığım bulunmadığını beyan ederim.\n\n'
      'Sağlık durumumda katılımımı etkileyebilecek bir değişiklik olursa '
      'maçlara katılmayacağımı; gerçeğe aykırı beyanımdan doğan sonuçlardan '
      'kendi kusurum ölçüsünde sorumlu olduğumu kabul ederim. Bu beyan, '
      'organizatörlerin ve Lig Masası’nın kendi kusurlarından doğan '
      'sorumluluğunu kaldırmaz.\n\n'
      'Bu beyan sağlık raporu değildir; hastalık, ilaç veya rapor bilgisi '
      'istenmez. Yalnızca beyanın verildiği, tarihi ve metin sürümü kaydedilir '
      've herkese açık yayımlanmaz. Beyan bu sezon için geçerlidir.';

  static const _fallbackCheckbox =
      'Okudum; futbol oynamama engel bir sağlık durumum olmadığını beyan '
      'ediyor, riskleri kabul ediyorum.';

  ConsentItem? get _item => widget.doc?.item('health_declaration');
  String get _version => widget.doc?.version ?? kFallbackConsentVersion;

  bool _checked = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'give_season_health_declarations',
        params: {
          'p_season_ids': [for (final s in widget.seasons) s.seasonId],
          'p_version': _version,
          'p_user_agent': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sağlık ve Risk Beyanı',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              for (final s in widget.seasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.emoji_events_outlined,
                        color: Color(0xFFFDE68A),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.team.isEmpty ? s.label : '${s.label} · ${s.team}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              ConsentBodyText(
                _item?.body ?? _fallbackBody,
                color: const Color(0xFFCBD5E1),
                fontSize: 14,
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _busy
                    ? null
                    : () => setState(() => _checked = !_checked),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _checked,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _checked = v ?? false),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _item?.checkbox ?? _fallbackCheckbox,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFCA5A5)),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _checked && !_busy ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'BEYANI ONAYLA',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
