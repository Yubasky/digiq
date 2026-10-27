// lib/services/deep_link_auth_handler.dart
//
// Mengelola dan mendeteksi deep link auth callback dari Supabase / Gmail
// (misal digiq://auth-callback?code=... atau digiq://auth-callback?error=...)

import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_service.dart';

class DeepLinkAuthHandler {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final StreamController<Uri> _uriStreamController =
      StreamController<Uri>.broadcast();
  static Stream<Uri> get onUriReceived => _uriStreamController.stream;

  /// Penanda apakah deep link verifikasi email baru saja diterima
  static bool isVerificationDeepLink = false;

  /// Pesan error jika deep link membawa parameter error (misal otp_expired)
  static String? pendingErrorMessage;

  /// Predikat untuk FlutterAuthClientOptions.detectSessionInUriPredicate
  static bool handleDetectSessionInUri(Uri uri) {
    _uriStreamController.add(uri);

    final query = uri.queryParameters;
    final fragment = Uri.splitQueryString(uri.fragment);

    final error = query['error'] ?? fragment['error'];
    final errorCode = query['error_code'] ?? fragment['error_code'];
    final errorDesc =
        query['error_description'] ?? fragment['error_description'];

    final isAuthCallback =
        uri.host == 'auth-callback' || uri.path.contains('auth-callback');

    if (error != null || errorCode != null || errorDesc != null) {
      final rawMsg =
          errorDesc ?? error ?? errorCode ?? 'Tautan verifikasi tidak valid';
      pendingErrorMessage = AuthService.translateAuthError(rawMsg);
      isVerificationDeepLink = false;
    } else if (isAuthCallback) {
      isVerificationDeepLink = true;
      pendingErrorMessage = null;
    }

    // Cek parameter standar autentikasi Supabase
    final hasAuthParam = query.containsKey('access_token') ||
        fragment.containsKey('access_token') ||
        query.containsKey('code') ||
        fragment.containsKey('code') ||
        query.containsKey('error') ||
        fragment.containsKey('error') ||
        query.containsKey('error_code') ||
        fragment.containsKey('error_code');

    return hasAuthParam;
  }

  /// Reset flag setelah diproses UI
  static void consumeFlags() {
    isVerificationDeepLink = false;
    pendingErrorMessage = null;
  }
}
