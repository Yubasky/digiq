// lib/screens/auth_gate_screen.dart
//
// AuthGate mendengarkan onAuthStateChange dari Supabase dan mendeteksi token
// dari link email (token_hash + type) langsung dari Uri.base.queryParameters
// saat startup di web.
//
// Alur:
// - Startup web dengan token_hash & type → verifyOtp → sukses/error state
// - type=recovery sukses → SetNewPasswordScreen (flag isPasswordRecovery aktif)
// - Ada error deep link (misal otp_expired) → EmailVerificationScreen(state: error)
// - Verifikasi email sukses → EmailVerificationScreen(state: verified, 3s countdown)
// - Tidak ada sesi → LoginScreen
// - Sesi aktif role customer → CustomerDashboardScreen
// - Sesi aktif role admin    → AdminDashboardScreen

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/deep_link_auth_handler.dart';
import '../services/supabase_config.dart';
import '../services/web_url_cleaner.dart';
import '../models/profile_model.dart';
import '../services/app_language.dart';
import 'auth/email_verification_screen.dart';
import 'auth/set_new_password_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'customer_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<Uri>? _uriSub;

  Session? _session;
  bool _isLoading = true;
  String? _deepLinkError;
  bool _showVerifiedScreen = false;

  /// Flag saat alur recovery aktif: cegah routing ke dashboard.
  bool _isPasswordRecovery = false;

  /// Penanda jika error terakhir berasal dari alur recovery (bukan verifikasi pendaftaran).
  bool _isRecoveryError = false;

  /// Guard: token hanya diproses sekali, karena token_hash sekali pakai.
  bool _tokenProcessed = false;

  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.supabase.auth.currentSession;
    _isLoading = false;

    // ── Deteksi token_hash dari URL saat startup (web only) ──────────────────
    // Hash-URL strategy: query ada SEBELUM '#', bisa dibaca dari Uri.base.queryParameters.
    if (kIsWeb && !_tokenProcessed) {
      final uri = Uri.base;
      final query = uri.queryParameters;
      // Fallback: beberapa konfigurasi meletakkan params di fragment
      final fragment = Uri.splitQueryString(uri.fragment);
      final tokenHash = query['token_hash'] ?? fragment['token_hash'];
      final type = query['type'] ?? fragment['type'];

      if (tokenHash != null && tokenHash.isNotEmpty) {
        _tokenProcessed = true;
        // Bersihkan URL sebelum proses async agar token tidak tersimpan di history
        removeTokensFromUrl(['token_hash', 'type']);
        _processToken(tokenHash, type);
      } else if (uri.path.contains('verify') ||
          uri.fragment.contains('verify') ||
          query.containsKey('token_hash') ||
          query.containsKey('type')) {
        _tokenProcessed = true;
        _deepLinkError =
            (AppLanguage.isId ? 'Tautan verifikasi tidak lengkap. Parameter token tidak ditemukan.' : 'Incomplete verification link. Token parameter not found.');
        _isRecoveryError = (type?.toLowerCase() == 'recovery');
      }
    }

    // ── Deep link yang sudah tertangkap sebelum initState ────────────────────
    if (!_tokenProcessed) {
      if (DeepLinkAuthHandler.pendingErrorMessage != null) {
        _deepLinkError = DeepLinkAuthHandler.pendingErrorMessage;
        DeepLinkAuthHandler.pendingErrorMessage = null;
      } else if (DeepLinkAuthHandler.isVerificationDeepLink && _session != null) {
        _showVerifiedScreen = true;
        DeepLinkAuthHandler.isVerificationDeepLink = false;
      }
    }

    _listenAuthChanges();
    _listenDeepLinks();
  }

  /// Verifikasi token dari URL, kemudian update state sesuai hasilnya.
  Future<void> _processToken(String tokenHash, String? type) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final result = await AuthService.verifyOtp(
      tokenHash: tokenHash,
      type: type ?? '',
    );

    if (!mounted) return;

    if (result.success) {
      // Cek apakah ini alur recovery
      final isRecovery = type?.toLowerCase() == 'recovery';
      AuthService.isPasswordRecovery = isRecovery;
      setState(() {
        _isLoading = false;
        if (isRecovery) {
          _isPasswordRecovery = true;
          _showVerifiedScreen = false;
        } else {
          _showVerifiedScreen = true;
          _isPasswordRecovery = false;
        }
        _isRecoveryError = false;
        _deepLinkError = null;
        // Perbarui sesi setelah verifyOTP membuat sesi baru
        _session = SupabaseConfig.supabase.auth.currentSession;
      });
    } else {
      final isRecovery = type?.toLowerCase() == 'recovery';
      setState(() {
        _isLoading = false;
        _isRecoveryError = isRecovery;
        _deepLinkError = result.message;
        _showVerifiedScreen = false;
      });
    }
  }

  void _listenAuthChanges() {
    _authSub = AuthService.authStateChanges.listen((data) {
      if (!mounted) return;
      final session = data.session;
      final event = data.event;

      // Event passwordRecovery dikirim Supabase setelah token recovery valid
      if (event == AuthChangeEvent.passwordRecovery) {
        AuthService.isPasswordRecovery = true;
        setState(() {
          _session = session;
          _isPasswordRecovery = true;
          _isLoading = false;
        });
        return;
      }

      if (event == AuthChangeEvent.signedOut) {
        AuthService.isPasswordRecovery = false;
        setState(() {
          _session = null;
          _isPasswordRecovery = false;
          _isLoading = false;
        });
        return;
      }

      // Verifikasi email sukses dari deep link sebelum tokenProcessed
      if (!_tokenProcessed &&
          DeepLinkAuthHandler.isVerificationDeepLink &&
          session != null) {
        DeepLinkAuthHandler.isVerificationDeepLink = false;
        setState(() {
          _session = session;
          _showVerifiedScreen = true;
          _deepLinkError = null;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _session = session;
        _isLoading = false;
      });
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        _deepLinkError = AuthService.translateAuthError(error.toString());
        _isLoading = false;
      });
    });
  }

  void _listenDeepLinks() {
    _uriSub = DeepLinkAuthHandler.onUriReceived.listen((uri) {
      if (!mounted) return;
      if (DeepLinkAuthHandler.pendingErrorMessage != null) {
        setState(() {
          _deepLinkError = DeepLinkAuthHandler.pendingErrorMessage;
          DeepLinkAuthHandler.pendingErrorMessage = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _uriSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 0. Loading saat memproses token
    if (_isLoading) {
      return const _LoadingPage();
    }

    // 1. Alur recovery aktif → wajib set password baru, blokir dashboard
    if (AuthService.isPasswordRecovery || _isPasswordRecovery) {
      return SetNewPasswordScreen(
        onDone: () {
          // Setelah password diset & signOut, reset flag dan kembali ke login
          AuthService.isPasswordRecovery = false;
          if (mounted) setState(() => _isPasswordRecovery = false);
        },
      );
    }

    // 2. Tampilkan layar error verifikasi jika deep link kedaluwarsa / invalid
    if (_deepLinkError != null) {
      return EmailVerificationScreen(
        initialStatus: VerificationStatus.error,
        errorMessage: _deepLinkError,
        isRecovery: _isRecoveryError,
      );
    }

    // 3. Tampilkan layar sukses verifikasi email
    if (_showVerifiedScreen) {
      return EmailVerificationScreen(
        initialStatus: VerificationStatus.verified,
        email: _session?.user.email,
      );
    }

    // 4. Tidak ada sesi login
    final session = _session;
    if (session == null) {
      if (kIsWeb &&
          (Uri.base.fragment == '/register' ||
           Uri.base.fragment == 'register' ||
           Uri.base.path == '/register')) {
        return const RegisterScreen();
      }
      return const LoginScreen();
    }

    // 4b. Sesi ada tetapi email belum terverifikasi -> arahkan ke verifikasi email
    if (session.user.emailConfirmedAt == null) {
      return EmailVerificationScreen(
        initialStatus: VerificationStatus.waiting,
        email: session.user.email,
      );
    }

    // 5. Ada sesi & email terkonfirmasi — ambil profil dan arahkan ke dashboard yang sesuai
    return FutureBuilder<ProfileModel?>(
      future: AuthService.getCurrentProfile(),
      builder: (context, profileSnap) {
        if (profileSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }

        final profile = profileSnap.data;
        if (profile == null) {
          return const LoginScreen();
        }

        if (profile.isAdmin) {
          return const AdminDashboardScreen();
        }
        return CustomerDashboardScreen(profile: profile);
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
