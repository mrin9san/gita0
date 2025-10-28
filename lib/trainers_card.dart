// trainers_card.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'trainer_list_page.dart';
import 'trainer_roster_page.dart'; // 👈 NEW
import 'glass_ui.dart';

class TrainersCard extends StatelessWidget {
  final String fireBaseId;
  final supa.SupabaseClient client;

  /// supply gyms with real GymID only:
  /// e.g. userGyms.where((g) => (g['GymID'] is String && g['GymID'].isNotEmpty))
  final List<Map<String, dynamic>> gymsWithId;

  const TrainersCard({
    super.key,
    required this.fireBaseId,
    required this.client,
    required this.gymsWithId,
  });

  void _navigateToTrainerList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainerListPage(fireBaseId: fireBaseId),
      ),
    );
  }

  void _navigateToRoster(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainerRosterPage(
          fireBaseId: fireBaseId,
          client: client,
          gymsWithId: gymsWithId,
        ),
      ),
    );
  }

  void _showAddTrainerForm(BuildContext context) async {
    final formKey = GlobalKey<FormState>();

    final nameC = TextEditingController();
    final ageC = TextEditingController();
    final qualC = TextEditingController();
    final heightC = TextEditingController();
    final weightC = TextEditingController();
    final bmiC = TextEditingController();
    final joinDateC = TextEditingController();
    final dobC = TextEditingController();

    File? avatarFile;
    String? avatarPublicUrl;
    bool uploadingAvatar = false;

    final selected = <String, bool>{
      for (final g in gymsWithId) (g['GymID'] as String): false,
    };

    void recalcBmi() {
      final w = int.tryParse(weightC.text.trim());
      final hCm = int.tryParse(heightC.text.trim());
      if (w != null && hCm != null && hCm > 0) {
        final h = hCm / 100.0;
        final bmi = (w / (h * h)).round();
        bmiC.text = bmi.toString();
      } else {
        bmiC.text = '';
      }
    }

    Future<void> pickDate(
      TextEditingController controller, {
      DateTime? initial,
    }) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: initial ?? now,
        firstDate: DateTime(now.year - 80, 1, 1),
        lastDate: DateTime(now.year + 10, 12, 31),
      );
      if (d != null) {
        controller.text = d.toIso8601String().split('T').first;
      }
    }

    String? _req(String? v) => (v?.trim().isEmpty ?? true) ? 'Required' : null;

    Future<void> _pickImage(
      ImageSource source,
      void Function(void Function()) setLocal,
    ) async {
      try {
        final picker = ImagePicker();
        final XFile? picked = await picker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1600,
        );
        if (picked == null) return;
        setLocal(() {
          avatarFile = File(picked.path);
          avatarPublicUrl = null;
        });
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
        }
      }
    }

    void _showAvatarSheet(void Function(void Function()) setLocal) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1A1C23),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.white),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, setLocal);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text(
                  'Take a Photo',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera, setLocal);
                },
              ),
              if (avatarFile != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Remove photo',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    setLocal(() {
                      avatarFile = null;
                      avatarPublicUrl = null;
                    });
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }

    Future<void> _ensureAvatarUploaded(
      void Function(void Function()) setLocal,
    ) async {
      if (avatarFile == null || avatarPublicUrl != null) return;
      try {
        setLocal(() => uploadingAvatar = true);

        final bytes = await avatarFile!.readAsBytes();
        final storage = client.storage.from('avatars');

        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeId = fireBaseId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final ext = avatarFile!.path.split('.').last.toLowerCase();
        final path = 'trainers/$safeId/$ts.${ext.isEmpty ? "jpg" : ext}';

        await storage.uploadBinary(
          path,
          bytes,
          fileOptions: const supa.FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );

        final publicUrl = storage.getPublicUrl(path);
        setLocal(() {
          avatarPublicUrl = publicUrl;
        });
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Avatar upload failed: $e')));
        }
      } finally {
        setLocal(() => uploadingAvatar = false);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF111214),
          title: const Text(
            'Add Trainer',
            style: TextStyle(color: Colors.white),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: const Color(0xFF2A2F3A),
                      backgroundImage: (avatarFile != null)
                          ? FileImage(avatarFile!)
                          : null,
                      child: (avatarFile == null)
                          ? const Icon(
                              Icons.sports_gymnastics,
                              size: 42,
                              color: Colors.white70,
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: uploadingAvatar
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        uploadingAvatar ? 'Uploading...' : 'Add / Change Photo',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2A2F3A)),
                        backgroundColor: const Color(0x201A1C23),
                      ),
                      onPressed: uploadingAvatar
                          ? null
                          : () => _showAvatarSheet(setLocal),
                    ),
                    const SizedBox(height: 14),
                    glassyField(
                      controller: nameC,
                      label: 'Name',
                      validator: _req,
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: ageC,
                      label: 'Age',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    glassyField(controller: qualC, label: 'Qualification'),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: heightC,
                      label: 'Height (cm)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: weightC,
                      label: 'Weight (kg)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: bmiC,
                      label: 'BMI (auto)',
                      readOnly: true,
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: joinDateC,
                      label: 'JoiningDate (YYYY-MM-DD)',
                      readOnly: true,
                      onTap: () => pickDate(joinDateC),
                      suffixIcon: const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: dobC,
                      label: 'DOB (YYYY-MM-DD)',
                      readOnly: true,
                      onTap: () => pickDate(dobC),
                      suffixIcon: const Icon(
                        Icons.cake_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Assign to Gyms',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (gymsWithId.isEmpty)
                      const Text(
                        'No synced gyms found. Please add a gym first.',
                        style: TextStyle(color: Colors.white70),
                      )
                    else
                      Column(
                        children: gymsWithId.map((g) {
                          final id = g['GymID'] as String;
                          final label =
                              '${g['name'] ?? 'Gym'} • ${g['location'] ?? ''}';
                          return CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.white,
                            value: selected[id] ?? false,
                            onChanged: (v) => setLocal(() {
                              selected[id] = v ?? false;
                            }),
                            title: Text(
                              label,
                              style: const TextStyle(color: Colors.white),
                            ),
                            checkboxShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2F3A),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await _ensureAvatarUploaded(setLocal);

                try {
                  int? _i(TextEditingController c) => c.text.trim().isEmpty
                      ? null
                      : int.tryParse(c.text.trim());

                  final payload = {
                    'GymID': null,
                    'AuthUserID': fireBaseId,
                    'Name': nameC.text.trim(),
                    'Age': _i(ageC),
                    'Qualification': qualC.text.trim().isEmpty
                        ? null
                        : qualC.text.trim(),
                    'Height': _i(heightC),
                    'Weight': _i(weightC),
                    'BMI': _i(bmiC),
                    'JoiningDate': joinDateC.text.trim().isEmpty
                        ? null
                        : joinDateC.text.trim(),
                    'DOB': dobC.text.trim().isNotEmpty
                        ? dobC.text.trim()
                        : null,
                    if (avatarPublicUrl != null && avatarPublicUrl!.isNotEmpty)
                      'PhotoURL': avatarPublicUrl,
                  };

                  final inserted = await client
                      .from('Trainer')
                      .insert(payload)
                      .select('TrainerID')
                      .single();

                  final trainerId = inserted['TrainerID'] as String?;
                  if (trainerId != null && trainerId.isNotEmpty) {
                    final gymIds = selected.entries
                        .where((e) => e.value)
                        .map((e) => e.key)
                        .toList();
                    if (gymIds.isNotEmpty) {
                      await client.from('TrainerGyms').insert([
                        for (final gId in gymIds)
                          {'TrainerID': trainerId, 'GymID': gId},
                      ]);
                    }
                  }

                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Trainer added${(inserted['TrainerID'] != null) ? ' (${inserted['TrainerID']})' : ''}',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Add trainer failed: $e');
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed to add trainer: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Geometry identical to GymCard for consistent sizing/positioning
    const double anchorIconSize = 36;
    const double anchorRightPadding = 142;
    const double arcRadius = 80;
    const double actionCircleSize = 36;
    const double actionIconSize = 18;
    const double actionLabelGap = 7;

    final actions = <ActionSpec>[
      ActionSpec(
        icon: Icons.person_add_alt_1,
        label: 'Add Trainer',
        bg: const Color(0xFF66BB6A),
        onTap: () => _showAddTrainerForm(context),
      ),
      ActionSpec(
        icon: Icons.groups_2_outlined,
        label: 'See Trainers',
        bg: Colors.purpleAccent,
        onTap: () => _navigateToTrainerList(context),
      ),
      ActionSpec(
        icon: Icons.calendar_month, // 👈 NEW
        label: 'Roster',
        bg: const Color(0xFF4F9CF9),
        onTap: () => _navigateToRoster(context),
      ),
    ];

    // Place 3 buttons around the anchor (you can tweak angles, height unaffected)
    final anglesDeg = [330.0, 30.0, 0.0];

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            final anchor = Offset(
              w - anchorRightPadding - anchorIconSize / 2,
              h / 2,
            );

            final content = Positioned.fill(
              child: Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: 120.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trainers',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Manage your trainer roster and assignments.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );

            final pinnedTrainersLabel = const Positioned(
              left: 12,
              top: 12,
              child: Row(
                children: [
                  Icon(
                    Icons.sports_gymnastics,
                    color: Color(0xFF4F9CF9),
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Trainers',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            );

            final anchorWidget = Positioned(
              left: anchor.dx - anchorIconSize / 2,
              top: anchor.dy - anchorIconSize / 2,
              child: Container(
                width: anchorIconSize,
                height: anchorIconSize,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2A2F3A),
                ),
                child: const Icon(
                  Icons.sports_gymnastics,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            );

            final radial = <Widget>[];
            for (var i = 0; i < actions.length; i++) {
              final spec = actions[i];
              final theta = anglesDeg[i] * math.pi / 180.0;
              final cx = anchor.dx + arcRadius * math.cos(theta);
              final cy = anchor.dy + arcRadius * math.sin(theta);

              radial.add(
                Positioned(
                  left: cx - actionCircleSize / 2,
                  top: cy - actionCircleSize / 2,
                  child: ActionButton(
                    icon: spec.icon,
                    label: spec.label,
                    bg: spec.bg,
                    circleSize: actionCircleSize,
                    iconSize: actionIconSize,
                    labelGap: actionLabelGap,
                    onTap: spec.onTap,
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [content, pinnedTrainersLabel, anchorWidget, ...radial],
            );
          },
        ),
      ),
    );
  }
}

class ActionSpec {
  final IconData icon;
  final String label;
  final Color bg;
  final VoidCallback onTap;
  ActionSpec({
    required this.icon,
    required this.label,
    required this.bg,
    required this.onTap,
  });
}
