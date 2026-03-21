import 'package:flutter/material.dart';
import '../../../config/routes.dart';
import '../../../services/family_service.dart';

class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key});
  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _codeController = TextEditingController();
  final _familyService = FamilyService();
  bool _isLoading = false;

  Future<void> _joinFamily() async {
    if (_codeController.text.length < 6) return;
    setState(() => _isLoading = true);
    try {
      // Actually join the family using the invite code
      final success = await _familyService.joinFamily(_codeController.text.trim());
      if (!mounted) return;
      
      if (success) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid invite code. Please check and try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Family')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Invite Code',
                hintText: 'Enter 6-digit code',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _codeController.text.length >= 6 && !_isLoading
                    ? _joinFamily
                    : null,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Join Family'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
