/// Kimlik kartı okuma modelleri ve arka yüzdeki MRZ (makinece okunur 3
/// satır) ayrıştırıcısı. Platformdan bağımsız; web'de de derlenir.
library;

/// Çipin kilidini açan bilgiler (arka yüzden okunur ya da elle girilir):
/// seri no, doğum tarihi, son geçerlilik tarihi.
class IdCardKey {
  const IdCardKey({
    required this.documentNumber,
    required this.birthDate,
    required this.expiryDate,
    this.alternatives = const [],
  });

  final String documentNumber;
  final DateTime birthDate;
  final DateTime expiryDate;

  /// OCR'dan çıkan, sağlamaları tutan diğer seri no adayları: ilki çipi
  /// açmazsa sırayla denenir.
  final List<String> alternatives;

  IdCardKey copyWith({
    String? documentNumber,
    DateTime? birthDate,
    DateTime? expiryDate,
  }) => IdCardKey(
    documentNumber: documentNumber ?? this.documentNumber,
    birthDate: birthDate ?? this.birthDate,
    expiryDate: expiryDate ?? this.expiryDate,
    // Elle düzeltilen bilgide adaylar geçersizdir.
    alternatives: documentNumber == null ? alternatives : const [],
  );
}

/// Çipten okunan kimlik bilgileri. Çipteki adlar Türkçe karakter içermez
/// ("SIMSEK"); eşleştirme sunucuda Türkçe karakterler katlanarak yapılır.
class IdCardData {
  const IdCardData({
    required this.firstName,
    required this.lastName,
    required this.birthDate,
    required this.tc,
  });

  final String firstName;
  final String lastName;
  final DateTime birthDate;
  final String tc;

  String get fullName => '$firstName $lastName'.trim();
}

enum NfcState { available, disabled, unsupported }

/// Okuma sırasında kullanıcıya gösterilecek hata.
class IdCardError implements Exception {
  const IdCardError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// TC kimlik no biçim ve sağlama kontrolü.
bool tcValid(String s) {
  if (!RegExp(r'^[1-9]\d{10}$').hasMatch(s)) return false;
  final d = [for (final c in s.split('')) int.parse(c)];
  final odd = d[0] + d[2] + d[4] + d[6] + d[8];
  final even = d[1] + d[3] + d[5] + d[7];
  if ((odd * 7 - even) % 10 != d[9]) return false;
  return d.take(10).fold<int>(0, (a, b) => a + b) % 10 == d[10];
}

/// MRZ satırlarındaki TC numarası (Türk kimlik kartında isteğe bağlı veri
/// alanında durur).
String? tcFromText(Iterable<String> parts) {
  for (final p in parts) {
    for (final m in RegExp(r'\d{11}').allMatches(p)) {
      if (tcValid(m.group(0)!)) return m.group(0);
    }
  }
  return null;
}

int _mrzValue(String c) {
  final u = c.codeUnitAt(0);
  if (u >= 48 && u <= 57) return u - 48;
  if (u >= 65 && u <= 90) return u - 55;
  return 0; // '<'
}

/// ICAO 9303 sağlama hanesi.
int mrzCheckDigit(String s) {
  const w = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < s.length; i++) {
    sum += _mrzValue(s[i]) * w[i % 3];
  }
  return sum % 10;
}

const _toDigit = {
  'O': '0',
  'Q': '0',
  'D': '0',
  'U': '0',
  'I': '1',
  'L': '1',
  'T': '1',
  'Z': '2',
  'S': '5',
  'G': '6',
  'B': '8',
};
const _toLetter = {'0': 'O', '1': 'I', '2': 'Z', '5': 'S', '6': 'G', '8': 'B'};

String _digits(String s) => s.split('').map((c) => _toDigit[c] ?? c).join();

/// OCR satırını MRZ alfabesine indirger.
String _clean(String line) => line
    .toUpperCase()
    .replaceAll(RegExp(r'[«‹<\(\[\{]'), '<')
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

DateTime? _yymmdd(String s, {required bool future}) {
  if (!RegExp(r'^\d{6}$').hasMatch(s)) return null;
  final yy = int.parse(s.substring(0, 2));
  final mm = int.parse(s.substring(2, 4));
  final dd = int.parse(s.substring(4, 6));
  if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return null;
  final now = DateTime.now().year % 100;
  // Doğum: gelecekte olamaz; son geçerlilik: 2000'ler.
  final year = future ? 2000 + yy : (yy > now ? 1900 + yy : 2000 + yy);
  return DateTime(year, mm, dd);
}

