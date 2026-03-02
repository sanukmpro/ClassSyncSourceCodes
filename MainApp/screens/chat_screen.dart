import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:profanity_filter/profanity_filter.dart';
import 'package:intl/intl.dart'; // Add to pubspec.yaml
import 'chat_utils.dart';

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String recipientId;
  final String recipientName;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _authUid = FirebaseAuth.instance.currentUser?.uid ?? "";
  final profanityFilter = ProfanityFilter();

  final String cloudName = "can not show this secret";
  final String uploadPreset = "class_sync_uploads";
  final String folderName = "chat_media";
  final String _apiKey = "can not show this secret";
  final String _apiSecret = "can not show this secret";

  String? _mySenderId;
  bool _isTeacher = false;
  StreamSubscription? _readStatusSubscription;

  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();
  bool _isRecording = false;
  PlatformFile? _pickedFile;
  bool _isUploading = false;

  Map<String, dynamic>? _replyingToMessage;
  String? _highlightedMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  final List<String> _customEmojis = ['🔥', '✨', '💯'];

  Timer? _recordTimer;
  int _recordDuration = 0;
  late AnimationController _micAnimController;

  @override
  void initState() {
    super.initState();
    _initializeChatter();
    _markMessagesAsRead();
    _micAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _readStatusSubscription?.cancel();
    _recordTimer?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    _micAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChatter() async {
    try {
      final doc = await _firestore.collection('users').doc(_authUid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _isTeacher = data?['teacherId'] != null && data?['teacherId'].toString().isNotEmpty == true;
          _mySenderId = _authUid;
        });
      }
    } catch (e) { debugPrint("Init Error: $e"); }
  }

  void _markMessagesAsRead() {
    _readStatusSubscription = _firestore.collection('chats').doc(widget.chatRoomId).collection('messages')
        .where('senderId', isEqualTo: widget.recipientId)
        .where('status', isEqualTo: 'sent')
        .snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'status': 'read'});
        }
        batch.commit();
      }
    });
  }

  void _scrollToMessage(String? msgId) {
    if (msgId == null) return;
    final key = _messageKeys[msgId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      setState(() => _highlightedMessageId = msgId);
      Timer(const Duration(seconds: 2), () { if (mounted) setState(() => _highlightedMessageId = null); });
    }
  }

  // --- DATE GROUPING HELPER ---
  String _getGroupDate(Timestamp? timestamp) {
    if (timestamp == null) return "";
    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) return "Today";
    DateTime yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day && date.month == yesterday.month && date.year == yesterday.year) return "Yesterday";
    return DateFormat('MMMM dd, yyyy').format(date);
  }

  Widget _buildRichText(String text, bool isMe) {
    final List<InlineSpan> spans = [];
    final RegExp linkRegex = RegExp(r"(https?:\/\/[^\s]+)|(www\.[^\s]+)", caseSensitive: false);
    int lastIndex = 0;
    for (final Match match in linkRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start), style: TextStyle(color: isMe ? Colors.black87 : Colors.black)));
      }
      final String url = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        child: GestureDetector(
          onTap: () async {
            final Uri uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
            if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Text(url, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
        ),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) spans.add(TextSpan(text: text.substring(lastIndex), style: TextStyle(color: isMe ? Colors.black87 : Colors.black)));
    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontSize: 16)));
  }

  void _previewMedia(String url, String type) async {
    if (type == "image") {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              InteractiveViewer(child: Center(child: Image.network(url, fit: BoxFit.contain))),
              Positioned(top: 40, right: 20, child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)))),
            ],
          ),
        ),
      );
    } else {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- RECORDING ---
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        String? path;
        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          path = p.join(tempDir.path, 'rec_${DateTime.now().millisecondsSinceEpoch}.m4a');
        }
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000), path: path ?? '');
        setState(() { _isRecording = true; _recordDuration = 0; });
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) { if (mounted) setState(() => _recordDuration++); });
      }
    } catch (e) { debugPrint("Start Rec Error: $e"); }
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        final source = kIsWeb ? (await http.get(Uri.parse(path))).bodyBytes : File(path);
        final url = await _uploadToCloudinary(source, "video");
        if (url != null) _sendMediaMessage(url, "audio");
      }
    } catch (e) { debugPrint("Stop Rec Error: $e"); }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() { _isRecording = false; _recordDuration = 0; });
  }

  // --- SENDING ---
  Future<String?> _uploadToCloudinary(dynamic source, String type) async {
    setState(() => _isUploading = true);
    try {
      final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/$type/upload");
      var request = http.MultipartRequest("POST", url)..fields['upload_preset'] = uploadPreset..fields['folder'] = folderName;
      if (source is Uint8List) request.files.add(http.MultipartFile.fromBytes('file', source, filename: 'voice.m4a'));
      else if (source is File) request.files.add(await http.MultipartFile.fromPath('file', source.path));
      var response = await request.send();
      var data = await response.stream.bytesToString();
      return jsonDecode(data)['secure_url'];
    } catch (e) { return null; }
    finally { if (mounted) setState(() => _isUploading = false); }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isNotEmpty && profanityFilter.hasProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Respectful language required."), backgroundColor: Colors.red));
      return;
    }
    if (text.isEmpty && _pickedFile == null) return;
    final replyContext = _replyingToMessage;
    if (_pickedFile != null) {
      final source = kIsWeb ? _pickedFile!.bytes : File(_pickedFile!.path!);
      final url = await _uploadToCloudinary(source, "auto");
      if (url != null) await _saveToFirestore(text: text, mediaUrl: url, messageType: _getMediaType(_pickedFile!.extension), fileName: _pickedFile!.name, replyData: replyContext);
      setState(() => _pickedFile = null);
    } else {
      await _saveToFirestore(text: text, messageType: "text", replyData: replyContext);
    }
    _messageController.clear();
    setState(() => _replyingToMessage = null);
  }

  void _sendMediaMessage(String url, String type, {String? caption, String? fileName}) {
    _saveToFirestore(text: caption ?? "", mediaUrl: url, messageType: type, fileName: fileName, replyData: _replyingToMessage);
  }

  String _getMediaType(String? ext) {
    if (ext == null) return "file";
    final e = ext.toLowerCase();
    if (["jpg", "jpeg", "png"].contains(e)) return "image";
    if (["m4a", "mp3", "wav"].contains(e)) return "audio";
    return "file";
  }

  Future<void> _saveToFirestore({required String text, String? mediaUrl, String messageType = "text", String? fileName, Map<String, dynamic>? replyData}) async {
    if (_mySenderId == null) return;
    final msgData = {
      'senderId': _mySenderId, 'text': text, 'mediaUrl': mediaUrl, 'fileName': fileName,
      'messageType': messageType, 'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent', 'isEdited': false, 'reactions': {}, 'replyTo': replyData,
    };
    await _firestore.collection('chats').doc(widget.chatRoomId).collection('messages').add(msgData);
    await _firestore.collection('chats').doc(widget.chatRoomId).update({
      'lastMessage': text.isEmpty ? "📎 Media" : text, 'lastTimestamp': FieldValue.serverTimestamp()
    });
  }

  // --- REACTION LOGIC ---
  void _toggleReaction(String msgId, String emoji, Map<String, dynamic> currentReactions) async {
    String? existing = currentReactions[_authUid];
    await _firestore.collection('chats').doc(widget.chatRoomId).collection('messages').doc(msgId).update({
      'reactions.$_authUid': (existing == emoji) ? FieldValue.delete() : emoji
    });
  }

  void _showEmojiPickerDialog(String msgId, Map<String, dynamic> currentReactions) {
    final TextEditingController emojiCtrl = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Pick Emoji"), content: TextField(controller: emojiCtrl, autofocus: true, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30), decoration: const InputDecoration(hintText: "😀"), onChanged: (val) {
      if (val.isNotEmpty) { String emoji = val.characters.last; Navigator.pop(c); if (!_customEmojis.contains(emoji)) setState(() => _customEmojis.add(emoji)); _toggleReaction(msgId, emoji, currentReactions); }
    })));
  }

  void _openReactionMenu(String msgId, Map<String, dynamic> data) {
    Map<String, dynamic> reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    List<String> emojis = ['❤️', '👍', '😂', '😮', '😢', '🙏', ..._customEmojis];
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (c) => Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
      ...emojis.map((emoji) {
        bool isSel = reactions[_authUid] == emoji;
        return GestureDetector(onTap: () { Navigator.pop(c); _toggleReaction(msgId, emoji, reactions); }, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isSel ? Colors.blue.withOpacity(0.1) : Colors.transparent, shape: BoxShape.circle), child: Text(emoji, style: const TextStyle(fontSize: 28))));
      }),
      GestureDetector(onTap: () { Navigator.pop(c); _showEmojiPickerDialog(msgId, reactions); }, child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle), child: const Icon(Icons.add, size: 28, color: Colors.grey))),
    ])));
  }

  void _openOptionsMenu(String msgId, Map<String, dynamic> data, bool isMe) {
    showModalBottomSheet(context: context, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.reply), title: const Text("Reply"), onTap: () { Navigator.pop(c); setState(() => _replyingToMessage = {'id': msgId, 'text': data['text'].toString().isEmpty ? '📎 Media' : data['text'], 'senderId': data['senderId']}); _messageFocusNode.requestFocus(); }),
      if (isMe && data['messageType'] == 'text') ListTile(leading: const Icon(Icons.edit), title: const Text("Edit"), onTap: () { Navigator.pop(c); final ctrl = TextEditingController(text: data['text']); showDialog(context: context, builder: (c) => AlertDialog(title: const Text("Edit"), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")), TextButton(onPressed: () { _firestore.collection('chats').doc(widget.chatRoomId).collection('messages').doc(msgId).update({'text': ctrl.text, 'isEdited': true}); Navigator.pop(c); }, child: const Text("Save"))])); }),
      if (isMe) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text("Delete"), onTap: () { Navigator.pop(c); _firestore.collection('chats').doc(widget.chatRoomId).collection('messages').doc(msgId).delete(); }),
    ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F0E8),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(widget.recipientName, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white),
      body: Column(children: [
        if (_isUploading) const LinearProgressIndicator(color: Colors.orange, minHeight: 2),
        Expanded(child: _buildMessagesList()),
        _buildBottomArea(),
      ]),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('chats').doc(widget.chatRoomId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        return ListView.builder(
          controller: _scrollController, reverse: true, padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final prevData = (i + 1 < docs.length) ? docs[i + 1].data() as Map<String, dynamic> : null;

            String currentGroup = _getGroupDate(data['timestamp'] as Timestamp?);
            String prevGroup = _getGroupDate(prevData?['timestamp'] as Timestamp?);
            bool showDateHeader = currentGroup != prevGroup;

            bool isMe = data['senderId'] == _mySenderId;
            _messageKeys.putIfAbsent(doc.id, () => GlobalKey());

            return Column(
              children: [
                if (showDateHeader) _buildDateHeader(currentGroup),
                _buildMessageBubble(doc.id, data, isMe),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateHeader(String date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)]),
      child: Text(date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
    );
  }

  Widget _buildMessageBubble(String docId, Map<String, dynamic> data, bool isMe) {
    String type = data['messageType'] ?? "text";
    bool isHighlighted = _highlightedMessageId == docId;
    Map<String, dynamic>? replyTo = data['replyTo'] != null ? Map<String, dynamic>.from(data['replyTo']) : null;
    Map<String, dynamic> reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final bubbleColor = isMe ? const Color(0xFFE7FFDB) : Colors.white;
    final replyBarColor = isMe ? const Color(0xFF075E54) : const Color(0xFF34B7F1);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: _messageKeys[docId],
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) IconButton(icon: const Icon(Icons.add_reaction_outlined, size: 18, color: Colors.grey), onPressed: () => _openReactionMenu(docId, data)),
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(color: isHighlighted ? Colors.orange.withOpacity(0.3) : bubbleColor, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)]),
                    padding: const EdgeInsets.all(6),
                    child: IntrinsicWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [GestureDetector(onTap: () => _openOptionsMenu(docId, data, isMe), child: const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black26))]),
                          if (replyTo != null) GestureDetector(onTap: () => _scrollToMessage(replyTo['id']), child: Container(margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: IntrinsicHeight(child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 4, decoration: BoxDecoration(color: replyBarColor, borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)))), const SizedBox(width: 8), Flexible(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(replyTo['senderId'] == _authUid ? "You" : widget.recipientName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: replyBarColor)), Text(replyTo['text'] ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54))])))])))),
                          if (type == "image" && data['mediaUrl'] != null) GestureDetector(onTap: () => _previewMedia(data['mediaUrl'], "image"), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(data['mediaUrl'], width: 220, fit: BoxFit.cover))),
                          if (type == "audio") _AudioPlayerWidget(url: data['mediaUrl'], isMe: isMe),
                          if (type == "file" && data['mediaUrl'] != null) InkWell(onTap: () => _previewMedia(data['mediaUrl'], "file"), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.insert_drive_file, color: Colors.blue), const SizedBox(width: 8), Flexible(child: Text(data['fileName'] ?? "File", style: const TextStyle(fontSize: 14, decoration: TextDecoration.underline)))]))),
                          if (data['text'] != null && data['text'].isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4), child: _buildRichText(data['text'], isMe)),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [if (data['isEdited'] ?? false) const Text("edited ", style: TextStyle(fontSize: 10, color: Colors.grey)), Text(ChatUtils.formatTimestamp(data['timestamp'] as Timestamp?), style: const TextStyle(fontSize: 10, color: Colors.black45)), if (isMe) ...[const SizedBox(width: 4), Icon(Icons.done_all, size: 14, color: data['status'] == 'read' ? Colors.blue : Colors.grey)]]),
                        ],
                      ),
                    ),
                  ),
                  if (reactions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Wrap(spacing: 4, children: reactions.entries.map((entry) => GestureDetector(onTap: () { if (entry.key == _authUid) _toggleReaction(docId, entry.value, reactions); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 1)]), child: Text(entry.value, style: const TextStyle(fontSize: 12))))).toList())),
                ],
              ),
            ),
            if (isMe) IconButton(icon: const Icon(Icons.add_reaction_outlined, size: 18, color: Colors.grey), onPressed: () => _openReactionMenu(docId, data)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomArea() {
    return Container(decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]), child: Column(mainAxisSize: MainAxisSize.min, children: [if (_replyingToMessage != null) _buildReplyDockedPreview(), if (_pickedFile != null) _buildFilePreview(), _buildInputArea()]));
  }

  Widget _buildReplyDockedPreview() {
    return Container(padding: const EdgeInsets.all(10), color: Colors.grey.shade50, child: Container(decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)), child: IntrinsicHeight(child: Row(children: [Container(width: 4, decoration: const BoxDecoration(color: Color(0xFF075E54), borderRadius: BorderRadius.horizontal(left: Radius.circular(8)))), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(_replyingToMessage!['senderId'] == _authUid ? "You" : widget.recipientName, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF075E54))), Text(_replyingToMessage!['text'], maxLines: 1, overflow: TextOverflow.ellipsis)])), IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _replyingToMessage = null))]))));
  }

  Widget _buildFilePreview() {
    return ListTile(leading: const Icon(Icons.insert_drive_file, color: Colors.orange), title: Text(_pickedFile!.name, maxLines: 1), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _pickedFile = null)));
  }

  Widget _buildInputArea() {
    return Padding(padding: const EdgeInsets.all(8), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (!_isRecording) ...[
        IconButton(icon: const Icon(Icons.camera_alt, color: Colors.grey), onPressed: () async { final XFile? img = await _picker.pickImage(source: ImageSource.camera); if (img != null) { final url = await _uploadToCloudinary(kIsWeb ? await img.readAsBytes() : File(img.path), "image"); if (url != null) _sendMediaMessage(url, "image", fileName: img.name); } }),
        IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: () async { final res = await FilePicker.platform.pickFiles(); if (res != null) setState(() => _pickedFile = res.files.first); }),
      ] else IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _cancelRecording),
      Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(25)), child: _isRecording ? Row(children: [FadeTransition(opacity: _micAnimController, child: const Icon(Icons.mic, color: Colors.red, size: 20)), const SizedBox(width: 10), Text("${(_recordDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordDuration % 60).toString().padLeft(2, '0')}", style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), const Text("Recording...", style: TextStyle(color: Colors.grey))]) : TextField(controller: _messageController, focusNode: _messageFocusNode, maxLines: 5, minLines: 1, decoration: const InputDecoration(hintText: "Type a message...", border: InputBorder.none), onChanged: (v) => setState(() {})))),
      const SizedBox(width: 8),
      CircleAvatar(backgroundColor: const Color(0xFF075E54), radius: 24, child: IconButton(icon: Icon(_isRecording ? Icons.send : (_messageController.text.isEmpty && _pickedFile == null ? Icons.mic : Icons.send), color: Colors.white), onPressed: () => _isRecording ? _stopAndSendRecording() : (_messageController.text.isEmpty && _pickedFile == null ? _startRecording() : _sendMessage()))),
    ]));
  }
}

