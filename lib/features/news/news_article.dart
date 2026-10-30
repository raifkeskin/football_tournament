import 'package:flutter/material.dart';

import '../../core/utils/team_colors.dart';
import '../../core/utils/team_name.dart';
import '../tournament/models/league_extras.dart';

/// Haberdeki bir takım (auto_data.home / away).
class ArticleTeam {
  ArticleTeam(Map? m)
    : name = shortTeamName((m?['name'] ?? '').toString()),
      logo = (m?['logo'] ?? '').toString().trim(),
      color = m?['color']?.toString();

  final String name;
  final String logo;
  final String? color;

  Color get band => TeamPalette.of(color, null).background;
}

/// Haberin türü: listede etiket ve süzgeç.
enum NewsKind { result, preview, pick, announcement }

extension NewsItemKind on NewsItem {
  NewsKind get kind {
    if (isMatchResult || isWeekResults) return NewsKind.result;
    if (isMatchPreview || isDayPreview) return NewsKind.preview;
    if (isWeeklyPick) return NewsKind.pick;
    return NewsKind.announcement;
  }

  /// Kart ve listedeki küçük etiket.
  String get tag {
    if (isMatchResult) return 'MAÇ SONUCU';
    if (isWeekResults) return 'HAFTA ÖZETİ';
    if (isMatchPreview || isDayPreview) return 'MAÇ GÜNÜ';
    if (autoKind == 'goal_of_week') return 'HAFTANIN GOLÜ';
    if (autoKind == 'player_of_week') return 'HAFTANIN OYUNCUSU';
    if (autoKind == 'team_of_week') return 'HAFTANIN TAKIMI';
    if (isInstagram) return 'INSTAGRAM';
    return 'DUYURU';
  }
}

/// Bir gol: dakika, atan, hangi takıma yazıldığı.
class _Goal {
  _Goal(
    this.minute,
    this.label,
    this.name, {
    required this.home,
    this.og = false,
  });

  final int minute;
  final String label;
  final String name;
  final bool home;
  final bool og;
}

/// Haberin uzun hâli: maç verisinden kurallarla yazılır (gazete küpürü).
class NewsArticle {
  NewsArticle({
    required this.kicker,
    required this.headline,
    this.deck = '',
    this.paragraphs = const [],
    this.home,
    this.away,
    this.hs,
    this.as,
  });

  final String kicker;
  final String headline;
  final String deck;
  final List<String> paragraphs;

  /// Skor kutusu (maç sonucu); maç gününde saat yazılır.
  final ArticleTeam? home;
  final ArticleTeam? away;
  final int? hs;
  final int? as;

  /// Küpürle anlatılamayan türler (günün programı, Haftanın Seçimi,
  /// Instagram) için null: detayda haberin kendi kartı gösterilir.
  static NewsArticle? of(NewsItem n) {
    final d = n.autoData;
    if (n.isMatchResult && d != null) return _result(n, d);
    if (n.isWeekResults && d != null) return _week(n, d);
    if (n.isMatchPreview && d != null) return _preview(n, d);
    if (n.autoKind == null && n.liveDrawId == null) return _manual(n);
    return null;
  }

  /// Listede ve kartta görünen başlık.
  static String headlineOf(NewsItem n) {
    final a = of(n);
    if (a != null) return a.headline;
    return _firstLine(n.content);
  }

  static String _firstLine(String text) {
    final t = text.trim();
    final nl = t.indexOf('\n');
    return (nl > 0 ? t.substring(0, nl) : t).trim();
  }

  static String _score(int a, int b) => '$a–$b';

  /// Sayının ayrılma eki: 0–3'ten, 1–1'den, 2–0'dan.
  static String _fromSuffix(int n) {
    const byLast = {
      0: "'dan",
      1: "'den",
      2: "'den",
      3: "'ten",
      4: "'ten",
      5: "'ten",
      6: "'dan",
      7: "'den",
      8: "'den",
      9: "'dan",
    };
    const byTen = {
      1: "'dan",
      2: "'den",
      3: "'dan",
      4: "'tan",
      5: "'den",
      6: "'tan",
      7: "'den",
      8: "'den",
      9: "'dan",
    };
    if (n >= 10 && n % 10 == 0) return byTen[(n ~/ 10) % 10] ?? "'dan";
    return byLast[n % 10]!;
  }

