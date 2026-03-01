import 'package:flutter/material.dart';
import 'student_home.dart';
import 'teacher_home.dart';



class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void navigateTo(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Your Role')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => navigateTo(context, const StudentHomeScreen()),
              child: const Text('Student'),
            ),
            ElevatedButton(
              onPressed: () => navigateTo(context, const TeacherHomeScreen()),
              child: const Text('Teacher'),
            ),
          ],
        ),
      ),
    );
  }
}
