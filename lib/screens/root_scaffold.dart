import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'badges_screen.dart';
import 'home_screen.dart';
import 'practice_hub_screen.dart';
import 'profile_screen.dart';

/// Top-level scaffold that owns the bottom navigation bar and an IndexedStack
/// of the four primary tabs. Using IndexedStack (instead of Navigator.push per
/// tab like the previous home screen did) preserves each tab's state — scroll
/// position, loaded data, animations — so switching tabs is instant and the
/// user's context isn't lost.
///
/// Badges are read from a Firestore stream here (not inside HomeScreen) so
/// the Awards tab gets live updates when the user earns a new badge in the
/// middle of a session, without the stale-snapshot problem of passing a list
/// into an IndexedStack child at construction time.
class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _currentIndex = 0;
  List<String> _badges = const [];

  Stream<DocumentSnapshot<Map<String, dynamic>>>? get _userDocStream {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null) {
          _badges = List<String>.from(data['badges'] ?? const []);
        }

        return PopScope(
          canPop: _currentIndex == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _currentIndex != 0 && mounted) {
              setState(() => _currentIndex = 0);
            }
          },
          child: Scaffold(
            body: IndexedStack(
              index: _currentIndex,
              children: [
                const HomeScreen(),
                const PracticeHubScreen(),
                BadgesScreen(unlockedBadges: _badges),
                const ProfileScreen(),
              ],
            ),
            bottomNavigationBar: _buildBottomNavBar(),
          ),
        );
      },
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      // Suppress the default ink ripple that radiates from each nav item
      // on tap — selection color alone is enough feedback.
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
        currentIndex: _currentIndex,
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.record_voice_over_rounded),
            label: 'Practice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events_rounded),
            label: 'Awards',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
        ),
      ),
    );
  }
}
