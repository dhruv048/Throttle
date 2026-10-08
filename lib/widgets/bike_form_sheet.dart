import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../repositories/bike_repository.dart';
import '../theme.dart';
import 'photo_picker.dart';
import 'ui.dart';

/// Add a bike, or edit one when [bike] is given. Returns true if saved.
Future<bool> showBikeFormSheet(
  BuildContext context, {
  BikeRecord? bike,
  bool defaultPrimary = false,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BikeForm(bike: bike, defaultPrimary: defaultPrimary),
  );
  return saved == true;
}

class _BikeForm extends StatefulWidget {
  const _BikeForm({this.bike, required this.defaultPrimary});

  final BikeRecord? bike;
  final bool defaultPrimary;

  @override
  State<_BikeForm> createState() => _BikeFormState();
}

class _BikeFormState extends State<_BikeForm> {
  late final _name = TextEditingController(text: widget.bike?.name ?? '');
  late final _year =
      TextEditingController(text: widget.bike?.year?.toString() ?? '');
  late final _make = TextEditingController(text: widget.bike?.make ?? '');
  late final _model = TextEditingController(text: widget.bike?.model ?? '');
  late bool _primary = widget.bike?.isPrimary ?? widget.defaultPrimary;
  PickedPhoto? _photo;
  bool _removePhoto = false;
  bool _saving = false;

  bool get _editing => widget.bike != null;

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    _make.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final photo = await pickPhoto(context, title: 'Bike photo');
    if (photo != null) {
      setState(() {
        _photo = photo;
        _removePhoto = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    String? optional(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    setState(() => _saving = true);
    final repo = BikeRepository();
    final messenger = ScaffoldMessenger.of(context);
    try {
      var bike = _editing
          ? await repo.update(
              widget.bike!.id,
              name: name,
              year: int.tryParse(_year.text.trim()),
              make: optional(_make),
              model: optional(_model),
              isPrimary: _primary,
            )
          : await repo.create(
              userId: uid,
              name: name,
              year: int.tryParse(_year.text.trim()),
              make: optional(_make),
              model: optional(_model),
              isPrimary: _primary,
            );
      try {
        if (_photo != null) {
          bike = await repo.setPhoto(bike, _photo!.file);
        } else if (_removePhoto && bike.photoUrl != null) {
          bike = await repo.removePhoto(bike);
        }
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(
              content: Text('Bike saved, but the photo didn\'t upload: $e')),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger
          .showSnackBar(SnackBar(content: Text('Couldn\'t save bike: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingUrl = _removePhoto ? null : widget.bike?.photoUrl;
    final hasPhoto = _photo != null || existingUrl != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LabelMono('Garage'),
            const SizedBox(height: 4),
            Text(_editing ? 'Edit motorcycle' : 'Add motorcycle',
                style: displayStyle(size: 24)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _saving ? null : _pickPhoto,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    color: AppColors.panel,
                    child: _photo != null
                        ? Image.memory(Uint8List.fromList(_photo!.bytes),
                            fit: BoxFit.cover)
                        : existingUrl != null
                            ? Image.network(existingUrl, fit: BoxFit.cover)
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_a_photo_outlined,
                                      color: AppColors.mutedForeground),
                                  SizedBox(height: 6),
                                  Text('Add a photo of your bike',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.mutedForeground)),
                                ],
                              ),
                  ),
                ),
              ),
            ),
            if (hasPhoto)
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : _pickPhoto,
                    child: const Text('Change photo'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _photo = null;
                              _removePhoto = true;
                            }),
                    child: const Text('Remove',
                        style: TextStyle(color: AppColors.mutedForeground)),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: !_editing,
              decoration: const InputDecoration(
                labelText: 'Motorcycle name *',
                hintText: 'Ducati Scrambler',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Year', hintText: '2023'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _make,
                    decoration: const InputDecoration(
                        labelText: 'Make', hintText: 'Ducati'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                  labelText: 'Model', hintText: 'Icon Dark'),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Primary bike'),
              value: _primary,
              onChanged: (v) => setState(() => _primary = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('SAVE BIKE',
                        style: displayStyle(size: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
