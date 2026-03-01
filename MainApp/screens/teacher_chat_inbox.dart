import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'chat_utils.dart';

class TeacherChatInboxScreen extends StatefulWidget {
  const TeacherChatInboxScreen({super.key});

  @override
  State<TeacherChatInboxScreen> createState() => _TeacherChatInboxScreenState();
}

class _TeacherChatInboxScreenState extends State<TeacherChatInboxScreen> {
  // This is the UID (e.g., MmTA8lIJm5Tbykl3yrIqg0owfpa2)
  final String _authUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // No need to fetch teacherId anymore for the query,
    // but we check if user is logged in
    if (_authUid.isNotEmpty) {
      setState(() => _isLoading = false);
    }
  }

  // --- STUDENT DETAIL POPUP ---
  void _showStudentDetails(BuildContext context, String studentId, String studentName) {
    showDialog(
      context: context,
      builder: (context) => FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final String? pic = userData?['profilePic'];
          final String bio = userData?['bio'] ?? "No bio available.";
          final String dept = userData?['department'] ?? "Not assigned";
          final String sem = userData?['semester'] ?? "N/A";

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: EdgeInsets.zero,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        color: Colors.indigo.shade900,
                        image: pic != null
                            ? DecorationImage(image: NetworkImage(pic), fit: BoxFit.cover)
                            : null,
                      ),
                      child: pic == null
                          ? const Icon(Icons.person, size: 80, color: Colors.white)
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
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(studentName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Semester $sem • $dept", style: TextStyle(color: Colors.grey.shade600)),
                      const Divider(height: 24),
                      Text(bio, textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Student Consultations",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildChatList(),
    );
  }

  Widget _buildChatList() {
    return StreamBuilder<QuerySnapshot>(
      // FIXED: Querying using the Auth UID as found in your Firestore screenshot
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _authUid)
          .orderBy('lastTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint("Firestore Error: ${snapshot.error}");
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final chatDocs = snapshot.data!.docs;
        if (chatDocs.isEmpty) {
          return const Center(child: Text("No incoming messages yet."));
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: chatDocs.length,
          separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
          itemBuilder: (context, index) {
            final data = chatDocs[index].data() as Map<String, dynamic>;
            final String chatRoomId = chatDocs[index].id;

            // Logic to find the recipient (Student) UID from the array
            final List participants = data['participants'] ?? [];
            final String studentId = participants.firstWhere(
                    (id) => id != _authUid,
                orElse: () => "");

            // Logic to find the Student Name from the map provided in your info
            final String studentName = (data['participantNames'] as Map?)?[studentId] ?? "Student";
            final String lastMsg = data['lastMessage'] ?? "No messages yet";
            final Timestamp? timestamp = data['lastTimestamp'] as Timestamp?;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(studentId).get(),
                builder: (context, userSnap) {
                  String? profilePicUrl;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    profilePicUrl = (userSnap.data!.data() as Map<String, dynamic>?)?['profilePic'];
                  }

                  return GestureDetector(
                    onTap: () => _showStudentDetails(context, studentId, studentName),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.indigo.shade50,
                      backgroundImage: (profilePicUrl != null && profilePicUrl.isNotEmpty)
                          ? NetworkImage(profilePicUrl)
                          : null,
                      child: (profilePicUrl == null || profilePicUrl.isEmpty)
                          ? Text(
                        studentName.isNotEmpty ? studentName[0].toUpperCase() : "S",
                        style: const TextStyle(color: Color(0xFF075E54), fontWeight: FontWeight.bold),
                      )
                          : null,
                    ),
                  );
                },
              ),
              title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    timestamp != null ? ChatUtils.formatTimestamp(timestamp) : "",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 5),
                  _buildUnreadBadge(chatRoomId),
                ],
              ),
              onTap: () {
                // When teacher opens the chat, mark it as claimed
                FirebaseFirestore.instance.collection('chats').doc(chatRoomId).update({
                  'isClaimed': true,
                  'claimedByUid': _authUid,
                });

                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                  chatRoomId: chatRoomId,
                  recipientId: studentId,
                  recipientName: studentName,
                )));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildUnreadBadge(String chatId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('status', isEqualTo: 'sent')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        // Count messages where the sender is NOT the current user (Teacher)
        final count = snap.data!.docs.where((d) => d['senderId'] != _authUid).length;
        if (count == 0) return const SizedBox();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(12)),
          child: Text("$count", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}