import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class TeacherDirectoryScreen extends StatefulWidget {
  const TeacherDirectoryScreen({super.key});

  @override
  State<TeacherDirectoryScreen> createState() => _TeacherDirectoryScreenState();
}

class _TeacherDirectoryScreenState extends State<TeacherDirectoryScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";

  String _searchQuery = "";
  String? _studentDept;
  String? _studentName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    if (_currentUserId.isEmpty) return;
    try {
      final doc = await _firestore.collection('users').doc(_currentUserId).get();
      if (mounted && doc.exists) {
        setState(() {
          _studentDept = doc.data()?['department'];
          _studentName = doc.data()?['name'] ?? "Student";
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading student data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UPDATED: FACULTY DETAIL POPUP (Removed Teacher ID) ---
  void _showFacultyDetails(BuildContext context, String teacherId, String teacherName) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<QuerySnapshot>(
        future: _firestore.collection('users').where('teacherId', isEqualTo: teacherId).limit(1).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text("Profile not found"));

          final userDoc = snapshot.data!.docs.first;
          final userData = userDoc.data() as Map<String, dynamic>;
          final String actualTeacherUid = userDoc.id;

          final String? pic = userData['profilePic'];
          final String bio = userData['bio'] ?? "No bio available.";
          final String dept = userData['department'] ?? "Not assigned";

          final Map<String, dynamic> semSubjects = userData['semesterSubjects'] != null
              ? Map<String, dynamic>.from(userData['semesterSubjects'])
              : {};

          List<String> allSubjects = [];
          semSubjects.forEach((key, value) {
            if (value is List) allSubjects.addAll(value.map((e) => e.toString()));
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: EdgeInsets.zero,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        color: Colors.indigo[800],
                        image: pic != null
                            ? DecorationImage(image: NetworkImage(pic), fit: BoxFit.cover)
                            : null,
                      ),
                      child: pic == null
                          ? const Icon(Icons.person, size: 70, color: Colors.white)
                          : null,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: CircleAvatar(
                        backgroundColor: Colors.black26,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Text(teacherName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(dept, style: TextStyle(color: Colors.indigo[800], fontWeight: FontWeight.w600)),
                      const Divider(height: 24),
                      const Text("BIO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic)),
                      if (allSubjects.isNotEmpty) ...[
                        const Divider(height: 24),
                        const Text("TEACHING", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(allSubjects.join(" • "), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _startConsultation(actualTeacherUid, teacherName);
                        },
                        icon: const Icon(Icons.chat_bubble),
                        label: const Text("START CONSULTATION"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo[800],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _startConsultation(String teacherUid, String teacherName) async {
    if (teacherUid.isEmpty) return;
    List<String> ids = [_currentUserId, teacherUid];
    ids.sort();
    String chatRoomId = ids.join('_');

    await _firestore.collection('chats').doc(chatRoomId).set({
      'participants': ids,
      'participantNames': {
        _currentUserId: _studentName,
        teacherUid: teacherName,
      },
      'lastTimestamp': FieldValue.serverTimestamp(),
      'department': _studentDept,
    }, SetOptions(merge: true));

    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
      chatRoomId: chatRoomId,
      recipientId: teacherUid,
      recipientName: teacherName,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Verified Faculty", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildApprovedTeacherList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: Colors.indigo[800],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "Search faculty name...", // Hint updated
          hintStyle: const TextStyle(color: Colors.white60),
          prefixIcon: const Icon(Icons.search, color: Colors.white60),
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildApprovedTeacherList() {
    if (_studentDept == null || _studentDept!.isEmpty) {
      return _buildEmptyState(Icons.error_outline, "Please update your department in your profile.");
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('teacher_ids')
          .where('isApproved', isEqualTo: true)
          .where('department', isEqualTo: _studentDept)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final approvedDocs = snapshot.data!.docs;
        final filteredTeachers = approvedDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? "").toString().toLowerCase();
          // We still keep search by teacherId logic internally if needed, but UI hint is removed
          return name.contains(_searchQuery);
        }).toList();

        if (filteredTeachers.isEmpty) {
          return _buildEmptyState(Icons.verified_user_outlined, "No faculty members found in your department.");
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredTeachers.length,
          itemBuilder: (context, index) {
            final adminData = filteredTeachers[index].data() as Map<String, dynamic>;
            final String teacherId = adminData['teacherId'] ?? "N/A";
            final String name = adminData['name'] ?? "Faculty Member";

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: GestureDetector(
                  onTap: () => _showFacultyDetails(context, teacherId, name),
                  child: _buildTeacherAvatar(teacherId, name),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("Verified Faculty", style: TextStyle(fontSize: 12, color: Colors.indigo[800], fontWeight: FontWeight.w500)), // Masked Teacher ID
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.chat_bubble_rounded, color: Colors.indigo[800], size: 20),
                ),
                onTap: () async {
                  final userQuery = await _firestore.collection('users').where('teacherId', isEqualTo: teacherId).limit(1).get();
                  if (userQuery.docs.isNotEmpty) {
                    _startConsultation(userQuery.docs.first.id, name);
                  }
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTeacherAvatar(String teacherId, String name) {
    return FutureBuilder<QuerySnapshot>(
      future: _firestore.collection('users').where('teacherId', isEqualTo: teacherId).limit(1).get(),
      builder: (context, snapshot) {
        String? profilePicUrl;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final userData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          profilePicUrl = userData['profilePic'];
        }
        return CircleAvatar(
          radius: 28,
          backgroundColor: Colors.indigo[50],
          backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty) ? NetworkImage(profilePicUrl) : null,
          child: (profilePicUrl == null || profilePicUrl.isEmpty)
              ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'T',
              style: TextStyle(color: Colors.indigo[800], fontWeight: FontWeight.bold, fontSize: 18))
              : null,
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