  static List<Map> _scorers(Map d, String side) {
    final s = d['scorers'];
    final l = s is Map ? s[side] : null;
    return [
      for (final m in (l as List? ?? const []))
        if (m is Map) m,
    ];
  }

  static NewsArticle _result(NewsItem n, Map<String, dynamic> d) {
    final home = ArticleTeam(d['home'] as Map?);
    final away = ArticleTeam(d['away'] as Map?);
    final hs = (d['hs'] as num?)?.toInt() ?? 0;
    final as = (d['as'] as num?)?.toInt() ?? 0;
    final week = (d['week'] as num?)?.toInt() ?? n.week;

    // Dakikalı goller sıraya dizilir; hepsinin dakikası varsa maçın akışı
    // (öne geçme, eşitleme, geri dönüş) anlatılır.
    final goals = <_Goal>[];
    var allTimed = true;
    for (final side in ['home', 'away']) {
      for (final m in _scorers(d, side)) {
        final name = (m['name'] ?? '').toString();
        final og = m['og'] == true;
        final mins = [
          for (final v in (m['minutes'] as List? ?? const []))
            if (v is num) v.toInt(),
        ];
        final labels = [
          for (final v in (m['labels'] as List? ?? const []))
            if (v != null) v.toString(),
        ];
        final count = (m['n'] as num?)?.toInt() ?? 1;
        if (mins.length != count) allTimed = false;
        for (var i = 0; i < mins.length; i++) {
          goals.add(
            _Goal(
              mins[i],
              i < labels.length ? labels[i] : "${mins[i]}'",
              name,
              home: side == 'home',
              og: og,
            ),
          );
        }
      }
    }
    goals.sort((a, b) => a.minute.compareTo(b.minute));
    final timed = allTimed && goals.length == hs + as && goals.isNotEmpty;

    // Akış: en büyük geriye düşme farkı (geri dönüş başlığı için).
    var h = 0, a = 0, homeWorst = 0, awayWorst = 0;
    var homeWorstScore = '', awayWorstScore = '';
    final sentences = <String>[];
    if (timed) {
      for (final g in goals) {
        final before = h - a;
        g.home ? h++ : a++;
        final team = g.home ? home.name : away.name;
        final who = g.og ? '${g.name} (kendi kalesine)' : g.name;
        final min = g.label.replaceAll("'", '');
        final sc = _score(h, a);
        final after = h - a;
        String s;
        if (h + a == 1) {
          s = '$min. dakikada $who ile $team öne geçti ($sc).';
        } else if (after == 0) {
          s = '$min. dakikada $who skoru eşitledi ($sc).';
        } else if (before == 0) {
          s = '$min. dakikada $who ile $team yeniden öne geçti ($sc).';
        } else if (after.abs() > before.abs() && after.abs() <= 3) {
          s = '$min. dakikada $who farkı ${after.abs()} gole çıkardı ($sc).';
        } else {
          s = after.abs() == 1
              ? '$min. dakikada $who farkı bire indirdi ($sc).'
              : '$min. dakikada $who skoru $sc yaptı.';
        }
        sentences.add(s);
        if (a - h > homeWorst) {
          homeWorst = a - h;
          homeWorstScore = _score(h, a);
        }
        if (h - a > awayWorst) {
          awayWorst = h - a;
          awayWorstScore = _score(a, h);
        }
      }
    }

    // Başlık: maçın akışından standart manşet.
    String back(String score) =>
        '$score${_fromSuffix(int.parse(score.split('–').last))} döndü';
    final win = hs == as ? null : (hs > as ? home : away);
    final winWorst = hs > as ? homeWorst : awayWorst;
    final winWorstScore = hs > as ? homeWorstScore : awayWorstScore;
    // Kazanan takımda 3+ gol atan oyuncu.
    String? hero;
    var heroGoals = 0;
    if (win != null) {
      for (final m in _scorers(d, hs > as ? 'home' : 'away')) {
        final c = (m['n'] as num?)?.toInt() ?? 1;
        if (c >= 3 && m['og'] != true && c > heroGoals) {
          hero = (m['name'] ?? '').toString();
          heroGoals = c;
        }
      }
    }
    final sc = _score(hs, as);
    final String headline;
    if (win == null) {
      if (homeWorst >= 2) {
        headline = '${home.name} ${back(homeWorstScore)}: $sc';
      } else if (awayWorst >= 2) {
        headline = '${away.name} ${back(awayWorstScore)}: $sc';
      } else if (hs == 0) {
        headline = '${home.name} ile ${away.name} golsüz berabere';
      } else {
        headline = '${home.name} ile ${away.name} yenişemedi: $sc';
      }
    } else if (winWorst >= 2) {
      headline = '${win.name} ${back(winWorstScore)}: $sc';
    } else if (winWorst == 1) {
      headline = '${win.name} geriden gelip kazandı: $sc';
    } else if ((hs - as).abs() >= 4) {
      headline = '${win.name} farka koştu: $sc';
    } else if (hero != null) {
      headline = '$hero $heroGoals gol attı, ${win.name} kazandı: $sc';
    } else if (as > hs) {
      headline = '${away.name} deplasmanda kazandı: $sc';
    } else {
      headline = '${home.name} sahasında kazandı: $sc';
    }

    // Özet satırı ve paragraflar.
    final paras = <String>[];
    paras.add(
      [
        if (week != null) '$week. haftada',
        '${home.name} ile ${away.name} karşı karşıya geldi.',
      ].join(' '),
    );
    if (timed) {
      for (var i = 0; i < sentences.length; i += 3) {
        paras.add(
          sentences.sublist(i, (i + 3).clamp(0, sentences.length)).join(' '),
        );
      }
    } else if (hs + as > 0) {
      String list(String side, String team) {
        final l = _scorers(d, side);
        if (l.isEmpty) return '';
        final names = [
          for (final m in l)
            [
              (m['name'] ?? '').toString(),
              if (m['og'] == true) ' (kendi kalesine)',
              if (((m['n'] as num?)?.toInt() ?? 1) > 1) ' (${m['n']})',
            ].join(),
        ];
        return '$team adına goller: ${names.join(', ')}.';
      }

      paras.add(
        [
          list('home', home.name),
          list('away', away.name),
        ].where((s) => s.isNotEmpty).join(' '),
      );
    }
    // Hat-trick ve üstü.
    for (final side in ['home', 'away']) {
      for (final m in _scorers(d, side)) {
        final c = (m['n'] as num?)?.toInt() ?? 1;
        if (c >= 3 && m['og'] != true) {
          paras.add('${m['name']} $c golle maçın yıldızı oldu.');
        }
      }
    }
    paras.add('Maç ${_score(hs, as)} sona erdi.');

    return NewsArticle(
      kicker: ['MAÇ SONUCU', if (week != null) '$week. HAFTA'].join(' · '),
      headline: headline,
      deck: '${home.name} ${_score(hs, as)} ${away.name}',
      paragraphs: paras.where((p) => p.trim().isNotEmpty).toList(),
      home: home,
      away: away,
      hs: hs,
      as: as,
    );
  }

