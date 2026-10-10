import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/image_upload_service.dart';
import '../../match/models/match.dart';

/// Profil değişikliğinde gönderilebilen alanlar (veritabanı sütun adları).
abstract final class ProfileField {
  static const photoUrl = 'photo_url';
  static const height = 'height';
  static const weight = 'weight';
  static const mainPosition = 'main_position';
  static const subPosition = 'sub_position';
  static const birthDate = 'birth_date';

  static String label(String key) => switch (key) {
    photoUrl => 'Fotoğraf',
    height => 'Boy',
    weight => 'Kilo',
    mainPosition => 'Mevki',
    subPosition => 'Alt mevki',
    birthDate => 'Doğum tarihi',
    _ => key,
  };

  /// Alan değerinin ekranda gösterimi (boy/kilo birimiyle, tarih GG.AA.YYYY).
  static String display(String key, dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return '-';
    switch (key) {
      case height:
        return '$s cm';
      case weight:
        return '$s kg';
      case birthDate:
        final d = DateTime.tryParse(s);
        if (d == null) return s;
        String two(int v) => v.toString().padLeft(2, '0');
        return '${two(d.day)}.${two(d.month)}.${d.year}';
    }
    return s;
  }
}

/// Mevki seçenekleri (kadro formuyla aynı).
const kMainPositions = <String>['Kaleci', 'Defans', 'Orta Saha', 'Forvet'];
const kSubPositionsByMain = <String, List<String>>{
  'Kaleci': ['Kaleci'],
  'Defans': ['Stoper', 'Bek'],
  'Orta Saha': ['Defansif', 'Merkez', 'Ofansif', 'Kanat'],
  'Forvet': ['Santrfor', 'Kanat Forvet'],
};

