import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Turnuva talimatnamesi (statü): sezona bağlı serbest metin. "🏆" ile
/// başlayan satırlar bölüm başlığı olur; ilk başlıktan önceki satırlar
/// talimatnamenin adıdır. Admin ve kurucu başkan düzenler.

/// Yeni özellik: admin her zaman, diğerleri ayar açıksa görür.
bool regulationsVisible(AppSessionState s) =>
    s.isAdmin || AppSettings.regulationsEnabled.value;

bool _canEdit(AppSessionState s, String leagueId) =>
    s.isAdmin || s.ownedLeagueIds.contains(leagueId);

@immutable
class _Regulations {
  const _Regulations({required this.text, this.updatedAt});

  final String text;
  final DateTime? updatedAt;

  bool get isEmpty => text.trim().isEmpty;
}

Future<_Regulations> _load(String seasonId) async {
  final row = await Supabase.instance.client
      .from('seasons')
      .select('regulations, regulations_updated_at')
      .eq('id', seasonId)
      .maybeSingle();
  return _Regulations(
    text: (row?['regulations'] ?? '').toString(),
    updatedAt: DateTime.tryParse('${row?['regulations_updated_at'] ?? ''}'),
  );
}

/// Ayrıştırılmış talimatname: ad ve bölümler.
class _Parsed {
  _Parsed(this.title, this.sections);

  final String title;
  final List<({String title, List<String> lines})> sections;

  static final _lead = RegExp(r'^[\s🏆⚽📌✅🔸🔹•▪️-]+');
  static final _flags = RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true);

  factory _Parsed.of(String text) {
    final head = <String>[];
    final sections = <({String title, List<String> lines})>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.trimLeft().startsWith('🏆')) {
        sections.add((
          title: line.replaceFirst(_lead, '').trim(),
          lines: <String>[],
        ));
      } else if (sections.isEmpty) {
        if (line.trim().isNotEmpty) head.add(line.trim());
      } else {
        sections.last.lines.add(line);
      }
    }
    final title = head.join(' ').replaceAll(_flags, '').trim();
    if (sections.isEmpty && head.isNotEmpty) {
      return _Parsed('', [(title: 'Talimatname', lines: head)]);
    }
    return _Parsed(title, sections);
  }
}

/// Seçili turnuvanın güncel sezonunun talimatnamesi: Ana Sayfa bandındaki
/// ikon ve menüdeki kısayol buna bakar.
@immutable
class RegulationsRef {
  const RegulationsRef({
    required this.leagueId,
    required this.seasonId,
    required this.seasonName,
    required this.hasText,
  });

  final String leagueId;
  final String seasonId;
  final String seasonName;
  final bool hasText;

  /// Menüde görünsün mü: metin varsa herkese, yoksa düzenleyebilene.
  bool shownTo(AppSessionState s) =>
      regulationsVisible(s) && (hasText || _canEdit(s, leagueId));

  Future<void> open(BuildContext context) async {
    await RegulationsScreen.open(
      context,
      leagueId: leagueId,
      seasonId: seasonId,
      leagueName: ActiveTournament.theme.value?.name ?? '',
      seasonName: seasonName,
    );
    RegulationsShortcut.reload();
  }
}

class RegulationsShortcut {
  RegulationsShortcut._();

  static final current = ValueNotifier<RegulationsRef?>(null);
  static String? _leagueId;

  /// Turnuva değişince güncel sezonun talimatnamesini (Ana Sayfa ile aynı
  /// sezon: aktif, yoksa en yeni) yükler.
  static Future<void> sync(String? leagueId) async {
    if (leagueId == _leagueId) return;
    _leagueId = leagueId;
    current.value = null;
    if (leagueId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('seasons')
          .select('id, name, regulations')
          .eq('league_id', leagueId)
          .order('is_active', ascending: false)
          .order('start_date', ascending: false)
          .limit(1);
      if (_leagueId != leagueId || rows.isEmpty) return;
      final row = rows.first;
      current.value = RegulationsRef(
        leagueId: leagueId,
        seasonId: row['id'].toString(),
        seasonName: (row['name'] ?? '').toString(),
        hasText: (row['regulations'] ?? '').toString().trim().isNotEmpty,
      );
    } catch (_) {}
  }

  static void reload() {
    final id = _leagueId;
    _leagueId = null;
    sync(id);
  }
}

class RegulationsScreen extends StatefulWidget {
  const RegulationsScreen({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.leagueName,
    required this.seasonName,
  });

  final String leagueId;
  final String seasonId;
  final String leagueName;
  final String seasonName;

