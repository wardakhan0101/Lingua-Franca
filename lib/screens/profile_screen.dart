import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const ProfileScreen({super.key, this.initialData});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Palette
  static const Color primaryPurple = Color(0xFF8A48F0);
  static const Color softBackground = Color(0xFFF7F7FA);
  static const Color textDark = Color(0xFF101828);
  static const Color textGrey = Color(0xFF667085);
  static const Color fireRed = Color(0xFFFF0000);
  static const Color xpYellow = Color(0xFFFF9900);

  bool _isLoading = true;
  bool _isUpdatingPhoto = false;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      // Render immediately with cached stats from the parent screen,
      // then silently refresh in the background to pick up any changes.
      _data = Map<String, dynamic>.from(widget.initialData!);
      _isLoading = false;
      _refreshSilently();
    } else {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;
      setState(() {
        _data = doc.data() ?? {};
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshSilently() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;
      final fresh = doc.data();
      if (fresh != null) setState(() => _data = fresh);
    } catch (_) {
      // Ignore — cached copy is already on screen.
    }
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  Future<void> _editUsername() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final currentName = (_data['username'] as String?) ??
        user.displayName ??
        '';
    final controller = TextEditingController(text: currentName);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Username'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Enter your username',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryPurple, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: textGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == currentName) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'username': result}, SetOptions(merge: true));
      await user.updateDisplayName(result);
      setState(() => _data['username'] = result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update username: $e')),
        );
      }
    }
  }

  Future<void> _pickProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (result == null || result.files.single.path == null) return;

      setState(() => _isUpdatingPhoto = true);

      final bytes = await File(result.files.single.path!).readAsBytes();
      // Firestore doc cap is ~1MB. Reject oversized encodings to stay safe.
      if (bytes.lengthInBytes > 700 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image is too large. Please pick a smaller one (under ~700 KB).')),
          );
        }
        setState(() => _isUpdatingPhoto = false);
        return;
      }
      final base64Str = base64Encode(bytes);

      await _firestore
          .collection('users')
          .doc(user.uid)
          .set({'photoBase64': base64Str}, SetOptions(merge: true));

      setState(() {
        _data['photoBase64'] = base64Str;
        _isUpdatingPhoto = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture updated')),
        );
      }
    } catch (e) {
      setState(() => _isUpdatingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update picture: $e')),
        );
      }
    }
  }

  String _formatJoinedDate(DateTime? date) {
    if (date == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: softBackground,
        body: Center(child: CircularProgressIndicator(color: primaryPurple)),
      );
    }

    final user = _auth.currentUser;
    final String username = (_data['username'] as String?) ??
        user?.displayName ??
        'Language Learner';
    final String email = user?.email ?? 'user@example.com';
    final String? photoBase64 = _data['photoBase64'] as String?;
    final String? photoUrl = user?.photoURL;

    final int totalXp = _data['totalXp'] ?? 0;
    final int currentStreak = _data['currentStreak'] ?? 0;
    final int longestStreak = _data['longestStreak'] ?? 0;
    final int totalSessions = _data['totalSessions'] ?? 0;
    final String level = _data['currentLevel'] ?? 'B1';
    final List<String> badges = List<String>.from(_data['badges'] ?? const []);
    // Source of truth for signup date is Firebase Auth — it's stamped at account creation
    // and is accurate even for accounts that pre-date our Firestore 'joinedAt' field.
    final DateTime? creationTime = user?.metadata.creationTime;
    final String memberSince = _formatJoinedDate(creationTime);

    ImageProvider? avatarImage;
    if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(photoBase64));
      } catch (_) {
        avatarImage = null;
      }
    } else if (photoUrl != null && photoUrl.isNotEmpty) {
      avatarImage = NetworkImage(photoUrl);
    }

    return Scaffold(
      backgroundColor: softBackground,
      appBar: AppBar(
        backgroundColor: softBackground,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: textDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: primaryPurple,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildHeader(username, email, avatarImage),
              const SizedBox(height: 12),
              _buildLevelChip(level),
              const SizedBox(height: 32),
              _buildStatsRow(currentStreak, totalXp),
              const SizedBox(height: 16),
              _buildSecondaryStats(longestStreak, totalSessions, badges.length),
              const SizedBox(height: 16),
              _buildMemberSinceCard(memberSince),
              const SizedBox(height: 32),
              _buildLogoutButton(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String username, String email, ImageProvider? avatarImage) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: primaryPurple.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? const Icon(Icons.person, size: 50, color: textGrey)
                      : null,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _isUpdatingPhoto ? null : _pickProfilePicture,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primaryPurple,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: _isUpdatingPhoto
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  username,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _editUsername,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 16, color: primaryPurple),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(fontSize: 14, color: textGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelChip(String level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: primaryPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Level $level',
        style: const TextStyle(
          color: primaryPurple,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildStatsRow(int streak, int xp) {
    return Row(
      children: [
        _buildStatCard(
          'Streak',
          '$streak',
          'Days',
          Icons.local_fire_department,
          fireRed,
        ),
        const SizedBox(width: 16),
        _buildStatCard(
          'XP',
          '$xp',
          'Pts',
          Icons.flash_on,
          xpYellow,
        ),
      ],
    );
  }

  Widget _buildSecondaryStats(int longestStreak, int totalSessions, int badgeCount) {
    return Row(
      children: [
        _buildSmallStatCard(
          'Longest Streak',
          '$longestStreak',
          Icons.trending_up_rounded,
          const Color(0xFF12B76A),
        ),
        const SizedBox(width: 12),
        _buildSmallStatCard(
          'Sessions',
          '$totalSessions',
          Icons.mic_rounded,
          const Color(0xFF2E90FA),
        ),
        const SizedBox(width: 12),
        _buildSmallStatCard(
          'Badges',
          '$badgeCount',
          Icons.military_tech_rounded,
          const Color(0xFFD4AF37),
        ),
      ],
    );
  }

  Widget _buildMemberSinceCard(String memberSince) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryPurple.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.calendar_today_rounded, color: primaryPurple, size: 18),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Member Since',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                memberSince,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _signOut,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: const Color(0xFFFEE4E2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout, color: Color(0xFFD92D20)),
            SizedBox(width: 8),
            Text(
              'Log Out',
              style: TextStyle(
                color: Color(0xFFD92D20),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, String unit, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: unit,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
