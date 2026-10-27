import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/widgets/admin_page.dart' show showAdminPopup;

const _bgDark = Color(0xFF0F172A);
const _mid = Color(0xFF94A3B8);
const _pitch = Color(0xFF2D4468);
const _pitchLine = Color(0xFF8AA2C6);

/// Asıl mevki her zaman turuncu; oynayabildiği mevkiler takım renginde.
const _mainColor = Color(0xFFF97316);

/// Oynayabildiği mevki seçenekleri; bek ve kanatlar sol / sağ ayrı (FIFA
/// gibi). Veritabanı `players_other_positions_check` ile de sınırlar.
const kOtherPositionOptions = <String>[
  'Kaleci',
  'Stoper',
  'Sol Bek',
  'Sağ Bek',
  'Defansif',
  'Merkez',
  'Ofansif',
  'Sol Kanat',
  'Sağ Kanat',
  'Santrfor',
  'Sol Kanat Forvet',
  'Sağ Kanat Forvet',
];

const _maxOther = 3;

/// Alt mevkinin bağlı olduğu ana mevki (hat).
String _lineOf(String position) {
  switch (position) {
    case 'Kaleci':
      return 'Kaleci';
    case 'Stoper':
    case 'Sol Bek':
    case 'Sağ Bek':
      return 'Defans';
    case 'Santrfor':
    case 'Sol Kanat Forvet':
    case 'Sağ Kanat Forvet':
      return 'Forvet';
  }
  return 'Orta Saha';
}

/// Sahadaki yerler (x, y oranı; hücum yukarı).
const _spots = <String, Offset>{
  'Santrfor': Offset(0.5, 0.11),
  'Sol Kanat Forvet': Offset(0.17, 0.17),
  'Sağ Kanat Forvet': Offset(0.83, 0.17),
  'Ofansif': Offset(0.5, 0.30),
  'Sol Kanat': Offset(0.15, 0.42),
  'Sağ Kanat': Offset(0.85, 0.42),
  'Merkez': Offset(0.5, 0.47),
  'Defansif': Offset(0.5, 0.62),
  'Sol Bek': Offset(0.15, 0.73),
  'Sağ Bek': Offset(0.85, 0.73),
  'Stoper': Offset(0.5, 0.79),
  'Kaleci': Offset(0.5, 0.92),
};

/// Asıl mevkinin sahadaki yeri: alt mevki varsa o, yoksa ana mevki (eski
/// serbest değerler dahil). Asıl mevkide taraf tutulmadığından Bek, Kanat
/// ve Kanat Forvet iki yanda birden gösterilir (veritabanı da iki yanı asıl
/// sayar).
Set<String> _mainSpotKeys(String main, String sub) {
  final v = sub.isNotEmpty ? sub : main;
  switch (v) {
    case 'Bek':
    case 'Kanat':
    case 'Kanat Forvet':
      return {'Sol $v', 'Sağ $v'};
    case 'Defans':
      return {'Stoper'};
    case 'Orta Saha':
      return {'Merkez'};
    case 'Forvet':
      return {'Santrfor'};
    case 'On Numara':
      return {'Ofansif'};
  }
  return _spots.containsKey(v) ? {v} : const {};
}

/// Oyuncu kartının "Mevki" sekmesi: asıl mevki büyük turuncu halka,
/// oynayabildiği mevkiler küçük halkalar. Futbolcunun kendisi ve onu
/// yönetenler (admin, kurucu başkan, bölge sorumlusu) "Düzenle" ile asıl
/// mevkiyi ve en çok 3 mevkiyi seçer; futbolcunun asıl mevki değişikliği
/// onaya gider.
class PlayerPositionsTab extends StatefulWidget {
  const PlayerPositionsTab({
    super.key,
    required this.playerId,
    required this.accent,
  });

  final String playerId;
  final Color accent;

  @override
  State<PlayerPositionsTab> createState() => _PlayerPositionsTabState();
}

class _PlayerPositionsTabState extends State<PlayerPositionsTab> {
  SupabaseClient get _sb => Supabase.instance.client;

  bool _loading = true;
  String _main = '';
  String _sub = '';
  List<String> _other = const [];
  bool _canEdit = false;

