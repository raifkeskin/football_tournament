import 'dart:math';

/// Kurada üretilen tek eşleşme.
typedef DrawPair = ({String home, String away});

/// Kuradaki bir hafta: maçlar ve (tek sayıda takımda) bay geçen takım.
typedef DrawWeek = ({List<DrawPair> pairs, String? bye});

/// Lig aşaması kurası: herkes herkesle (çember yöntemi), her hafta bir takım
/// en fazla bir maç yapar. Tek sayıda takımda her hafta biri bay geçer.
///
/// Ev sahibi dengelenir: ev sahibi sayısı az olan takım ev sahibi olur; eşitse
/// önceki maçını deplasmanda oynayan. Rövanşlıda ikinci devre ilk devrenin
/// aynısıdır, yalnızca ev sahibi değişir.
List<DrawWeek> drawLeagueFixture(
  List<String> teamIds, {
  required bool doubleRound,
  Random? random,
}) {
  final rnd = random ?? Random();
  // Açgözlü atama her denemede aynı dengeyi vermez (özellikle tek sayıda
  // takımda); birçok deneme yapılır, en dengelisi seçilir.
  List<DrawWeek>? best;
  var bestScore = 1 << 30;
  for (var attempt = 0; attempt < 300 && bestScore > 0; attempt++) {
    final weeks = _drawOnce(teamIds, doubleRound: doubleRound, rnd: rnd);
    final score = _imbalance(weeks, teamIds);
    if (score < bestScore) {
      best = weeks;
      bestScore = score;
    }
  }
  return best ?? const [];
}

/// Puan: ev sahibi sayıları arasındaki en büyük fark (ağır) + üst üste aynı
/// yerde oynanan maç sayısı (hafif). Küçük olan daha dengeli.
int _imbalance(List<DrawWeek> weeks, List<String> teamIds) {
  final home = <String, int>{};
  final last = <String, bool>{};
  var streaks = 0;
  for (final w in weeks) {
    for (final p in w.pairs) {
      home[p.home] = (home[p.home] ?? 0) + 1;
      if (last[p.home] == true) streaks++;
      if (last[p.away] == false) streaks++;
      last[p.home] = true;
      last[p.away] = false;
    }
  }
  final counts = [for (final t in teamIds) home[t] ?? 0];
  if (counts.isEmpty) return 0;
  final spread = counts.reduce(max) - counts.reduce(min);
  // Çift sayıda takımda ±1 fark kaçınılmazdır.
  final allowed = teamIds.length.isEven ? 1 : 0;
  return max(0, spread - allowed) * 1000 + streaks;
}

List<DrawWeek> _drawOnce(
  List<String> teamIds, {
  required bool doubleRound,
  required Random rnd,
}) {
  final teams = <String?>[...teamIds]..shuffle(rnd);
  if (teams.length < 2) return const [];
  if (teams.length.isOdd) teams.add(null); // bay
  final n = teams.length;

  final homeCount = <String, int>{};
  final lastWasHome = <String, bool>{};

  bool preferHome(String a, String b) {
    final ha = homeCount[a] ?? 0, hb = homeCount[b] ?? 0;
    if (ha != hb) return ha < hb;
    final la = lastWasHome[a], lb = lastWasHome[b];
    if (la != lb) return la != true;
    return rnd.nextBool();
  }

  final firstHalf = <DrawWeek>[];
  final arr = [...teams];
  for (var round = 0; round < n - 1; round++) {
    final pairs = <DrawPair>[];
    String? bye;
    for (var i = 0; i < n ~/ 2; i++) {
      final a = arr[i], b = arr[n - 1 - i];
      if (a == null || b == null) {
        bye = a ?? b;
        continue;
      }
      final aHome = preferHome(a, b);
      final home = aHome ? a : b, away = aHome ? b : a;
      homeCount[home] = (homeCount[home] ?? 0) + 1;
      lastWasHome[home] = true;
      lastWasHome[away] = false;
      pairs.add((home: home, away: away));
    }
    pairs.shuffle(rnd);
    firstHalf.add((pairs: pairs, bye: bye));
    // İlk takım sabit, diğerleri bir adım döner.
    arr.insert(1, arr.removeLast());
  }

  if (!doubleRound) return firstHalf;
  return [
    ...firstHalf,
    for (final w in firstHalf)
      (
        pairs: [for (final p in w.pairs) (home: p.away, away: p.home)],
        bye: w.bye,
      ),
  ];
}
