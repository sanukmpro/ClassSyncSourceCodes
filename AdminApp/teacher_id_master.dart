import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'login_screen.dart';
import 'app_data.dart';
import 'id_request_screen.dart';
import 'content_cleanup_screen.dart';

class TeacherIdMasterScreen extends StatefulWidget {
  const TeacherIdMasterScreen({super.key});

  @override
  State<TeacherIdMasterScreen> createState() => _TeacherIdMasterScreenState();
}

class _TeacherIdMasterScreenState extends State<TeacherIdMasterScreen> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  String? _selectedDept;
  String? _selectedSem;
  String _filterDept = "All";
  String _filterSem = "All";
  bool _isProcessing = false;

  final String _cloudName = "dahslwjab";
  final String _apiKey = "886847796499475";
  final String _apiSecret = "ed5NfxsJf007_4n2lI2GfJTFB3k";

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // --- ADDED: Helper to fetch Profile Pic ---
  Future<String?> _getProfilePic(String? email) async {
    if (email == null || email.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.data()['profilePic'];
      }
    } catch (e) {
      debugPrint("Profile pic fetch error: $e");
    }
    return null;
  }

  // --- IMAGE PREVIEW LOGIC ---
  void _showImagePreview(BuildContext context, String? url, String name) {
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(name, style: const TextStyle(color: Colors.white)),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- CLOUDINARY DELETION LOGIC ---
  Future<void> _deleteFromCloudinary(String? publicId, String fileExt) async {
    if (publicId == null || publicId.isEmpty) return;
    String resourceType;
    final ext = fileExt.toLowerCase();
    if (["jpg", "jpeg", "png", "gif"].contains(ext)) {
      resourceType = "image";
    } else if (["mp4", "mov", "avi", "mkv"].contains(ext)) {
      resourceType = "video";
    } else {
      resourceType = "raw";
    }
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signatureSource = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final signature = sha1.convert(utf8.encode(signatureSource)).toString();

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
      debugPrint("Cloudinary Error: $e");
    }
  }

  // --- CONSOLIDATED PURGE LOGIC ---
  Future<void> _performFullPurge({
    String? tid,
    required String email,
    required bool wipeContent,
    required String userDocId,
  }) async {
    setState(() => _isProcessing = true);
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final normalizedEmail = email.toLowerCase().trim();

    try {
      if (tid != null) batch.delete(firestore.collection('teacher_ids').doc(tid));
      batch.delete(firestore.collection('users').doc(userDocId));

      final requests = await firestore.collection('id_requests').where('email', isEqualTo: normalizedEmail).get();
      for (var d in requests.docs) {
        batch.delete(d.reference);
      }

      if (wipeContent && normalizedEmail.isNotEmpty) {
        final materialsQuery = await firestore.collection('contents').where('uploaderEmail', isEqualTo: normalizedEmail).get();
        for (final doc in materialsQuery.docs) {
          final data = doc.data();
          await _deleteFromCloudinary(data['publicId'], data['fileExtension'] ?? 'raw');
          batch.delete(doc.reference);
        }
      }
      await batch.commit();
      _showSnack("Purge Complete: User removed.", isError: false);
    } catch (e) {
      _showSnack("Purge failed: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _confirmDelete(DocumentSnapshot doc, String? tid) {
    final data = doc.data() as Map<String, dynamic>;
    final email = data['email'] as String? ?? "";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirm Removal", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to revoke access for ${data['name'] ?? 'this user'}? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: const StadiumBorder()),
            onPressed: () {
              Navigator.pop(ctx);
              _performFullPurge(
                tid: tid,
                email: email,
                wipeContent: false,
                userDocId: doc.id,
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Master Dashboard"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Column(
              children: [
                const TabBar(
                  indicatorColor: Colors.red,
                  labelColor: Colors.red,
                  tabs: [
                    Tab(icon: Icon(Icons.verified_user), text: "Faculty"),
                    Tab(icon: Icon(Icons.groups), text: "Students"),
                  ],
                ),
                _buildListFilterBar(),
              ],
            ),
          ),
        ),
        drawer: _buildDrawer(),
        body: Stack(
          children: [
            TabBarView(
              children: [_buildTeacherIdList(), _buildStudentList()],
            ),
            if (_isProcessing)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.red.shade800,
          onPressed: _showAddDialog,
          icon: const Icon(Icons.person_add, color: Colors.white),
          label: const Text("Authorize Faculty", style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildTeacherIdList() {
    Query query = FirebaseFirestore.instance.collection('teacher_ids').where('isApproved', isEqualTo: true);
    if (_filterDept != "All") query = query.where('department', isEqualTo: _filterDept);
    if (_filterSem != "All") query = query.where('semester', isEqualTo: _filterSem);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final tid = docs[index].id;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: _buildProfileAvatar(data['email'], data['name'], Colors.red),
                title: Text("$tid — ${data['name']}"),
                subtitle: Text("${data['department']} | Sem ${data['semester']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(docs[index], tid),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileEditScreen(docId: tid, collection: 'teacher_ids', initialData: data))),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStudentList() {
    Query query = FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'student');
    if (_filterDept != "All") query = query.where('department', isEqualTo: _filterDept);
    if (_filterSem != "All") query = query.where('semester', isEqualTo: _filterSem);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: _buildProfileAvatar(data['email'], data['name'], Colors.blue),
                title: Text(data['name'] ?? "Unknown"),
                subtitle: Text("${data['department']} | Sem ${data['semester']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove_outlined, color: Colors.grey),
                  onPressed: () => _confirmDelete(docs[index], null),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileEditScreen(docId: docs[index].id, collection: 'users', initialData: data))),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileAvatar(String? email, String? name, Color color) {
    return FutureBuilder<String?>(
      future: _getProfilePic(email),
      builder: (context, snap) {
        final imageUrl = snap.data;
        return GestureDetector(
          onTap: () => _showImagePreview(context, imageUrl, name ?? "Profile"),
          child: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null,
            child: (imageUrl == null || imageUrl.isEmpty)
                ? Text(name != null && name.isNotEmpty ? name[0].toUpperCase() : "?", style: TextStyle(color: color, fontWeight: FontWeight.bold))
                : null,
          ),
        );
      },
    );
  }

  Widget _buildListFilterBar() {
    return Container(
      height: 50,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _filterDept,
                items: ["All", ...AppData.departments].map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) => setState(() => _filterDept = v!),
              ),
            ),
          ),
          const VerticalDivider(),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterSem,
              items: ["All", "1", "2", "3", "4", "5", "6"].map((s) => DropdownMenuItem(value: s, child: Text(s == "All" ? "All Sem" : "Sem $s", style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => setState(() => _filterSem = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.red.shade900),
            accountName: const Text("Admin Panel"),
            accountEmail: const Text("Master Control"),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.security, color: Colors.red, size: 40)),
          ),
          ListTile(leading: const Icon(Icons.pending), title: const Text("ID Requests"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IdRequestScreen()))),
          ListTile(leading: const Icon(Icons.auto_delete), title: const Text("Cleanup Tool"), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContentCleanupScreen()))),
          const Spacer(),
          ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Logout"),
              onTap: () {
                Navigator.pop(context); // Close the drawer first
                _logout();              // Then trigger logout logic
              }
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      // 1. Sign out from Google and Firebase
      await GoogleSignIn().signOut();
      await FirebaseAuth.instance.signOut();

      // 2. Navigate back to the login screen and clear the navigation stack
      if (mounted) {
        // Replace 'AdminLoginScreen()' with the actual name of your login class
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      _showSnack("Logout failed: $e");
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red : Colors.green));
  }

  void _clearDialogInputs() {
    _idController.clear(); _nameController.clear(); _emailController.clear();
    setState(() { _selectedDept = null; _selectedSem = null; });
  }

  Future<void> _addAuthorizedId() async {
    final String tid = _idController.text.trim().toUpperCase();
    final String email = _emailController.text.trim().toLowerCase();
    final String name = _nameController.text.trim();
    if (tid.isEmpty || name.isEmpty || email.isEmpty || _selectedDept == null || _selectedSem == null) {
      _showSnack("Please fill all fields!");
      return;
    }
    try {
      setState(() => _isProcessing = true);
      final idCheck = await FirebaseFirestore.instance.collection('teacher_ids').doc(tid).get();
      if (idCheck.exists) {
        _showSnack("Teacher ID already exists.");
        return;
      }
      await FirebaseFirestore.instance.collection('teacher_ids').doc(tid).set({
        'name': name,
        'email': email,
        'department': _selectedDept,
        'semester': _selectedSem,
        'isApproved': true,
        'teacherId': tid,
        'role': 'teacher',
        'isClaimed': false,
        'authorizedAt': FieldValue.serverTimestamp(),
      });
      _clearDialogInputs();
      if (mounted) Navigator.pop(context);
      _showSnack("Faculty authorized successfully.", isError: false);
    } catch (e) {
      _showSnack("Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Authorize Faculty"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _idController, decoration: const InputDecoration(labelText: "Teacher ID")),
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name")),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Official Email")),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedDept,
                  hint: const Text("Department"),
                  items: AppData.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: (v) => setDialogState(() => _selectedDept = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSem,
                  hint: const Text("Semester"),
                  items: ["1", "2", "3", "4", "5", "6"].map((s) => DropdownMenuItem(value: s, child: Text("Sem $s"))).toList(),
                  onChanged: (v) => setDialogState(() => _selectedSem = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(onPressed: _addAuthorizedId, child: const Text("Authorize")),
          ],
        ),
      ),
    );
  }
}

