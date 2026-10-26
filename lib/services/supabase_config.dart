import 'package:supabase_flutter/supabase_flutter.dart';

/// Inisialisasi Supabase dari dart-define (tidak di-hardcode).
/// Jalankan dengan:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
class SupabaseConfig {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Panggil sekali di main() sebelum runApp().
  static Future<void> initialize() async {
    assert(_url.isNotEmpty, 'SUPABASE_URL belum di-set via --dart-define');
    assert(_anonKey.isNotEmpty, 'SUPABASE_ANON_KEY belum di-set via --dart-define');

    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  /// Shortcut getter global.
  static SupabaseClient get supabase => Supabase.instance.client;
}
