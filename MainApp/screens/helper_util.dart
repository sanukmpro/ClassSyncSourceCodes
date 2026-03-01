import 'dart:io' show File, Platform;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

// Import your helper util
import 'chat_utils.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String recipientId;
  final String recipientName;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String cloudName = "dahslwjab";
  final String uploadPreset = "class_sync_uploads";

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isUploading = false;
  String? _editingMessageId;

  // --- MESSAGING LOGIC ---

  void _handleSendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .collection('messages');

    if (_editingMessageId != null) {
      msgRef.doc(_editingMessageId).update({'text': text, 'isEdited': true});
      setState(() => _editingMessageId = null);
    } else {
      msgRef.add({
        'senderId': _currentUid,
        'text': text,
        'type': 'text',
        'status': 'sent',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update Parent for Teacher Inbox (Unified field names)
      FirebaseFirestore.instance.collection('chats').doc(widget.chatRoomId).update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
    _messageController.clear();
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        foregroundColor: Colors.white,
        title: Text(widget.recipientName),
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessagesList()),
          if (_editingMessageId != null) _buildEditBar(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs;

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final currentMsgDate = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

            // Date Header Logic
            bool showDateHeader = false;
            if (index == docs.length - 1) {
              showDateHeader = true;
            } else {
              final prevData = docs[index + 1].data() as Map<String, dynamic>;
              final prevMsgDate = (prevData['timestamp'] as Timestamp?)?.toDate();
              if (prevMsgDate != null && currentMsgDate.day != prevMsgDate.day) {
                showDateHeader = true;
              }
            }

            return Column(
              children: [
                if (showDateHeader) _buildDateHeader(currentMsgDate),
                _buildBubble(docs[index].id, data),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        ChatUtils.formatHeaderDate(date), // Using your helper!
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
      ),
    );
  }

  Widget _buildBubble(String id, Map<String, dynamic> data) {
    bool isMe = data['senderId'] == _currentUid;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(data['text'] ?? "", style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              ChatUtils.formatTimestamp(data['timestamp'] as Timestamp?), // Using your helper!
              style: const TextStyle(fontSize: 10, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  // --- Input & Upload logic truncated for brevity ---
  Widget _buildInputArea() { /* Same as your Input Row */ return const SizedBox(); }
  Widget _buildEditBar() { /* Same as your Edit Bar */ return const SizedBox(); }
}