  static NewsArticle _week(NewsItem n, Map<String, dynamic> d) {
    final week = (d['week'] as num?)?.toInt() ?? n.week;
    final matches = [
      for (final m in (d['matches'] as List? ?? const []))
        if (m is Map) m,
    ];
    var goals = 0;
    Map? biggest;
    var gap = -1;
    for (final m in matches) {
      final hs = (m['hs'] as num?)?.toInt() ?? 0;
      final as = (m['as'] as num?)?.toInt() ?? 0;
      goals += hs + as;
      if ((hs - as).abs() > gap) {
        gap = (hs - as).abs();
        biggest = m;
      }
    }
    String line(Map m) =>
        '${ArticleTeam(m['home'] as Map?).name} '
        '${_score((m['hs'] as num?)?.toInt() ?? 0, (m['as'] as num?)?.toInt() ?? 0)} '
        '${ArticleTeam(m['away'] as Map?).name}';
    // Her maç: skor ve iki takımın golcüleri (kısa takım adlarıyla).
    String scorers(Map m, String side) => [
      for (final x in _scorers(m, side))
        [
          (x['name'] ?? '').toString(),
          if (x['og'] == true) ' (kendi kalesine)',
          if (((x['n'] as num?)?.toInt() ?? 1) > 1) ' (${x['n']})',
        ].join(),
    ].join(', ');
    final blocks = [
      for (final m in matches)
        [
          '${line(m)}.',
          for (final side in ['home', 'away'])
            if (scorers(m, side).isNotEmpty)
              '${ArticleTeam(m[side] as Map?).name}: ${scorers(m, side)}.',
        ].join(' '),
    ];
    return NewsArticle(
      kicker: ['HAFTA ÖZETİ', if (week != null) '$week. HAFTA'].join(' · '),
      headline: week == null
          ? '${matches.length} maçta $goals gol'
          : '$week. Hafta: ${matches.length} maçta $goals gol',
      deck: biggest == null || gap <= 0
          ? ''
          : 'En farklı skor: ${line(biggest)}',
      paragraphs: blocks.isNotEmpty
          ? blocks
          : [for (final m in matches) line(m)],
    );
  }

