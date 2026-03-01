import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Screens
import 'role_selection_screen.dart';
import 'upload_content.dart';
import 'mail_box.dart';
import 'leaderboard_screen.dart';
import 'forum_home_screen.dart';
import 'teacher_directory_screen.dart';
import 'edit_profile.dart';
import 'profile_view_screen.dart';
import 'settings_screen.dart';

// Key for accessing ForumHomeScreen's state
final GlobalKey<ForumHomeScreenState> forumKey = GlobalKey<ForumHomeScreenState>();

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  // --- STATE MANAGEMENT ---
  int _selectedIndex = 0;
  Map<String, dynamic>? _userData;
  DateTime? _lastPressedAt;

  // Search and Filter State
  String _selectedSemester = "All";
  final TextEditingController _searchController = TextEditingController();
  Stream<QuerySnapshot>? _contentStream;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
    _initNotificationListeners();
    _checkInitialMessage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- DYNAMIC THEME HELPER ---
  Map<String, dynamic> _getDeptTheme(String? dept) {
    final d = (dept ?? "").toLowerCase();
    if (d.contains("computer") || d.contains("cse") || d.contains("it")) {
      return {
        "primary": Colors.indigo.shade700,
        "accent": Colors.blue.shade100,
        "icon": Icons.computer_rounded,
        "bg": Colors.indigo.shade50,
      };
    } else if (d.contains("mech") || d.contains("automobile")) {
      return {
        "primary": Colors.orange.shade800,
        "accent": Colors.orange.shade100,
        "icon": Icons.settings_suggest_rounded,
        "bg": Colors.orange.shade50,
      };
    } else if (d.contains("civil") || d.contains("arch")) {
      return {
        "primary": Colors.brown.shade700,
        "accent": Colors.brown.shade100,
        "icon": Icons.architecture_rounded,
        "bg": Colors.brown.shade50,
      };
    } else if (d.contains("elec") || d.contains("eee")) {
      return {
        "primary": Colors.amber.shade900,
        "accent": Colors.yellow.shade100,
        "icon": Icons.electric_bolt_rounded,
        "bg": Colors.amber.shade50,
      };
    }
    return {
      "primary": Colors.indigo.shade700,
      "accent": Colors.grey.shade100,
      "icon": Icons.description_rounded,
      "bg": Colors.white,
    };
  }

  // --- IMAGE PREVIEW LOGIC ---
  void _showFullImage(String url) {
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
              top: 40,
              right: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- FILE PREVIEW LOGIC ---
  Future<void> _previewFile(String? url, String? extension) async {
    if (url == null || url.isEmpty) return;
    final ext = (extension ?? "").toLowerCase();

    if (["jpg", "jpeg", "png"].contains(ext)) {
      _showFullImage(url);
    } else {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not open file externally.")),
          );
        }
      }
    }
  }

  void _navigateToProfile() {
    if (_userData == null) return;
    Navigator.pop(context); // Close drawer
    Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileViewScreen(userData: _userData!)));
  }

  Future<void> _initializeScreen() async {
    await _fetchStudentProfile();
    _updateContentStream();
  }

  Future<void> _fetchStudentProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() => _userData = doc.data());
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    }
  }

  void _initNotificationListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (mounted) _showForegroundNotification(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateToConsultations();
    });
  }

  void _checkInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(milliseconds: 1000), _navigateToConsultations);
    }
  }

  void _updateContentStream() {
    final String? department = _userData?['department'];
    if (department == null || department.isEmpty) return;

    Query query = FirebaseFirestore.instance
        .collection('contents')
        .where('isApproved', isEqualTo: true)
        .where('department', isEqualTo: department);

    if (_selectedSemester != "All") {
      query = query.where('semester', isEqualTo: _selectedSemester);
    }
    query = query.orderBy('timestamp', descending: true);
    setState(() => _contentStream = query.snapshots());
  }

  void _navigateToConsultations() {
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDirectoryScreen()));
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(notification.title ?? "New Notification"),
        backgroundColor: Colors.indigo.shade700,
        action: SnackBarAction(label: "VIEW", textColor: Colors.white, onPressed: _navigateToConsultations),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
        final now = DateTime.now();
        if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Double tap back to exit app"), duration: Duration(seconds: 2)));
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        drawer: _buildDrawer(uid),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildExplorerTab(),
            ForumHomeScreen(key: forumKey),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.indigo.shade700,
      foregroundColor: Colors.white,
      title: _selectedIndex == 0 ? _buildSearchField() : Text(_selectedIndex == 1 ? "Community Forum" : "My Library"),
      elevation: 0,
    );
  }

  Widget _buildDrawer(String uid) {
    final String studentName = _userData?['name'] ?? "Student";
    final String studentEmail = FirebaseAuth.instance.currentUser?.email ?? "";
    final String? profilePic = _userData?['profilePic'];
    final String bio = _userData?['bio'] ?? "Learning every day ✨";

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Colors.indigo[900],
              image: profilePic != null ? DecorationImage(
                image: NetworkImage(profilePic),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
              ) : null,
            ),
            accountName: GestureDetector(
              onTap: _navigateToProfile,
              child: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            accountEmail: Text(studentEmail),
            currentAccountPicture: GestureDetector(
              onTap: _navigateToProfile,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                child: profilePic == null ? const Icon(Icons.person, size: 40, color: Colors.indigo) : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              bio,
              textAlign: TextAlign.start,
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade700, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _buildDrawerItem(icon: Icons.explore_outlined, title: "My Library", index: 0),
          _buildDrawerItem(icon: Icons.forum_outlined, title: "Community Forum", index: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: Colors.blue),
            title: const Text("Edit Profile Settings"),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfileScreen()));
              _fetchStudentProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text("Consult a Teacher"),
            onTap: () {
              Navigator.pop(context);
              _navigateToConsultations();
            },
          ),
          _buildMailboxTile(uid),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined, color: Colors.amber),
            title: const Text("Leaderboard"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.blueAccent),
            title: const Text("Settings"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (r) => false);
            },
          ),
        ],
      ),
    );
  }

  ListTile _buildDrawerItem({required IconData icon, required String title, required int index}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: _selectedIndex == index,
      selectedTileColor: Colors.indigo.withOpacity(0.1),
      selectedColor: Colors.indigo.shade700,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildMailboxTile(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('notifications').where('userId', isEqualTo: uid).where('isRead', isEqualTo: false).snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text("Mailbox"),
          trailing: count > 0 ? CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white))) : null,
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MailBoxScreen()));
          },
        );
      },
    );
  }

  Widget? _buildFloatingActionButton() {
    if (_selectedIndex == 0) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadContentScreen(isTeacher: false))),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file),
        label: const Text("Upload"),
      );
    }
    if (_selectedIndex == 1) {
      return FloatingActionButton(
        onPressed: () => forumKey.currentState?.showAskQuestionDialog(),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_comment),
      );
    }
    return null;
  }

  Widget _buildSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() {}),
        decoration: InputDecoration(
          hintText: "Search in your branch...",
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.clear, color: Colors.grey.shade600),
            onPressed: () {
              _searchController.clear();
              setState(() {});
            },
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        ),
      ),
    );
  }

  Widget _buildExplorerTab() {
    final String studentName = _userData?['name'] ?? "Student";
    final String studentDept = _userData?['department'] ?? "Not Set";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Hello, $studentName 👋", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              if (studentDept != "Not Set")
                Text("Branch: $studentDept", style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
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
                  onSelected: (selected) {
                    setState(() {
                      _selectedSemester = sem;
                      _updateContentStream();
                    });
                  },
                  backgroundColor: isSelected ? Colors.indigo.shade100 : Colors.grey.shade200,
                  labelStyle: TextStyle(color: isSelected ? Colors.indigo.shade800 : Colors.black87),
                  shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.indigo.shade700 : Colors.transparent)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _contentStream,
            builder: (context, snapshot) {
              if (studentDept == "Not Set") {
                return const Center(child: Text("Please set your department in your profile."));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text("No materials found for your branch."));
              }

              final searchQuery = _searchController.text.toLowerCase();
              final docs = snapshot.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final title = (data['title'] as String? ?? '').toLowerCase();
                final subject = (data['subject'] as String? ?? '').toLowerCase();
                return title.contains(searchQuery) || subject.contains(searchQuery);
              }).toList();

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return _buildContentCard(data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContentCard(Map<String, dynamic> data) {
    final theme = _getDeptTheme(data['department']);
    final fileExt = (data['fileExtension'] ?? 'file').toLowerCase();
    final String uploaderName = data['uploaderName'] ?? "Anonymous";

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PREVIEW SECTION (Tappable Area for File)
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            onTap: () => _previewFile(data['fileUrl'], fileExt),
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme['bg'],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Center(
                child: Icon(
                  fileExt == 'pdf' ? Icons.picture_as_pdf_rounded : (["jpg", "jpeg", "png"].contains(fileExt) ? Icons.image_rounded : theme['icon']),
                  size: 60,
                  color: theme['primary'].withOpacity(0.7),
                ),
              ),
            ),
          ),

          // INFO SECTION
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] ?? "Untitled Material",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: theme['primary']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

                // UPLOADER INFO SECTION (Simple Text)
                Row(
                  children: [
                    Text(
                      "By: $uploaderName",
                      style: TextStyle(
                          fontSize: 13,
                          color: theme['primary'],
                          fontWeight: FontWeight.w600
                      ),
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