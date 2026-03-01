import 'dart:io';
import 'package:flutter/foundation.dart'; // Required for kIsWeb
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'app_data.dart';

class TeacherIdRequestScreen extends StatefulWidget {
  const TeacherIdRequestScreen({super.key});

  @override
  State<TeacherIdRequestScreen> createState() => _TeacherIdRequestScreenState();
}

class _TeacherIdRequestScreenState extends State<TeacherIdRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  String? _selectedDepartment;
  String? _selectedSemester;
  final List<String> _selectedSubjects = [];
  List<String> _availableSubjects = [];
  PlatformFile? _pickedFile;
  bool _isSubmitting = false;

  // Cloudinary Config
  final String _cloudName = "dahslwjab";
  final String _uploadPreset = "class_sync_uploads";

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _updateAvailableSubjects() {
    if (_selectedDepartment != null && _selectedSemester != null) {
      setState(() {
        _availableSubjects = AppData.subjectMap[_selectedDepartment]?[_selectedSemester] ?? [];
        _selectedSubjects.removeWhere((s) => !_availableSubjects.contains(s));
      });
    }
  }

  // --- FIXED FILE PICKER FOR WEB & MOBILE ---
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'pdf'],
        withData: true, // Crucial for Web to access .bytes
      );
      if (result != null) setState(() => _pickedFile = result.files.first);
    } catch (e) {
      _showSnack("Error picking file: $e");
    }
  }

  // --- FIXED SUBMIT LOGIC FOR WEB & MOBILE ---
  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSubjects.isEmpty) {
      _showSnack("Please select at least one subject.");
      return;
    }

    // On Web we check .bytes, on Mobile we check .path
    if (_pickedFile == null || (kIsWeb ? _pickedFile!.bytes == null : _pickedFile!.path == null)) {
      _showSnack("Please upload your Identity Proof.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final email = _emailController.text.trim().toLowerCase();
      final name = _nameController.text.trim();
      final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

      // 1. Upload ID Proof to Cloudinary (Platform Aware)
      final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);

      CloudinaryResponse response;
      if (kIsWeb) {
        // FIXED: Change fromBytes to fromBytesData
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            _pickedFile!.bytes!,
            identifier: _pickedFile!.name,
            resourceType: CloudinaryResourceType.Auto,
            folder: 'faculty_verification',
          ),
        );
      } else {
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            _pickedFile!.path!,
            resourceType: CloudinaryResourceType.Auto,
            folder: 'faculty_verification',
          ),
        );
      }

      // 2. Database Batch Update
      final batch = FirebaseFirestore.instance.batch();
      final requestRef = FirebaseFirestore.instance.collection('id_requests').doc(email);
      final teacherIdRef = FirebaseFirestore.instance.collection('teacher_ids').doc(email);
      final userRef = FirebaseFirestore.instance.collection('users').doc(currentUid ?? email);

      final Map<String, dynamic> teacherData = {
        'uid': currentUid ?? email,
        'name': name,
        'email': email,
        'department': _selectedDepartment,
        'semester': _selectedSemester,
        'subjects': _selectedSubjects,
        'role': 'teacher',
        'isApproved': false,
        'isProfileComplete': true,
        'idProofUrl': response.secureUrl,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      };

      batch.set(requestRef, {
        ...teacherData,
        'type': 'faculty_verification',
      }, SetOptions(merge: true));

      batch.set(teacherIdRef, {
        'email': email,
        'name': name,
        'department': _selectedDepartment,
        'subjects': _selectedSubjects,
        'role': 'teacher',
        'claimedByUid': currentUid,
        'isApproved': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(userRef, teacherData, SetOptions(merge: true));

      await batch.commit();

      if (mounted) _showSuccessDialog();
    } catch (e) {
      _showSnack("Submission failed: $e");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- WIDGET HELPERS ---

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: (v) => v == null || v.isEmpty ? "Required" : null,
    );
  }

  Widget _buildDropdown(String label, List<String> items, String? value, Function(String?) onChanged, IconData icon) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? "Required" : null,
    );
  }

  Widget _buildSubjectChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: _availableSubjects.map((subject) {
        final isSelected = _selectedSubjects.contains(subject);
        return FilterChip(
          label: Text(subject, style: TextStyle(fontSize: 12, color: isSelected ? Colors.indigo[900] : Colors.black87)),
          selected: isSelected,
          selectedColor: Colors.indigo[50],
          checkmarkColor: Colors.indigo[900],
          onSelected: (bool selected) {
            setState(() {
              selected ? _selectedSubjects.add(subject) : _selectedSubjects.remove(subject);
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildFilePicker() {
    return InkWell(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.indigo[900]!, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(15),
          color: Colors.indigo[50]!.withOpacity(0.3),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_outlined, color: Colors.indigo[900], size: 30),
            const SizedBox(height: 8),
            Text(
              _pickedFile == null ? "Tap to upload Identity Document" : _pickedFile!.name,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Request Submitted"),
        content: const Text("Your faculty verification request is pending approval. You will be able to log in once the administrator verifies your details."),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Faculty Verification"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: _isSubmitting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600), // Ensures clean layout on Web
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle("Identity Details"),
                  const SizedBox(height: 15),
                  _buildTextField(_nameController, "Full Name", Icons.person),
                  const SizedBox(height: 15),
                  _buildTextField(_emailController, "Official Email", Icons.email, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 30),
                  _buildSectionTitle("Teaching Scope"),
                  const SizedBox(height: 15),
                  _buildDropdown("Department", AppData.departments, _selectedDepartment, (val) {
                    setState(() { _selectedDepartment = val; _updateAvailableSubjects(); });
                  }, Icons.business),
                  const SizedBox(height: 15),
                  _buildDropdown("Semester", AppData.semesters, _selectedSemester, (val) {
                    setState(() { _selectedSemester = val; _updateAvailableSubjects(); });
                  }, Icons.school),
                  const SizedBox(height: 20),
                  if (_availableSubjects.isNotEmpty) ...[
                    const Text("Select Teaching Subjects", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildSubjectChips(),
                  ],
                  const SizedBox(height: 30),
                  _buildSectionTitle("Identity Proof (ID Card)"),
                  const SizedBox(height: 10),
                  _buildFilePicker(),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo[900],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: const Text("SUBMIT REQUEST", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}