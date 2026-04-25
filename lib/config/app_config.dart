enum DatabaseType { firebase, supabase }

class AppConfig {
  static const DatabaseType defaultDatabase = DatabaseType.supabase;

  static final DatabaseType _defaultDatabase =
      String.fromEnvironment('ACTIVE_DB', defaultValue: defaultDatabase == DatabaseType.supabase ? 'supabase' : 'firebase') == 'supabase'
          ? DatabaseType.supabase
          : DatabaseType.firebase;

  static DatabaseType activeDatabase = _defaultDatabase;

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
    print(message);
  }

  static String _safe(String? v, {String fallback = '-'}) {
    final s = (v ?? '').trim();
    return s.isEmpty ? fallback : s;
  }

  static String _formatError(Object error) {
    final dynamic dyn = error;
    try {
      final code = (dyn.code ?? dyn.statusCode ?? dyn.errorCode)?.toString().trim();
      final message = (dyn.message ?? dyn.details ?? dyn.toString()).toString().trim();
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

    print('---------------- [SUPABASE QUERY START] ----------------');
    print('📍 CALLER  : $callerText');
    print('🏗️ SERVICE : $serviceText -> $methodText');
    print('📊 TABLE   : $table | OP: $operation');
    print('🔍 FILTERS : $filtersText');
    print('--------------------------------------------------------');
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
      print('❌ ERROR: ${_formatError(error)}');
      return;
    }

    final c = count;
    final msg = (message ?? '').trim();
    if (msg.isNotEmpty) {
      print('✅ RESULT: $msg');
      return;
    }
    if (c != null) {
      print('✅ RESULT: $c kayıt');
      return;
    }
    print('✅ RESULT: Başarılı');
  }
}