// --- USER PROFILE EDIT SCREEN ---

class UserProfileEditScreen extends StatefulWidget {
  final String docId;
  final String collection;
  final Map<String, dynamic> initialData;
  const UserProfileEditScreen({super.key, required this.docId, required this.collection, required this.initialData});
  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  String? _selectedDept;
  String? _selectedSem;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDept = widget.initialData['department'];
    _selectedSem = widget.initialData['semester']?.toString();
  }

  // --- ADDED: Helper for profile pic on this screen ---
  Future<String?> _getProfilePic(String? email) async {
    if (email == null || email.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first.data()['profilePic'];
      }
    } catch (e) {
      debugPrint("Profile pic fetch error: $e");
    }
    return null;
  }

  void _showImagePreview(BuildContext context, String? url, String name) {
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(name, style: const TextStyle(color: Colors.white)),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateProfile() async {
    setState(() => _isSaving = true);
    final batch = FirebaseFirestore.instance.batch();
    try {
      final updateData = {'department': _selectedDept, 'semester': _selectedSem};
      final primaryRef = FirebaseFirestore.instance.collection(widget.collection).doc(widget.docId);
      batch.update(primaryRef, updateData);
      if (widget.collection == 'teacher_ids' && widget.initialData['claimedByUid'] != null) {
        final userRef = FirebaseFirestore.instance.collection('users').doc(widget.initialData['claimedByUid']);
        batch.update(userRef, updateData);
      }
      await batch.commit();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.initialData['email'] ?? "";
    final name = widget.initialData['name'] ?? "User";

    return Scaffold(
      appBar: AppBar(title: const Text("Edit User Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // --- UPDATED: Dynamic Profile Pic with Preview ---
            Center(
              child: FutureBuilder<String?>(
                future: _getProfilePic(email),
                builder: (context, snapshot) {
                  final imageUrl = snapshot.data;
                  return GestureDetector(
                    onTap: () => _showImagePreview(context, imageUrl, name),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null,
                      child: (imageUrl == null || imageUrl.isEmpty)
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Column(
                children: [
                  _buildReadOnlyTile(Icons.person, "Name", name),
                  _buildReadOnlyTile(Icons.email, "Email", email),
                  _buildReadOnlyTile(Icons.info, "Bio", widget.initialData['bio'] ?? 'No bio provided.'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _selectedDept,
              decoration: const InputDecoration(labelText: "Department", border: OutlineInputBorder()),
              items: AppData.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (v) => setState(() => _selectedDept = v),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedSem,
              decoration: const InputDecoration(labelText: "Semester", border: OutlineInputBorder()),
              items: ["1", "2", "3", "4", "5", "6"].map((s) => DropdownMenuItem(value: s, child: Text("Semester $s"))).toList(),
              onChanged: (v) => setState(() => _selectedSem = v),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _updateProfile,
                child: _isSaving ? const CircularProgressIndicator() : const Text("Save Changes"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }
}