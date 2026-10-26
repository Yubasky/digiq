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

        // Session ada — ambil data profil & role
        return FutureBuilder<ProfileModel?>(
          future: AuthService.getCurrentProfile(),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingPage();
            }

            final profile = profileSnap.data;
            if (profile == null) return const LoginScreen();

            if (profile.isAdmin) {
              return const AdminDashboardScreen();
            }
            return CustomerDashboardScreen(profile: profile);
          },
        );
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
