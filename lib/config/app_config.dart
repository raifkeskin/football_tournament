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

  static void sqlLogStart({
    required String table,
    required String operation,
    String? filters,
  }) {
    if (!dbLogEnabled) return;
    print('[SQL LOG] Tablo: $table | İşlem: $operation');
    final f = (filters ?? '').trim();
    if (f.isNotEmpty) {
      print('[SQL LOG] Filtreler: $f');
    }
  }

  static void sqlLogResult({
    required String table,
    required String operation,
    int? count,
    Object? error,
  }) {
    if (!dbLogEnabled) return;
    if (error != null) {
      print('[SQL LOG] Sonuç: Hata: $error');
      return;
    }
    final c = count;
    final suffix = c == null ? '' : ' | Kayıt: $c';
    print('[SQL LOG] Sonuç: Başarılı$suffix');
  }
}