/// Seri no adayları: OCR'ın karıştırdığı harf/rakamlar sağlama hanesi
/// tutacak şekilde değiştirilir; en az değişiklik yapılan önce gelir.
List<String> _docCandidates(String raw, String check) {
  final cd = int.tryParse(_digits(check));
  if (cd == null) return const [];
  final chars = raw.split('');
  final amb = [
    for (var i = 0; i < chars.length; i++)
      if (_toDigit.containsKey(chars[i]) || _toLetter.containsKey(chars[i])) i,
  ];
  if (amb.length > 7) return const [];
  final masks = List.generate(1 << amb.length, (i) => i)
    ..sort((a, b) => _bits(a).compareTo(_bits(b)));
  final out = <String>[];
  for (final mask in masks) {
    final c = [...chars];
    for (var b = 0; b < amb.length; b++) {
      if (mask & (1 << b) == 0) continue;
      final ch = c[amb[b]];
      c[amb[b]] = _toDigit[ch] ?? _toLetter[ch] ?? ch;
    }
    final s = c.join();
    if (mrzCheckDigit(s) == cd) out.add(s);
  }
  return out;
}

int _bits(int v) {
  var n = 0;
  for (; v > 0; v >>= 1) {
    n += v & 1;
  }
  return n;
}

/// Kimlik kartı arka yüzünün OCR metninden çip anahtarını çıkarır. Bütün
/// alanlar sağlama haneleriyle doğrulanır; tutmazsa null (tekrar okutulur
/// ya da elle girilir).
IdCardKey? parseIdCardMrz(String ocrText) {
  final lines = [
    for (final l in ocrText.split('\n'))
      if (_clean(l).length >= 20) _clean(l),
  ];
  String? l1;
  String? l2;
  DateTime? birth;
  DateTime? expiry;
  for (final l in lines) {
    // 1. satır: I<TUR + seri no (9) + sağlama + isteğe bağlı veri (TC).
    if (l1 == null &&
        l.length >= 25 &&
        RegExp(r'^[I1][A-Z<0-9][A-Z0-9]{3}').hasMatch(l)) {
      l1 = l.padRight(30, '<').substring(0, 30);
      continue;
    }
    // 2. satır: doğum (6) + sağlama + cinsiyet + son geçerlilik (6) + sağlama.
    if (birth == null && l.length >= 18) {
      final d = _digits(l.substring(0, 7));
      final e = _digits(l.substring(8, 15));
      final b = _yymmdd(d.substring(0, 6), future: false);
      final x = _yymmdd(e.substring(0, 6), future: true);
      final sex = l[7];
      if (b != null &&
          x != null &&
          'MF<'.contains(sex) &&
          mrzCheckDigit(d.substring(0, 6)).toString() == d[6] &&
          mrzCheckDigit(e.substring(0, 6)).toString() == e[6]) {
        birth = b;
        expiry = x;
        l2 = '$d$sex$e${l.substring(15)}';
      }
    }
  }
  if (l1 == null || birth == null || expiry == null) return null;
  final docs = _docCandidates(l1.substring(5, 14), l1[14]);
  if (docs.isEmpty) return null;
  var picks = docs;
  // Bileşik sağlama (2. satırın 30. hanesi) adayları eler.
  if (docs.length > 1 && l2 != null && l2.length >= 30) {
    final opt = l1.substring(15).split('').map((c) {
      return c == '<' ? c : (_toDigit[c] ?? c);
    }).join();
    final cdDoc = _digits(l1[14]);
    final tail =
        l2.substring(0, 7) + l2.substring(8, 15) + l2.substring(18, 29);
    final cd = _digits(l2[29]);
    final ok = [
      for (final d in docs)
        if (mrzCheckDigit('$d$cdDoc$opt$tail').toString() == cd) d,
    ];
    if (ok.isNotEmpty) picks = ok;
  }
  final doc = picks.first;
  return IdCardKey(
    documentNumber: doc.replaceAll('<', ''),
    birthDate: birth,
    expiryDate: expiry,
    alternatives: [
      for (final d in picks.skip(1).take(2)) d.replaceAll('<', ''),
    ],
  );
}
