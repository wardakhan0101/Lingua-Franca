import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lingua_franca/screens/login_screen.dart';
import 'package:lingua_franca/screens/home_screen.dart';
import 'package:lingua_franca/screens/assessment_screen.dart';
import 'package:lingua_franca/services/auth_service.dart';
import 'package:lingua_franca/services/gamification_service.dart';
// import 'package:flutter_gemma/core/api/flutter_gemma.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FlutterGemma.initialize();
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lingua Franca',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B72AB)),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _FullPageLoader();
        }

        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Signed in — check whether the initial placement assessment is done.
        // GamificationService.getUserStats() handles both fresh-user
        // initialization AND backfill for pre-feature accounts (grandfathered
        // to hasCompletedInitialAssessment = true).
        return FutureBuilder<Map<String, dynamic>>(
          future: GamificationService().getUserStats(),
          builder: (context, statsSnap) {
            if (statsSnap.connectionState != ConnectionState.done) {
              return const _FullPageLoader();
            }
            if (statsSnap.hasError) {
              // If we can't reach Firestore, fall through to Home — the app
              // is still largely usable and the user can retry from there.
              return const HomeScreen();
            }
            final stats = statsSnap.data ?? const <String, dynamic>{};
            final done = stats['hasCompletedInitialAssessment'] == true;
            if (!done) {
              return const AssessmentScreen(mode: AssessmentMode.initial);
            }
            return const HomeScreen();
          },
        );
      },
    );
  }
}

class _FullPageLoader extends StatelessWidget {
  const _FullPageLoader();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
