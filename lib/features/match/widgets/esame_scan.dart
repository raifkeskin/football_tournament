import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';

/// Kağıttan okunup onaylanan esame satırı.
class EsamePick {
  const EsamePick({
    required this.playerId,
    required this.starting,
    this.jersey,
  });

  final String playerId;
  final bool starting;
  final String? jersey;
}

const _consentKey = 'esame_ai_consent_v1';

/// Fotoğraf yapay zekâya (Google Gemini) gitmeden önce bir kez açık onay
/// alınır (App Store 5.1.2); onay cihazda hatırlanır.
Future<bool> _aiConsent(BuildContext context) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_consentKey) == true) return true;
  } catch (_) {}
  if (!context.mounted) return false;
  final ok = await showAdminConfirmDialog(
    context: context,
    title: 'Kağıttan okuma',
    message:
        'Esame kâğıdının fotoğrafı, oyuncu adlarının ve forma numaralarının '
        'okunması için Google Gemini yapay zekâ hizmetine gönderilir. '
        'Fotoğraf saklanmaz ve model eğitiminde kullanılmaz.',
    confirmLabel: 'DEVAM',
    destructive: false,
    icon: Icons.auto_awesome_rounded,
  );
  if (ok) {
    try {
      await prefs?.setBool(_consentKey, true);
    } catch (_) {}
  }
  return ok;
}

const _connectionError =
    'Bağlantı yavaş ya da koptu, esame okunamadı. İnternet bağlantınızı '
    'kontrol edip tekrar deneyin.';

/// Esame kağıdının fotoğrafını kamerayla çektirir ya da galeriden seçtirir, sunucuda (esame-read,
/// Gemini) okutur ve sonucu kontrol penceresinde gösterir. Onaylanan
/// satırlar döner; vazgeçilirse ya da okuma başarısızsa null.
///
/// Kayıt yapılmaz: çağıran ekran sonucu esame formuna doldurur, kullanıcı
/// yine "Kaydet" ile kaydeder.
Future<List<EsamePick>?> scanEsameFromPhoto(
  BuildContext context, {
  required String matchId,
  required String teamId,
  required String teamName,
  required List<PlayerModel> players,
}) async {
  if (!await _aiConsent(context) || !context.mounted) return null;
  final source = await showAdminOptionPicker<ImageSource>(
    context: context,
    title: 'Esame kâğıdı',
    items: const [ImageSource.camera, ImageSource.gallery],
    labelBuilder: (s) =>
        s == ImageSource.camera ? 'Kamerayla çek' : 'Galeriden seç',
  );
  if (source == null || !context.mounted) return null;
  final picked = await ImagePicker().pickImage(
    source: source,
    // Zayıf bağlantıda yükleme uzamasın: el yazısı okumaya 1600 px yeter.
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 75,
  );
  if (picked == null || !context.mounted) return null;

  final bytes = await picked.readAsBytes();
  if (!context.mounted) return null;
  final mime = (picked.mimeType ?? '').startsWith('image/')
      ? picked.mimeType!
      : 'image/jpeg';

  // Okuma 5-20 sn sürer; bu sırada bekleme penceresi açık kalır. Bağlantı
  // takılırsa 45 sn sonra vazgeçilir.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(canPop: false, child: _ReadingDialog()),
  );
  Map<String, dynamic>? data;
  String? error;
  try {
    final res = await Supabase.instance.client.functions
        .invoke(
          'esame-read',
          body: {
            'match_id': matchId,
            'team_id': teamId,
            'image_base64': base64Encode(bytes),
            'mime': mime,
          },
        )
        .timeout(const Duration(seconds: 45));
    data = Map<String, dynamic>.from(res.data as Map);
  } on FunctionException catch (e) {
    final d = e.details;
    error = d is Map && d['error'] != null ? '${d['error']}' : '$d';
  } on TimeoutException {
    error = _connectionError;
  } catch (e) {
    // Bağlantı koptu (ClientException, SocketException): teknik metin yerine.
    final t = '$e';
    error =
        t.contains('ClientException') ||
            t.contains('SocketException') ||
            t.contains('connection')
        ? _connectionError
        : t;
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();

  if (data == null) {
    await showAdminInfoDialog(
      context: context,
      title: 'Okunamadı',
      message: error ?? 'Bilinmeyen hata.',
    );
    return null;
  }

  final byId = {for (final p in players) p.id: p};
  final rows = [
    for (final r in (data['rows'] as List? ?? const []))
      if (r is Map)
        _Row(
          jersey: r['jersey']?.toString(),
          readName: (r['name'] ?? '').toString(),
          readYear: (r['year'] as num?)?.toInt(),
          starting: r['starting'] != false,
          player: byId[r['player_id']],
        ),
  ];
  if (rows.isEmpty) {
    await showAdminInfoDialog(
      context: context,
      title: 'Okunamadı',
      message:
          'Fotoğrafta esame satırı bulunamadı. Daha net bir fotoğraf deneyin.',
    );
    return null;
  }
  if (!context.mounted) return null;

  final readTeam = (data['team_name'] ?? '').toString();
  return showDialog<List<EsamePick>>(
    context: context,
    builder: (_) => _ReviewDialog(
      rows: rows,
      players: players,
      teamName: teamName,
      teamWarning: readTeam.isNotEmpty && _similarity(readTeam, teamName) < 0.4
          ? readTeam
          : null,
    ),
  );
}