  /// Yöneten (admin / kurucu başkan / bölge sorumlusu) asıl mevkiyi doğrudan
  /// değiştirir; yalnız futbolcunun kendisiyse talep açılır.
  bool _manages = false;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final session = AppSession.of(context).value;
    var main = '', sub = '';
    var other = <String>[];
    var canEdit = session.isAdmin;
    var manages = session.isAdmin;
    try {
      final r = await _sb
          .from('players')
          .select('main_position, sub_position, other_positions, auth_uid')
          .eq('id', widget.playerId)
          .maybeSingle();
      if (r != null) {
        main = (r['main_position'] ?? '').toString().trim();
        sub = (r['sub_position'] ?? '').toString().trim();
        final o = r['other_positions'];
        if (o is List) other = [for (final x in o) x.toString()];
        final me = _sb.auth.currentUser?.id;
        if (me != null && (r['auth_uid'] ?? '').toString() == me) {
          canEdit = true;
        }
      }
      if (!manages && session.hasManagementPanel) {
        manages =
            await _sb.rpc(
              'owns_player',
              params: {'p_player_id': widget.playerId},
            ) ==
            true;
        canEdit = canEdit || manages;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _main = main;
      _sub = sub;
      _other = other;
      _canEdit = canEdit;
      _manages = manages;
      _loading = false;
    });
  }

  /// [main] true: asıl mevki, false: oynayabildiği mevkiler seçimiyle açılır.
  Future<void> _edit({required bool main}) async {
    final saved = await showAdminPopup<_SavedPositions>(
      context: context,
      builder: (_) => _PositionsEditor(
        initialMainMode: main,
        playerId: widget.playerId,
        mainKeys: _mainSpotKeys(_main, _sub),
        initial: _other,
        accent: widget.accent,
        manages: _manages,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _other = saved.other;
      final m = saved.main;
      if (m != null && !saved.pending) {
        _main = _lineOf(m);
        _sub = m == 'Kaleci' ? '' : m;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.pending
              ? 'Mevkiler kaydedildi; asıl mevki değişikliği onaya gönderildi.'
              : 'Mevkiler kaydedildi.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final mainKeys = _mainSpotKeys(_main, _sub);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Başlıklar yan yana; mevki adları sahada yazar.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              _legend(
                ring: _Ring.main(_mainColor, size: 14),
                label: 'Asıl mevki',
                onEdit: _canEdit ? () => _edit(main: true) : null,
              ),
              _legend(
                ring: _Ring.other(widget.accent, size: 12),
                label: 'Oynayabildiği',
                onEdit: _canEdit ? () => _edit(main: false) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PositionsPitch(
            mainKeys: mainKeys,
            other: _other,
            accent: widget.accent,
          ),
        ],
      ),
    );
  }

  Widget _legend({
    required Widget ring,
    required String label,
    VoidCallback? onEdit,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 18, child: Center(child: ring)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            tooltip: '$label düzenle',
            icon: Icon(Icons.edit_rounded, color: widget.accent, size: 18),
          ),
      ],
    );
  }
}

/// Halka işareti: asıl mevki kalın turuncu, oynayabildiği ince takım renkli.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.color,
    required this.size,
    required this.width,
    required this.dot,
  });

  factory _Ring.main(Color color, {double size = 34}) =>
      _Ring(color: color, size: size, width: size / 8.5, dot: size * 0.32);

  factory _Ring.other(Color color, {double size = 24}) =>
      _Ring(color: color, size: size, width: size / 8, dot: size * 0.34);

  final Color color;
  final double size;
  final double width;
  final double dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: width),
      ),
      alignment: Alignment.center,
      child: Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Saha çizimi; [onTap] verilirse her mevki dokunulabilir olur (düzenleme).
class _PositionsPitch extends StatelessWidget {
  const _PositionsPitch({
    required this.mainKeys,
    required this.other,
    required this.accent,
    this.onTap,
  });

  final Set<String> mainKeys;
  final List<String> other;
  final Color accent;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final editing = onTap != null;
    return AspectRatio(
      aspectRatio: editing ? 0.74 : 0.86,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final line = BorderSide(color: _pitchLine, width: 1.5);
          final children = <Widget>[
            // Orta çizgi, orta yuvarlak ve iki ceza sahası.
            Positioned(
              left: 0,
              right: 0,
              top: h / 2,
              child: Container(height: 1.5, color: _pitchLine),
            ),
            Positioned(
              left: w / 2 - w * 0.14,
              top: h / 2 - w * 0.14,
              child: Container(
                width: w * 0.28,
                height: w * 0.28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(line),
                ),
              ),
            ),
            Positioned(
              left: w * 0.22,
              right: w * 0.22,
              top: 0,
              height: h * 0.15,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: line, right: line, bottom: line),
                ),
              ),
            ),
            Positioned(
              left: w * 0.22,
              right: w * 0.22,
              bottom: 0,
              height: h * 0.15,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: line, right: line, top: line),
                ),
              ),
            ),
          ];

          for (final e in _spots.entries) {
            final key = e.key;
            final isMain = mainKeys.contains(key);
            final isOther = !isMain && other.contains(key);
            if (!editing && !isMain && !isOther) continue;
            final ring = isMain
                ? _Ring.main(_mainColor)
                : isOther
                ? _Ring.other(accent)
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _bgDark.withValues(alpha: 0.35),
                      border: Border.all(color: _pitchLine, width: 2),
                    ),
                  );
            final o = e.value;
            const boxW = 96.0, boxH = 58.0;
            Widget mark = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ring,
                if (editing || isMain || isOther) ...[
                  const SizedBox(height: 2),
                  Text(
                    key,
                    maxLines: 1,
                    style: TextStyle(
                      color: isMain || isOther
                          ? Colors.white
                          : const Color(0xFFC9D6EA),
                      fontSize: 11,
                      fontWeight: isMain || isOther
                          ? FontWeight.w800
                          : FontWeight.w600,
                      shadows: const [Shadow(color: _bgDark, blurRadius: 3)],
                    ),
                  ),
                ],
              ],
            );
            if (editing) {
              mark = Semantics(
                button: true,
                selected: isOther,
                label: isMain ? '$key, asıl mevki' : key,
                child: InkWell(
                  onTap: () => onTap!(key),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: boxW,
                    height: boxH,
                    child: Center(child: mark),
                  ),
                ),
              );
            } else {
              mark = SizedBox(
                width: boxW,
                height: boxH,
                child: Center(child: mark),
              );
            }
            children.add(
              Positioned(
                left: (o.dx * w - boxW / 2).clamp(0, w - boxW),
                top: (o.dy * h - boxH / 2).clamp(0, h - boxH),
                child: mark,
              ),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: _pitch,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4D6890), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: children),
          );
        },
      ),
    );
  }
}

