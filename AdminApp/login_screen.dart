import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'teacher_id_master.dart';
import 'dart:ui';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  bool _isLoading = false;
  final TextEditingController _pinController = TextEditingController();

  // --- STEP 1: Google Authentication ---
  Future<void> _handleGoogleAuth() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      // --- STEP 2: Firestore Whitelist Check ---
      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(googleUser.email.toLowerCase())
          .get();

      if (!adminDoc.exists) {
        await GoogleSignIn().signOut();
        _showError("Unauthorized: This account is not an admin.");
        setState(() => _isLoading = false);
        return;
      }

      // --- STEP 3: 2-Factor PIN Authentication ---
      String storedPin = adminDoc.data()?['accessKey'] ?? "";
      if (mounted) {
        _showPinDialog(googleUser, storedPin);
      }
    } catch (e) {
      _showError("Auth Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- STEP 4: Secondary PIN Dialog (2FA) ---
  void _showPinDialog(GoogleSignInAccount googleUser, String correctPin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.grey.shade900.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Secondary Verification", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Enter your 6-digit Admin Access Key",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black26,
                  counterText: "", // Hides the counter to prevent UI clutter
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  _pinController.clear();
                  Navigator.pop(context);
                },
                child: const Text("Cancel", style: TextStyle(color: Colors.red))
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _verifyAndFinalize(googleUser, correctPin),
              child: const Text("Verify & Login"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyAndFinalize(GoogleSignInAccount googleUser, String correctPin) async {
    if (_pinController.text == correctPin) {
      try {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await FirebaseAuth.instance.signInWithCredential(credential);

        if (mounted) {
          _pinController.clear();
          Navigator.pop(context); // Close dialog
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const TeacherIdMasterScreen())
          );
        }
      } catch (e) {
        _showError("Login Error: $e");
      }
    } else {
      _showError("Invalid Access Key!");
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), // Sleek Dark
      body: Stack(
        children: [
          // Background Aesthetic Decoration
          Positioned(
            top: -100,
            right: -100,
            child: CircleAvatar(radius: 150, backgroundColor: Colors.red.withOpacity(0.1)),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shield Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 20, spreadRadius: 5)
                      ]
                  ),
                  child: const Icon(Icons.shield_outlined, size: 80, color: Colors.red),
                ),
                const SizedBox(height: 30),
                const Text("CLASSSYNC",
                    style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 4)),
                const Text("ADMINISTRATOR CORE",
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 60),

                if (_isLoading)
                  const CircularProgressIndicator(color: Colors.red)
                else
                  SizedBox(
                    width: 250,
                    height: 55,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                      ),
                      onPressed: _handleGoogleAuth,
                      icon: Image.network(
                        'https://www.gstatic.com/images/branding/product/2x/googleg_48dp.png',
                        height: 24,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_circle, color: Colors.grey),
                      ),
                      label: const Text("System Authenticate", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}