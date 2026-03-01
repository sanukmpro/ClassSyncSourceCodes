import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'app_data.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _bioController;
  late TextEditingController _phoneController;

  String? _selectedDepartment;
  String? _selectedSemester;
  List<String> _teacherSelectedSemesters = [];

  // CHANGED: Map stores a list of subjects for each semester key
  Map<String, List<String>> _semesterSubjects = {};

  String? _profileImageUrl;
  String? _userRole;
  File? _imageFile;
  bool _isLoading = true;

  final String _cloudName = "dahslwjab";
  final String _uploadPreset = "class_sync_uploads";
  final String _apiKey = "886847796499475";
  final String _apiSecret = "ed5NfxsJf007_4n2lI2GfJTFB3k";

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _bioController = TextEditingController();
    _phoneController = TextEditingController();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // --- CLOUDINARY LOGIC ---
  String? _getPublicIdFromUrl(String url) {
    try {
      final segments = url.split('/');
      final fileWithExtension = segments.last;
      final fileName = fileWithExtension.split('.').first;
      return "profile_pics/$fileName";
    } catch (e) {
      return null;
    }
  }

  Future<bool> _deleteImageFromCloudinary(String url) async {
    final publicId = _getPublicIdFromUrl(url);
    if (publicId == null) return false;
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signatureSource = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final signature = sha1.convert(utf8.encode(signatureSource)).toString();
    try {
      final response = await http.post(
        Uri.parse("https://api.cloudinary.com/v1_1/$_cloudName/image/destroy"),
        body: {
          "public_id": publicId,
          "timestamp": timestamp.toString(),
          "api_key": _apiKey,
          "signature": signature,
        },
      );
      final responseData = json.decode(response.body);
      return responseData['result'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  // --- DATA LOADING & SAVING ---
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? "";
          _bioController.text = data['bio'] ?? "";
          _phoneController.text = data['phone'] ?? "";
          _profileImageUrl = data['profilePic'];
          _userRole = data['role']?.toString().toLowerCase();
          _selectedDepartment = data['department'];

          if (_userRole == "student") {
            _selectedSemester = data['semester'];
          } else if (_userRole == "teacher") {
            _teacherSelectedSemesters = List<String>.from(data['assignedSemesters'] ?? []);

            // CHANGED: Handle dynamic list of subjects from Firestore
            var savedSubjects = data['semesterSubjects'] ?? {};
            _semesterSubjects = {};
            savedSubjects.forEach((key, value) {
              _semesterSubjects[key] = List<String>.from(value);
            });
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // Teacher Validation: Ensure at least one subject is picked for every selected semester
    if (_userRole == "teacher") {
      for (var sem in _teacherSelectedSemesters) {
        if (_semesterSubjects[sem] == null || _semesterSubjects[sem]!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Please select at least one subject for Semester $sem")),
          );
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      String? imageUrl = _profileImageUrl;
      if (_imageFile != null) {
        if (_profileImageUrl != null) await _deleteImageFromCloudinary(_profileImageUrl!);
        final cloudinary = CloudinaryPublic(_cloudName, _uploadPreset, cache: false);
        CloudinaryResponse response = await cloudinary.uploadFile(CloudinaryFile.fromFile(_imageFile!.path, folder: 'profile_pics'));
        imageUrl = response.secureUrl;
      }

      Map<String, dynamic> updateData = {
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'phone': _phoneController.text.trim(),
        'profilePic': imageUrl,
        'department': _selectedDepartment,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (_userRole == "student") {
        updateData['semester'] = _selectedSemester;
      } else if (_userRole == "teacher") {
        updateData['assignedSemesters'] = _teacherSelectedSemesters;
        updateData['semesterSubjects'] = _semesterSubjects;
      }

      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update(updateData);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI BUILDERS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileImageHeader(),
              const SizedBox(height: 20),
              _sectionHeader("Personal Information"),
              _buildTextField(_nameController, "Display Name", Icons.person_outline),
              const SizedBox(height: 15),
              _buildTextField(_phoneController, "Phone Number", Icons.phone_outlined, keyboardType: TextInputType.phone),
              const SizedBox(height: 15),
              _buildTextField(_bioController, "Bio", Icons.info_outline, maxLines: 3),
              const SizedBox(height: 30),
              _sectionHeader("Academic Details"),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                isExpanded: true,
                decoration: _inputDecoration("Department", Icons.business_outlined),
                items: AppData.departments.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedDepartment = val;
                    _semesterSubjects.clear();
                  });
                },
                validator: (v) => v == null ? "Select Department" : null,
              ),
              const SizedBox(height: 15),
              if (_userRole == "student") _buildStudentForm(),
              if (_userRole == "teacher") _buildTeacherForm(),
              const SizedBox(height: 40),
              _buildSaveButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherForm() {
    if (_selectedDepartment == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text("Please select a department to see teaching options.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Semesters You Teach:", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: AppData.semesters.map((sem) {
            bool isSelected = _teacherSelectedSemesters.contains(sem);
            return FilterChip(
              label: Text("Sem $sem"),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _teacherSelectedSemesters.add(sem);
                    _semesterSubjects[sem] = []; // Initialize empty list for new semester
                  } else {
                    _teacherSelectedSemesters.remove(sem);
                    _semesterSubjects.remove(sem);
                  }
                });
              },
              selectedColor: Colors.indigo[100],
              checkmarkColor: Colors.indigo,
            );
          }).toList(),
        ),
        if (_teacherSelectedSemesters.isNotEmpty) ...[
          const SizedBox(height: 25),
          const Text("Select Subjects for each Semester:", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          ..._teacherSelectedSemesters.map((sem) {
            List<String> availableSubjects = AppData.subjectMap[_selectedDepartment]?[sem] ?? [];

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Semester $sem", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo[900])),
                  const Divider(),
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: availableSubjects.map((subject) {
                      bool isPicked = _semesterSubjects[sem]?.contains(subject) ?? false;
                      return ChoiceChip(
                        label: Text(subject, style: TextStyle(fontSize: 12, color: isPicked ? Colors.white : Colors.black87)),
                        selected: isPicked,
                        selectedColor: Colors.indigo[700],
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _semesterSubjects[sem] ??= [];
                              _semesterSubjects[sem]!.add(subject);
                            } else {
                              _semesterSubjects[sem]?.remove(subject);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ]
      ],
    );
  }

  // --- REUSABLE UI ---
  Widget _buildStudentForm() {
    return DropdownButtonFormField<String>(
      value: _selectedSemester,
      decoration: _inputDecoration("Current Semester", Icons.school_outlined),
      items: AppData.semesters.map((s) => DropdownMenuItem(value: s, child: Text("Semester $s"))).toList(),
      onChanged: (val) => setState(() => _selectedSemester = val),
      validator: (v) => v == null ? "Select your semester" : null,
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon),
      validator: (v) => v == null || v.isEmpty ? "This field is required" : null,
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.indigo[900]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.indigo[900]!, width: 1.5)),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo[900],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text("SAVE CHANGES", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      ),
    );
  }

  Widget _buildProfileImageHeader() {
    return Center(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10)],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: Colors.indigo[50],
              backgroundImage: _imageFile != null
                  ? FileImage(_imageFile!)
                  : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) : null) as ImageProvider?,
              child: _profileImageUrl == null && _imageFile == null
                  ? Icon(Icons.person, size: 60, color: Colors.indigo[200])
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                backgroundColor: Colors.indigo[900],
                radius: 18,
                child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo[900])),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  Future<void> _removePhoto() async {
    if (_profileImageUrl == null && _imageFile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Photo?"),
        content: const Text("This will delete your profile picture permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Remove", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      if (_profileImageUrl != null) await _deleteImageFromCloudinary(_profileImageUrl!);
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({'profilePic': null});
      setState(() {
        _profileImageUrl = null;
        _imageFile = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}