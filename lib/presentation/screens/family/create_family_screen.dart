import 'package:flutter/material.dart';
import '../../../config/routes.dart';
import '../../../services/family_service.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key});
  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _familyService = FamilyService();
  bool _isLoading = false;

  Future<void> _createFamily() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // Actually create the family in Firebase
      await _familyService.createFamily(_nameController.text.trim());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating family: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Family')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Family Name',
                  hintText: 'e.g., The Sharmas',
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Enter a name' : null,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createFamily,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Create Family'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
