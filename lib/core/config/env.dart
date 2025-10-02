import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get appEnv => dotenv.env['APP_ENV'] ?? 'dev';

  // Optional debug overrides
  static bool get geofenceDebug =>
      (dotenv.env['GEOFENCE_DEBUG'] ?? 'false').toLowerCase() == 'true';
  static double? get debugLat => double.tryParse(dotenv.env['DEBUG_LAT'] ?? '');
  static double? get debugLng => double.tryParse(dotenv.env['DEBUG_LNG'] ?? '');

  // Heartbeat interval seconds (default 60)
  static int get heartbeatSeconds {
    final v = int.tryParse(dotenv.env['HEARTBEAT_SECONDS'] ?? '');
    return (v != null && v > 0) ? v : 60;
  }

  // Geofence poll interval seconds when no position updates (default 20)
  static int get geofencePollSeconds {
    final v = int.tryParse(dotenv.env['GEOFENCE_POLL_SECONDS'] ?? '');
    return (v != null && v > 0) ? v : 60;
  }
}