class _ReadingDialog extends StatelessWidget {
  const _ReadingDialog();

  @override
  Widget build(BuildContext context) {
    return const Dialog(
      backgroundColor: Color(0xFF1E293B),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 16),
            Flexible(
              child: Text(
                'Esame okunuyor…',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row {
  _Row({
    required this.jersey,
    required this.readName,
    required this.readYear,
    required this.starting,
    required this.player,
  });

  final String? jersey;
  final String readName;
  final int? readYear;
  bool starting;
  PlayerModel? player;
}

/// Türkçe büyük/küçük harf ve aksan farkını yok sayan sadeleştirme.
String _norm(String v) {
  const map = {
    'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', //
    'â': 'a', 'î': 'i', 'û': 'u', '\u0307': '',
  };
  var s = v.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  map.forEach((k, r) => s = s.replaceAll(k, r));
  return s.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
}

/// İki ad arasında 0–1 benzerlik (harf ikilileri, Dice katsayısı).
double _similarity(String a, String b) {
  Set<String> grams(String s) {
    final t = _norm(s).replaceAll(' ', '');
    return {for (var i = 0; i < t.length - 1; i++) t.substring(i, i + 2)};
  }

  final x = grams(a), y = grams(b);
  if (x.isEmpty || y.isEmpty) return 0;
  return 2 * x.intersection(y).length / (x.length + y.length);
}

int? _birthYear(PlayerModel p) => int.tryParse(
  (p.birthDate ?? '')
      .split(RegExp(r'[-./]'))
      .firstWhere((e) => e.length == 4, orElse: () => ''),
);

/// Satırın güveni: 2 kesin (ad ve yıl uyuşuyor), 1 kontrol edin, 0 eşleşmedi.
int _confidence(_Row r) {
  final p = r.player;
  if (p == null) return 0;
  final nameOk = _similarity(r.readName, p.name) >= 0.6;
  final year = _birthYear(p);
  final yearOk = r.readYear == null || year == null || r.readYear == year;
  return nameOk && yearOk ? 2 : 1;
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.rows,
    required this.players,
    required this.teamName,
    this.teamWarning,
  });

  final List<_Row> rows;
  final List<PlayerModel> players;
  final String teamName;

  /// Formda okunan takım adı, seçili takıma benzemiyorsa.
  final String? teamWarning;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFFBBF24);
  static const _red = Color(0xFFF87171);
  static const _blue = Color(0xFF3B82F6);

  Future<void> _pick(_Row r) async {
    const none = PlayerModel(id: '', name: 'Esameye ekleme');
    final taken = {
      for (final x in widget.rows)
        if (x != r && x.player != null) x.player!.id,
    };
    final items = [none, ...widget.players.where((p) => !taken.contains(p.id))];
    final picked = await showAdminOptionPicker<PlayerModel>(
      context: context,
      title: '${r.jersey ?? '-'} · ${r.readName}',
      items: items,
      labelBuilder: (p) {
        final y = _birthYear(p);
        return p.id.isEmpty ? p.name : '${p.name}${y == null ? '' : '  ($y)'}';
      },
      selected: r.player ?? none,
    );
    if (picked == null) return;
    setState(() => r.player = picked.id.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final counts = [0, 0, 0];
    for (final r in rows) {
      counts[_confidence(r)]++;
    }
    final matched = rows.where((r) => r.player != null).toList();

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Okunan Esame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _legend(_green, '${counts[2]} eşleşti'),
                if (counts[1] > 0) _legend(_amber, '${counts[1]} kontrol edin'),
                if (counts[0] > 0) _legend(_red, '${counts[0]} kadroda yok'),
              ],
            ),
          ),
          if (widget.teamWarning != null)
            Container(
              margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _amber.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Formda "${widget.teamWarning}" yazıyor; seçili takım '
                '${widget.teamName}. Doğru takımın kağıdı olduğundan emin olun.',
                style: const TextStyle(color: _amber, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _rowTile(rows[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Onaylayınca esame formuna doldurulur; kaydetmek için '
                  'formdaki Kaydet düğmesine basın.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: matched.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final r in matched)
                              EsamePick(
                                playerId: r.player!.id,
                                starting: r.starting,
                                jersey: r.jersey,
                              ),
                          ]),
                    child: Text(
                      'Esameye Doldur (${matched.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(color: c, fontSize: 12.5)),
    ],
  );

  Widget _rowTile(_Row r) {
    final conf = _confidence(r);
    final color = [_red, _amber, _green][conf];
    final p = r.player;
    final year = p == null ? null : _birthYear(p);
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pick(r),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  r.jersey ?? '-',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p == null
                          ? 'Kadroda bulunamadı'
                          : '${p.name}${year == null ? '' : '  ($year)'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p == null ? _red : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      'Kağıtta: ${r.readName}'
                      '${r.readYear == null ? '' : ' · ${r.readYear}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              // İlk 11 / yedek: dokununca değişir.
              GestureDetector(
                onTap: () => setState(() => r.starting = !r.starting),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: (r.starting ? _green : _blue).withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (r.starting ? _green : _blue).withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                  child: Text(
                    r.starting ? 'İlk 11' : 'Yedek',
                    style: TextStyle(
                      color: r.starting ? _green : _blue,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
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
