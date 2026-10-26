// lib/screens/auth_gate_screen.dart
//
// AuthGate mendengarkan onAuthStateChange dari Supabase.
// Setelah auth state berubah:
// - Tidak ada sesi → LoginScreen
// - Ada sesi tapi aal1 → MfaVerifyScreen (minta kode TOTP)
// - Ada sesi aal2 dan role customer → CustomerDashboardScreen
// - Ada sesi aal2 dan role admin    → AdminDashboardScreen

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_config.dart';
import '../services/auth_service.dart';
import '../models/profile_model.dart';
import 'login_screen.dart';
import 'customer_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';

class AuthGateScreen extends StatelessWidget {
  const AuthGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        // Menunggu event pertama
        if (!snapshot.hasData) {
          return const _LoadingPage();
        }

        final session = snapshot.data!.session;
        if (session == null) {
          return const LoginScreen();
        }

        // Session ada — cek aal2 + role asinkron
        return FutureBuilder<_GateData>(
          future: _resolveDestination(),
          builder: (context, gateSnap) {
            if (!gateSnap.hasData) return const _LoadingPage();

            final gate = gateSnap.data!;
            if (!gate.isAal2) {
              // Belum aal2 → perlu verifikasi MFA
              return const LoginScreen();
            }

            if (gate.profile == null) return const LoginScreen();

            if (gate.profile!.isAdmin) {
              return const AdminDashboardScreen();
            }
            return CustomerDashboardScreen(profile: gate.profile!);
          },
        );
      },
    );
  }

  static Future<_GateData> _resolveDestination() async {
    final isAal2 = await AuthService.isAal2();
    if (!isAal2) return _GateData(isAal2: false, profile: null);

    final profile = await AuthService.getCurrentProfile();
    return _GateData(isAal2: true, profile: profile);
  }
}

class _GateData {
  final bool isAal2;
  final ProfileModel? profile;
  _GateData({required this.isAal2, required this.profile});
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
