import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:profanity_filter/profanity_filter.dart';
import 'package:url_launcher/url_launcher.dart';

class ForumDetailScreen extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> postData;
  final String? targetAnswerId; // NEW: Passed from MailBox for highlighting

  const ForumDetailScreen({
    super.key,
    required this.postId,
    required this.postData,
    this.targetAnswerId,
  });

  @override
  State<ForumDetailScreen> createState() => _ForumDetailScreenState();
}

class _ForumDetailScreenState extends State<ForumDetailScreen> {
  final TextEditingController _answerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final profanityFilter = ProfanityFilter();

  final String cloudName = "dahslwjab";
  final String uploadPreset = "class_sync_uploads";
  final String folderName = "forum_media";
  final String _apiKey = "can not show this secret";
  final String _apiSecret = "can not show this secret";

  String? _replyingToId;
  String? _replyingToName;
  String? _replyingToAuthorId;

  // Highlighting Logic
  String? _highlightedId;

  List<Map<String, dynamic>> _userSuggestions = [];
  bool _showSuggestions = false;
  PlatformFile? _pickedFile;
  bool _isUploading = false;

  final Color primaryIndigo = const Color(0xFF303F9F);
  final Color teacherGreen = const Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    // If we arrived from a notification, set the highlight
    if (widget.targetAnswerId != null) {
      _highlightedId = widget.targetAnswerId;
      // Clear highlight after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightedId = null);
      });
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- 1. MEDIA & LINK LOGIC ---

  Future<void> _handleLinkTap(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<Map<String, String>?> _uploadToCloudinary() async {
    if (_pickedFile == null) return null;
    setState(() => _isUploading = true);
    try {
      final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/auto/upload");
      var request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folderName;

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes('file', _pickedFile!.bytes!, filename: _pickedFile!.name));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', _pickedFile!.path!));
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = jsonDecode(responseData);

      return {
        'url': jsonResponse['secure_url'],
        'publicId': jsonResponse['public_id'],
      };
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // --- 2. DATA ACTIONS (WITH NOTIFICATION TRIGGER) ---

  Future<void> _sendReply() async {
    final text = _answerController.text.trim();
    if (text.isEmpty && _pickedFile == null) return;
    if (profanityFilter.hasProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Respectful language required.")));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? fileUrl, fileName, publicId;
      if (_pickedFile != null) {
        var cloudRes = await _uploadToCloudinary();
        if (cloudRes != null) {
          fileUrl = cloudRes['url'];
          publicId = cloudRes['publicId'];
          fileName = _pickedFile!.name;
        }
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final String senderName = userData['name'] ?? "User";

      // 1. Add Answer to Sub-collection
      DocumentReference answerRef = await FirebaseFirestore.instance
          .collection('forum_posts')
          .doc(widget.postId)
          .collection('answers')
          .add({
        'text': text,
        'authorId': user.uid,
        'authorName': senderName,
        'authorPic': userData['profilePic'],
        'authorRole': userData['role'] ?? 'student',
        'timestamp': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'parentId': _replyingToId,
        'replyToName': _replyingToName,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'cloudinaryPublicId': publicId,
      });

      // 2. Update parent count
      await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).update({'answersCount': FieldValue.increment(1)});

      // 3. TRIGGER MAIL (NOTIFICATION)
      // Recipient is either the author of the specific comment being replied to,
      // or the author of the main post if it's a top-level reply.
      String recipientId = _replyingToAuthorId ?? widget.postData['authorId'];

      if (recipientId != user.uid) { // Don't notify yourself
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': recipientId,
          'senderId': user.uid,
          'senderName': senderName,
          'message': _replyingToId != null
              ? "Replied to your comment: $text"
              : "Answered your post: ${widget.postData['title']}",
          'notificationType': 'forum',
          'postId': widget.postId,
          'answerId': answerRef.id, // For highlighting when they click the mail
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }

      _answerController.clear();
      setState(() {
        _pickedFile = null;
        _replyingToId = null;
        _replyingToName = null;
        _replyingToAuthorId = null;
      });
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      debugPrint("Reply Error: $e");
    }
  }

  // --- 3. UI COMPONENTS ---

  Widget _buildPostHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primaryIndigo,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.postData['title'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.postData['description'] ?? "", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildRichText(String text) {
    final List<InlineSpan> spans = [];
    final RegExp combinedRegex = RegExp(r"(https?:\/\/[^\s]+)|(@[^\s]+)");
    int lastIndex = 0;

    combinedRegex.allMatches(text).forEach((match) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: const TextStyle(color: Colors.black87)));
      }
      final String matchText = match.group(0)!;
      if (matchText.startsWith('http')) {
        spans.add(WidgetSpan(
          child: GestureDetector(
            onTap: () => _handleLinkTap(matchText),
            child: Text(matchText, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline, fontWeight: FontWeight.bold)),
          ),
        ));
      } else {
        spans.add(TextSpan(text: matchText, style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)));
      }
      lastIndex = match.end;
    });

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex), style: const TextStyle(color: Colors.black87)));
    }
    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontSize: 14)));
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingToId != null)
              Container(
                color: Colors.indigo.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 16, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Expanded(child: Text("Replying to $_replyingToName", style: const TextStyle(fontSize: 12, color: Colors.indigo))),
                    IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() { _replyingToId = null; _replyingToAuthorId = null; })),
                  ],
                ),
              ),
            if (_pickedFile != null)
              Container(
                color: Colors.orange.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_pickedFile!.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _pickedFile = null)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.indigo), onPressed: _pickFile),
                  Expanded(
                    child: TextField(
                      controller: _answerController,
                      onChanged: _onTextChanged,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: "Type your answer...",
                        hintStyle: const TextStyle(fontSize: 14),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    backgroundColor: primaryIndigo,
                    child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: _sendReply),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    final bool isPostOwner = widget.postData['authorId'] == currentUserId;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text("Discussion Forum", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: primaryIndigo,
        foregroundColor: Colors.white,
        actions: [
          if (isPostOwner) IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _deleteEntireDiscussion)
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: _buildPostHeader()),
                    if (_isUploading) SliverToBoxAdapter(child: const LinearProgressIndicator(color: Colors.orange)),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('forum_posts')
                          .doc(widget.postId)
                          .collection('answers')
                          .orderBy('timestamp', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                        final threadedData = _buildThreadedList(snapshot.data!.docs);
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) {
                              final doc = threadedData[index]['doc'] as DocumentSnapshot;
                              final data = doc.data() as Map<String, dynamic>;
                              final int level = threadedData[index]['level'];
                              return _buildMessageCard(doc.id, data, level, currentUserId);
                            },
                            childCount: threadedData.length,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (_showSuggestions) _buildSuggestionsOverlay(),
              ],
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  // --- 4. DATA LOGIC & HELPERS ---

  List<Map<String, dynamic>> _buildThreadedList(List<QueryDocumentSnapshot> docs) {
    List<Map<String, dynamic>> threaded = [];
    void addChildren(String? pId, int level) {
      var kids = docs.where((d) => (d.data() as Map)['parentId'] == pId).toList();
      kids.sort((a, b) => (a['timestamp'] as Timestamp? ?? Timestamp.now()).compareTo(b['timestamp'] as Timestamp? ?? Timestamp.now()));
      for (var k in kids) {
        threaded.add({'doc': k, 'level': level});
        addChildren(k.id, level + 1);
      }
    }
    addChildren(null, 0);
    return threaded;
  }

  Widget _buildMessageCard(String docId, Map<String, dynamic> data, int level, String currentUserId) {
    final bool isTeacher = data['authorRole'] == 'teacher';
    final bool isMe = data['authorId'] == currentUserId;

    // HIGHLIGHT LOGIC
    final bool isTarget = _highlightedId == docId;

    return Padding(
      padding: EdgeInsets.only(left: (level.clamp(0, 3) * 12.0) + 12, right: 12, top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isTarget ? Colors.amber.shade100 : (isTeacher ? Colors.green.shade50 : Colors.white),
              borderRadius: BorderRadius.circular(15),
              border: isTarget ? Border.all(color: Colors.orange, width: 2) : Border.all(color: Colors.transparent, width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 12, backgroundImage: data['authorPic'] != null ? NetworkImage(data['authorPic']) : null),
                    const SizedBox(width: 8),
                    Text(data['authorName'] ?? "", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isTeacher ? teacherGreen : Colors.black87)),
                    const Spacer(),
                    _buildLikeButton(docId, currentUserId, data['likesCount'] ?? 0),
                  ],
                ),
                if (data['replyToName'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text("Replying to ${data['replyToName']}", style: const TextStyle(fontSize: 10, color: Colors.indigo, fontStyle: FontStyle.italic)),
                  ),
                _buildRichText(data['text'] ?? ""),
                if (data['fileUrl'] != null)
                  InkWell(
                    onTap: () => _previewMedia(data['fileUrl'], data['fileName']),
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.insert_drive_file, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(data['fileName'] ?? "File", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _replyingToId = docId;
                    _replyingToName = data['authorName'];
                    _replyingToAuthorId = data['authorId']; // CAPTURE FOR NOTIFICATION
                  }),
                  child: const Text("Reply", style: TextStyle(fontSize: 11)),
                ),
                if (isMe)
                  TextButton(
                    onPressed: () => _deleteMessage(docId),
                    child: const Text("Delete", style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ... [Keep _buildLikeButton, _deleteMessage, _deleteEntireDiscussion, _deleteFromCloudinary, _toggleLike, _onTextChanged, _fetchUserSuggestions, _applyMention, _previewMedia exactly as they were]

  Widget _buildLikeButton(String answerId, String uid, int count) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).collection('answers').doc(answerId).collection('likes').doc(uid).snapshots(),
      builder: (context, snapshot) {
        bool liked = snapshot.hasData && snapshot.data!.exists;
        return InkWell(
          onTap: () => _toggleLike(answerId, liked, uid),
          child: Row(
            children: [
              Icon(liked ? Icons.favorite : Icons.favorite_border, size: 14, color: liked ? Colors.red : Colors.grey),
              const SizedBox(width: 4),
              Text(count.toString(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(String docId) async {
    final doc = await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).collection('answers').doc(docId).get();
    final data = doc.data();
    if (data != null && data.containsKey('cloudinaryPublicId')) {
      await _deleteFromCloudinary(data['cloudinaryPublicId']);
    }
    await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).collection('answers').doc(docId).delete();
    await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).update({'answersCount': FieldValue.increment(-1)});
  }

  Future<void> _deleteEntireDiscussion() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Discussion?"),
        content: const Text("This will permanently remove all messages and media."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isUploading = true);
    try {
      final answers = await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).collection('answers').get();
      for (var doc in answers.docs) {
        if (doc.data().containsKey('cloudinaryPublicId')) {
          await _deleteFromCloudinary(doc.data()['cloudinaryPublicId']);
        }
      }
      await FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).delete();
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Delete error: $e");
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteFromCloudinary(String? publicId) async {
    if (publicId == null || publicId.isEmpty) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signatureSource = "public_id=$publicId&timestamp=$timestamp$_apiSecret";
    final signature = sha1.convert(utf8.encode(signatureSource)).toString();
    for (var type in ["image", "raw", "video"]) {
      try {
        await http.post(
          Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/$type/destroy"),
          body: {"public_id": publicId, "timestamp": timestamp.toString(), "api_key": _apiKey, "signature": signature},
        );
      } catch (e) { debugPrint("Cloudinary Delete error: $e"); }
    }
  }

  Future<void> _toggleLike(String answerId, bool alreadyLiked, String userId) async {
    final answerRef = FirebaseFirestore.instance.collection('forum_posts').doc(widget.postId).collection('answers').doc(answerId);
    final likeRef = answerRef.collection('likes').doc(userId);
    WriteBatch batch = FirebaseFirestore.instance.batch();
    if (alreadyLiked) {
      batch.delete(likeRef);
      batch.update(answerRef, {'likesCount': FieldValue.increment(-1)});
    } else {
      batch.set(likeRef, {'t': FieldValue.serverTimestamp()});
      batch.update(answerRef, {'likesCount': FieldValue.increment(1)});
    }
    await batch.commit();
  }

  void _onTextChanged(String value) {
    final lastWord = value.split(' ').last;
    if (lastWord.startsWith('@') && lastWord.length > 1) {
      _fetchUserSuggestions(lastWord.substring(1));
    } else {
      setState(() => _showSuggestions = false);
    }
  }

  Future<void> _fetchUserSuggestions(String query) async {
    final snapshot = await FirebaseFirestore.instance.collection('users').where('name', isGreaterThanOrEqualTo: query).limit(5).get();
    setState(() {
      _userSuggestions = snapshot.docs.map((d) => {'id': d.id, 'name': d['name']}).toList();
      _showSuggestions = _userSuggestions.isNotEmpty;
    });
  }

  void _applyMention(Map<String, dynamic> user) {
    final words = _answerController.text.split(' ');
    words.removeLast();
    setState(() {
      _answerController.text = "${words.join(' ')} @${user['name']} ";
      _showSuggestions = false;
    });
  }

  Widget _buildSuggestionsOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _userSuggestions.length,
          itemBuilder: (context, index) {
            final u = _userSuggestions[index];
            return ListTile(
              leading: const Icon(Icons.alternate_email, size: 18),
              title: Text(u['name'], style: const TextStyle(fontSize: 14)),
              onTap: () => _applyMention(u),
            );
          },
        ),
      ),
    );
  }

  void _previewMedia(String url, String fileName) async {
    final ext = fileName.split('.').last.toLowerCase();
    if (["jpg", "jpeg", "png"].contains(ext)) {
      showDialog(context: context, builder: (context) => Dialog(backgroundColor: Colors.transparent, child: InteractiveViewer(child: Image.network(url))));
    } else {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open file.")));
      }
    }
  }

}
