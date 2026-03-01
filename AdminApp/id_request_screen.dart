import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class IdRequestScreen extends StatefulWidget {
  const IdRequestScreen({super.key});

  @override
  State<IdRequestScreen> createState() => _IdRequestScreenState();
}

class _IdRequestScreenState extends State<IdRequestScreen> {
  static const String _serviceId = 'class_sync_admin';
  static const String _templateId = 'template_3nnc8bx';
  static const String _publicKey = 'oSQlLeSsuJJmvZXh9';

  String _formatSubjects(dynamic subjectsData) {
    if (subjectsData == null) return "Not Assigned";
    if (subjectsData is List) {
      return subjectsData.isEmpty ? "Not Assigned" : subjectsData.join(", ");
    }
    return subjectsData.toString();
  }

  Future<void> _approveRequest(String docId, Map<String, dynamic> data) async {
    final newIdController = TextEditingController();
    final dynamic rawSubjects = data['subjects'] ?? data['subject'];
    final String displaySubjects = _formatSubjects(rawSubjects);
    final String teacherEmail = data['email'].toString().trim().toLowerCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Approve Faculty Access"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Assign a security ID for ${data['name']}:"),
            const SizedBox(height: 15),
            TextField(
              controller: newIdController,
              decoration: const InputDecoration(
                labelText: "Teacher ID",
                hintText: "e.g. T-CSE-01",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              final newId = newIdController.text.trim();
              if (newId.isEmpty) return;
              if (mounted) Navigator.pop(context); // Close dialog immediately

              try {
                final firestore = FirebaseFirestore.instance;
                final idCheck = await firestore.collection('teacher_ids').doc(newId).get();
                if (idCheck.exists) {
                  _showSnackBar("Error: This Teacher ID is already assigned.");
                  return;
                }

                WriteBatch batch = firestore.batch();

                // 1. Update the original request
                DocumentReference requestRef = firestore.collection('id_requests').doc(docId);
                batch.update(requestRef, {
                  'status': 'approved',
                  'teacherId': newId,
                  'approvedAt': FieldValue.serverTimestamp(),
                });

                // 2. Create the master 'teacher_ids' record
                DocumentReference masterRef = firestore.collection('teacher_ids').doc(newId);
                batch.set(masterRef, {
                  'teacherId': newId,
                  'name': data['name'],
                  'email': teacherEmail,
                  'department': data['department'],
                  'semester': data['semester'],
                  'subjects': rawSubjects,
                  'active': true,
                  'isApproved': true,
                  'authorizedAt': FieldValue.serverTimestamp(),
                });

                // 3. CRITICAL: Create or Update the 'users' document
                final userQuery = await firestore.collection('users').where('email', isEqualTo: teacherEmail).limit(1).get();

                final userDataToSet = {
                  'email': teacherEmail,
                  'name': data['name'],
                  'department': data['department'],
                  'semester': data['semester'],
                  'role': 'teacher', // Assign the role
                  'isApproved': true, // Mark as approved
                  'teacherId': newId, // Link to the master ID
                  'createdAt': FieldValue.serverTimestamp(),
                };

                if (userQuery.docs.isNotEmpty) {
                  // User already exists (logged in before), so update them
                  batch.update(userQuery.docs.first.reference, userDataToSet);
                } else {
                  // User does NOT exist, create a new document for them
                  // They will claim this doc and add their UID upon first login
                  DocumentReference newUserRef = firestore.collection('users').doc();
                  batch.set(newUserRef, userDataToSet);
                }

                // Commit all changes at once
                await batch.commit();

                // 4. Notify via Email
                await _sendEmailJS(
                  teacherEmail: teacherEmail,
                  teacherName: data['name'],
                  statusMessage: "CONGRATULATIONS! Your Faculty Verification is Approved.\n\n"
                      "YOUR OFFICIAL TEACHER ID: $newId\n"
                      "ASSIGNED SUBJECTS: $displaySubjects\n\n"
                      "HOW TO LOGIN:\n"
                      "1. Open the Teacher App.\n"
                      "2. Sign in with Google using: $teacherEmail\n"
                      "3. Enter your Teacher ID: $newId when prompted.\n\n"
                      "Welcome aboard!",
                );

                _showSnackBar("Approved! Teacher '$newId' is now active and visible to students.");
              } catch (e) {
                _showSnackBar("Approval failed: $e");
              }
            },
            child: const Text("Approve & Notify"),
          ),
        ],
      ),
    );
  }

  // --- LOGIC: REJECT --- (No changes needed here)
  Future<void> _rejectRequest(String docId, Map<String, dynamic> data) async {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Request"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
              labelText: "Reason for rejection", hintText: "e.g. Invalid document"),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              if (reasonController.text.isEmpty) return;
              if (mounted) Navigator.pop(context);
              try {
                await _sendEmailJS(
                  teacherEmail: data['email'],
                  teacherName: data['name'],
                  statusMessage: "Faculty Access Denied.\n\nReason: ${reasonController.text}\n\n"
                      "If you believe this is a mistake, please re-submit the form.",
                );
                await FirebaseFirestore.instance.collection('id_requests').doc(docId).update({
                  'status': 'rejected',
                  'rejectionReason': reasonController.text,
                  'rejectedAt': FieldValue.serverTimestamp(),
                });
                _showSnackBar("Request Rejected.");
              } catch (e) {
                _showSnackBar("Rejection Error: $e");
              }
            },
            child: const Text("Confirm Reject"),
          ),
        ],
      ),
    );
  }

  // --- HELPERS --- (No changes needed)
  Future<void> _viewDoc(String? url) async {
    if (url == null || url.isEmpty) {
      _showSnackBar("No document URL found.");
      return;
    }
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnackBar("Could not launch browser.");
    }
  }

  Future<void> _sendEmailJS(
      {required String teacherEmail,
        required String teacherName,
        required String statusMessage}) async {
    try {
      final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'origin': 'http://localhost'},
        body: json.encode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'teacher_email': teacherEmail,
            'teacher_name': teacherName,
            'status_message': statusMessage,
          }
        }),
      );
    } catch (e) {
      debugPrint("Email Error: $e");
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: msg.startsWith("Error") ? Colors.red : Colors.green,
      ));
    }
  }

  // --- BUILD METHOD --- (No changes needed)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verification Requests"),
        backgroundColor: Colors.orange.shade100,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('id_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 50, color: Colors.grey),
                  Text("No pending requests.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  title: Text(data['name'] ?? "Unknown",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "Subjects: ${_formatSubjects(data['subjects'] ?? data['subject'])}\n"
                          "Dept: ${data['department']} | Sem: ${data['semester']}\n"
                          "Email: ${data['email']}",
                      style: const TextStyle(height: 1.4),
                    ),
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          tooltip: "View ID Proof",
                          icon: const Icon(Icons.remove_red_eye, color: Colors.blue),
                          onPressed: () => _viewDoc(data['idProofUrl'])),
                      IconButton(
                          tooltip: "Approve",
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _approveRequest(doc.id, data)),
                      IconButton(
                          tooltip: "Reject",
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => _rejectRequest(doc.id, data)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
