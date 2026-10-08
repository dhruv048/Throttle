import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../repositories/profile_repository.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/photo_picker.dart';
import '../../widgets/ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.auth,
    this.profiles,
    this.initialUsername,
    this.initialDisplayName,
    this.onCompleted,
  });

  final AuthService auth;
  final ProfileRepository? profiles;
  final String? initialUsername;
  final String? initialDisplayName;
  final ValueChanged<Profile>? onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final TextEditingController _username;
  late final TextEditingController _bike;
  late final TextEditingController _city;
  late final TextEditingController _year;
  PickedPhoto? _bikePhoto;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.initialUsername ?? '');
    _bike = TextEditingController();
    _city = TextEditingController();
    _year = TextEditingController();
  }

  @override
  void dispose() {
    _username.dispose();
    _bike.dispose();
    _city.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _username.text.trim().toLowerCase();
    final bike = _bike.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      setState(
          () => _error = 'Use lowercase letters, numbers, and underscores');
      return;
    }
    if (bike.isEmpty) {
      setState(() => _error = 'Add your first motorcycle');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final profiles = widget.profiles ?? ProfileRepository();
      final uid = widget.auth.currentUser!.id;
      final available =
          await profiles.isUsernameAvailable(username, excludingUserId: uid);
      if (!available) {
        setState(() {
          _error = 'That username is taken';
          _busy = false;
        });
        return;
      }

      final year = int.tryParse(_year.text.trim());
      final profile = await widget.auth.completeOnboarding(
        username: username,
        bikeName: bike,
        bikeYear: year,
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        displayName: widget.initialDisplayName,
        bikePhoto: _bikePhoto?.file,
      );
      widget.onCompleted?.call(profile);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              children: [
                LabelMono('Welcome', color: AppColors.primary),
                const SizedBox(height: 8),
                Text('Set up your garage', style: displayStyle(size: 34)),
                const SizedBox(height: 8),
                Text(
                  'Pick a username and add the bike you ride most.',
                  style:
                      TextStyle(color: AppColors.mutedForeground, height: 1.4),
                ),
                const SizedBox(height: 28),
                _field(
                  label: 'Username',
                  controller: _username,
                  hint: 'valley_rider',
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LowerCaseTextFormatter(),
                  ],
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'City (optional)',
                  controller: _city,
                  hint: 'Kathmandu',
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'First motorcycle',
                  controller: _bike,
                  hint: 'Yamaha MT-15',
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'Year (optional)',
                  controller: _year,
                  hint: '2023',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _busy
                      ? null
                      : () async {
                          final photo =
                              await pickPhoto(context, title: 'Bike photo');
                          if (photo != null) setState(() => _bikePhoto = photo);
                        },
                  child: AppCard(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _bikePhoto != null
                          ? Image.memory(Uint8List.fromList(_bikePhoto!.bytes),
                              fit: BoxFit.cover)
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    color: AppColors.mutedForeground),
                                SizedBox(height: 6),
                                Text('Bike photo (optional)',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.mutedForeground)),
                              ],
                            ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'LET’S RIDE',
                            style: displayStyle(
                              size: 20,
                              color: AppColors.primaryForeground,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => widget.auth.signOut(),
                    child: Text(
                      'Sign out / switch account',
                      style: monoStyle(
                          size: 11,
                          tracking: 0,
                          color: AppColors.mutedForeground),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelMono(label),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              hintStyle: TextStyle(
                  color: AppColors.mutedForeground.withValues(alpha: 0.7)),
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class LowerCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toLowerCase(),
      selection: newValue.selection,
    );
  }
}
