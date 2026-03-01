import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'teacher_home.dart';
import 'teacher_id_request.dart';

class TeacherLoginScreen extends StatefulWidget {
  const TeacherLoginScreen({super.key});

  @override
  State<TeacherLoginScreen> createState() => _TeacherLoginScreenState();
}

class _TeacherLoginScreenState extends State<TeacherLoginScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _loading = false;

  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      final String currentUid = _auth.currentUser!.uid;
      final String userEmail = googleUser.email.trim().toLowerCase();

      // 1. Check if the user is already fully registered
      final userDoc = await _firestore.collection('users').doc(currentUid).get();
      if (userDoc.exists && userDoc.data()?['role'] == 'teacher') {
        _navigateToHome();
        return;
      }

      // 2. Check if this Email is pre-approved in the 'teacher_ids' collection
      // Query looking for a document where email matches and admin has approved it
      final teacherIdQuery = await _firestore
          .collection('teacher_ids')
          .where('email', isEqualTo: userEmail)
          .where('isApproved', isEqualTo: true)
          .limit(1)
          .get();

      if (teacherIdQuery.docs.isEmpty) {
        await _handleLogout();
        _showSnack("Access Denied: Your email is not approved by Admin.");
        return;
      }

      // 3. Prompt the teacher to enter their specific Teacher ID to link the account
      _showLinkIDPrompt();

    } catch (e) {
      debugPrint("Login Error: $e");
      _showSnack("Login Error. Check connection.");
      await _handleLogout();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showLinkIDPrompt() {
    final idController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Verify Teacher ID"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Enter the unique Teacher ID assigned to your email:"),
                const SizedBox(height: 15),
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: "Teacher ID",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await _handleLogout();
                  Navigator.pop(context);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  final enteredID = idController.text.trim();
                  if (enteredID.isEmpty) return;

                  setDialogState(() => isSubmitting = true);

                  try {
                    // Check if the ID exists in teacher_ids collection
                    final masterDoc = await _firestore.collection('teacher_ids').doc(enteredID).get();

                    if (!masterDoc.exists) {
                      _showSnack("Invalid ID. Please check and try again.");
                      setDialogState(() => isSubmitting = false);
                      return;
                    }

                    final data = masterDoc.data()!;
                    final String masterEmail = (data['email'] ?? "").toLowerCase();
                    final String currentEmail = _auth.currentUser!.email!.toLowerCase();

                    // Security check: Ensure the ID belongs to the logged-in email
                    if (masterEmail != currentEmail) {
                      _showSnack("This ID belongs to another email address.");
                      setDialogState(() => isSubmitting = false);
                      return;
                    }

                    if (data['isClaimed'] == true) {
                      _showSnack("This ID is already linked to another account.");
                      setDialogState(() => isSubmitting = false);
                      return;
                    }

                    // --- LINKING PROCESS ---
                    final currentUid = _auth.currentUser!.uid;
                    final batch = _firestore.batch();

                    // 1. Mark the ID as claimed
                    batch.update(masterDoc.reference, {
                      'claimedByUid': currentUid,
                      'isClaimed': true,
                      'lastLogin': FieldValue.serverTimestamp(),
                    });

                    // 2. Create the official user profile
                    batch.set(_firestore.collection('users').doc(currentUid), {
                      'role': 'teacher',
                      'teacherId': enteredID,
                      'email': currentEmail,
                      'name': data['name'] ?? "Teacher",
                      'department': data['department'] ?? "N/A", // Important for filtering content
                      'createdAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    await batch.commit();

                    if (mounted) {
                      Navigator.pop(context);
                      _navigateToHome();
                    }
                  } catch (e) {
                    _showSnack("Verification failed. Try again.");
                    setDialogState(() => isSubmitting = false);
                  }
                },
                child: isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Verify & Login"),
              )
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    await _auth.signOut();
    await GoogleSignIn().signOut();
    if (mounted) setState(() => _loading = false);
  }

  void _navigateToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const TeacherHomeScreen()),
          (route) => false,
    );
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school_rounded, size: 100, color: Colors.indigo),
              const SizedBox(height: 20),
              const Text("Teacher Portal",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo)),
              const SizedBox(height: 10),
              const Text("Secure login for authorized faculty",
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),

              if (_loading)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                    onPressed: _loginWithGoogle,
                    icon: const Icon(Icons.login),
                    label: const Text("Sign in with Google", style: TextStyle(fontSize: 16)),
                  ),
                ),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeacherIdRequestScreen())
                ),
                child: const Text("Don't have an ID? Request Verification"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}