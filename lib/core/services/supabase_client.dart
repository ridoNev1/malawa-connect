import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

class Supa {
  static SupabaseClient get I => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
      // optional: realtime log/headers bisa ditambah nanti
    );
  }
}