  static Future<void> open(
    BuildContext context, {
    required String leagueId,
    required String seasonId,
    required String leagueName,
    required String seasonName,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'RegulationsScreen'),
      builder: (_) => RegulationsScreen(
        leagueId: leagueId,
        seasonId: seasonId,
        leagueName: leagueName,
        seasonName: seasonName,
      ),
    ),
  );

  @override
  State<RegulationsScreen> createState() => _RegulationsScreenState();
}

class _RegulationsScreenState extends State<RegulationsScreen> {
  late Future<_Regulations> _future = _load(widget.seasonId);
  final Set<int> _open = {0};

  Future<void> _edit(_Regulations current) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'RegulationsEditScreen'),
        builder: (_) => _RegulationsEditScreen(
          seasonId: widget.seasonId,
          initial: current.text,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _future = _load(widget.seasonId));
    }
  }

  Future<void> _share(String text) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text.trim(),
        subject: '${widget.leagueName} talimatnamesi',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSession.of(context).value;
    final canEdit = _canEdit(s, widget.leagueId);
    return AdminPageScaffold(
      title: 'Turnuva Talimatnamesi',
      body: FutureBuilder<_Regulations>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          final p = _Parsed.of(r.text);
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.leagueName.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFE0A526),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.title.isEmpty ? widget.seasonName : p.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (r.updatedAt != null)
                          'Son güncelleme: '
                              '${DateFormat('dd.MM.yyyy', 'tr_TR').format(r.updatedAt!.toLocal())}',
                        if (p.sections.isNotEmpty) '${p.sections.length} bölüm',
                      ].join(' · '),
                      style: const TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (r.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    canEdit
                        ? 'Bu sezon için henüz talimatname eklenmedi. '
                              'Aşağıdaki "Düzenle" ile metni yapıştırın; '
                              '🏆 ile başlayan satırlar bölüm başlığı olur.'
                        : 'Bu sezon için henüz talimatname eklenmedi.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              for (var i = 0; i < p.sections.length; i++)
                _section(i, p.sections[i]),
            ],
          );
        },
      ),
      bottomBar: FutureBuilder<_Regulations>(
        future: _future,
        builder: (context, snap) {
          final r = snap.data;
          if (r == null) return const SizedBox(height: 46);
          return Row(
            children: [
              if (!r.isEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _share(r.text),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Paylaş'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),
              if (!r.isEmpty && canEdit) const SizedBox(width: 10),
              if (canEdit)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _edit(r),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Düzenle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kAdminAccent,
                      minimumSize: const Size.fromHeight(46),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(int i, ({String title, List<String> lines}) sec) {
    final open = _open.contains(i);
    final paragraphs = <String>[];
    for (final l in sec.lines) {
      final t = l.trim();
      if (t.isNotEmpty) paragraphs.add(t);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: open
                ? kAdminAccent.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => open ? _open.remove(i) : _open.add(i)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0A526).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          color: Color(0xFFE0A526),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sec.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                    ),
                  ],
                ),
                if (open && paragraphs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final t in paragraphs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: t.startsWith('-')
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 7, right: 8),
                                  child: Icon(
                                    Icons.circle,
                                    size: 6,
                                    color: Color(0xFFE0A526),
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    t.substring(1).trim(),
                                    style: _body,
                                  ),
                                ),
                              ],
                            )
                          : SelectableText(t, style: _body),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _body = TextStyle(
    color: Color(0xFFCBD5E1),
    fontSize: 13.5,
    height: 1.45,
  );
}

/// Talimatname metnini düzenleme (yapıştır, kaydet).
class _RegulationsEditScreen extends StatefulWidget {
  const _RegulationsEditScreen({required this.seasonId, required this.initial});

  final String seasonId;
  final String initial;

  @override
  State<_RegulationsEditScreen> createState() => _RegulationsEditScreenState();
}

class _RegulationsEditScreenState extends State<_RegulationsEditScreen> {
  late final _ctrl = TextEditingController(text: widget.initial);
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final rows = await Supabase.instance.client
          .from('seasons')
          .update({'regulations': _ctrl.text.trim()})
          .eq('id', widget.seasonId)
          .select('id');
      if (rows.isEmpty) throw Exception('Düzenleme yetkiniz yok.');
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Talimatname kaydedildi.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Talimatnameyi Düzenle',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Metni yapıştırın. 🏆 ile başlayan satırlar bölüm başlığı, '
              '"-" ile başlayan satırlar madde olur. İlk başlıktan önceki '
              'satır talimatnamenin adıdır.',
              style: TextStyle(color: kAdminMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  hintText: '🏆 TURNUVA KURALLARI\n-Maçlar 35 × 2 oynanır…',
                ),
              ),
            ),
          ],
        ),
      ),
      bottomBar: AdminPrimaryButton(
        label: 'KAYDET',
        icon: Icons.check_rounded,
        busy: _saving,
        onPressed: _saving ? null : _save,
      ),
    );
  }
}
