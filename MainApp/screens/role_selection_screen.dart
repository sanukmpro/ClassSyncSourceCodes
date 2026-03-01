import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';import 'package:package_info_plus/package_info_plus.dart';
import 'student_login.dart';
import 'teacher_login.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  String _currentVersion = "v1.0.0"; // Fallback version

  @override
  void initState() {
    super.initState();
    _loadAppVersion();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );

    _fadeController.forward();
  }

  /// Fetches version from pubspec.yaml dynamically
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentVersion = "v${info.version}";
        });
      }
    } catch (e) {
      debugPrint("Error loading version: $e");
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleRoleNavigation(BuildContext context, Widget screen) async {
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint("Logout error: $e");
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(color: Colors.white),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- LOGO MADE BIGGER ---
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 300,
                      height: 300,
                    ),
                    const SizedBox(height: 20),
                    //const Text(
                      //"ClassSync",
                      //style: TextStyle(
                        //fontSize: 32,
                        //fontWeight: FontWeight.bold,
                        //color: Color(0xFF1A237E),
                        //letterSpacing: 1.2,
                      //),
                    //),
                    const Text(
                      "Choose your portal to continue",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 60),

                    // --- CALLING THE CORRECTED FUNCTION ---
                    _buildRoleCard(
                      title: "Student",
                      subtitle: "Access notes, PYQs, and forums",
                      icon: Icons.school_rounded,
                      primaryColor: const Color(0xFF1A237E),
                      onTap: () => _handleRoleNavigation(context, const StudentLoginScreen()),
                    ),

                    const SizedBox(height: 20),

                    _buildRoleCard(
                      title: "Faculty",
                      subtitle: "Manage content and approvals",
                      icon: Icons.assignment_ind_rounded,
                      primaryColor: const Color(0xFF3F51B5),
                      onTap: () => _handleRoleNavigation(context, const TeacherLoginScreen()),
                    ),

                    const SizedBox(height: 40),

                    // --- DYNAMIC VERSION ---
                    Text(
                      _currentVersion,
                      style: const TextStyle(color: Colors.black26, fontSize: 12),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- FUNCTION DEFINITION CORRECTED ---
  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: primaryColor.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 30, color: primaryColor),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: primaryColor.withOpacity(0.3), size: 18)
              ],
            ),
          ),
        ),
      ),
    );
  }
}