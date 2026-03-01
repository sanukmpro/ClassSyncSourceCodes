import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ForumDetailReviewScreen extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> postData;

  const ForumDetailReviewScreen({
    super.key,
    required this.postId,
    required this.postData,
  });

  @override
  Widget build(BuildContext context) {
    // --- DYNAMIC AUTHOR DETECTION (Synced with Cleanup Screen) ---
    final String authorName = postData['userName'] ??
        postData['authorName'] ??
        postData['senderName'] ??
        postData['displayName'] ??
        postData['name'] ??
        "Unknown User";

    final String dept = postData['department'] ?? 'N/A';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Post Moderation"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          // 1. THE MAIN POST HEADER (Modernized)
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(0.3),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        dept,
                        style: TextStyle(color: Colors.blue.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.history, size: 14, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  postData['question'] ?? postData['title'] ?? "No Title",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.blue.shade100,
                      child: Text(authorName[0].toUpperCase(), style: const TextStyle(fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      authorName,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ],
                ),
                const Divider(height: 30),
                Text(
                  postData['description'] ?? postData['text'] ?? "No content.",
                  style: const TextStyle(
                    fontSize: 15,
                    height:1.5,
                    color: Colors.black87, // Standard readable dark grey/black
                  ),
                ),
              ],
            ),
          ),

          // 2. ANSWERS SECTION HEADER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            width: double.infinity,
            color: Colors.grey.shade50,
            child: const Text(
              "MODERATE REPLIES",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
            ),
          ),

          // 3. LIST OF REPLIES (Real-time Stream)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('forum_posts')
                  .doc(postId)
                  .collection('answers')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final answers = snapshot.data!.docs;

                if (answers.isEmpty) {
                  return const Center(child: Text("No replies found."));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: answers.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final aDoc = answers[index];
                    final aData = aDoc.data() as Map<String, dynamic>;
                    final String rAuthor = aData['authorName'] ?? aData['userName'] ?? "User";

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text(aData['text'] ?? "Empty content"),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text("By: $rAuthor", style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _deleteReply(context, aDoc.reference),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- ATOMIC REPLY DELETION ---
  Future<void> _deleteReply(BuildContext context, DocumentReference ref) async {
    final bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Reply?"),
        content: const Text("This will permanently remove this answer from the forum. Continue?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ) ??
        false;

    if (confirm) {
      try {
        await ref.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reply removed")));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to delete: $e")));
        }
      }
    }
  }
}