import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Screens
import 'role_selection_screen.dart';
import 'package:class_sync/screens/teacher_upload_screen.dart';
import 'teacher_dashboard.dart';
import 'pending_approvals.dart';
import 'forum_home_screen.dart';
import 'teacher_chat_inbox.dart';
import 'mail_box.dart';
import 'edit_profile.dart';
import 'profile_view_screen.dart';
import 'settings_screen.dart';

final GlobalKey<ForumHomeScreenState> teacherForumKey = GlobalKey<ForumHomeScreenState>();

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  String _teacherName = "Teacher";
  Map<String, dynamic>? _userData;
  int _selectedIndex = 0;
  DateTime? _lastPressedAt;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const TeacherDashboardScreen(),
      const PendingApprovalsScreen(),
      ForumHomeScreen(key: teacherForumKey),
    ];
    _fetchTeacherProfile();
    _initNotificationListeners();
    _checkInitialMessage();
  }

  void _navigateToProfile() {
    if (_userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile data still loading...")),
      );
      return;
    }
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => ProfileViewScreen(userData: _userData!)));
  }
  void _showVerificationScanner() {
    final TextEditingController _idController = TextEditingController();showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        // Adjust padding for keyboard
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text("Verify Student Certificate",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // --- OPTION 1: QR SCANNER ---
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: MobileScanner(
                    controller: MobileScannerController(
                      facing: CameraFacing.back,
                      // Web sometimes needs a lower resolution to initialize faster
                      detectionSpeed: DetectionSpeed.normal,
                    ),
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final String code = barcodes.first.rawValue ?? "";
                        Navigator.pop(context);
                        _processVerification(code);
                      }
                    },
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Text("OR", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              ),

              // --- OPTION 2: MANUAL ID ENTRY ---
              TextField(
                controller: _idController,
                decoration: InputDecoration(
                  hintText: "Enter Certificate ID (e.g. POLY-MND-...)",
                  prefixIcon: const Icon(Icons.edit),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward, color: Colors.blue),
                    onPressed: () {
                      if (_idController.text.isNotEmpty) {
                        Navigator.pop(context);
                        _processVerification(_idController.text.trim());
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text("Manual entry is useful if the QR code is damaged.",
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processVerification(String certId) async {
    // Show loading
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator())
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('verified_certificates')
          .doc(certId)
          .get();

      if (!mounted) return;
      Navigator.pop(context); // Remove loading

      if (doc.exists) {
        final data = doc.data()!;
        _showResultDialog(
          title: "Certificate Verified",
          message: "This is an authentic ClassSync document.\n\n"
              "Name: ${data['name']}\n"
              "Rank: #${data['rank']}\n"
              "Dept: ${data['department']}\n"
              "Score: ${data['honorScore']}",
          isSuccess: true,
        );
      } else {
        _showResultDialog(
          title: "Verification Failed",
          message: "Invalid Certificate ID. This document is not registered in our database.",
          isSuccess: false,
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showResultDialog({required String title, required String message, required bool isSuccess}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(isSuccess ? Icons.verified : Icons.gpp_bad,
                color: isSuccess ? Colors.green : Colors.red),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))
        ],
      ),
    );
  }
  Future<void> _fetchTeacherProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted && doc.exists) {
        setState(() {
          _userData = doc.data();
          _teacherName = _userData?['name'] ?? "Teacher";
        });
      }
    } catch (e) {
      debugPrint("Error fetching teacher profile: $e");
    }
  }

  void _initNotificationListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (mounted) _showForegroundNotification(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) => _navigateToInbox());
  }


  void _checkInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToInbox());
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.blue.shade900,
        content: Text(notification.title ?? "New Message"),
        action: SnackBarAction(label: "VIEW", textColor: Colors.amber, onPressed: _navigateToInbox),
      ),
    );
  }

  void _navigateToInbox() {
    if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherChatInboxScreen()));
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final String? profilePic = _userData?['profilePic'];
    final String bio = _userData?['bio'] ?? "Faculty Member";
    final String? dept = _userData?['department'];

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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Double tap back to exit app")));
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue.shade800,
          foregroundColor: Colors.white,
          title: Text(_selectedIndex == 0 ? "Teacher Dashboard" : _selectedIndex == 1 ? "Pending Approvals" : "Community Forum"),
        ),
        drawer: Drawer(
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
                  child: Text(_userData?['name'] ?? "User", style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                accountEmail: Text(FirebaseAuth.instance.currentUser?.email ?? ""),
                currentAccountPicture: GestureDetector(
                  onTap: _navigateToProfile,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                    child: profilePic == null ? const Icon(Icons.person, size: 40, color: Colors.blue) : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(bio, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13, color: Colors.grey)),
              ),

              _buildDrawerItem(0, Icons.dashboard_outlined, "Dashboard"),

              // --- UPDATED: PENDING APPROVALS WITH LIVE BADGE ---
              _buildApprovalDrawerItem(1, Icons.fact_check_outlined, "Pending Approvals", dept),

              _buildDrawerItem(2, Icons.forum_outlined, "Community Forum"),

              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.blue),
                title: const Text("Edit Profile Settings"),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfileScreen()));
                  _fetchTeacherProfile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                title: const Text("Student Consultations"),
                onTap: () { Navigator.pop(context); _navigateToInbox(); },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner, color: Colors.amber),
                title: const Text("Verify Student Certificate"),
                subtitle: const Text("Authenticate honors credentials"),
                onTap: () {
                  Navigator.pop(context);
                  _showVerificationScanner();
                },
              ),
              _buildMailboxTile(uid),
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
                onTap: _logout,
              ),
            ],
          ),
        ),
        body: IndexedStack(index: _selectedIndex, children: _screens),
        floatingActionButton: _buildFloatingActionButton(),
      ),
    );
  }

  // --- NEW: DRAWER ITEM WITH APPROVALS BADGE ---
  Widget _buildApprovalDrawerItem(int index, IconData icon, String title, String? department) {
    if (department == null) return _buildDrawerItem(index, icon, title, color: Colors.orange);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contents')
          .where('isApproved', isEqualTo: false)
          .where('department', isEqualTo: department)
          .snapshots(),
      builder: (context, snapshot) {
        int count = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return ListTile(
          leading: Icon(icon, color: Colors.orange),
          title: Text(title),
          selected: _selectedIndex == index,
          selectedColor: Colors.blue.shade800,
          trailing: count > 0
              ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          )
              : null,
          onTap: () {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Widget _buildMailboxTile(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('notifications').where('userId', isEqualTo: uid).where('isRead', isEqualTo: false).snapshots(),
      builder: (context, snap) {
        int count = snap.hasData ? snap.data!.docs.length : 0;
        return ListTile(
          leading: const Icon(Icons.mail_outline, color: Colors.blueGrey),
          title: const Text("Mailbox"),
          trailing: count > 0 ? CircleAvatar(radius: 10, backgroundColor: Colors.red, child: Text('$count', style: const TextStyle(fontSize: 10, color: Colors.white))) : null,
          onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const MailBoxScreen())); },
        );
      },
    );
  }

  Widget _buildFloatingActionButton() {
    if (_selectedIndex == 2) {
      return FloatingActionButton(
        backgroundColor: Colors.blue.shade800,
        onPressed: () => teacherForumKey.currentState?.showAskQuestionDialog(),
        child: const Icon(Icons.add_comment, color: Colors.white),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherUploadScreen())),
      label: const Text("Contribute", style: TextStyle(color: Colors.white)),
      icon: const Icon(Icons.cloud_upload, color: Colors.white),
      backgroundColor: Colors.blue.shade800,
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String title, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      selected: _selectedIndex == index,
      selectedColor: Colors.blue.shade800,
      onTap: () { setState(() => _selectedIndex = index); Navigator.pop(context); },
    );
  }
}
