enum DatabaseType { firebase, supabase }

class AppConfig {
  static const DatabaseType activeDatabase = DatabaseType.firebase;

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qxdjebzszikeslobrozf.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4ZGplYnpzemlrZXNsb2Jyb3pmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NDk4NDMsImV4cCI6MjA5MjMyNTg0M30.5BHWMrohdL0x4I3ZgiJadkv1koJngGS4eYnB6RLvzaQ',
  );
}