/// Giriş yapan futbolcunun oyuncu kaydı.
class MyPlayer {
  const MyPlayer({
    required this.id,
    required this.name,
    this.photoUrl,
    this.height,
    this.weight,
    this.mainPosition,
    this.subPosition,
    this.birthDate,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final int? height;
  final int? weight;
  final String? mainPosition;
  final String? subPosition;

  /// YYYY-AA-GG
  final String? birthDate;

  int? get age {
    final d = DateTime.tryParse(birthDate ?? '');
    if (d == null) return null;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  /// Formdaki alanların mevcut değerleri (talep karşılaştırması için).
  Map<String, dynamic> get values => {
    ProfileField.photoUrl: photoUrl,
    ProfileField.height: height,
    ProfileField.weight: weight,
    ProfileField.mainPosition: mainPosition,
    ProfileField.subPosition: subPosition,
    ProfileField.birthDate: birthDate,
  };

  factory MyPlayer.fromMap(Map<String, dynamic> r) {
    String? s(String k) {
      final v = (r[k] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return MyPlayer(
      id: (r['id'] ?? '').toString(),
      name: [s('name'), s('surname')].whereType<String>().join(' '),
      photoUrl: s('photo_url'),
      height: (r['height'] as num?)?.toInt(),
      weight: (r['weight'] as num?)?.toInt(),
      mainPosition: s('main_position'),
      subPosition: s('sub_position'),
      birthDate: s('birth_date'),
    );
  }
}

/// Oyuncunun bir sezondaki takımı (`season_team_players`).
class MyTeam {
  const MyTeam({
    required this.seasonId,
    required this.teamId,
    required this.teamName,
    required this.leagueName,
    required this.seasonName,
    this.logoUrl,
    this.color,
    this.jerseyNumber,
    this.year,
  });

  /// Sezonun yılı (profilde sezon seçici ve toplam istatistik için).
  final int? year;
  final String seasonId;
  final String teamId;
  final String teamName;
  final String leagueName;
  final String seasonName;
  final String? logoUrl;

  /// Takımın birinci rengi (#RRGGBB).
  final String? color;
  final int? jerseyNumber;

  String get key => '$seasonId/$teamId';
}

/// Takım maçı + ekranda gereken adlar.
class TeamMatch {
  const TeamMatch({
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    this.homeColor,
    this.awayColor,
    this.pitchName,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final String? homeColor;
  final String? awayColor;
  final String? pitchName;

  /// Maç tarihi + saati (yerel); tarih yoksa null.
  DateTime? get startsAt {
    final d = DateTime.tryParse(match.matchDate ?? '');
    if (d == null) return null;
    final t = (match.matchTime ?? '').split(':');
    final h = t.isNotEmpty ? int.tryParse(t[0]) ?? 0 : 0;
    final m = t.length > 1 ? int.tryParse(t[1]) ?? 0 : 0;
    return DateTime(d.year, d.month, d.day, h, m);
  }

  bool get isPlayed =>
      match.status == MatchStatus.finished ||
      match.status == MatchStatus.cancelled;
}

/// Sezon içi kişisel istatistik.
class MySeasonStats {
  const MySeasonStats({
    this.matches = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellow = 0,
    this.red = 0,
  });

  final int matches;
  final int goals;
  final int assists;
  final int yellow;
  final int red;
}

enum ProfileChangeStatus { pending, approved, rejected, withdrawn }

/// Profil değişiklik talebi (`profile_change_requests`).
class ProfileChangeRequest {
  const ProfileChangeRequest({
    required this.id,
    required this.playerId,
    required this.changes,
    required this.previous,
    required this.status,
    required this.isMine,
    this.playerName,
    this.teamName,
    this.currentPhotoUrl,
    this.reviewNote,
    this.reviewerName,
    this.reviewedAt,
    this.createdAt,
  });

  final String id;
  final String playerId;
  final Map<String, dynamic> changes;
  final Map<String, dynamic> previous;
  final ProfileChangeStatus status;
  final bool isMine;
  final String? playerName;
  final String? teamName;
  final String? currentPhotoUrl;
  final String? reviewNote;
  final String? reviewerName;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  /// Mevki ve alt mevki tek satırda gösterilir.
  List<String> get fieldLabels {
    final labels = <String>[];
    for (final k in changes.keys) {
      final l = k == ProfileField.subPosition
          ? ProfileField.label(ProfileField.mainPosition)
          : ProfileField.label(k);
      if (!labels.contains(l)) labels.add(l);
    }
    return labels;
  }

  factory ProfileChangeRequest.fromMap(Map<String, dynamic> r) {
    Map<String, dynamic> obj(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    String? s(String k) {
      final v = (r[k] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    return ProfileChangeRequest(
      id: (r['id'] ?? '').toString(),
      playerId: (r['player_id'] ?? '').toString(),
      changes: obj(r['changes']),
      previous: obj(r['previous']),
      status: ProfileChangeStatus.values.firstWhere(
        (e) => e.name == r['status'],
        orElse: () => ProfileChangeStatus.pending,
      ),
      isMine: r['is_mine'] == true,
      playerName: s('player_name'),
      teamName: s('team_name'),
      currentPhotoUrl: s('current_photo_url'),
      reviewNote: s('review_note'),
      reviewerName: s('reviewer_name'),
      reviewedAt: DateTime.tryParse(s('reviewed_at') ?? '')?.toLocal(),
      createdAt: DateTime.tryParse(s('created_at') ?? '')?.toLocal(),
    );
  }
}

/// Futbolcu profili: takımlar, maçlar, istatistikler ve onaylı profil
/// değişiklikleri (bkz. 20261004110000_profile_change_requests.sql).
class PlayerProfileService {
  PlayerProfileService({SupabaseClient? client, ImageUploadService? uploads})
    : _client = client ?? Supabase.instance.client,
      _uploads = uploads ?? SupabaseImageUploadService();

  final SupabaseClient _client;
  final ImageUploadService _uploads;

  Future<MyPlayer?> loadPlayer(String playerId) async {
    final rows = await _client
        .from('players')
        .select(
          'id, name, surname, photo_url, height, weight, main_position, '
          'sub_position, birth_date',
        )
        .eq('id', playerId)
        .limit(1);
    return rows.isEmpty ? null : MyPlayer.fromMap(rows.first);
  }

  /// Aktif kadro kayıtları, en yeni sezon önce.
  Future<List<MyTeam>> loadTeams(String playerId) async {
    final rows = await _client
        .from('season_team_players')
        .select(
          'season_id, team_id, jersey_number, '
          'teams(name, logo_url, first_color), '
          'seasons(name, start_date, season_year, leagues(name))',
        )
        .eq('player_id', playerId)
        .eq('is_active', true);
    final list = rows.map((r) {
      final t = (r['teams'] as Map?) ?? const {};
      final s = (r['seasons'] as Map?) ?? const {};
      final l = (s['leagues'] as Map?) ?? const {};
      String? str(dynamic v) {
        final x = (v ?? '').toString().trim();
        return x.isEmpty ? null : x;
      }

      return (
        start: str(s['start_date']) ?? '',
        team: MyTeam(
          year:
              (s['season_year'] as num?)?.toInt() ??
              DateTime.tryParse(str(s['start_date']) ?? '')?.year ??
              int.tryParse(
                RegExp(r'\d{4}').firstMatch(str(s['name']) ?? '')?.group(0) ??
                    '',
              ),
          seasonId: (r['season_id'] ?? '').toString(),
          teamId: (r['team_id'] ?? '').toString(),
          teamName: str(t['name']) ?? 'Takım',
          leagueName: str(l['name']) ?? '',
          seasonName: str(s['name']) ?? '',
          logoUrl: str(t['logo_url']),
          color: str(t['first_color']),
          jerseyNumber: (r['jersey_number'] as num?)?.toInt(),
        ),
      );
    }).toList()..sort((a, b) => b.start.compareTo(a.start));
    return list.map((e) => e.team).toList();
  }

  /// Takımın sezondaki maçları (tarih sırasıyla).
  Future<List<TeamMatch>> loadTeamMatches(MyTeam team) async {
    final rows = await _client
        .from('matches')
        .select()
        .eq('season_id', team.seasonId)
        .or('home_team_id.eq.${team.teamId},away_team_id.eq.${team.teamId}')
        .order('match_date', ascending: true)
        .order('match_time', ascending: true);
    if (rows.isEmpty) return const [];

    final teamIds = <String>{};
    final pitchIds = <String>{};
    for (final r in rows) {
      teamIds.add((r['home_team_id'] ?? '').toString());
      teamIds.add((r['away_team_id'] ?? '').toString());
      final p = (r['pitch_id'] ?? '').toString();
      if (p.isNotEmpty) pitchIds.add(p);
    }
    teamIds.remove('');
    final teams = {
      for (final t
          in await _client
              .from('teams')
              .select('id, name, logo_url, first_color')
              .inFilter('id', teamIds.toList()))
        t['id'].toString(): t,
    };
    final pitches = pitchIds.isEmpty
        ? const <String, String>{}
        : {
            for (final p
                in await _client
                    .from('pitches')
                    .select('id, name')
                    .inFilter('id', pitchIds.toList()))
              p['id'].toString(): (p['name'] ?? '').toString(),
          };

    return rows.map((r) {
      final m = MatchModel.fromMap(r, r['id'].toString());
      final h = teams[m.homeTeamId] ?? const {};
      final a = teams[m.awayTeamId] ?? const {};
      return TeamMatch(
        match: m,
        homeName: (h['name'] ?? '').toString(),
        awayName: (a['name'] ?? '').toString(),
        homeLogo: (h['logo_url'] ?? '').toString(),
        awayLogo: (a['logo_url'] ?? '').toString(),
        homeColor: h['first_color']?.toString(),
        awayColor: a['first_color']?.toString(),
        pitchName: pitches[(r['pitch_id'] ?? '').toString()],
      );
    }).toList();
  }

  /// Sezondaki kişisel istatistik: kadroda olduğu maçlar ve maç olayları.
  Future<MySeasonStats> loadStats(String playerId, String seasonId) async {
    final results = await Future.wait([
      _client
          .from('match_rosters')
          .select('match_id')
          .eq('player_id', playerId)
          .eq('season_id', seasonId),
      _client
          .from('match_events')
          .select(
            'event_type, match_id, player_id, assist_player_id, is_own_goal',
          )
          .eq('season_id', seasonId)
          .or('player_id.eq.$playerId,assist_player_id.eq.$playerId'),
      // Ertelenen / iptal maçlar oynanmadı: sayılara katılmaz.
      _client.from('matches').select('id').eq('season_id', seasonId).inFilter(
        'status',
        ['cancelled', 'postponed'],
      ),
    ]);
    final unplayed = results[2].map((r) => r['id'].toString()).toSet();
    final matchIds = results[0]
        .map((r) => r['match_id'].toString())
        .where((id) => !unplayed.contains(id))
        .toSet();
    var goals = 0, assists = 0, yellow = 0, red = 0;
    final yellowMatches = <String>{};
    for (final e in results[1]) {
      if (unplayed.contains(e['match_id']?.toString())) continue;
      final type = (e['event_type'] ?? '').toString();
      final mine = e['player_id']?.toString() == playerId;
      if (type == 'goal') {
        if (mine && e['is_own_goal'] != true) goals++;
        if (e['assist_player_id']?.toString() == playerId) assists++;
      } else if (mine && type == 'yellow_card') {
        // Aynı maçta ikinci sarı: iki sarı yerine bir kırmızı sayılır.
        if (yellowMatches.add(e['match_id']?.toString() ?? '')) {
          yellow++;
        } else {
          yellow--;
          red++;
        }
      } else if (mine && type == 'red_card') {
        red++;
      }
    }
    return MySeasonStats(
      matches: matchIds.length,
      goals: goals,
      assists: assists,
      yellow: yellow,
      red: red,
    );
  }

  // --- Profil değişiklik talepleri -----------------------------------------

  Future<List<ProfileChangeRequest>> listRequests({
    bool onlyPending = true,
    String? playerId,
  }) async {
    final rows = await _client.rpc(
      'list_profile_change_requests',
      params: {'p_only_pending': onlyPending, 'p_player_id': playerId},
    );
    return (rows as List)
        .map((r) => ProfileChangeRequest.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Yeni fotoğrafı futbolcunun onay klasörüne yükler; linki döner.
  Future<String> uploadPendingPhoto(XFile file) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Giriş yapmalısınız.');
    final url = await _uploads.uploadImage(
      file,
      folder: MediaFolder.profileRequests,
      subfolder: uid,
    );
    if (url == null) throw Exception('Fotoğraf yüklenemedi.');
    return url;
  }

  Future<void> deletePhoto(String? url) => _uploads.deleteImageByUrl(url);

  /// Talep açar; değişmeyen alanlar sunucuda atılır.
  Future<void> submit(Map<String, dynamic> changes) async {
    await _client.rpc('submit_profile_change', params: {'p_changes': changes});
  }

  /// Bekleyen talebi geri çeker; yüklenmiş yeni fotoğrafı da siler.
  Future<void> withdraw(String requestId) async {
    final photo = await _client.rpc(
      'withdraw_profile_change',
      params: {'p_id': requestId},
    );
    if (photo is String && photo.isNotEmpty) await deletePhoto(photo);
  }

  Future<void> review(String requestId, {required bool approve, String? note}) {
    return _client.rpc(
      'review_profile_change',
      params: {'p_id': requestId, 'p_approve': approve, 'p_note': note},
    );
  }
}
