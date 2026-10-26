import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/widgets/admin_page.dart' show showAdminPopup;

const _bgDark = Color(0xFF0F172A);
const _mid = Color(0xFF94A3B8);
const _pitch = Color(0xFF2D4468);
const _pitchLine = Color(0xFF8AA2C6);

/// Oynayabildiği mevki seçenekleri (alt mevki listesiyle aynı; veritabanı
/// `players_other_positions_check` ile de sınırlar).
const kOtherPositionOptions = <String>[
  'Kaleci',
  'Stoper',
  'Bek',
  'Defansif',
  'Merkez',
  'Ofansif',
  'Kanat',
  'Santrfor',
  'Kanat Forvet',
];

const _maxOther = 3;

/// Sahadaki yerler (x, y oranı; hücum yukarı). Tarafı tutulmayan Bek ve
/// kanatlar iki kanatta birden gösterilir.
const _spots = <String, List<Offset>>{
  'Santrfor': [Offset(0.5, 0.12)],
  'Kanat Forvet': [Offset(0.16, 0.18), Offset(0.84, 0.18)],
  'Ofansif': [Offset(0.5, 0.32)],
  'Kanat': [Offset(0.16, 0.41), Offset(0.84, 0.41)],
  'Merkez': [Offset(0.5, 0.48)],
  'Defansif': [Offset(0.5, 0.62)],
  'Bek': [Offset(0.16, 0.72), Offset(0.84, 0.72)],
  'Stoper': [Offset(0.5, 0.79)],
  'Kaleci': [Offset(0.5, 0.92)],
};

/// Asıl mevkinin sahadaki karşılığı: alt mevki varsa o, yoksa ana mevki
/// (eski serbest değerler dahil).
String? _mainSpotKey(String main, String sub) {
  if (_spots.containsKey(sub)) return sub;
  switch (main) {
    case 'Kaleci':
      return 'Kaleci';
    case 'Defans':
      return 'Stoper';
    case 'Orta Saha':
      return 'Merkez';
    case 'Forvet':
      return 'Santrfor';
    case 'On Numara':
      return 'Ofansif';
    case 'Kanat':
      return 'Kanat';
  }
  return null;
}

/// Oyuncu kartının "Mevki" sekmesi: asıl mevki büyük beyaz halka, oynayabildiği
/// mevkiler küçük halkalar. Futbolcunun kendisi ve onu yönetenler (admin,
/// kurucu başkan, bölge sorumlusu) "Düzenle" ile en çok 3 mevki seçer.
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
      if (!canEdit && session.hasManagementPanel) {
        canEdit =
            await _sb.rpc(
              'owns_player',
              params: {'p_player_id': widget.playerId},
            ) ==
            true;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _main = main;
      _sub = sub;
      _other = other;
      _canEdit = canEdit;
      _loading = false;
    });
  }

  String get _mainLabel {
    if (_sub.isNotEmpty && _sub != _main) {
      return _main.isEmpty ? _sub : '$_main · $_sub';
    }
    return _main.isEmpty ? '-' : _main;
  }

  Future<void> _edit() async {
    final saved = await showAdminPopup<List<String>>(
      context: context,
      builder: (_) => _OtherPositionsEditor(
        playerId: widget.playerId,
        mainKey: _mainSpotKey(_main, _sub),
        initial: _other,
        accent: widget.accent,
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _other = saved);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mevkiler kaydedildi.')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final mainKey = _mainSpotKey(_main, _sub);
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
          _infoRow(
            ring: _Ring.main(Colors.white, size: 14),
            label: 'Asıl mevki',
            value: _mainLabel,
          ),
          const SizedBox(height: 10),
          _infoRow(
            ring: _Ring.other(widget.accent, size: 12),
            label: 'Oynayabildiği',
            value: _other.isEmpty ? '-' : _other.join(' / '),
          ),
          const SizedBox(height: 14),
          _PositionsPitch(
            mainKey: mainKey,
            other: _other,
            accent: widget.accent,
          ),
          if (_canEdit) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _edit,
              icon: Icon(Icons.edit_rounded, color: widget.accent, size: 18),
              label: const Text('Oynayabildiği mevkileri düzenle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                side: BorderSide(color: widget.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow({
    required Widget ring,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        SizedBox(width: 18, child: Center(child: ring)),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(
              color: _mid,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// Halka işareti: asıl mevki kalın beyaz, oynayabildiği ince renkli.
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
    required this.mainKey,
    required this.other,
    required this.accent,
    this.onTap,
  });

  final String? mainKey;
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
            final isMain = key == mainKey;
            final isOther = !isMain && other.contains(key);
            if (!editing && !isMain && !isOther) continue;
            final ring = isMain
                ? _Ring.main(Colors.white)
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
            for (final o in e.value) {
              const boxW = 84.0, boxH = 58.0;
              Widget mark = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ring,
                  if (editing) ...[
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
                        shadows: const [
                          Shadow(color: _bgDark, blurRadius: 3),
                        ],
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
                    onTap: isMain ? null : () => onTap!(key),
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

/// Oynayabildiği mevkileri seçme penceresi (asıl mevki sabit, en çok 3).
class _OtherPositionsEditor extends StatefulWidget {
  const _OtherPositionsEditor({
    required this.playerId,
    required this.mainKey,
    required this.initial,
    required this.accent,
  });

  final String playerId;
  final String? mainKey;
  final List<String> initial;
  final Color accent;

  @override
  State<_OtherPositionsEditor> createState() => _OtherPositionsEditorState();
}

class _OtherPositionsEditorState extends State<_OtherPositionsEditor> {
  late final List<String> _picked = [
    for (final p in widget.initial)
      if (p != widget.mainKey) p,
  ];
  bool _saving = false;

  void _toggle(String key) {
    setState(() {
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
    try {
      final res = await Supabase.instance.client.rpc(
        'set_player_other_positions',
        params: {'p_player_id': widget.playerId, 'p_positions': _picked},
      );
      if (!mounted) return;
      Navigator.of(context).pop<List<String>>([
        if (res is List)
          for (final x in res) x.toString(),
      ]);
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Oynayabildiği mevkiler',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Asıl mevki dışında en çok 3 yere dokun (${_picked.length}/$_maxOther). '
            'Asıl mevki profil düzenlemeden değişir.',
            style: const TextStyle(color: _mid, fontSize: 13),
          ),
          const SizedBox(height: 12),
          _PositionsPitch(
            mainKey: widget.mainKey,
            other: _picked,
            accent: widget.accent,
            onTap: _toggle,
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
