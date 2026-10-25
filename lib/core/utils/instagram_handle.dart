final _handleRe = RegExp(r'^[A-Za-z0-9._]{1,30}$');

/// "@takim", "takim" ya da profil linkinden kullanıcı adını çıkarır
/// ("instagram.com/takim?igsh=..." → "takim"). Geçersizse null.
String? instagramHandle(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'instagram\.com/([A-Za-z0-9._]+)').firstMatch(s);
  if (m != null) s = m.group(1)!;
  if (s.startsWith('@')) s = s.substring(1);
  return _handleRe.hasMatch(s) ? s : null;
}

/// Kayıt biçimi: `https://www.instagram.com/kullaniciadi`.
String? instagramUrl(String? raw) {
  final h = instagramHandle(raw);
  return h == null ? null : 'https://www.instagram.com/$h';
}