  static NewsArticle _preview(NewsItem n, Map<String, dynamic> d) {
    final home = ArticleTeam(d['home'] as Map?);
    final away = ArticleTeam(d['away'] as Map?);
    final hm = d['home'] as Map? ?? const {};
    final am = d['away'] as Map? ?? const {};
    final week = (d['week'] as num?)?.toInt() ?? n.week;
    final time = (d['time'] ?? '').toString();
    final pitch = (d['pitch'] ?? '').toString();
    final paras = <String>[];
    String standing(Map m, String name) {
      final rank = (m['rank'] as num?)?.toInt();
      final pts = (m['points'] as num?)?.toInt();
      if (rank == null) return '';
      return '$name ligde $rank. sırada${pts == null ? '' : ' ($pts puan)'}';
    }

    final st = [
      standing(hm, home.name),
      standing(am, away.name),
    ].where((s) => s.isNotEmpty).join(', ');
    if (st.isNotEmpty) paras.add('$st.');
    String form(Map m) => [
      for (final f in (m['form'] as List? ?? const [])) f.toString(),
    ].join(' ');
    final hf = form(hm), af = form(am);
    if (hf.isNotEmpty || af.isNotEmpty) {
      paras.add(
        'Son maçlar (G galibiyet, B beraberlik, M mağlubiyet): '
        '${home.name} $hf · ${away.name} $af.',
      );
    }
    final h2h = d['h2h'];
    if (h2h is Map) {
      final flip = h2h['home_id']?.toString() == (hm['id'] ?? '').toString()
          ? false
          : h2h['home_id']?.toString() == (am['id'] ?? '').toString();
      final a = (h2h['hs'] as num?)?.toInt();
      final b = (h2h['as'] as num?)?.toInt();
      if (a != null && b != null) {
        final first = flip ? away.name : home.name;
        final second = flip ? home.name : away.name;
        paras.add(
          'İki takımın son karşılaşması: $first ${_score(a, b)} $second.',
        );
      }
    }
    final w = d['weather'];
    if (w is Map && w['temp'] != null) {
      final desc = (w['desc'] ?? '').toString();
      paras.add(
        'Maç saatinde hava ${w['temp']}°${desc.isEmpty ? '' : ', $desc'} bekleniyor.',
      );
    }
    return NewsArticle(
      kicker: ['MAÇ GÜNÜ', if (week != null) '$week. HAFTA'].join(' · '),
      headline: '${home.name} – ${away.name}',
      deck: [
        if (time.isNotEmpty) 'Saat $time',
        if (pitch.isNotEmpty) pitch,
      ].join(' · '),
      paragraphs: paras,
      home: home,
      away: away,
    );
  }

  static NewsArticle _manual(NewsItem n) {
    final t = n.content.trim();
    final nl = t.indexOf('\n');
    final title = nl > 0 && nl <= 140 ? t.substring(0, nl).trim() : t;
    final body = nl > 0 && nl <= 140 ? t.substring(nl + 1).trim() : '';
    return NewsArticle(
      kicker: 'DUYURU',
      headline: title,
      paragraphs: body
          .split(RegExp(r'\n\s*\n'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList(),
    );
  }
}
