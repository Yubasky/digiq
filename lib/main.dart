// lib/main.dart

import 'package:flutter/material.dart';
import 'services/supabase_config.dart';
import 'services/deep_link_auth_handler.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const DigiQApp());
}

class DigiQApp extends StatelessWidget {
  const DigiQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: DeepLinkAuthHandler.navigatorKey,
      title: 'DigiQ - Digital Store & QRIS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGateScreen(),
    );
  }
}