/// Düzenleme sonucu: [main] seçilen asıl mevki (değişmediyse null);
/// [pending] asıl mevki onaya gittiyse true.
class _SavedPositions {
  const _SavedPositions(this.other, {this.main, this.pending = false});

  final List<String> other;
  final String? main;
  final bool pending;
}

/// Mevki düzenleme penceresi: üstte "Asıl mevki" / "Oynayabildiği" seçimi,
/// altta dokunulabilir saha (asıl tek, oynayabildiği en çok 3).
class _PositionsEditor extends StatefulWidget {
  const _PositionsEditor({
    required this.playerId,
    required this.mainKeys,
    required this.initial,
    required this.accent,
    required this.manages,
    this.initialMainMode = false,
  });

  final bool initialMainMode;
  final String playerId;
  final Set<String> mainKeys;
  final List<String> initial;
  final Color accent;
  final bool manages;

  @override
  State<_PositionsEditor> createState() => _PositionsEditorState();
}

class _PositionsEditorState extends State<_PositionsEditor> {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Asıl mevki tek yerdir; kayıtlı değer tarafsız kalmışsa (iki yan) seçim
  /// yeniden yapılana dek ikisi de gösterilir.
  late Set<String> _mainKeys = {...widget.mainKeys};
  late final List<String> _picked = [
    for (final p in widget.initial)
      if (!widget.mainKeys.contains(p) && _spots.containsKey(p)) p,
  ];
  late bool _mainMode = widget.initialMainMode;
  bool _saving = false;

  String? get _newMain {
    if (_mainKeys.length != 1) return null;
    final m = _mainKeys.first;
    return widget.mainKeys.length == 1 && widget.mainKeys.contains(m)
        ? null
        : m;
  }

  void _tap(String key) {
    setState(() {
      if (_mainMode) {
        _mainKeys = {key};
        _picked.remove(key);
        return;
      }
      if (_mainKeys.contains(key)) return;
      if (_picked.contains(key)) {
        _picked.remove(key);
      } else if (_picked.length < _maxOther) {
        _picked.add(key);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asıl mevki dışında en çok 3 mevki seçilebilir.'),
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final main = _newMain;
    var pending = false;
    try {
      if (main != null) {
        if (widget.manages) {
          await _sb.rpc(
            'set_player_main_position',
            params: {'p_player_id': widget.playerId, 'p_position': main},
          );
        } else {
          await _sb.rpc(
            'submit_profile_change',
            params: {
              'p_changes': {
                'main_position': _lineOf(main),
                'sub_position': main == 'Kaleci' ? '' : main,
              },
            },
          );
          pending = true;
        }
      }
      final res = await _sb.rpc(
        'set_player_other_positions',
        params: {'p_player_id': widget.playerId, 'p_positions': _picked},
      );
      if (!mounted) return;
      Navigator.of(context).pop<_SavedPositions>(
        _SavedPositions(
          [
            if (res is List)
              for (final x in res)
                if (!pending || x.toString() != main) x.toString(),
          ],
          main: main,
          pending: pending,
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Widget _segment(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF1F5F9) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _bgDark : _mid,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainText = _mainKeys.length == 1 ? _mainKeys.first : '-';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Mevkiler',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _segment(
                  'Asıl mevki',
                  _mainMode,
                  () => setState(() => _mainMode = true),
                ),
                _segment(
                  'Oynayabildiği (${_picked.length}/$_maxOther)',
                  !_mainMode,
                  () => setState(() => _mainMode = false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _mainMode
                ? widget.manages
                      ? 'Asıl mevkiye dokun.'
                      : 'Asıl mevkiye dokun; değişiklik onaydan sonra geçer.'
                : 'Oynayabildiği diğer yerlere dokun (asıl mevki dışında en çok 3).',
            style: const TextStyle(color: _mid, fontSize: 13),
          ),
          const SizedBox(height: 10),
          _PositionsPitch(
            mainKeys: _mainKeys,
            other: _picked,
            accent: widget.accent,
            onTap: _tap,
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 13),
              children: [
                const TextSpan(
                  text: 'Asıl: ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: mainText),
                const TextSpan(
                  text: ' · Oynayabildiği: ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: _picked.isEmpty ? '-' : _picked.join(', ')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: widget.accent,
              foregroundColor: _bgDark,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Kaydet',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ],
      ),
    );
  }
}
