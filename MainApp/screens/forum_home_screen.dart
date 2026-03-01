import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'forum_detail_screen.dart';

class ForumHomeScreen extends StatefulWidget {
  const ForumHomeScreen({super.key});

  @override
  // MUST BE PUBLIC: No underscore, so the GlobalKey from the home screen can access it.
  ForumHomeScreenState createState() => ForumHomeScreenState();
}

// MUST BE PUBLIC: No underscore.
class ForumHomeScreenState extends State<ForumHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// --- VERIFIED ---
  /// Displays a clean, public-only profile dialog.
  /// This method is self-contained and safe to call.
  void _showPublicProfileDialog(Map<String, dynamic> authorData) {
    // Gracefully handle potentially null or missing data.
    final String name = authorData['authorName'] ?? "Anonymous";
    final String? profilePicUrl = authorData['authorProfilePic'];
    final String bio = authorData['authorBio'] ?? "No bio provided.";

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Prevents the dialog from taking full screen height.
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.indigo.shade50,
                backgroundImage: profilePicUrl != null ? NetworkImage(profilePicUrl) : null,
                child: profilePicUrl == null ? Icon(Icons.person, size: 50, color: Colors.indigo.shade700) : null,
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                bio,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search Bar UI - Unchanged and Verified
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search questions...",
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = "");
                  },
                )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          // --- Main Content ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('forum_posts').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                final allPosts = snapshot.data?.docs ?? [];
                final filteredPosts = allPosts.where((post) {
                  final data = post.data() as Map<String, dynamic>;
                  final title = data['title']?.toString().toLowerCase() ?? '';
                  return title.contains(_searchQuery);
                }).toList();

                if (filteredPosts.isEmpty) {
                  return Center(child: Text(_searchQuery.isNotEmpty ? "No questions found for '$_searchQuery'." : "No questions yet. Be the first!"));
                }

                return ListView.builder(
                  itemCount: filteredPosts.length,
                  itemBuilder: (context, index) {
                    final post = filteredPosts[index];
                    final data = post.data() as Map<String, dynamic>;
                    final String? profilePicUrl = data['authorProfilePic'];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        /// --- VERIFIED ---
                        /// Tappable avatar that opens the public profile dialog.
                        leading: GestureDetector(
                          onTap: () => _showPublicProfileDialog(data),
                          child: CircleAvatar(
                            backgroundColor: Colors.blue.shade50,
                            backgroundImage: profilePicUrl != null ? NetworkImage(profilePicUrl) : null,
                            child: profilePicUrl == null ? const Icon(Icons.person, size: 20, color: Colors.blue) : null,
                          ),
                        ),
                        title: Text(data['title'] ?? "No Title", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("By ${data['authorName'] ?? 'Anonymous'}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.comment, size: 18, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text("${data['answersCount'] ?? 0}"),
                          ],
                        ),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForumDetailScreen(postId: post.id, postData: data))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue.shade800,
        onPressed: showAskQuestionDialog,
        child: const Icon(Icons.add_comment, color: Colors.white),
      ),
    );
  }

  /// --- VERIFIED ---
  /// This method now correctly fetches and saves the user's public profile
  /// info when they post a question.
  void showAskQuestionDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows the sheet to resize when the keyboard appears.
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ask a Question", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(controller: titleController, decoration: const InputDecoration(labelText: "Topic Title", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: descController, maxLines: 3, decoration: const InputDecoration(labelText: "Details (Optional)", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800, foregroundColor: Colors.white),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) return;

                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return; // Safety check for logged-out user.

                  try {
                    // Fetch the user's profile data to embed in the post.
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                    final userData = userDoc.data();

                    await FirebaseFirestore.instance.collection('forum_posts').add({
                      'title': titleController.text.trim(),
                      'description': descController.text.trim(),
                      'authorId': user.uid,
                      'authorName': userData?['name'] ?? "Anonymous",
                      'authorProfilePic': userData?['profilePic'], // Embeds pic URL
                      'authorBio': userData?['bio'], // Embeds bio
                      'timestamp': FieldValue.serverTimestamp(),
                      'answersCount': 0,
                    });

                    if (mounted) Navigator.pop(context); // Close sheet on success.
                  } catch (e) {
                    // If something fails, show an error and don't close the sheet.
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to post: $e")));
                  }
                },
                child: const Text("Post to Community"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
