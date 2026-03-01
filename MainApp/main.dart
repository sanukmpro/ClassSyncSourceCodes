import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// Import screens
import 'package:class_sync/screens/role_selection_screen.dart';
import 'package:class_sync/screens/student_home.dart';
import 'package:class_sync/screens/teacher_home.dart';
import 'package:class_sync/screens/splash_screen.dart';

// --- THEME PROVIDER ---
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeProvider() { _loadTheme(); }

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', isOn);
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    bool isDark = prefs.getBool('isDarkMode') ?? false;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

// --- BACKGROUND MESSAGE HANDLER ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Class Sync',
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: Colors.indigo,
            scaffoldBackgroundColor: Colors.grey[50],
            appBarTheme: const AppBarTheme(backgroundColor: Colors.indigo, foregroundColor: Colors.white, centerTitle: true),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: Colors.indigo,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1F1F1F), foregroundColor: Colors.white, centerTitle: true),
          ),
          themeMode: themeProvider.themeMode,
          // APP STARTS HERE: Splash Screen handles the initial animation
          home: const SplashScreen(),
        );
      },
    );
  }
}

// --- AUTHENTICATION & ROLE GATE ---
// This is called by the SplashScreen after the animation ends
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<void> _setupMessaging(String uid) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return;
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'fcmToken': token,
            'lastActive': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) { debugPrint("Messaging Setup Skipped: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!authSnapshot.hasData) {
          return const RoleSelectionScreen();
        }

        final user = authSnapshot.data!;
        _setupMessaging(user.uid);
        return _buildRoleChecker(user.uid);
      },
    );
  }

  Widget _buildRoleChecker(String uid) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (roleSnapshot.hasData && roleSnapshot.data!.exists) {
          final data = roleSnapshot.data!.data() as Map<String, dynamic>;
          final String role = data['role'] ?? 'student';
          return (role == 'teacher') ? const TeacherHomeScreen() : const StudentHomeScreen();
        }

        return const RoleSelectionScreen();
      },
    );
  }
}