import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_data.dart';
import 'assets/pdf_preview.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedDept = "All";
  String _selectedSem = "All";
  final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Honor Leaderboard"),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 1. GLOBAL ACHIEVEMENT HEADER
          _buildGlobalAchievementHeader(),

          // 2. FILTERED LEADERBOARD LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getFilteredStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) return const SizedBox();

                final docs = snapshot.data!.docs.where((d) {
                  var data = d.data() as Map<String, dynamic>;
                  return data['role'] == 'student';
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text("No rankings found."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    return _buildRankCard(
                      rank: index + 1,
                      name: data['name'] ?? "Anonymous",
                      score: _parseScore(data['honorScore']),
                      dept: data['department'] ?? "N/A",
                      profilePic: data['profilePic'],
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

  Widget _buildGlobalAchievementHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('honorScore', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic>? userAchievement;
        int globalRank = -1;

        if (snapshot.hasData && currentUserId != null) {
          final allDocs = snapshot.data!.docs.where((d) {
            var data = d.data() as Map<String, dynamic>;
            return data['role'] == 'student';
          }).toList();

          final index = allDocs.indexWhere((doc) => doc.id == currentUserId);
          if (index != -1) {
            globalRank = index + 1;
            userAchievement = allDocs[index].data() as Map<String, dynamic>;
          }
        }

        bool canClaim = userAchievement != null &&
            globalRank <= 3 &&
            _parseScore(userAchievement['honorScore']) >= 50;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 25, left: 20, right: 20, top: 10),
          decoration: const BoxDecoration(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Column(
            children: [
              const Icon(Icons.emoji_events, size: 50, color: Colors.amber),
              const SizedBox(height: 10),
              const Text("Top Contributors",
                  style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              if (canClaim)
                ElevatedButton.icon(
                  icon: const Icon(Icons.card_membership_rounded),
                  label: Text("Claim Rank #$globalRank Certificate"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CertificatePreviewPage(
                        name: userAchievement!['name'],
                        rank: globalRank,
                        dept: userAchievement['department'],
                        // FIX: Added the semester parameter required by the constructor
                        semester: userAchievement['semester'] ?? "N/A",
                        score: _parseScore(userAchievement['honorScore']),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
                  child: const Text("certificates unlock at reaching score 50 & above", style: TextStyle(color: Colors.white70)),
                ),

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: _buildFilterDropdown("Dept", _selectedDept, ["All", ...AppData.departments], (val) => setState(() => _selectedDept = val!))),
                  const SizedBox(width: 10),
                  Expanded(child: _buildFilterDropdown("Sem", _selectedSem, ["All", ...AppData.semesters], (val) => setState(() => _selectedSem = val!))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot> _getFilteredStream() {
    Query query = FirebaseFirestore.instance.collection('users');
    if (_selectedDept != "All") query = query.where('department', isEqualTo: _selectedDept);
    if (_selectedSem != "All") query = query.where('semester', isEqualTo: _selectedSem);
    return query.orderBy('honorScore', descending: true).snapshots();
  }

  Widget _buildRankCard({required int rank, required String name, required int score, required String dept, String? profilePic}) {
    Color? cardColor;
    if (rank == 1) cardColor = Colors.amber.shade50;
    else if (rank == 2) cardColor = Colors.blueGrey.shade50;
    else if (rank == 3) cardColor = Colors.orange.shade50;

    return Card(
      elevation: rank <= 3 ? 4 : 1,
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: SizedBox(
          width: 65,
          child: Row(
            children: [
              Text("#$rank", style: TextStyle(fontWeight: FontWeight.bold, color: _getRankColor(rank))),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                child: profilePic == null ? const Icon(Icons.person) : null,
              ),
            ],
          ),
        ),
        title: Text(name, style: TextStyle(fontWeight: rank <= 3 ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text("Honor: $score • $dept"),
      ),
    );
  }

  Widget _buildFilterDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: Colors.blueAccent,
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          onChanged: onChanged,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        ),
      ),
    );
  }

  int _parseScore(dynamic score) {
    if (score is int) return score;
    if (score is String) return int.tryParse(score) ?? 0;
    return 0;
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return Colors.amber.shade700;
    if (rank == 2) return Colors.blueGrey.shade600;
    if (rank == 3) return Colors.brown.shade400;
    return Colors.blue.shade300;
  }
}