// lib/screens/auth_gate_screen.dart
//
// AuthGate mendengarkan onAuthStateChange dari Supabase dan mendeteksi deep link.
// Alur:
// - Ada error deep link (misal otp_expired) → EmailVerificationScreen(state: error)
// - Verifikasi email sukses via deep link → EmailVerificationScreen(state: verified, 3s countdown)
// - Tidak ada sesi → LoginScreen
// - Sesi aktif role customer → CustomerDashboardScreen
// - Sesi aktif role admin    → AdminDashboardScreen

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/deep_link_auth_handler.dart';
import '../services/supabase_config.dart';
import '../models/profile_model.dart';
import 'auth/email_verification_screen.dart';
import 'login_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _session = SupabaseConfig.supabase.auth.currentSession;
    _isLoading = false;

    // Cek apakah ada error atau verifikasi yang sudah tertangkap saat deep link pertama
    if (DeepLinkAuthHandler.pendingErrorMessage != null) {
      _deepLinkError = DeepLinkAuthHandler.pendingErrorMessage;
      DeepLinkAuthHandler.pendingErrorMessage = null;
    } else if (DeepLinkAuthHandler.isVerificationDeepLink && _session != null) {
      _showVerifiedScreen = true;
      DeepLinkAuthHandler.isVerificationDeepLink = false;
    }

    _listenAuthChanges();
    _listenDeepLinks();
  }

  void _listenAuthChanges() {
    _authSub = AuthService.authStateChanges.listen((data) {
      if (!mounted) return;
      final session = data.session;

      // Jika aplikasi terbuka dari deep link verifikasi email baru
      if (DeepLinkAuthHandler.isVerificationDeepLink && session != null) {
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
    // 1. Tampilkan layar error verifikasi jika deep link kedaluwarsa / invalid
    if (_deepLinkError != null) {
      return EmailVerificationScreen(
        initialStatus: VerificationStatus.error,
        errorMessage: _deepLinkError,
      );
    }

    // 2. Tampilkan layar sukses verifikasi email jika baru kembali dari Gmail
    if (_showVerifiedScreen) {
      return EmailVerificationScreen(
        initialStatus: VerificationStatus.verified,
        email: _session?.user.email,
      );
    }

    // 3. Loading state awal
    if (_isLoading) {
      return const _LoadingPage();
    }

    // 4. Tidak ada sesi login
    final session = _session;
    if (session == null) {
      return const LoginScreen();
    }

    // 5. Ada sesi — ambil profil dan arahkan ke dashboard yang sesuai
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
