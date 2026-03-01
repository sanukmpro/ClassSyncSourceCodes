import 'dart:io';
import 'package:flutter/foundation.dart'; // Required for kIsWeb check
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';

// Import your central AppData file
import 'app_data.dart';

class UploadContentScreen extends StatefulWidget {
  final bool isTeacher;
  const UploadContentScreen({super.key, required this.isTeacher});

  @override
  State<UploadContentScreen> createState() => _UploadContentScreenState();
}

class _UploadContentScreenState extends State<UploadContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  bool _isUploading = false;
  bool _isLoadingUserData = true;
  PlatformFile? _pickedFile;

  String? _selectedDepartment;
  String? _selectedSemester;
  String? _selectedSubject;
  String _selectedContentType = 'Notes';

  List<String> _availableDepartments = [];
  List<String> _availableSubjects = [];

  final String _cloudName = "dahslwjab";
  final String _uploadPreset = "class_sync_uploads";

  final List<String> _contentTypes = [
    'Notes', 'Assignment', 'PYQ (Previous Year)', 'Lab Manual', 'Syllabus', 'Video Lecture', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _initializeForm() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoadingUserData = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        setState(() => _isLoadingUserData = false);
        return;
      }

      final data = userDoc.data()!;
      final department = data['department'] as String?;

      if (department != null && AppData.departments.contains(department)) {
        _selectedDepartment = department;
        _availableDepartments = [department];
      } else {
        _availableDepartments = AppData.departments;
      }
    } catch (e) {
      debugPrint("Error initializing form: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
          _updateAvailableSubjects();
        });
      }
    }
  }

  void _updateAvailableSubjects() {
    final subjects = AppData.subjectMap[_selectedDepartment]?[_selectedSemester] ?? [];
    setState(() {
      _availableSubjects = subjects;
      if (!_availableSubjects.contains(_selectedSubject)) {
        _selectedSubject = null;
      }
    });
  }

  // --- PLATFORM AGNOSTIC FILE PICKER ---
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true, // REQUIRED for Web to populate result.files.single.bytes
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

  // --- FIXED SUBMIT LOGIC (Web & Mobile Compatible) ---
  Future<void> _submitContent() async {
    if (!_formKey.currentState!.validate() || _pickedFile == null) {
      _showSnackBar("Please fill all required fields and select a file.");
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Authentication error.");

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final uploaderName = userDoc.data()?['name'] ?? "Anonymous";

      final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
      CloudinaryResponse response;

      // Handle file upload based on platform
      if (kIsWeb) {
        // WEB: Must use bytes and fromBytesData constructor
        if (_pickedFile!.bytes == null) throw Exception("File data missing (Web).");
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            _pickedFile!.bytes!,
            identifier: _pickedFile!.name,
            folder: 'college_content/$_selectedDepartment',
          ),
        );
      } else {
        // MOBILE/DESKTOP: Use file path
        if (_pickedFile!.path == null) throw Exception("File path unavailable.");
        response = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(
            _pickedFile!.path!,
            folder: 'college_content/$_selectedDepartment',
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
        'publicId': response.publicId,
        'fileName': _pickedFile!.name,
        'fileExtension': _pickedFile!.extension?.toLowerCase() ?? 'file',
        'fileSize': _pickedFile!.size,
        'uploaderId': user.uid,
        'uploaderName': uploaderName,
        'isApproved': widget.isTeacher,
        'timestamp': FieldValue.serverTimestamp(),
        'views': 0,
        'downloads': 0,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar(widget.isTeacher ? "Material published successfully!" : "Submitted for review.");
      }
    } catch (e) {
      _showSnackBar("Upload failed: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.isTeacher ? Colors.blue.shade800 : Colors.indigo.shade700;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTeacher ? "Publish Material" : "Submit Material"),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingUserData || _isUploading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: themeColor),
            const SizedBox(height: 20),
            Text(
              _isUploading ? "Uploading file..." : "Loading user data...",
              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600), // Better layout for Web
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilePicker(themeColor),
                  const SizedBox(height: 24),
                  _buildLabel("Material Title *"),
                  _buildTextField(_titleController, "e.g., Unit 1 Notes - Thermodynamics"),
                  const SizedBox(height: 20),
                  _buildLabel("Categorization *"),
                  _buildDropdown(
                    value: _selectedDepartment,
                    hint: "Department",
                    items: _availableDepartments,
                    onChanged: _availableDepartments.length == 1 ? null : (val) {
                      setState(() {
                        _selectedDepartment = val;
                        _updateAvailableSubjects();
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          value: _selectedSemester,
                          hint: "Semester",
                          items: AppData.semesters,
                          onChanged: (val) {
                            setState(() {
                              _selectedSemester = val;
                              _updateAvailableSubjects();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildDropdown(
                          value: _selectedContentType,
                          hint: "Content Type",
                          items: _contentTypes,
                          onChanged: (val) => setState(() => _selectedContentType = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    value: _selectedSubject,
                    hint: "Subject",
                    items: _availableSubjects,
                    onChanged: (val) => setState(() => _selectedSubject = val),
                    disabled: _availableSubjects.isEmpty,
                  ),
                  const SizedBox(height: 20),
                  _buildLabel("Description (Optional)"),
                  _buildTextField(_descController, "e.g., Covers the first and second laws.", maxLines: 3),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      onPressed: _submitContent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      label: Text(widget.isTeacher ? "PUBLISH MATERIAL" : "SUBMIT FOR REVIEW"),
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

  // --- UI Components ---

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      validator: (v) => v == null || v.isEmpty ? "This field is required" : null,
    );
  }

  Widget _buildDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required void Function(String?)? onChanged,
    bool disabled = false,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: hint,
        filled: true,
        fillColor: (disabled || onChanged == null) ? Colors.grey.shade200 : Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      items: items.map((item) => DropdownMenuItem(value: item, child: Text(item, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (disabled || onChanged == null) ? null : onChanged,
      validator: (v) => v == null ? "Required" : null,
    );
  }

  Widget _buildFilePicker(Color color) {
    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30), // Increased padding to match the size
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
              color: color.withOpacity(0.3),
              width: 2,
              style: BorderStyle.solid
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.cloud_upload_rounded, size: 50, color: color), // Larger icon
            const SizedBox(height: 10),
            Text(
              _pickedFile == null ? "Select Document / Media" : _pickedFile!.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 16
              ),
            ),
            if (_pickedFile != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  "${(_pickedFile!.size / (1024 * 1024)).toStringAsFixed(2)} MB",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

}