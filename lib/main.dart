import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/jarvis_service.dart';
import 'services/account_service.dart';
import 'screens/auth_screen.dart';
import 'services/memory_service.dart';
import 'screens/main_screen.dart';
import 'utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to landscape for TV, allow both for mobile
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: JarvisColors.background,
  ));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccountService()),
        ChangeNotifierProvider(create: (_) => JarvisService()),
        ChangeNotifierProvider(create: (_) => MemoryService()),
      ],
      child: const JarvisApp(),
    ),
  );
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: JarvisColors.background,
        colorScheme: const ColorScheme.dark(
          primary: JarvisColors.cyan,
          secondary: JarvisColors.electricBlue,
          surface: JarvisColors.surface,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: JarvisColors.textPrimary, fontFamily: 'Roboto', fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(color: JarvisColors.textPrimary, fontFamily: 'Roboto'),
          bodyMedium: TextStyle(color: JarvisColors.textSecondary, fontFamily: 'Roboto'),
        ),
      ),
      home: const _AccountGate(),
    );
  }
}

class _AccountGate extends StatelessWidget {
  const _AccountGate();
  @override Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    if (!account.isReady) return const Scaffold(backgroundColor: JarvisColors.background,body:Center(child:CircularProgressIndicator(color:JarvisColors.cyan)));
    if (!account.isLoggedIn) return const AuthScreen();
    if (!account.hasRecovery) return const RecoverySetupScreen();
    return const MainScreen();
  }
}
