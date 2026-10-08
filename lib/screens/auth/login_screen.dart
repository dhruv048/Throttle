import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LabelMono('Throttle', color: AppColors.primary),
                  const SizedBox(height: 8),
                  Text('Ride. Record. Share.', style: displayStyle(size: 40)),
                  const SizedBox(height: 12),
                  Text(
                    'Sign in to sync rides, follow riders, and keep your garage online.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const Spacer(),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _busy ? null : _signIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.foreground,
                        foregroundColor: AppColors.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              'CONTINUE WITH GOOGLE',
                              style: displayStyle(
                                  size: 18, color: AppColors.background),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By continuing you agree to share your Google email for account creation.',
                    style: monoStyle(size: 10, tracking: 0, uppercase: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
