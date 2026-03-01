import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PendingApprovalsScreen extends StatefulWidget {
  const PendingApprovalsScreen({super.key});

  @override
  State<PendingApprovalsScreen> createState() => _PendingApprovalsScreenState();
}

class _PendingApprovalsScreenState extends State<PendingApprovalsScreen> {
  String _searchQuery = "";
  String? _teacherDepartment;
  bool _isProcessing = false;

  // Cloudinary Config
  final String _cloudName = "dahslwjab";
  final String _apiKey = "886847796499475";
  final String _apiSecret = "ed5NfxsJf007_4n2lI2GfJTFB3k";

  @override
  void initState() {
    super.initState();
    _fetchTeacherDepartment();
  }

  Future<void> _fetchTeacherDepartment() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted && doc.exists) {
          setState(() => _teacherDepartment = doc.data()?['department']);
        }
      }
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  Query<Map<String, dynamic>> get _baseQuery {
    return FirebaseFirestore.instance
        .collection('contents')
        .where('isApproved', isEqualTo: false)
        .where('department', isEqualTo: _teacherDepartment);
  }

  // --- REWRITTEN CLOUDINARY DELETION ---
  Future<void> _deleteFromCloudinary(String? url, String? ext) async {
    if (url == null || url.isEmpty) return;

    String? publicId;
    try {
      final Uri uri = Uri.parse(url);
      final String path = uri.path;

      // 1. Extract everything after /upload/vXXXXXXXX/
      // This ensures folder paths like "Home/college_content/Computer Engineering" are captured
      RegExp regex = RegExp(r'\/upload\/v\d+\/(.+)');
      Match? match = regex.firstMatch(path);

      if (match != null && match.groupCount > 0) {
        String fullPathWithExt = match.group(1)!;

        // 2. Remove the file extension (the last .pdf or .jpg)
        int lastDotIndex = fullPathWithExt.lastIndexOf('.');
        if (lastDotIndex != -1) {
          publicId = fullPathWithExt.substring(0, lastDotIndex);
        } else {
          publicId = fullPathWithExt;
        }

        // 3. Decode URL characters (Critical: converts %20 back to actual spaces)
        publicId = Uri.decodeComponent(publicId);
      }
    } catch (e) {
      debugPrint("PublicID extraction error: $e");
      return;
    }

    if (publicId == null) return;

    // 4. Determine RESOURCE TYPE (Crucial: Cloudinary treats PDFs/Docs as 'raw')
    String resType = "raw";
    final fileExt = (ext ?? "").toLowerCase();
    if (["jpg", "jpeg", "png", "webp", "gif"].contains(fileExt)) {
      resType = "image";
    } else if (["mp4", "mov", "avi"].contains(fileExt)) {
      resType = "video";
    }

    final String timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // 5. Generate Signature (Parameters must be in alphabetical order)
    final String signatureSource = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final String signature = sha1.convert(utf8.encode(signatureSource)).toString();

    try {
      debugPrint("Cloudinary: Deleting ID: $publicId as Type: $resType");
      final response = await http.post(
        Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/$resType/destroy"),
        body: {
          "public_id": publicId,
          "timestamp": timestamp,
          "api_key": _apiKey,
          "signature": signature,
        },
      );

      final resData = jsonDecode(response.body);
      if (resData['result'] == 'ok') {
        debugPrint("Cloudinary Success: File purged.");
      } else {
        debugPrint("Cloudinary Failure: ${response.body}");
      }
    } catch (e) {
      debugPrint("Cloudinary Request Error: $e");
    }
  }

  // --- ACTION LOGIC ---

  Future<void> _handleApproval(String docId, Map<String, dynamic> data) async {
    setState(() => _isProcessing = true);
    try {
      final uploaderId = data['uploaderId'];
      final batch = FirebaseFirestore.instance.batch();

      batch.update(FirebaseFirestore.instance.collection('contents').doc(docId), {'isApproved': true});

      if (uploaderId != null) {
        batch.update(FirebaseFirestore.instance.collection('users').doc(uploaderId), {'honorScore': FieldValue.increment(10)});
        batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
          'userId': uploaderId,
          'senderName': 'Academic Dept',
          'message': 'Material "${data['title']}" was approved! +10 Honor Points.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'notificationType': 'system',
        });
      }

      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Submission approved! ✅")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleRejection(String docId, Map<String, dynamic> data) async {
    final reasonController = TextEditingController();
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Submission"),
        content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(hintText: "Reason for rejection..."),
            maxLines: 2
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Reject & Delete", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        // 1. Delete from Cloudinary first
        await _deleteFromCloudinary(data['fileUrl'], data['fileExtension']);

        // 2. Notify student
        if (data['uploaderId'] != null) {
          await FirebaseFirestore.instance.collection('notifications').add({
            'userId': data['uploaderId'],
            'senderName': 'Academic Dept',
            'message': 'Submission Rejected: ${reasonController.text.isEmpty ? "Does not meet guidelines" : reasonController.text}',
            'timestamp': FieldValue.serverTimestamp(),
            'isRead': false,
            'notificationType': 'penalty',
          });
        }

        // 3. Delete from Firestore
        await FirebaseFirestore.instance.collection('contents').doc(docId).delete();

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Rejected and purged.")));
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildStreamList()),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: Colors.indigo)),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        decoration: InputDecoration(
          hintText: "Search in ${_teacherDepartment ?? 'department'}...",
          prefixIcon: const Icon(Icons.search, color: Colors.indigo),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildStreamList() {
    if (_teacherDepartment == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: _baseQuery.orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Error loading data"));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final title = (data['title'] ?? "").toString().toLowerCase();
          return title.contains(_searchQuery);
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("All caught up!", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildContentCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildContentCard(String id, Map<String, dynamic> data) {
    final String ext = (data['fileExtension'] ?? "").toLowerCase();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.indigo.shade50,
          child: Icon(
            ext == 'pdf' ? Icons.picture_as_pdf : (['png', 'jpg', 'jpeg'].contains(ext) ? Icons.image : Icons.description),
            color: Colors.indigo,
          ),
        ),
        title: Text(data['title'] ?? "Untitled", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text("${data['uploaderName'] ?? 'Student'} • Sem ${data['semester']}"),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text("Subject: ${data['subject'] ?? 'N/A'}", style: TextStyle(color: Colors.grey.shade800, fontSize: 13)),
                const SizedBox(height: 4),
                Text("Department: ${data['department'] ?? 'N/A'}", style: TextStyle(color: Colors.grey.shade800, fontSize: 13)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _actionBtn(Icons.visibility, "View", Colors.blue, () => _previewFile(data['fileUrl'])),
                    _actionBtn(Icons.check_circle, "Approve", Colors.green, () => _handleApproval(id, data)),
                    _actionBtn(Icons.delete_forever, "Reject", Colors.red, () => _handleRejection(id, data)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _previewFile(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error opening file.")));
    }
  }
}