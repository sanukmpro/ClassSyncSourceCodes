import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'chat_utils.dart';
import 'forum_detail_screen.dart'; // Ensure this filename is correct

class MailBoxScreen extends StatefulWidget {
  const MailBoxScreen({super.key});

  @override
  State<MailBoxScreen> createState() => _MailBoxScreenState();
}

class _MailBoxScreenState extends State<MailBoxScreen> {
  String _userRole = "student";
  bool _isLoading = true;
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? "";

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = (doc.data()?['role'] ?? "student").toString().toLowerCase();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isTeacher => _userRole == 'teacher';

  void _confirmDelete(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Notification?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final Color primaryColor = _isTeacher ? const Color(0xFF2E7D32) : const Color(0xFF303F9F);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(_isTeacher ? "Faculty Mailbox" : "My Notifications"),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: _myUid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return _buildEmptyState();

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return _buildNotificationTile(docs[index].id, data, primaryColor);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(String docId, Map<String, dynamic> data, Color themeColor) {
    final type = data['notificationType'] ?? 'chat';
    final bool isRead = data['isRead'] ?? false;
    final bool isUrgent = type == 'penalty' || type == 'system';

    IconData icon;
    Color color;

    if (isUrgent) {
      icon = Icons.report_problem_rounded;
      color = Colors.red.shade700;
    } else if (type == 'forum') {
      icon = Icons.forum_rounded;
      color = Colors.orange.shade800;
    } else {
      icon = Icons.chat_bubble_rounded;
      color = themeColor;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: !isRead ? Border.all(color: color.withOpacity(0.2), width: 1) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color),
            ),
            if (!isRead)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isUrgent ? Colors.red : Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          data['senderName'] ?? "System",
          style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(data['message'] ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(ChatUtils.formatTimestamp(data['timestamp'] as Timestamp?), style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.grey),
          onPressed: () => _confirmDelete(docId),
        ),
        onTap: () => _handleNavigation(docId, data, type),
      ),
    );
  }

  Future<void> _handleNavigation(String docId, Map<String, dynamic> data, String type) async {
    // Mark as read immediately
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({'isRead': true});

    if (!mounted) return;

    if (type == 'chat' && data['chatRoomId'] != null) {
      Navigator.push(context, MaterialPageRoute(builder: (c) => ChatScreen(
        chatRoomId: data['chatRoomId'],
        recipientId: data['senderId'],
        recipientName: data['senderName'] ?? "Chat",
      )));
    }
    else if (type == 'forum' && data['postId'] != null) {
      // Show loading while we fetch post data
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

      try {
        final postDoc = await FirebaseFirestore.instance.collection('forum_posts').doc(data['postId']).get();
        Navigator.pop(context); // Close loading

        if (postDoc.exists) {
          Navigator.push(context, MaterialPageRoute(builder: (c) => ForumDetailScreen(
            postId: data['postId'],
            postData: postDoc.data()!,
            targetAnswerId: data['answerId'], // Trigger the flash highlight
          )));
        }
      } catch (e) {
        Navigator.pop(context);
      }
    }
    else if (type == 'penalty' || type == 'system') {
      _showNoticeDialog(data['senderName'] ?? "Notice", data['message'] ?? "");
    }
  }

  void _showNoticeDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(body),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Understood"))],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline_rounded, size: 80, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text("Your mailbox is empty", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}