import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../screens/student_home.dart';
import 'app_data.dart'; // Ensure this path is correct

class StudentSignupScreen extends StatefulWidget {
  const StudentSignupScreen({super.key});

  @override
  State<StudentSignupScreen> createState() => _StudentSignupScreenState();
}

class _StudentSignupScreenState extends State<StudentSignupScreen> {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  // Selected Values
  String? _selectedDepartment;
  String? _selectedSemester;

  bool _loading = false;
  bool _obscurePassword = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  // --- 1. TRADITIONAL EMAIL SIGNUP ---
  Future<void> _signupEmail() async {
    if (!_validateFields()) return;

    setState(() => _loading = true);
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Traditional signup always creates a new doc because createUser fails if email exists
      await _saveUserToFirestore(userCredential.user!);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showError("This email is already registered. Please login instead.");
      } else {
        _showError(e.message ?? "Signup failed");
      }
    } catch (e) {
      _showError("An unexpected error occurred: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- 2. GOOGLE SIGNUP (With Duplicate Check) ---
  Future<void> _signupWithGoogle() async {
    // Validate Department and Semester before starting Google flow
    if (_selectedDepartment == null || _selectedSemester == null) {
      _showError("Please select Department and Semester first!");
      return;
    }

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

      final userCred = await _auth.signInWithCredential(credential);
      final User? user = userCred.user;

      if (user != null) {
        // --- CRITICAL STEP: Check if user document already exists ---
        final doc = await _firestore.collection('users').doc(user.uid).get();

        if (doc.exists) {
          // User already has an account, prevent data loss (overwriting)
          _showError("Account already exists! Redirecting to Home...");
          _navigateToHome();
        } else {
          // New User: Auto-fill name if controller is empty
          if (_nameController.text.isEmpty) {
            _nameController.text = user.displayName ?? "";
          }
          await _saveUserToFirestore(user);
        }
      }
    } catch (e) {
      _showError("Google Signup failed: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- HELPER: SAVE TO FIRESTORE ---
  Future<void> _saveUserToFirestore(User user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'email': user.email ?? _emailController.text.trim(),
        'department': _selectedDepartment,
        'semester': _selectedSemester,
        'role': 'student',
        'honorScore': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _navigateToHome();
    } catch (e) {
      _showError("Failed to save user data: $e");
    }
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const StudentHomeScreen()),
      );
    }
  }

  bool _validateFields() {
    if (_nameController.text.trim().isEmpty ||
        _selectedDepartment == null ||
        _selectedSemester == null ||
        _emailController.text.trim().isEmpty) {
      _showError("Please fill in Name, Department, Semester, and Email");
      return false;
    }
    if (_passwordController.text.length < 6) {
      _showError("Password must be at least 6 characters");
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Student Signup")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          const Text("Academic Information",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
          const SizedBox(height: 15),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: "Full Name",
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
                labelText: "Department",
                prefixIcon: Icon(Icons.business),
                border: OutlineInputBorder()),
            value: _selectedDepartment,
            items: AppData.departments
                .map((dept) => DropdownMenuItem(value: dept, child: Text(dept)))
                .toList(),
            onChanged: (val) => setState(() => _selectedDepartment = val),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
                labelText: "Current Semester",
                prefixIcon: Icon(Icons.school),
                border: OutlineInputBorder()),
            value: _selectedSemester,
            items: AppData.semesters
                .map((sem) => DropdownMenuItem(value: sem, child: Text("Semester $sem")))
                .toList(),
            onChanged: (val) => setState(() => _selectedSemester = val),
          ),
          const SizedBox(height: 30),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text("EMAIL SIGNUP", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: "Email", prefixIcon: Icon(Icons.email), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: "Password",
              prefixIcon: const Icon(Icons.lock),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 25),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _signupEmail,
            child: const Text("Create Account", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text("OR USE SOCIAL", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: const BorderSide(color: Colors.grey)),
              icon: Image.network(
                'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                height: 24,
              ),
              label: const Text("Sign up with Google", style: TextStyle(fontSize: 16, color: Colors.black87)),
              onPressed: _signupWithGoogle,
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}