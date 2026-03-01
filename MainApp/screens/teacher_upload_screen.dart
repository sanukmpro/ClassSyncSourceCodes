import 'dart:io';
import 'package:flutter/foundation.dart'; // Required for kIsWeb
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'app_data.dart';

class TeacherUploadScreen extends StatefulWidget {
  const TeacherUploadScreen({super.key});

  @override
  State<TeacherUploadScreen> createState() => _TeacherUploadScreenState();
}

class _TeacherUploadScreenState extends State<TeacherUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  bool _isUploading = false;
  bool _isLoadingData = true;
  PlatformFile? _pickedFile;

  String? _selectedDepartment;
  String? _selectedSemester;
  String? _selectedSubject;
  String _selectedContentType = 'Notes';

  List<String> _availableSubjects = [];

  // Configuration
  final String _cloudName = "dahslwjab";
  final String _uploadPreset = "class_sync_uploads";

  final List<String> _contentTypes = [
    'Notes', 'Assignment', 'PYQ', 'Lab Manual', 'Syllabus', 'Video Lecture', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _initializeTeacherProfile();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _initializeTeacherProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final dept = doc.data()?['department'] as String?;
          if (dept != null && AppData.departments.contains(dept)) {
            setState(() => _selectedDepartment = dept);
          }
        }
      }
    } catch (e) {
      _showSnackBar("Error loading profile: $e");
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _updateSubjects() {
    if (_selectedDepartment == null || _selectedSemester == null) return;
    final subjects = AppData.subjectMap[_selectedDepartment]?[_selectedSemester] ?? [];
    setState(() {
      _availableSubjects = List<String>.from(subjects);
      _selectedSubject = null;
    });
  }

  // --- FIXED FILE PICKER FOR ALL PLATFORMS ---
  Future<void> _handleFilePick() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // Crucial for Web to populate bytes
      );
      if (result != null) {
        setState(() {
          _pickedFile = result.files.single;
          if (_titleController.text.isEmpty) {
            _titleController.text = _pickedFile!.name.split('.').first.replaceAll('_', ' ');
          }
        });
      }
    } catch (e) {
      _showSnackBar("Error selecting file: $e");
    }
  }

  // --- FIXED PUBLISH LOGIC FOR ALL PLATFORMS ---
  Future<void> _handlePublish() async {
    if (!_formKey.currentState!.validate() || _pickedFile == null) {
      _showSnackBar(_pickedFile == null ? "Please select a file first" : "Fill all required fields");
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user?.uid).get();
      final uploaderName = userDoc.data()?['name'] ?? "Faculty";

      final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
      CloudinaryResponse response;

      // Platform Conditional logic
      if (kIsWeb) {
        // FIXED: Using fromBytesData instead of fromBytes for Web
        if (_pickedFile!.bytes == null) throw Exception("File data missing (Web).");
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            _pickedFile!.bytes!,
            identifier: _pickedFile!.name,
            folder: 'content/$_selectedDepartment',
          ),
        );
      } else {
        // MOBILE/DESKTOP: Use file path
        if (_pickedFile!.path == null) throw Exception("File path missing.");
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            _pickedFile!.path!,
            folder: 'content/$_selectedDepartment',
          ),
        );
      }

      await FirebaseFirestore.instance.collection('contents').add({
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'department': _selectedDepartment,
        'semester': _selectedSemester,
        'subject': _selectedSubject,
        'contentType': _selectedContentType,
        'fileUrl': response.secureUrl,
        'fileName': _pickedFile!.name,
        'uploaderId': user?.uid,
        'uploaderName': uploaderName,
        'isApproved': true,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Material Published Successfully!");
      }
    } catch (e) {
      _showSnackBar("Upload Failed: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.indigo.shade800;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Publish Material", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoadingData || _isUploading
          ? _buildLoadingOverlay(primaryColor)
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600), // Responsive layout
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFileCard(primaryColor),
                  const SizedBox(height: 25),
                  _buildSectionTitle("General Information"),
                  _buildTextField(_titleController, "Title", Icons.title, "Enter material title"),
                  const SizedBox(height: 15),
                  _buildTextField(_descController, "Description", Icons.description, "Optional details...", maxLines: 3),
                  const SizedBox(height: 25),
                  _buildSectionTitle("Categorization"),
                  _buildDropdown(
                    label: "Department",
                    value: _selectedDepartment,
                    items: AppData.departments,
                    icon: Icons.business,
                    onChanged: _selectedDepartment == null ? (v) => setState(() => _selectedDepartment = v) : null,
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: "Semester",
                          value: _selectedSemester,
                          items: AppData.semesters,
                          icon: Icons.calendar_month,
                          onChanged: (v) {
                            setState(() => _selectedSemester = v);
                            _updateSubjects();
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildDropdown(
                          label: "Type",
                          value: _selectedContentType,
                          items: _contentTypes,
                          icon: Icons.category,
                          onChanged: (v) => setState(() => _selectedContentType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    label: "Subject",
                    value: _selectedSubject,
                    items: _availableSubjects,
                    icon: Icons.book,
                    onChanged: _availableSubjects.isEmpty ? null : (v) => setState(() => _selectedSubject = v),
                    disabled: _availableSubjects.isEmpty,
                  ),
                  const SizedBox(height: 40),
                  _buildSubmitButton(primaryColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- UI Components ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildFileCard(Color color) {
    return InkWell(
      onTap: _handleFilePick,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3), width: 2, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_rounded, size: 50, color: color),
            const SizedBox(height: 10),
            Text(
              _pickedFile == null ? "Select Document / Media" : _pickedFile!.name,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (_pickedFile != null)
              Text("${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, String hint, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.indigo),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (v) => v == null || v.isEmpty ? "Required" : null,
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required void Function(String?)? onChanged,
    bool disabled = false,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: disabled ? null : onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.indigo),
        filled: true,
        fillColor: (disabled || onChanged == null) ? Colors.grey.shade200 : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (v) => v == null ? "Select $label" : null,
    );
  }

  Widget _buildSubmitButton(Color color) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isUploading ? null : _handlePublish,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 5,
        ),
        child: const Text("PUBLISH TO LIBRARY", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      ),
    );
  }

  Widget _buildLoadingOverlay(Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: color),
          const SizedBox(height: 20),
          Text(_isUploading ? "Uploading to Cloud..." : "Preparing Form...", style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}