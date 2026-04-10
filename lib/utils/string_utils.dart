class StringUtils {
  static String normalizeTrKey(String input) {
    var s = input.trim().toLowerCase();
    s = s
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('i̇', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }
}
