import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String _searchQuery = "";
  String _selectedSemester = "All";
  String? _teacherDepartment;
  bool _isProcessing = false;
  final TextEditingController _searchController = TextEditingController();

  // Cloudinary Credentials
  final String _cloudName = "dahslwjab";
  final String _apiKey = "886847796499475";
  final String _apiSecret = "ed5NfxsJf007_4n2lI2GfJTFB3k";

  // Firestore instance for cleaner access
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchTeacherProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTeacherProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() => _teacherDepartment = data['department']);
      }
    } catch (e) {
      debugPrint("Error fetching teacher profile: $e");
    }
  }

  // --- CLOUDINARY LOGIC ---

  Future<void> _deleteFromCloudinary(String? publicId, String fileExt) async {
    if (publicId == null || publicId.isEmpty) {
      debugPrint("Cloudinary delete skipped: publicId is null or empty.");
      return;
    }

    String resourceType;
    final ext = fileExt.toLowerCase();

    if (["jpg", "jpeg", "png", "gif"].contains(ext)) {
      resourceType = "image";
    } else if (["mp4", "mov", "avi", "mkv", "webm"].contains(ext)) {
      resourceType = "video";
    } else {
      resourceType = "raw"; // For PDFs, DOCs, etc.
    }

    final String timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final String signatureSource = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final String signature = sha1.convert(utf8.encode(signatureSource)).toString();

    try {
      final response = await http.post(
        Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy"),
        body: {
          "public_id": publicId,
          "timestamp": timestamp,
          "api_key": _apiKey,
          "signature": signature,
        },
      );
      debugPrint("Cloudinary Delete Status: ${response.statusCode} for public_id: $publicId, type: $resourceType. Body: ${response.body}");
    } catch (e) {
      debugPrint("Cloudinary API Error: $e");
    }
  }

  // --- THE ATOMIC PURGE LOGIC ---

  Future<void> _handleDelete(String docId, Map<String, dynamic> data) async {
    final TextEditingController reasonCtrl = TextEditingController();
    final theme = _getDeptTheme(_teacherDepartment);

    // Use field names exactly as they appear in your Firestore documents
    final String title = data['title'] ?? "Material";
    final String uploaderId = data['uploaderId'] ?? "";
    final String? publicId = data['publicId']; // Using the direct field from Firestore
    final String fileExt = (data['fileExtension'] ?? "file").toLowerCase();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Remove Approved Content", style: TextStyle(color: theme['primary'], fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Delete '$title'?", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              "This deducts 10 Honor points from the student and sends a notification.",
              style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "Reason for removal (required)...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: const StadiumBorder()),
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) {
                // You can show a small visual cue here if you want
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text("Confirm & Purge", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);

    try {
      // 1. Delete from Cloudinary first.
      await _deleteFromCloudinary(publicId, fileExt);

      // 2. Prepare atomic Firestore operations.
      final WriteBatch batch = _firestore.batch();

      // Reference to the content document that will be deleted.
      final DocumentReference contentRef = _firestore.collection('contents').doc(docId);

      // Only perform user-related actions if an uploaderId is present.
      if (uploaderId.isNotEmpty) {
        final DocumentReference userRef = _firestore.collection('users').doc(uploaderId);
        final userDoc = await userRef.get();

        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          // Use lowercase 'student' to match your database exactly.
          if (userData['role'] == "student") {
            // Action A: Deduct 10 points.
            batch.update(userRef, {'honorScore': FieldValue.increment(-10)});

            // Action B: Send a notification to the user's mailbox.
            final DocumentReference notifRef = _firestore.collection('notifications').doc();
            batch.set(notifRef, {
              'userId': uploaderId,
              'title': 'Content Removed ⚠️',
              'message': 'Your material "$title" was removed by faculty. -10 Honor Points.\nReason: ${reasonCtrl.text.trim()}',
              'notificationType': 'penalty',
              'isRead': false,
              'senderName': 'Academic Review',
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // Action C: Delete the content document itself.
      batch.delete(contentRef);

      // 3. Commit all Firestore actions (A, B, and C) at once.
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Purge complete: File, Score, and DB updated.")));
      }
    } catch (e) {
      debugPrint("Purge error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("An error occurred during the purge: $e")));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  // --- THEME & UI HELPERS (No changes needed here, assuming they are correct) ---

  Map<String, dynamic> _getDeptTheme(String? dept) {
    final d = (dept ?? "").toLowerCase();
    if (d.contains("computer") || d.contains("cse") || d.contains("it")) {
      return {"primary": Colors.indigo.shade700, "accent": Colors.blue.shade100, "icon": Icons.computer_rounded, "bg": Colors.indigo.shade50};
    } else if (d.contains("mech") || d.contains("automobile")) {
      return {"primary": Colors.orange.shade800, "accent": Colors.orange.shade100, "icon": Icons.settings_suggest_rounded, "bg": Colors.orange.shade50};
    } else if (d.contains("civil") || d.contains("arch")) {
      return {"primary": Colors.brown.shade700, "accent": Colors.brown.shade100, "icon": Icons.architecture_rounded, "bg": Colors.brown.shade50};
    } else if (d.contains("elec") || d.contains("eee")) {
      return {"primary": Colors.amber.shade900, "accent": Colors.yellow.shade100, "icon": Icons.electric_bolt_rounded, "bg": Colors.amber.shade50};
    }
    return {"primary": Colors.indigo.shade700, "accent": Colors.grey.shade100, "icon": Icons.description_rounded, "bg": Colors.white};
  }

  Future<void> _previewFile(String? url, String? extension) async {
    if (url == null || url.isEmpty) return;
    final ext = (extension ?? "").toLowerCase();
    if (["jpg", "jpeg", "png"].contains(ext)) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(child: Image.network(url)),
              Positioned(
                top: 40, right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ),
              )
            ],
          ),
        ),
      );
    } else {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open file.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _getDeptTheme(_teacherDepartment);
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                height: 40,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: "Search in ${_teacherDepartment ?? 'Branch'}...",
                    prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  ),
                ),
              ),
            ),
            // Semester Filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: ["All", "1", "2", "3", "4", "5", "6"].map((sem) {
                  final isSelected = _selectedSemester == sem;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(sem == "All" ? "All Semesters" : "Sem $sem"),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedSemester = sem),
                      backgroundColor: isSelected ? theme['accent'] : Colors.grey.shade200,
                      selectedColor: theme['accent'],
                      labelStyle: TextStyle(color: isSelected ? theme['primary'] : Colors.black87),
                      shape: const StadiumBorder(),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            // Stream List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _teacherDepartment == null
                    ? const Stream.empty()
                    : _firestore
                    .collection('contents')
                    .where('isApproved', isEqualTo: true)
                    .where('department', isEqualTo: _teacherDepartment)
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text("No materials found in ${_teacherDepartment ?? 'your department'}."));
                  }

                  var docs = snapshot.data!.docs.where((doc) {
                    var d = doc.data() as Map<String, dynamic>;
                    if (_selectedSemester != "All" && d['semester'] != _selectedSemester) return false;
                    return (d['title'] ?? "").toString().toLowerCase().contains(_searchQuery);
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(child: Text("No results for '$_searchQuery'"));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      return _buildContentCard(docs[index].id, data, theme);
                    },
                  );
                },
              ),
            ),
          ],
        ),
        if (_isProcessing)
          Container(
            color: Colors.black38,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _buildContentCard(String docId, Map<String, dynamic> data, Map<String, dynamic> theme) {
    final fileExt = (data['fileExtension'] ?? 'file').toLowerCase();
    // Icon mapping for different file types
    IconData fileIcon;
    if (fileExt == 'pdf') {
      fileIcon = Icons.picture_as_pdf_rounded;
    } else if (['jpg', 'jpeg', 'png'].contains(fileExt)) {
      fileIcon = Icons.image_rounded;
    } else if (['mp4', 'mov', 'avi'].contains(fileExt)) {
      fileIcon = Icons.video_library_rounded;
    } else {
      fileIcon = theme['icon'];
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias, // Ensures InkWell ripple respects the border radius
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _previewFile(data['fileUrl'], fileExt),
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(color: theme['bg']),
              child: Center(
                child: Icon(
                  fileIcon,
                  size: 60,
                  color: theme['primary'].withOpacity(0.7),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] ?? "Untitled",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: theme['primary']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
                      onPressed: () => _handleDelete(docId, data),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text("${data['subject'] ?? 'General'}", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: theme['accent'], borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        "Sem ${data['semester']}",
                        style: TextStyle(color: theme['primary'], fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Text(
                      "By: ${data['uploaderName'] ?? "Anonymous"}",
                      style: TextStyle(fontSize: 13, color: theme['primary'], fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      data['contentType'] ?? 'Study Material',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
