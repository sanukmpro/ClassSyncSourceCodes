import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class ApprovalQueueScreen extends StatefulWidget {
  const ApprovalQueueScreen({super.key});

  @override
  State<ApprovalQueueScreen> createState() => _ApprovalQueueScreenState();
}

class _ApprovalQueueScreenState extends State<ApprovalQueueScreen> {
  // EmailJS Credentials
  static const String _serviceId = 'class_sync_admin';
  static const String _templateId = 'template_3nnc8bx';
  static const String _publicKey = 'oSQlLeSsuJJmvZXh9';

  // --- LOGIC: APPROVE TEACHER ---
  Future<void> _approveTeacher(String docId, Map<String, dynamic> data) async {
    // Normalizing email from the document ID or the data
    final String teacherEmail = docId.toLowerCase();
    final String teacherName = data['name'] ?? "Teacher";

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. Update the 'users' document (This is the primary profile)
      // Since our Request Screen used the Email as the Doc ID, we update that same doc.
      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(teacherEmail);

      batch.update(userRef, {
        'isApproved': true,
        'status': 'active',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // 2. Update 'teacher_ids' collection to mark as approved
      DocumentReference teacherIdRef = FirebaseFirestore.instance.collection('teacher_ids').doc(teacherEmail);
      batch.update(teacherIdRef, {
        'isApproved': true,
        'active': true,
      });

      // 3. Delete from 'id_requests'
      DocumentReference requestRef = FirebaseFirestore.instance.collection('id_requests').doc(teacherEmail);
      batch.delete(requestRef);

      // Execute database changes
      await batch.commit();

      // 4. Notify via Email
      await _sendEmailJS(
        teacherEmail: teacherEmail,
        teacherName: teacherName,
        statusMessage: "APPROVED! Your faculty account is now active. You can now log in to ClassSync.",
      );

      _showSnackBar("$teacherName approved successfully!");
    } catch (e) {
      debugPrint("Approval Error: $e");
      _showSnackBar("Approval failed: $e");
    }
  }

  // --- LOGIC: REJECT TEACHER ---
  Future<void> _rejectTeacher(String docId, String email, String name) async {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reject Faculty Request"),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: "Reason for rejection",
            hintText: "e.g., Invalid ID card or wrong department",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              String reason = reasonController.text.trim();
              if (reason.isEmpty) return;

              try {
                // 1. Send Rejection Email
                await _sendEmailJS(
                  teacherEmail: email,
                  teacherName: name,
                  statusMessage: "REJECTED. Reason: $reason. Please resubmit your request with correct details.",
                );

                // 2. Cleanup: Delete the request and the temporary user profile
                WriteBatch batch = FirebaseFirestore.instance.batch();
                batch.delete(FirebaseFirestore.instance.collection('id_requests').doc(docId));
                batch.delete(FirebaseFirestore.instance.collection('users').doc(docId));
                batch.delete(FirebaseFirestore.instance.collection('teacher_ids').doc(docId));

                await batch.commit();

                if (mounted) {
                  Navigator.pop(context);
                  _showSnackBar("Request rejected and deleted.");
                }
              } catch (e) {
                _showSnackBar("Error during rejection: $e");
              }
            },
            child: const Text("Reject & Notify", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- LOGIC: SEND EMAIL VIA EMAILJS ---
  Future<void> _sendEmailJS({
    required String teacherEmail,
    required String teacherName,
    required String statusMessage,
  }) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost',
        },
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
      if (response.statusCode != 200) {
        debugPrint("❌ EmailJS Failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Email request failed: $e");
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Faculty Approvals", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[800],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder(
        // Updated collection name to 'id_requests' and field to 'requestedAt'
        stream: FirebaseFirestore.instance
            .collection('id_requests')
            .orderBy('requestedAt', descending: true)
            .snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text("No pending faculty requests.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              var doc = docs[index];
              var data = doc.data() as Map<String, dynamic>;
              String email = doc.id; // The email is our ID

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo[50],
                    child: Text(data['name']?[0] ?? "T", style: TextStyle(color: Colors.indigo[800])),
                  ),
                  title: Text(data['name'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${data['department']} • Sem ${data['semester']}"),
                      Text(email, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _approveTeacher(email, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _rejectTeacher(email, email, data['name'] ?? "Teacher"),
                      ),
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