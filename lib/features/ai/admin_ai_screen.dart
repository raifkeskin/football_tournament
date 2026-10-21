import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/utils/team_name.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../match/utils/season_match_settings.dart';

/// Yapay Zekâ Yönetimi (yalnız admin):
///  * Sezon bazında esame okuma / gol videosu yakalama aç-kapa (ileride
///    ücretli üyelik özelliği).
///  * Esame ve gol videosu için model (Flash / Pro); sunucu her işlemde
///    okur, uygulama güncellemesi gerekmez.
///  * İşlem başına maliyet (TL, işlem anındaki TCMB kuruyla).
class AdminAiScreen extends StatefulWidget {
  const AdminAiScreen({super.key});

  @override
  State<AdminAiScreen> createState() => _AdminAiScreenState();
}

typedef _Season = ({
  String id,
  String name,
  bool esame,
  bool clips,
  bool autoPublish,
});

class _Op {
  _Op(Map r)
    : at = DateTime.tryParse('${r['at'] ?? ''}')?.toLocal(),
      esame = r['kind'] == 'esame',
      pro = '${r['model'] ?? ''}'.contains('pro'),
      home = shortTeamName('${r['home_name'] ?? ''}'),
      away = shortTeamName('${r['away_name'] ?? ''}'),
      league = '${r['league_name'] ?? ''}',
      tl = (r['cost_try'] as num?)?.toDouble() ?? 0;

  final DateTime? at;
  final bool esame;
  final bool pro;
  final String home;
  final String away;
  final String league;
  final double tl;
}

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

/// 1234.5 → "1.234,50 TL"
String _tl(double v) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$whole,${parts[1]} TL';
}

String _two(int n) => n.toString().padLeft(2, '0');

