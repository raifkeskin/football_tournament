/// Olay dakikası etiketi: uzatma ayrı tutulduysa 30+2', tutulmadıysa ve
/// dakika maç süresini aştıysa ([fullTime]) 60+4', diğerlerinde 37'.
String minuteLabel(int? minute, int? added, {int? fullTime}) {
  if (minute == null) return '';
  if (added != null && added > 0) return "$minute+$added'";
  if (fullTime != null && minute > fullTime) {
    return "$fullTime+${minute - fullTime}'";
  }
  return "$minute'";
}

/// Satırdan uzatma dakikası (added_minute); yoksa null.
int? readAddedMinute(Map<String, dynamic> row) {
  final v = row['added_minute'] ?? row['addedMinute'];
  if (v is num) return v.toInt() > 0 ? v.toInt() : null;
  if (v is String) {
    final n = int.tryParse(v.trim());
    return n != null && n > 0 ? n : null;
  }
  return null;
}
