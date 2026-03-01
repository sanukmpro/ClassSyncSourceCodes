import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'teacher_id_master.dart';
import 'splash_screen.dart'; // 1. Import your splash screen file

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ClassSyncAdminApp());
}

class ClassSyncAdminApp extends StatelessWidget {
  const ClassSyncAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClassSync Admin',
      // Admin Theme is Red
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true
      ),
      // 2. Start with the Splash Screen
      home: const SplashScreen(),
    );
  }
}

// 3. Create a helper widget to handle the Auth logic after the splash
class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const TeacherIdMasterScreen();
        }
        return const AdminLoginScreen();
      },
    );
  }
}