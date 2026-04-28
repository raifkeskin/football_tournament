String _normalizeSecret(String input) {
  return input.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();
}

bool matchesBackdoorPassword(Map<String, dynamic> data, String password) {
  final p = _normalizeSecret(password);
  if (p.isEmpty) return false;

  final candidates = <String>[
    (data['backdoorPassword'] ?? '').toString(),
    (data['password'] ?? '').toString(),
    (data['sifre'] ?? '').toString(),
    (data['secret'] ?? '').toString(),
    (data['pin'] ?? '').toString(),
  ].map(_normalizeSecret).where((e) => e.isNotEmpty).toList();

  return candidates.any((c) => c == p);
}
