/// `players` tablosundan okunan sütunlar. Telefon ve kimlik no burada yok:
/// kişisel veri tablodan okunmaz, telefon yalnız yetkiliye `player_phones`
/// fonksiyonuyla gelir (bkz. 20261025450000_players_privacy_rpcs.sql).
const kPlayerColumns =
    'id, name, surname, birth_date, preferred_foot, main_position, '
    'sub_position, photo_url, height, weight, auth_uid, created_at, '
    'updated_at';

/// Oyuncu anahtarı uuid mi (eski ekranlarda anahtar telefon olabiliyordu).
bool isPlayerUuid(String s) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(s.trim());
