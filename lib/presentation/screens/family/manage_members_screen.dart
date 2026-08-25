import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../config/theme_config.dart';
import '../../../services/family_service.dart';

class ManageMembersScreen extends StatefulWidget {
  final String familyId;
  const ManageMembersScreen({super.key, required this.familyId});

  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  final FamilyService _familyService = FamilyService();
  bool _isLoading = false;

  void _confirmRemoveMember(String memberId, String memberName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Member?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove $memberName from this family circle?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(this.context);
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await _familyService.removeMemberFromFamily(widget.familyId, memberId);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('$memberName removed successfully.'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Manage Members',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('families').doc(widget.familyId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(
                    child: Text('Family not found', style: TextStyle(color: Colors.white)),
                  );
                }

                final familyData = snapshot.data!.data() as Map<String, dynamic>;
                final List<dynamic> memberIds = familyData['memberIds'] ?? [];
                final String createdBy = familyData['createdBy'] ?? '';

                if (memberIds.isEmpty) {
                  return const Center(
                    child: Text('No members found.', style: TextStyle(color: Colors.white)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: memberIds.length,
                  separatorBuilder: (context, index) => const Divider(color: Colors.white24, height: 1),
                  itemBuilder: (context, index) {
                    final memberId = memberIds[index] as String;
                    final isAdmin = memberId == createdBy;
                    final isSelf = memberId == _familyService.currentUserId;

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(memberId).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return const ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.white12),
                            title: Text('Loading...', style: TextStyle(color: Colors.white70)),
                          );
                        }

                        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                        final name = userData?['displayName'] ?? userData?['name'] ?? 'Unknown';
                        final photoUrl = userData?['photoUrl'];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                            child: photoUrl == null
                                ? Text(
                                    name[0].toUpperCase(),
                                    style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            isAdmin ? 'Admin' : 'Member',
                            style: TextStyle(
                              color: isAdmin ? AppTheme.primaryColor : Colors.white54,
                            ),
                          ),
                          trailing: (isAdmin || isSelf) 
                              ? null 
                              : IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.errorColor),
                                  onPressed: () => _confirmRemoveMember(memberId, name),
                                ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
