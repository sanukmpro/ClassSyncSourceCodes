import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_data.dart';

class ContentCleanupScreen extends StatefulWidget {
  const ContentCleanupScreen({super.key});

  @override
  State<ContentCleanupScreen> createState() => _ContentCleanupScreenState();
}

class _ContentCleanupScreenState extends State<ContentCleanupScreen> {
  String _filterDept = "All";
  String _filterSem = "All";
  bool _isProcessing = false;

  // --- CLOUDINARY CREDENTIALS ---
  final String _cloudName = "dahslwjab";
  final String _apiKey = "can not show this secret";
  final String _apiSecret = "can not show this secret";

  // --- CLOUDINARY DELETE LOGIC ---
  Future<void> _deleteFromCloudinary(String? publicId, String? fileExt) async {
    if (publicId == null || publicId.isEmpty) return;

    String resourceType = "raw";
    final ext = (fileExt ?? "").toLowerCase();
    if (["jpg", "jpeg", "png"].contains(ext)) {
      resourceType = "image";
    } else if (["mp4", "mov", "avi"].contains(ext)) {
      resourceType = "video";
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signature = sha1.convert(utf8.encode("public_id=$publicId&timestamp=$timestamp$_apiSecret")).toString();

    try {
      await http.post(
        Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy"),
        body: {
          "public_id": publicId,
          "timestamp": timestamp,
          "api_key": _apiKey,
          "signature": signature,
        },
      );
    } catch (e) {
      debugPrint("Cloudinary Cleanup Error: $e");
    }
  }

  String _getResilientName(Map<String, dynamic> data) {
    return data['authorName'] ?? data['userName'] ?? data['uploaderName'] ?? "Unknown User";
  }

  Future<void> _viewFile(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not launch file")));
    }
  }

  // --- ENHANCED DELETE LOGIC ---
  Future<void> _deleteDocument(BuildContext context, DocumentSnapshot doc, bool isMaterial) async {
    bool confirm = await _showConfirmDialog(context, "Permanently delete this ${isMaterial ? 'file and record' : 'post'}?");
    if (!confirm) return;

    setState(() => _isProcessing = true);
    try {
      final data = doc.data() as Map<String, dynamic>;

      if (isMaterial) {
        // Delete from Cloudinary first
        await _deleteFromCloudinary(data['publicId'], data['fileExtension']);
      }

      // Delete from Firestore
      await doc.reference.delete();

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Deleted successfully")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Content Moderation"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: Column(
              children: [
                const TabBar(
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(icon: Icon(Icons.forum), text: "Forum Posts"),
                    Tab(icon: Icon(Icons.cloud_download), text: "Materials"),
                  ],
                ),
                _buildFilterBar(),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _buildFilteredList(collectionName: 'forum_posts', isMaterial: false),
                _buildFilteredList(collectionName: 'contents', isMaterial: true),
              ],
            ),
            if (_isProcessing)
              Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterDept,
                isExpanded: true,
                items: ["All", ...AppData.departments].map((dept) => DropdownMenuItem(value: dept, child: Text(dept))).toList(),
                onChanged: (val) => setState(() => _filterDept = val!),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterSem,
                items: ["All", ...AppData.semesters].map((sem) => DropdownMenuItem(value: sem, child: Text(sem == "All" ? "All Sem" : "Sem $sem"))).toList(),
                onChanged: (val) => setState(() => _filterSem = val!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredList({required String collectionName, required bool isMaterial}) {
    Query query = FirebaseFirestore.instance.collection(collectionName);
    if (_filterDept != "All") query = query.where('department', isEqualTo: _filterDept);
    if (_filterSem != "All") query = query.where('semester', isEqualTo: _filterSem);
    query = query.orderBy('timestamp', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("No items found."));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                onTap: () {
                  if (isMaterial) {
                    _viewFile(context, data['fileUrl']);
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ForumDetailReviewScreen(postId: doc.id, postData: data)));
                  }
                },
                leading: CircleAvatar(
                  backgroundColor: isMaterial ? Colors.orange.shade50 : Colors.blue.shade50,
                  child: Icon(isMaterial ? Icons.file_present : Icons.chat, color: isMaterial ? Colors.orange : Colors.blue),
                ),
                title: Text(data['title'] ?? data['question'] ?? "Untitled", maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text("${_getResilientName(data)} • Sem ${data['semester'] ?? '?'}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  onPressed: () => _deleteDocument(context, doc, isMaterial),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showConfirmDialog(BuildContext context, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Action"),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ??
        false;
  }
}

class ForumDetailReviewScreen extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> postData;

  const ForumDetailReviewScreen({super.key, required this.postId, required this.postData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Moderation: Forum")),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(postData['title'] ?? postData['question'] ?? "No Title", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("Author: ${postData['authorName'] ?? 'Unknown'}", style: const TextStyle(color: Colors.blueGrey)),
                const Divider(),
                Text(postData['description'] ?? postData['text'] ?? "", style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('forum_posts').doc(postId).collection('answers').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final answers = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: answers.length,
                  itemBuilder: (context, index) {
                    final aDoc = answers[index];
                    final aData = aDoc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(aData['text'] ?? ""),
                      subtitle: Text("By: ${aData['authorName'] ?? 'User'}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => aDoc.reference.delete(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}
