import 'package:flutter/foundation.dart';

class AppConfig {
  static bool dbLogEnabled =
      String.fromEnvironment('DB_LOG', defaultValue: '0') == '1';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qxdjebzszikeslobrozf.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4ZGplYnpzemlrZXNsb2Jyb3pmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NDk4NDMsImV4cCI6MjA5MjMyNTg0M30.5BHWMrohdL0x4I3ZgiJadkv1koJngGS4eYnB6RLvzaQ',
  );

  static void logDb(String message) {
    if (!dbLogEnabled) return;
    debugPrint(message);
  }

  static String _safe(String? v, {String fallback = '-'}) {
    final s = (v ?? '').trim();
    return s.isEmpty ? fallback : s;
  }

  static String _formatError(Object error) {
    final dynamic dyn = error;
    try {
      final code = (dyn.code ?? dyn.statusCode ?? dyn.errorCode)
          ?.toString()
          .trim();
      final message = (dyn.message ?? dyn.details ?? dyn.toString())
          .toString()
          .trim();
      final c = (code ?? '').isEmpty ? null : code;
      if (c != null) return '($c) $message';
      return message;
    } catch (_) {
      return error.toString();
    }
  }

  static void sqlLogStart({
    required String table,
    required String operation,
    String? filters,
    String? caller,
    String? service,
    String? method,
  }) {
    if (!dbLogEnabled) return;

    final callerText = _safe(caller);
    final serviceText = _safe(service);
    final methodText = _safe(method);
    final filtersText = _safe(filters);

    debugPrint('---------------- [SUPABASE QUERY START] ----------------');
    debugPrint('📍 CALLER  : $callerText');
    debugPrint('🏗️ SERVICE : $serviceText -> $methodText');
    debugPrint('📊 TABLE   : $table | OP: $operation');
    debugPrint('🔍 FILTERS : $filtersText');
    debugPrint('--------------------------------------------------------');
  }

  static void sqlLogResult({
    required String table,
    required String operation,
    int? count,
    Object? error,
    String? caller,
    String? service,
    String? method,
    String? message,
  }) {
    if (!dbLogEnabled) return;

    if (error != null) {
      debugPrint('❌ ERROR: ${_formatError(error)}');
      return;
    }

    final c = count;
    final msg = (message ?? '').trim();
    if (msg.isNotEmpty) {
      debugPrint('✅ RESULT: $msg');
      return;
    }
    if (c != null) {
      debugPrint('✅ RESULT: $c kayıt');
      return;
    }
    debugPrint('✅ RESULT: Başarılı');
  }
}
