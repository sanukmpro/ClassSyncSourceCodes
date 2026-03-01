import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../screens/student_home.dart';
import 'package:class_sync/screens/student_signup.dart';

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  // CRITICAL: We do NOT initialize GoogleSignIn here anymore because
  // just calling the constructor crashes Windows.
  // We will initialize it only when needed on Mobile/Web.
  GoogleSignIn? _googleSignIn;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Initialize GoogleSignIn ONLY if we are NOT on Windows/Desktop
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      _googleSignIn = GoogleSignIn(
        clientId: "492706844423-tu054p5vrcgrk0vergole7vj31ju05vn.apps.googleusercontent.com",
      );
    }
  }

  // --- GOOGLE LOGIN LOGIC (STABILIZED FOR WINDOWS) ---
  Future<void> _loginWithGoogle() async {
    setState(() => _loading = true);
    try {
      UserCredential userCred;

      // 1. WINDOWS / DESKTOP FLOW
      // This opens the system browser, lets the user pick an account,
      // and redirects back to the app automatically.
      if (!kIsWeb && Platform.isWindows) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        // Force the selection of an account in the browser
        googleProvider.setCustomParameters({'prompt': 'select_account'});

        // This is the stable Desktop method
        userCred = await _auth.signInWithProvider(googleProvider);
      }

      // 2. WEB FLOW
      else if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        userCred = await _auth.signInWithPopup(googleProvider);
      }

      // 3. MOBILE FLOW (Android/iOS)
      else {
        final GoogleSignInAccount? googleUser = await _googleSignIn?.signIn();
        if (googleUser == null) {
          setState(() => _loading = false);
          return;
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        userCred = await _auth.signInWithCredential(credential);
      }

      // --- COMMON SUCCESS LOGIC ---
      final User? user = userCred.user;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (doc.exists && doc.data()?['role'] == 'student') {
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const StudentHomeScreen()),
                  (route) => false,
            );
          }
        } else {
          await _auth.signOut();
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            await _googleSignIn?.signOut();
          }
          _showError("No student account found. Please sign up first.");
        }
      }
    } on FirebaseAuthException catch (e) {
      debugPrint("Firebase Auth Error (${e.code}): ${e.message}");
      if (e.code != 'cancelled' && e.code != 'popup-closed-by-user') {
        _showError(e.message ?? "Authentication failed.");
      }
    } catch (e) {
      debugPrint("General Google Login Error: $e");
      _showError("Sign-in failed. Please use Email/Password on this device.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- STANDARD EMAIL LOGIN ---
  Future<void> _loginStudent() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      _showError("Please fill in all fields.");
      return;
    }
    setState(() => _loading = true);
    try {
      final userCred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final doc = await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).get();
      if (doc.exists && doc['role'] == "student") {
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const StudentHomeScreen()),
                (route) => false,
          );
        }
      } else {
        await _auth.signOut();
        _showError("This account is not registered as a student.");
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Login failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) { _showError("Enter email to reset password."); return; }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reset link sent!"), backgroundColor: Colors.green),
        );
      }
    } catch (e) { _showError("Error sending reset email."); }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the Google Logo source safely
    const String googleLogoUrl = 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png';

    return Scaffold(
      appBar: AppBar(title: const Text("Student Login")),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Icon(Icons.school, size: 80, color: Colors.indigo),
                const SizedBox(height: 10),
                const Text("Welcome Back", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: "Password",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword)
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _forgotPassword,
                    child: const Text("Forgot Password?", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const CircularProgressIndicator()
                else ...[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 55),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white),
                    onPressed: _loginStudent,
                    child: const Text("Login"),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text("OR CONTINUE WITH", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: OutlinedButton.icon(
                      icon: Image.network(googleLogoUrl, height: 24, errorBuilder: (c, e, s) => const Icon(Icons.login)),
                      label: const Text("Google Login", style: TextStyle(color: Colors.black)),
                      onPressed: _loginWithGoogle,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                TextButton(
                  onPressed: _loading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (context) => const StudentSignupScreen())),
                  child: const Text("No account yet? Sign up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}