import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'deep_link_auth_handler.dart';

/// Inisialisasi Supabase dari dart-define (tidak di-hardcode).
/// Jalankan dengan:
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
class SupabaseConfig {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Membersihkan URL jika tidak sengaja ditambahkan path seperti /rest/v1/ atau trailing slash.
  static String get _cleanUrl {
    var url = _url.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Panggil sekali di main() sebelum runApp().
  static Future<void> initialize() async {
    assert(_url.isNotEmpty, 'SUPABASE_URL belum di-set via --dart-define');
    assert(_anonKey.isNotEmpty, 'SUPABASE_ANON_KEY belum di-set via --dart-define');

    await Supabase.initialize(
      url: _cleanUrl,
      publishableKey: _anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
        detectSessionInUriPredicate: DeepLinkAuthHandler.handleDetectSessionInUri,
      ),
    );
  }

  /// Klien Supabase mock/fake untuk pengujian unit & widget.
  @visibleForTesting
  static SupabaseClient? testClient;

  /// Shortcut getter global.
  static SupabaseClient get supabase => testClient ?? Supabase.instance.client;
}
