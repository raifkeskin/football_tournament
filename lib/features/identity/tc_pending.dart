import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';

/// Lisans Yönetimi'nde TC girişi (yalnız admin). TC düz saklanmaz: sunucu
/// girildiği anda kimlik doğrulamadaki geri çevrilemez özeti alır ve
/// "bekleyen" olarak tutar; futbolcu kimliğini okutunca özetler karşılaştırılır
/// (bkz. supabase/migrations/20261113200000_tc_pending.sql). TC hiçbir
/// ekranda geri gösterilmez.

/// 11 haneli TC'nin hane kontrolü (sunucudaki tc_valid ile aynı).
bool tcChecksumValid(String s) {
  if (!RegExp(r'^[1-9][0-9]{10}$').hasMatch(s)) return false;
  final d = [for (final c in s.split('')) int.parse(c)];
  final d10 =
      ((d[0] + d[2] + d[4] + d[6] + d[8]) * 7 - (d[1] + d[3] + d[5] + d[7])) %
      10;
  if (d10 != d[9]) return false;
  return d.take(10).fold<int>(0, (a, b) => a + b) % 10 == d[10];
}

class TcPendingInfo {
  const TcPendingInfo({
    this.verified = false,
    this.pending = false,
    this.mismatch = false,
  });

  /// Futbolcu kimlikle doğrulanmış (alan çıkmaz).
  final bool verified;

  /// TC girilmiş, kimlik bekleniyor.
  final bool pending;

  /// Kimlik okutuldu ama girilen TC uyuşmadı.
  final bool mismatch;
}

class TcPendingService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<TcPendingInfo> info(String playerId) async {
    final r = await _sb.rpc(
      'tc_pending_info',
      params: {'p_player_id': playerId},
    );
    final m = r is Map ? r : const {};
    return TcPendingInfo(
      verified: m['verified'] == true,
      pending: m['pending'] == true,
      mismatch: m['mismatch'] == true,
    );
  }

  /// Çakışma varsa açıklaması (başka profile girilmiş vb.), yoksa null.
  static Future<String?> check(String tc, {String? playerId}) async {
    final r = await _sb.rpc(
      'tc_pending_check',
      params: {'p_tc': tc, 'p_player_id': playerId},
    );
    final s = (r ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  static Future<void> set(String playerId, String tc, {required bool sent}) =>
      _sb.rpc(
        'tc_pending_set',
        params: {'p_player_id': playerId, 'p_tc': tc, 'p_sent': sent},
      );

  static Future<void> clear(String playerId) =>
      _sb.rpc('tc_pending_clear', params: {'p_player_id': playerId});
}

/// Formdaki TC satırı (Kimlik grubunun içinde).
class TcPendingRow extends StatelessWidget {
  const TcPendingRow({
    super.key,
    required this.controller,
    required this.info,
    required this.enabled,
    this.onClear,
  });

  final TextEditingController controller;
  final TcPendingInfo? info;
  final bool enabled;

  /// Girilmiş TC'yi sil (yalnız bekleyen varken).
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i?.verified == true) {
      return const AdminFieldRow(
        icon: Icons.verified_user_outlined,
        label: 'TC Kimlik No',
        child: Text(
          'Kimlikle doğrulandı',
          style: TextStyle(
            color: Color(0xFF34D399),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final pending = i?.pending == true;
    return AdminFieldRow(
      icon: Icons.badge_outlined,
      label: 'TC Kimlik No',
      trailing: pending && onClear != null
          ? TextButton(
              onPressed: enabled ? onClear : null,
              child: const Text(
                'SİL',
                style: TextStyle(
                  color: Color(0xFFF87171),
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
        decoration: adminInlineInputDecoration(
          hint: pending
              ? 'Girildi · değiştirmek için yeni TC'
              : '11 hane (isteğe bağlı)',
        ),
      ),
    );
  }
}

/// TC satırının altındaki durum, rıza kutusu ve gizlilik notu.
class TcPendingNote extends StatelessWidget {
  const TcPendingNote({
    super.key,
    required this.info,
    required this.typed,
    required this.sent,
    required this.onSent,
    required this.enabled,
  });

  final TcPendingInfo? info;

  /// Alana yeni TC yazıldı mı (rıza kutusu yalnız o zaman çıkar).
  final bool typed;
  final bool sent;
  final ValueChanged<bool> onSent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i?.verified == true) return const SizedBox.shrink();
    final status = i?.mismatch == true
        ? (
            'Futbolcu kimliğini okuttu ama girilen TC kimlikle uyuşmadı. '
                'Doğrulama kimliğe göre yapıldı; TC\'yi silip kontrol edin.',
            const Color(0xFFFBBF24),
            Icons.warning_amber_rounded,
          )
        : i?.pending == true
        ? (
            'TC girildi, kimlik bekleniyor. Futbolcu kimliğini okutunca '
                'eşleşirse mavi tik gelir.',
            const Color(0xFF93C5FD),
            Icons.hourglass_top_rounded,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(status.$3, size: 18, color: status.$2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.$1,
                      style: TextStyle(
                        color: status.$2,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (typed)
            CheckboxListTile(
              value: sent,
              onChanged: enabled ? (v) => onSent(v ?? false) : null,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: kAdminAccent,
              title: const Text(
                'Futbolcu TC\'sini kendisi gönderdi',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Text(
            'TC hiçbir yerde gösterilmez, admin dahil kimse göremez. Yalnız '
            'futbolcu kimliğini okutunca eşleştirmek için geri çevrilemez '
            'şekilde saklanır.',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}
