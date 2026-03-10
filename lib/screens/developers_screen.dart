import 'package:flutter/material.dart';

import 'package:lingua_franca/screens/sherpa_stt_test.dart';
import 'package:lingua_franca/screens/timed_presentation_screen.dart';
import 'package:lingua_franca/services/auth_service.dart';
import 'package:lingua_franca/screens/login_screen.dart';
import 'package:lingua_franca/screens/native_stt_screen_test.dart';
import 'package:lingua_franca/screens/accent_test_screen.dart';

import 'chat_screen_test.dart';

class DevelopersScreen extends StatelessWidget {
  const DevelopersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Developer Tools"),
        backgroundColor: const Color(0xFF9B7EC9),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF7BB9E8),
              Color(0xFF9B7EC9),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Dev & Testing Area',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (user?.email != null)
                    Text(
                      'Logged as: ${user!.email!}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  const SizedBox(height: 48),

                  // Start Conversation (Legacy Test)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ChatScreenTest(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF6B72AB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Test Chat Interface'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // STT NATIVE BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const NativeSttScreenTest(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B72AB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic_none, size: 24),
                          SizedBox(width: 8),
                          Text('Test Native STT'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sherpa Onnx STT Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SherpaSttTest(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B72AB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic_none, size: 24),
                          SizedBox(width: 8),
                          Text('Test sherpa_onnx STT'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const TimedPresentationScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B72AB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.mic_none, size: 24),
                          SizedBox(width: 8),
                          Text('Test deepgram'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Test TTS Engine Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AccentTestScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B72AB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.record_voice_over, size: 24),
                          SizedBox(width: 8),
                          Text('Test TTS Engine'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Spacer(),

                  // Sign Out Button
                  TextButton.icon(
                    onPressed: () async {
                      await authService.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text(
                      'Sign Out',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