class _AudioPlayerWidget extends StatefulWidget {
  final String? url;
  final bool isMe;
  const _AudioPlayerWidget({required this.url, required this.isMe});
  @override State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  bool _isReady = false;
  @override void initState() { super.initState(); _init(); }
  Future<void> _init() async { if (widget.url != null) { try { await _player.setUrl(widget.url!); if (mounted) setState(() => _isReady = true); } catch (e) { debugPrint("Audio Error: $e"); } } }
  @override void dispose() { _player.dispose(); super.dispose(); }
  String _fmt(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  @override
  Widget build(BuildContext context) {
    return Container(width: 240, padding: const EdgeInsets.symmetric(vertical: 4), child: !_isReady ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))) : StreamBuilder<PlayerState>(stream: _player.playerStateStream, builder: (context, snapshot) {
      final playing = snapshot.data?.playing ?? false;
      if (snapshot.data?.processingState == ProcessingState.completed) { _player.seek(Duration.zero); _player.pause(); }
      return Row(children: [
        IconButton(icon: Icon(playing ? Icons.pause : Icons.play_arrow), color: widget.isMe ? Colors.black54 : Colors.green, onPressed: () => playing ? _player.pause() : _player.play()),
        Expanded(child: StreamBuilder<Duration>(stream: _player.positionStream, builder: (context, snap) {
          final pos = snap.data ?? Duration.zero;
          final dur = _player.duration ?? Duration.zero;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SliderTheme(data: SliderTheme.of(context).copyWith(thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), trackHeight: 2, overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)), child: Slider(activeColor: widget.isMe ? Colors.black54 : Colors.green, inactiveColor: Colors.black12, value: pos.inMilliseconds.toDouble().clamp(0.0, dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0), max: dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0, onChanged: (v) => _player.seek(Duration(milliseconds: v.toInt())))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_fmt(pos), style: const TextStyle(fontSize: 10)), Text(_fmt(dur), style: const TextStyle(fontSize: 10))]))
          ]);
        })),
      ]);
    }));
  }

}
