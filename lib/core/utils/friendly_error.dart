/// Veritabanı ve ağ hatalarını kullanıcıya anlaşılır Türkçe metne çevirir.
/// Tanınmayan hata olduğu gibi (başındaki "Exception: " atılarak) döner.
String friendlyErrorText(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();

  // Boş bırakılamaz: null value in column "birth_date" ...
  final nn = RegExp(r'null value in column "([a-z_]+)"').firstMatch(raw);
  if (nn != null) {
    return '${_columnLabel(nn.group(1)!)} boş geçilemez.';
  }
  if (raw.contains('row-level security') || raw.contains('42501')) {
    return 'Bu işlem için yetkiniz yok.';
  }
  if (raw.contains('violates foreign key constraint')) {
    return 'Bu kayıt başka kayıtlarla ilişkili olduğu için işlem yapılamadı.';
  }
  if (raw.contains('violates check constraint')) {
    return 'Girilen değer geçerli değil. Lütfen alanları kontrol edin.';
  }
  if (raw.contains('duplicate key value')) {
    return 'Bu kayıt zaten var.';
  }
  if (raw.contains('SocketException') ||
      raw.contains('ClientException') ||
      raw.contains('Failed host lookup')) {
    return 'Bağlantı kurulamadı. İnternetinizi kontrol edip tekrar deneyin.';
  }
  if (raw.contains('TimeoutException')) {
    return 'İşlem zaman aşımına uğradı. Tekrar deneyin.';
  }
  return raw;
}

String _columnLabel(String column) => switch (column) {
  'birth_date' => 'Doğum tarihi',
  'name' => 'Ad',
  'surname' => 'Soyad',
  'phone' => 'Telefon',
  'content' => 'Metin',
  'season_id' => 'Sezon',
  'league_id' => 'Turnuva',
  'team_id' => 'Takım',
  'player_id' => 'Oyuncu',
  'start_date' => 'Başlangıç tarihi',
  'end_date' => 'Bitiş tarihi',
  _ => 'Zorunlu alan ($column)',
};
