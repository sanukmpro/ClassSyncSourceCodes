import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileViewScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const ProfileViewScreen({super.key, required this.userData});

  void _showImagePreview(BuildContext context, String? imageUrl) {
    if (imageUrl == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String name = userData['name'] ?? "User";
    final String email = FirebaseAuth.instance.currentUser?.email ?? "";
    final String? profilePic = userData['profilePic'];
    final String bio = userData['bio'] ?? "No bio added yet.";
    final String role = userData['role'] ?? "Student";
    final String? phone = userData['phone'];
    final String? department = userData['department'];

    // Student Data
    final String? semester = userData['semester'];

    // Teacher Data
    final Map<String, dynamic>? semesterSubjects = userData['semesterSubjects'] != null
        ? Map<String, dynamic>.from(userData['semesterSubjects'])
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("My Profile"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.indigo[900],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _showImagePreview(context, profilePic),
                      child: Hero(
                        tag: 'profile_pic_hero',
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.white,
                          backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                          child: profilePic == null
                              ? Icon(Icons.person, size: 50, color: Colors.indigo[900])
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      role.toUpperCase(),
                      style: TextStyle(color: Colors.indigo[100], fontSize: 14, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("About Me"),
                  _buildInfoCard(Icons.info_outline, "Bio", bio),
                  const SizedBox(height: 20),

                  _buildSectionTitle("Contact Information"),
                  _buildInfoCard(Icons.email_outlined, "Email", email),
                  if (phone != null && phone.isNotEmpty)
                    _buildInfoCard(Icons.phone_outlined, "Phone", phone),
                  const SizedBox(height: 20),

                  _buildSectionTitle("Academic Details"),
                  if (department != null)
                    _buildInfoCard(Icons.business_outlined, "Department", department),

                  // Student-specific UI
                  if (role.toLowerCase() == "student" && semester != null)
                    _buildInfoCard(Icons.school_outlined, "Current Semester", "Semester $semester"),

                  // Teacher-specific UI
                  if (role.toLowerCase() == "teacher" && semesterSubjects != null)
                    ...semesterSubjects.entries.map((entry) {
                      final String semNum = entry.key;
                      final List<dynamic> subjects = entry.value is List ? entry.value : [];
                      return _buildInfoCard(
                        Icons.book_outlined,
                        "Semester $semNum Subjects",
                        subjects.join(", "),
                      );
                    }),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.indigo[900]),
        title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(
          value.isEmpty ? "Not assigned" : value,
          style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}