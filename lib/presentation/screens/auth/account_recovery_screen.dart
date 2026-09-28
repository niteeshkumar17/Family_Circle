import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../config/routes.dart';
import '../../../config/theme_config.dart';
import '../../../services/account_service.dart';
import '../../blocs/auth/auth_bloc.dart';

/// Shown when someone signs in to an account that is waiting out its
/// deletion grace period.
class AccountRecoveryScreen extends StatefulWidget {
  final DateTime deleteOn;

  const AccountRecoveryScreen({super.key, required this.deleteOn});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  bool _isLoading = false;

  Future<void> _recover() async {
    setState(() => _isLoading = true);
    try {
      await AccountService().cancelDeletion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome back! Your account has been recovered.')),
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.splash);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _signOut() {
    context.read<AuthBloc>().add(AuthLogoutRequested());
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final date = AccountService.formatDate(widget.deleteOn);
    final expired = !widget.deleteOn.isAfter(DateTime.now());
    final daysLeft = widget.deleteOn.difference(DateTime.now()).inDays + 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.restore_rounded,
                  size: 80,
                  color: AppTheme.errorColor,
                ),
              ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(height: 40),
              Text(
                expired ? 'Account deleted' : 'Recover your account?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
              const SizedBox(height: 12),
              Text(
                expired
                    ? 'The ${AccountService.recoveryDays}-day recovery period ended on $date, '
                        'so this account and its data are being permanently deleted.'
                    : 'This account is scheduled for permanent deletion on $date '
                        '($daysLeft ${daysLeft == 1 ? 'day' : 'days'} left).\n\n'
                        'Recover it now to keep your nests, places and history.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
              const Spacer(),
              if (!expired) SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _recover,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.restore_rounded),
                  label: const Text('Recover My Account'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ).animate().fadeIn(duration: 400.ms, delay: 300.ms).slideY(begin: 0.1),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _isLoading ? null : _signOut,
                child: Text(
                  expired ? 'Sign out' : 'No, keep it deleted',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
