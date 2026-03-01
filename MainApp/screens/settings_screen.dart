import 'dart:async';
import 'dart:io' show Platform; // Required for OS check
import 'package:flutter/foundation.dart' show kIsWeb; // Required for Web safety
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentVersion = "0.0.0";
  bool _isCheckingForUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  /// Fetches version from pubspec.yaml dynamically
  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _currentVersion = info.version;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final User? user = FirebaseAuth.instance.currentUser;

    // Platform Guard: Only true if on physical/emulator Android and NOT web browser
    final bool isAndroid = !kIsWeb && Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // --- APPEARANCE SECTION ---
          _buildSectionHeader("Appearance"),
          _buildSettingsCard(
            child: SwitchListTile(
              secondary: Icon(
                themeProvider.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: Colors.blueAccent,
              ),
              title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(themeProvider.isDarkMode ? "Dark theme enabled" : "Light theme enabled"),
              value: themeProvider.isDarkMode,
              onChanged: (bool value) => themeProvider.toggleTheme(value),
            ),
          ),

          const SizedBox(height: 25),

          // --- ACCOUNT SECURITY SECTION ---
          _buildSectionHeader("Account Security"),
          _buildSettingsCard(
            child: Column(
              children: [
                _buildListTile(
                  icon: Icons.lock_reset_rounded,
                  title: "Change Password",
                  subtitle: "Email link will be sent to your inbox",
                  onTap: () => _handleChangePassword(context, user?.email),
                ),
                const Divider(height: 1, indent: 55),
                _buildListTile(
                  icon: Icons.delete_forever_rounded,
                  iconColor: Colors.redAccent,
                  title: "Delete Account",
                  titleColor: Colors.redAccent,
                  subtitle: "Permanently remove all your data",
                  onTap: () => _showDeleteConfirmation(context, user),
                ),
              ],
            ),
          ),

          const SizedBox(height: 25),

          // --- ABOUT & FEEDBACK SECTION ---
          _buildSectionHeader("About & Feedback"),
          _buildSettingsCard(
            child: Column(
              children: [
                _buildListTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: "Send Feedback",
                  subtitle: "Help us make ClassSync better",
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
                  onTap: () => _launchURL("mailto:sanukmpro@gmail.com?subject=ClassSync Feedback"),
                ),
                const Divider(height: 1, indent: 55),
                _buildListTile(
                  icon: Icons.description_outlined,
                  title: "Privacy Policy",
                  subtitle: "View our terms and conditions",
                  trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.grey),
                  onTap: () => _launchURL("https://drive.google.com/file/d/17bnLVwGuq52Df73aMqeqQylUk1V5Baqr/view?usp=sharing"),
                ),

                // --- CONDITIONAL UPDATE CHECKER (ANDROID ONLY) ---
                if (isAndroid) ...[
                  const Divider(height: 1, indent: 55),
                  _buildListTile(
                    icon: _isCheckingForUpdate ? null : Icons.system_update_rounded,
                    leadingWidget: _isCheckingForUpdate
                        ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : null,
                    title: "Check for Updates",
                    subtitle: "Tap to see if a newer version is available",
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentVersion,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    onTap: _checkForUpdate,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 40),

          // --- BOTTOM FOOTER ---
          Center(
            child: Column(
              children: [
                Text(
                  "v$_currentVersion",
                  style: const TextStyle(
                    color: Colors.black26,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Made with ❤️ for ClassSync",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withOpacity(0.1)),
      ),
      child: child,
    );
  }

  Widget _buildListTile({
    IconData? icon,
    Widget? leadingWidget,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color iconColor = Colors.blueAccent,
    Color titleColor = Colors.black87,
    Widget? trailing,
  }) {
    return ListTile(
      leading: leadingWidget ?? Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(color: titleColor, fontWeight: FontWeight.w500, fontSize: 15),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: trailing ?? const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
      onTap: onTap,
    );
  }

  // --- LOGIC METHODS ---

  Future<void> _checkForUpdate() async {
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_info')
          .doc('version_control')
          .get();

      if (!doc.exists) throw "Update server unreachable.";

      final data = doc.data() as Map<String, dynamic>;
      final String latestVersion = data['latestVersion'] ?? '0.0.0';
      final String releaseNotes = data['releaseNotes'] ?? "Minor improvements and bug fixes.";
      final String? updateUrl = data['updateUrl'];

      if (_isNewerVersion(latestVersion, _currentVersion)) {
        _showUpdateDialog(latestVersion, releaseNotes, updateUrl);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ClassSync is up to date"),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Update Check Failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < latestParts.length; i++) {
        int curr = i < currentParts.length ? currentParts[i] : 0;
        if (latestParts[i] > curr) return true;
        if (latestParts[i] < curr) return false;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  void _showUpdateDialog(String version, String notes, String? url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("New Update v$version"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("A newer version of ClassSync is available. Update now to enjoy new features!"),
            const SizedBox(height: 15),
            const Text("What's New:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(notes, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Later")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (url != null) _launchURL(url);
              Navigator.pop(context);
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  void _handleChangePassword(BuildContext context, String? email) async {
    if (email == null) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reset link sent to your email"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void _showDeleteConfirmation(BuildContext context, User? user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account?"),
        content: const Text("This is irreversible. You will lose all your progress, certificates, and data."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              try {
                // Delete user doc from Firestore first
                await FirebaseFirestore.instance.collection('users').doc(user?.uid).delete();
                // Delete Auth user
                await user?.delete();
                // Restart to Role Selection
                if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
              } catch (e) {
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Please log out and log back in to verify your identity before deleting."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}