class _AdminAiScreenState extends State<AdminAiScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  List<LeagueChoice>? _leagues;
  String? _leagueId;
  List<_Season>? _seasons;
  String? _seasonId;

  Map<String, dynamic>? _settings;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<_Op>? _ops;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
    _loadSettings();
    _loadOps();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _loadLeagues() async {
    try {
      final rows = await _sb
          .from('leagues')
          .select('id, name, logo_url, status')
          .order('name');
      final list = [
        for (final r in rows)
          if (r['status'] == 'active')
            LeagueChoice(
              id: r['id'].toString(),
              name: (r['name'] ?? '').toString(),
              logoUrl: (r['logo_url'] ?? '').toString(),
            ),
      ];
      if (!mounted) return;
      final current = ActiveTournament.currentLeagueId.value;
      setState(() {
        _leagues = list;
        _leagueId = list.any((l) => l.id == current)
            ? current
            : list.firstOrNull?.id;
      });
      await _loadSeasons();
    } catch (e) {
      if (mounted) {
        setState(() => _leagues = const []);
        _snack('Turnuvalar yüklenemedi: $e');
      }
    }
  }

  Future<void> _loadSeasons() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      final rows = await _sb
          .from('seasons')
          .select(
            'id, name, is_default, ai_esame_enabled, ai_clips_enabled, '
            'ai_clips_auto_publish',
          )
          .eq('league_id', id)
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false);
      final list = <_Season>[
        for (final r in rows)
          (
            id: r['id'].toString(),
            name: (r['name'] ?? '').toString(),
            esame: r['ai_esame_enabled'] != false,
            clips: r['ai_clips_enabled'] != false,
            autoPublish: r['ai_clips_auto_publish'] != false,
          ),
      ];
      final def = rows
          .where((r) => r['is_default'] == true)
          .firstOrNull?['id']
          ?.toString();
      if (!mounted || id != _leagueId) return;
      setState(() {
        _seasons = list;
        _seasonId = def ?? list.firstOrNull?.id;
      });
    } catch (e) {
      if (mounted) _snack('Sezonlar yüklenemedi: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final r = await _sb.rpc('ai_admin_settings');
      if (mounted) setState(() => _settings = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) _snack('Ayarlar okunamadı: $e');
    }
  }

  Future<void> _loadOps() async {
    final from = _month;
    final to = DateTime(from.year, from.month + 1);
    setState(() => _ops = null);
    try {
      final rows = await _sb.rpc(
        'ai_usage_list',
        params: {
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
        },
      );
      if (!mounted || from != _month) return;
      setState(() => _ops = [for (final r in rows as List) _Op(r as Map)]);
    } catch (e) {
      if (mounted) {
        setState(() => _ops = const []);
        _snack('Kullanım okunamadı: $e');
      }
    }
  }

  Future<void> _pickLeague() async {
    final leagues = _leagues ?? const <LeagueChoice>[];
    final picked = await showAdminOptionPicker<LeagueChoice>(
      context: context,
      title: 'Turnuva',
      items: leagues,
      labelBuilder: (l) => l.name,
      selected: leagues.where((l) => l.id == _leagueId).firstOrNull,
    );
    if (picked == null || picked.id == _leagueId) return;
    setState(() {
      _leagueId = picked.id;
      _seasons = null;
      _seasonId = null;
    });
    await _loadSeasons();
  }

  Future<void> _pickSeason() async {
    final seasons = _seasons ?? const <_Season>[];
    final picked = await showAdminOptionPicker<_Season>(
      context: context,
      title: 'Sezon',
      items: seasons,
      labelBuilder: (s) => s.name,
      selected: seasons.where((s) => s.id == _seasonId).firstOrNull,
    );
    if (picked != null) setState(() => _seasonId = picked.id);
  }

  Future<void> _setFlag(
    _Season s, {
    bool? esame,
    bool? clips,
    bool? autoPublish,
  }) async {
    setState(() => _busy = true);
    try {
      await _sb
          .from('seasons')
          .update({
            'ai_esame_enabled': ?esame,
            'ai_clips_enabled': ?clips,
            'ai_clips_auto_publish': ?autoPublish,
          })
          .eq('id', s.id);
      SeasonMatchSettings.invalidate(s.id);
      if (!mounted) return;
      setState(() {
        _seasons = [
          for (final x in _seasons ?? const <_Season>[])
            x.id == s.id
                ? (
                    id: x.id,
                    name: x.name,
                    esame: esame ?? x.esame,
                    clips: clips ?? x.clips,
                    autoPublish: autoPublish ?? x.autoPublish,
                  )
                : x,
        ];
      });
    } catch (e) {
      if (mounted) _snack('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickModel(String purpose) async {
    final current = '${_settings?['ai_model_$purpose'] ?? 'flash'}';
    final picked = await showAdminOptionPicker<String>(
      context: context,
      title: purpose == 'esame' ? 'Esame okuma modeli' : 'Gol videosu modeli',
      items: const ['flash', 'pro'],
      labelBuilder: (m) => m == 'pro'
          ? 'Pro · daha dikkatli, yaklaşık 4 kat pahalı'
          : 'Flash · hızlı ve ucuz (önerilen)',
      selected: current,
    );
    if (picked == null || picked == current) return;
    setState(() => _busy = true);
    try {
      await _sb.rpc(
        'ai_admin_set_model',
        params: {'p_purpose': purpose, 'p_model': picked},
      );
      await _loadSettings();
    } catch (e) {
      if (mounted) _snack('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final items = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final picked = await showAdminOptionPicker<DateTime>(
      context: context,
      title: 'Ay',
      items: items,
      labelBuilder: (d) => '${_months[d.month - 1]} ${d.year}',
      selected: items.where((d) => d == _month).firstOrNull,
    );
    if (picked == null || picked == _month) return;
    _month = picked;
    await _loadOps();
  }

  Widget _switchRow(
    IconData icon,
    String label,
    String hint,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return AdminFieldRow(
      icon: icon,
      label: label,
      onTap: _busy ? null : () => onChanged(!value),
      trailing: Switch(
        value: value,
        activeThumbColor: kAdminAccent,
        onChanged: _busy ? null : onChanged,
      ),
      child: Text(
        hint,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }

  Widget _modelRow(String purpose, IconData icon, String label) {
    final m = '${_settings?['ai_model_$purpose'] ?? 'flash'}';
    return AdminSelectRow(
      icon: icon,
      label: label,
      value: m == 'pro' ? 'Gemini Pro' : 'Gemini Flash',
      placeholder: '',
      onTap: _busy || _settings == null ? null : () => _pickModel(purpose),
    );
  }

  Widget _opRow(_Op o) {
    final at = o.at;
    final when = at == null
        ? ''
        : '${at.day} ${_months[at.month - 1].substring(0, 3)} '
              '${_two(at.hour)}:${_two(at.minute)}';
    final match = o.home.isEmpty && o.away.isEmpty
        ? ''
        : '${o.home} – ${o.away}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Icon(
            o.esame ? Icons.document_scanner_outlined : Icons.movie_outlined,
            color: kAdminAccent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o.esame ? 'Esame okuma' : 'Gol videosu',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (match.isNotEmpty) match,
                    if (when.isNotEmpty) when,
                    o.pro ? 'Pro' : 'Flash',
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _tl(o.tl),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usage() {
    final ops = _ops;
    final rate = double.tryParse('${_settings?['usd_try'] ?? ''}');
    final rateDay = '${_settings?['usd_try_date'] ?? ''}';
    final budgetUsd = double.tryParse(
      '${_settings?['ai_clip_monthly_usd'] ?? ''}',
    );
    final total = (ops ?? const <_Op>[]).fold<double>(0, (a, o) => a + o.tl);
    final esameN = (ops ?? const <_Op>[]).where((o) => o.esame).length;
    final clipsN = (ops?.length ?? 0) - esameN;
    return AdminFormSection(
      title: 'Kullanım',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminFieldGroup(
            children: [
              AdminSelectRow(
                icon: Icons.calendar_month_rounded,
                label: 'Ay',
                value: '${_months[_month.month - 1]} ${_month.year}',
                placeholder: '',
                onTap: _pickMonth,
              ),
              AdminFieldRow(
                icon: Icons.payments_outlined,
                label: 'Toplam',
                child: Text(
                  ops == null
                      ? '…'
                      : [
                          _tl(total),
                          if (budgetUsd != null && rate != null)
                            'bütçe ${_tl(budgetUsd * rate)}',
                        ].join(' / '),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Text(
              [
                if (ops != null) '$esameN esame okuma, $clipsN gol videosu',
                if (rate != null)
                  'Kur: 1 \$ = ${rate.toStringAsFixed(4).replaceAll('.', ',')} TL'
                      '${rateDay.isEmpty ? '' : ' (TCMB $rateDay)'}',
              ].join(' · '),
              style: const TextStyle(color: kAdminMuted, fontSize: 12),
            ),
          ),
          if (ops == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (ops.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Bu ay yapay zekâ kullanılmadı.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kAdminMuted),
              ),
            )
          else
            AdminFieldGroup(children: [for (final o in ops) _opRow(o)]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Yapay Zekâ Yönetimi';
    if (!AppSession.of(context).value.isAdmin) {
      return const AdminPageScaffold(
        title: title,
        body: Center(
          child: Text(
            'Bu ekrana yalnızca admin erişebilir.',
            style: TextStyle(color: kAdminMuted),
          ),
        ),
      );
    }
    final leagues = _leagues;
    final league = leagues?.where((l) => l.id == _leagueId).firstOrNull;
    final season = _seasons?.where((s) => s.id == _seasonId).firstOrNull;
    return AdminPageScaffold(
      title: title,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AdminFormSection(
            title: 'Sezon özellikleri',
            child: AdminFieldGroup(
              children: [
                AdminSelectRow(
                  icon: Icons.emoji_events_rounded,
                  label: 'Turnuva',
                  value: league?.name,
                  placeholder: leagues == null ? '…' : 'Turnuva seçin',
                  onTap: (leagues?.length ?? 0) > 1 && !_busy
                      ? _pickLeague
                      : null,
                ),
                AdminSelectRow(
                  icon: Icons.event_note_rounded,
                  label: 'Sezon',
                  value: season?.name,
                  placeholder: _seasons == null ? '…' : 'Sezon yok',
                  onTap: (_seasons?.length ?? 0) > 1 && !_busy
                      ? _pickSeason
                      : null,
                ),
                if (season != null) ...[
                  _switchRow(
                    Icons.document_scanner_outlined,
                    'Esame okuma',
                    season.esame ? 'Aktif' : 'Pasif',
                    season.esame,
                    (v) => _setFlag(season, esame: v),
                  ),
                  _switchRow(
                    Icons.movie_filter_outlined,
                    'Gol videosu yakalama',
                    season.clips ? 'Aktif' : 'Pasif',
                    season.clips,
                    (v) => _setFlag(season, clips: v),
                  ),
                  if (season.clips)
                    _switchRow(
                      Icons.publish_rounded,
                      'Gol kesitleri otomatik yayınlansın',
                      season.autoPublish
                          ? 'Açık · maç bitince bulunan kesitler hemen '
                                'yayında; sorumlu ±5 sn düzeltebilir'
                          : 'Kapalı · sorumlu kontrol edip onaylayınca '
                                'yayınlanır',
                      season.autoPublish,
                      (v) => _setFlag(season, autoPublish: v),
                    ),
                ],
              ],
            ),
          ),
          AdminFormSection(
            title: 'Model',
            child: AdminFieldGroup(
              children: [
                _modelRow(
                  'esame',
                  Icons.document_scanner_outlined,
                  'Esame okuma',
                ),
                _modelRow('clips', Icons.movie_filter_outlined, 'Gol videosu'),
              ],
            ),
          ),
          _usage(),
        ],
      ),
    );
  }
}
