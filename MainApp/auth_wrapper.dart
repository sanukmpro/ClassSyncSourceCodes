import 'package:class_sync/screens/role_selection.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/student_home.dart';
import 'screens/teacher_home.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  Future<String?> _getUserRole(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      return doc['role']; // "student" or "teacher"
    }
    return null;
  }

  @override

  Widget build(BuildContext context) {

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const RoleSelectionScreen();
        }


        return FutureBuilder<String?>(
          future: _getUserRole(snapshot.data!),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (roleSnapshot.hasData) {
              if (roleSnapshot.data == "student") {
                return const StudentHomeScreen();
              } else if (roleSnapshot.data == "teacher") {
                return const TeacherHomeScreen();
              }
            }
            if (roleSnapshot.hasError) {
              return const Scaffold(
                body: Center(child: Text("Error loading user role")),
              );
            }

            return const RoleSelectionScreen();
          },
        );
      },
    );
  }

}
