import 'package:flutter/material.dart';
import 'screens/admin_dashboard_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DigiQApp());
}

class DigiQApp extends StatelessWidget {
  const DigiQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DigiQ - Digital Store & QRIS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AdminDashboardScreen(),
    );
  }
}
