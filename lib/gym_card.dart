import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'dashboard.dart';
import 'user_view_page.dart';
import 'glass_ui.dart';

/// Minimal package option for the membership dropdown (top-level).
class _PackageOption {
  final String name;
  const _PackageOption(this.name);
}

class GymCard extends StatelessWidget {
  final Map<String, dynamic> gym;
  final int index;
  final List<Map<String, dynamic>> allGyms;
  final String fireBaseId;
  final Box gymsBox;
  final supa.SupabaseClient client;

  /// Called after we replace the entire gyms list (create/edit/delete).
  final ValueChanged<List<Map<String, dynamic>>> onReplaceGyms;

  /// Let parent optionally trigger a re-sync after changes to keep parity.
  final Future<void> Function() onAfterChange;

  const GymCard({
    super.key,
    required this.gym,
    required this.index,
    required this.allGyms,
    required this.fireBaseId,
    required this.gymsBox,
    required this.client,
    required this.onReplaceGyms,
    required this.onAfterChange,
  });

  // ==================== Helpers (moved from HomePage) ====================

  Future<void> _persist(List<Map<String, dynamic>> gyms) async {
    await gymsBox.put(fireBaseId, gyms);
    onReplaceGyms(List<Map<String, dynamic>>.from(gyms));
  }

  Future<void> _deleteGym(BuildContext context) async {
    final g = gym;
    final gymName = (g['name'] ?? '').toString();

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: const Text(
          'Confirm delete',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$gymName"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final id = g['GymID'] as String?;
    try {
      if (id != null && id.isNotEmpty) {
        await client.from('Gyms').delete().eq('GymID', id);
      } else {
        await client
            .from('Gyms')
            .delete()
            .eq('AuthUserID', fireBaseId)
            .eq('GymName', g['name'] ?? '')
            .eq('Location', g['location'] ?? '');
      }
    } catch (e) {
      // ignore remote failure but continue locally
      debugPrint('⚠️ Remote delete failed (continuing with local): $e');
    }

    final newList = List<Map<String, dynamic>>.from(allGyms);
    newList.removeAt(index);
    await _persist(newList);
    await onAfterChange();
  }

  Future<void> _showGymForm(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final nameC = TextEditingController(text: gym['name'] ?? '');
    final locC = TextEditingController(text: gym['location'] ?? '');
    final capC = TextEditingController(text: (gym['capacity'] ?? 0).toString());

    Future<void> _save() async {
      if (!formKey.currentState!.validate()) return;

      final payload = <String, dynamic>{
        'name': nameC.text.trim(),
        'location': locC.text.trim(),
        'capacity': int.tryParse(capC.text.trim()) ?? 0,
      };

      try {
        final String? id = gym['GymID'] as String?;

        if (id != null && id.isNotEmpty) {
          // UPDATE existing
          await client
              .from('Gyms')
              .update({
                'GymName': payload['name'],
                'Location': payload['location'],
                'Capacity': payload['capacity'],
              })
              .eq('GymID', id);
          payload['GymID'] = id;
        } else {
          // INSERT and backfill ID
          final resp = await client
              .from('Gyms')
              .insert({
                'GymName': payload['name'],
                'Location': payload['location'],
                'Capacity': payload['capacity'],
                'AuthUserID': fireBaseId,
              })
              .select('GymID')
              .single();
          payload['GymID'] = resp['GymID'];
        }

        final newList = List<Map<String, dynamic>>.from(allGyms);
        newList[index] = payload;
        await _persist(newList);
        if (context.mounted) Navigator.of(context).pop();
        await onAfterChange();
      } catch (e) {
        debugPrint("❌ Supabase insert/update failed: $e");
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Failed to save gym: $e")));
        }
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: const Text('Edit Gym', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                glassyField(
                  controller: nameC,
                  label: 'Gym Name',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter gym name' : null,
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: locC,
                  label: 'Location',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter location' : null,
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: capC,
                  label: 'Capacity',
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter capacity' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
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
            onPressed: _save,
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<String?> _ensureGymId(Map<String, dynamic> g) async {
    final existing = g['GymID'];
    if (existing is String && existing.isNotEmpty) return existing;

    final name = (g['name'] ?? '').toString();
    final loc = (g['location'] ?? '').toString();
    if (name.isEmpty) return null;

    final List<dynamic> rows = await client
        .from('Gyms')
        .select('GymID')
        .eq('AuthUserID', fireBaseId)
        .eq('GymName', name)
        .eq('Location', loc)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isNotEmpty) {
      final id = rows.first['GymID'] as String?;
      if (id != null && id.isNotEmpty) {
        g['GymID'] = id;

        // also persist the updated ID locally
        final newList = List<Map<String, dynamic>>.from(allGyms);
        newList[index] = Map<String, dynamic>.from(g);
        await _persist(newList);

        return id;
      }
    }
    return null;
  }

  // ==================== MEMBERSHIP: dynamic from Packages ====================

  // Fetch all packages for the logged-in owner (fireBaseId / AuthUserID).
  Future<List<_PackageOption>> _fetchOwnerPackages() async {
    try {
      final rows = await client
          .from('Packages')
          .select('Name')
          .eq('AuthUserID', fireBaseId)
          // not forcing IsActive; show whatever exists
          .order('IsDefault', ascending: false)
          .order('created_at', ascending: true);

      final list = (rows as List)
          .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      return list
          .map((r) => _PackageOption((r['Name'] ?? '').toString()))
          .where((p) => p.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const <_PackageOption>[];
    }
  }

  // ======= Add Customer dialog (moved here) =======
  void _showAddCustomerForm(BuildContext context) async {
    final formKey = GlobalKey<FormState>();

    final nameC = TextEditingController();
    final ageC = TextEditingController();
    final addressC = TextEditingController();
    final weightC = TextEditingController();
    final bmiC = TextEditingController();
    final gymHistoryC = TextEditingController();
    final targetC = TextEditingController();
    final healthHistoryC = TextEditingController();
    final supplementHistoryC = TextEditingController();
    final heightC = TextEditingController();
    final membershipC = TextEditingController();
    final exercizeTypeC = TextEditingController();
    final sexC = TextEditingController();
    final emailC = TextEditingController();
    final joinDateC = TextEditingController();
    final phoneC = TextEditingController();

    File? avatarFile;
    String? avatarPublicUrl;
    bool uploadingAvatar = false;

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

    DateTime? pickedJoin;
    Future<void> pickJoinDate() async {
      final now = DateTime.now();
      final first = DateTime(now.year - 5, 1, 1);
      final last = DateTime(now.year + 5, 12, 31);
      final d = await showDatePicker(
        context: context,
        initialDate: pickedJoin ?? now,
        firstDate: first,
        lastDate: last,
      );
      if (d != null) {
        pickedJoin = d;
        joinDateC.text = d.toIso8601String().split('T').first;
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
        final path = 'users/$safeId/$ts.${ext.isEmpty ? 'jpg' : ext}';

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
            'Add Customer',
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
                              Icons.person,
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
                    glassyField(
                      controller: addressC,
                      label: 'Address',
                      maxLines: 3,
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
                      controller: heightC,
                      label: 'Height (cm)',
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
                      controller: gymHistoryC,
                      label: 'GymHistory',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: targetC,
                      label: 'Target',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: healthHistoryC,
                      label: 'HealthHistory',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 10),

                    // === MEMBERSHIP: dynamic Packages for this owner (fireBaseId) ===
                    FutureBuilder<List<_PackageOption>>(
                      future: _fetchOwnerPackages(),
                      builder: (context, snap) {
                        final isLoading =
                            snap.connectionState == ConnectionState.waiting;
                        final pkgs = snap.data ?? const <_PackageOption>[];
                        final names = pkgs.map((e) => e.name).toList();

                        if (isLoading) {
                          return DropdownButtonFormField<String>(
                            value: null,
                            items: const [],
                            onChanged: null,
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF111214),
                            iconEnabledColor: Colors.white70,
                            decoration: const InputDecoration(
                              labelText: 'Membership (loading...)',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF2A2F3A),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF4F9CF9),
                                ),
                              ),
                            ),
                          );
                        }

                        if (snap.hasError) {
                          // If fetch fails, allow free text entry.
                          return glassyField(
                            controller: membershipC,
                            label: 'Membership (failed to load — type custom)',
                          );
                        }

                        if (names.isEmpty) {
                          // Fallback: free text so the form still works
                          return glassyField(
                            controller: membershipC,
                            label:
                                'Membership (no packages found — type custom)',
                          );
                        }

                        return DropdownButtonFormField<String>(
                          value: names.contains(membershipC.text.trim())
                              ? membershipC.text.trim()
                              : null,
                          items: names
                              .map(
                                (n) => DropdownMenuItem<String>(
                                  value: n,
                                  child: Text(
                                    n,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setLocal(() => membershipC.text = v ?? ''),
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: const Color(0xFF111214),
                          iconEnabledColor: Colors.white70,
                          decoration: const InputDecoration(
                            labelText: 'Membership',
                            labelStyle: TextStyle(color: Colors.white70),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 10),
                    glassDropdown<String>(
                      label: 'ExercizeType',
                      value: null,
                      items: const [
                        'Strength',
                        'Cardio',
                        'CrossFit',
                        'Yoga',
                        'Mixed',
                      ],
                      onChanged: (v) =>
                          setLocal(() => exercizeTypeC.text = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    glassDropdown<String>(
                      label: 'Sex',
                      value: null,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (v) => setLocal(() => sexC.text = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: emailC,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: joinDateC,
                      label: 'JoinDate (YYYY-MM-DD)',
                      readOnly: true,
                      onTap: pickJoinDate,
                      suffixIcon: const Icon(
                        Icons.calendar_today,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    glassyField(
                      controller: phoneC,
                      label: 'Phone',
                      keyboardType: TextInputType.phone,
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

                final gymId = await _ensureGymId(gym);
                if (gymId == null || gymId.isEmpty) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Couldn't resolve GymID. Try re-saving the gym.",
                        ),
                      ),
                    );
                  }
                  return;
                }

                await _ensureAvatarUploaded(setLocal);

                try {
                  int? _toInt(TextEditingController c) => c.text.trim().isEmpty
                      ? null
                      : int.tryParse(c.text.trim());

                  final payload = {
                    'GymID': gymId,
                    'AuthUserID': fireBaseId,
                    'Name': nameC.text.trim(),
                    'Age': _toInt(ageC),
                    'Address': addressC.text.trim().isEmpty
                        ? null
                        : addressC.text.trim(),
                    'Weight': _toInt(weightC),
                    'Height': _toInt(heightC),
                    'BMI': _toInt(bmiC),
                    'GymHistory': gymHistoryC.text.trim().isEmpty
                        ? null
                        : gymHistoryC.text.trim(),
                    'Target': targetC.text.trim().isEmpty
                        ? null
                        : targetC.text.trim(),
                    'HealthHistory': healthHistoryC.text.trim().isEmpty
                        ? null
                        : healthHistoryC.text.trim(),
                    'SupplementHistory': supplementHistoryC.text.trim().isEmpty
                        ? null
                        : supplementHistoryC.text.trim(),
                    'Membership': membershipC.text.trim().isEmpty
                        ? null
                        : membershipC.text.trim(),
                    'ExercizeType': exercizeTypeC.text.trim().isEmpty
                        ? null
                        : exercizeTypeC.text.trim(),
                    'Sex': sexC.text.trim().isEmpty ? null : sexC.text.trim(),
                    'Email': emailC.text.trim().isEmpty
                        ? null
                        : emailC.text.trim(),
                    'JoinDate': joinDateC.text.trim().isEmpty
                        ? null
                        : joinDateC.text.trim(),
                    'Phone': phoneC.text.trim().isEmpty
                        ? null
                        : phoneC.text.trim(),
                    if (avatarPublicUrl != null && avatarPublicUrl!.isNotEmpty)
                      'PhotoURL': avatarPublicUrl,
                  };

                  final inserted = await client
                      .from('Users')
                      .insert(payload)
                      .select('UserID')
                      .single();

                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Customer added (UserID: ${inserted['UserID'] ?? 'new'})',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Add customer failed: $e');
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed to add customer: $e')),
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

  // ========================== UI ==========================

  @override
  Widget build(BuildContext context) {
    // Geometry identical to your original
    const double anchorIconSize = 36;
    const double anchorRightPadding = 142;
    const double arcRadius = 80;
    const double actionCircleSize = 36;
    const double actionIconSize = 18;
    const double actionLabelGap = 7;
    const List<double> arcAnglesDeg = [280, 325, 360, 35, 80];

    final actions = <ActionSpec>[
      ActionSpec(
        icon: Icons.delete,
        label: 'Delete Gym',
        bg: const Color(0xFFE53935),
        onTap: () => _deleteGym(context),
      ),
      ActionSpec(
        icon: Icons.edit,
        label: 'Edit Gym',
        bg: const Color(0xFFFFCA28),
        onTap: () => _showGymForm(context),
      ),
      ActionSpec(
        icon: Icons.person_add_alt_1,
        label: 'Add User',
        bg: const Color(0xFF66BB6A),
        onTap: () => _showAddCustomerForm(context),
      ),
      ActionSpec(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        bg: Colors.white,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardPage(
                gymName: gym['name'] ?? '',
                gymLocation: gym['location'] ?? '',
                gymCapacity: gym['capacity'] ?? 0,
                gymId: gym['GymID'] as String?,
              ),
            ),
          );
        },
      ),
      ActionSpec(
        icon: Icons.group_outlined,
        label: 'Users',
        bg: Colors.purpleAccent,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserViewPage(
                gymName: gym['name'] ?? '',
                gymLocation: gym['location'] ?? '',
                gymCapacity: gym['capacity'] ?? 0,
                gymId: gym['GymID'] as String?,
              ),
            ),
          );
        },
      ),
    ];

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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 120.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gym['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Location:",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          Text(
                            gym['location'] ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Capacity: ${gym['capacity'] ?? 0}",
                            style: const TextStyle(
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

            final pinnedGymLabel = Positioned(
              left: 12,
              top: 12,
              child: Row(
                children: const [
                  Icon(
                    Icons.fitness_center,
                    color: Color(0xFF4F9CF9),
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Gym",
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
                  Icons.fitness_center,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            );

            final radial = <Widget>[];
            for (var i = 0; i < actions.length; i++) {
              final spec = actions[i];
              final theta = arcAnglesDeg[i] * math.pi / 180.0;

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
              children: [content, pinnedGymLabel, anchorWidget, ...radial],
            );
          },
        ),
      ),
    );
  }
}

/// Use this when tapping "Add Another Gym" from HomePage.
/// Shows the **same** add gym dialog as before (look/feel preserved).
Future<void> showAddGymDialog({
  required BuildContext context,
  required supa.SupabaseClient client,
  required String fireBaseId,
  required List<Map<String, dynamic>> allGyms,
  required Box gymsBox,
  required ValueChanged<List<Map<String, dynamic>>> onReplaceGyms,
  required Future<void> Function() onAfterChange,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameC = TextEditingController();
  final locC = TextEditingController();
  final capC = TextEditingController();

  Future<void> _persist(List<Map<String, dynamic>> gyms) async {
    await gymsBox.put(fireBaseId, gyms);
    onReplaceGyms(List<Map<String, dynamic>>.from(gyms));
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;

    final payload = <String, dynamic>{
      'name': nameC.text.trim(),
      'location': locC.text.trim(),
      'capacity': int.tryParse(capC.text.trim()) ?? 0,
    };
    Future<List<_PackageOption>> _fetchOwnerPackages() async {
      try {
        // (A) Pull a few rows without filter to confirm data exists
        final anyRows = await client
            .from('Packages')
            .select('AuthUserID,Name')
            .limit(5);
        debugPrint('Packages(any, first 5): $anyRows');

        // (B) Pull rows for this owner id
        final rows = await client
            .from('Packages')
            .select('AuthUserID,Name,IsActive,IsDefault,created_at')
            .eq('AuthUserID', fireBaseId)
            .order('IsDefault', ascending: false)
            .order('created_at', ascending: true);

        debugPrint('Packages(for $fireBaseId): $rows');

        final list = (rows as List)
            .map<Map<String, dynamic>>(
              (r) => Map<String, dynamic>.from(r as Map),
            )
            .toList();

        return list
            .map((r) => _PackageOption((r['Name'] ?? '').toString()))
            .where((p) => p.name.isNotEmpty)
            .toList();
      } catch (e) {
        debugPrint('❌ fetchOwnerPackages error: $e');
        return const <_PackageOption>[];
      }
    }

    try {
      final resp = await client
          .from('Gyms')
          .insert({
            'GymName': payload['name'],
            'Location': payload['location'],
            'Capacity': payload['capacity'],
            'AuthUserID': fireBaseId,
          })
          .select('GymID')
          .single();

      payload['GymID'] = resp['GymID'];

      final newList = List<Map<String, dynamic>>.from(allGyms);
      newList.add(payload);
      await _persist(newList);

      if (context.mounted) Navigator.of(context).pop();
      await onAfterChange();
    } catch (e) {
      debugPrint("❌ Supabase insert failed: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to save gym: $e")));
      }
    }
  }

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF111214),
      title: const Text('Add Gym', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              glassyField(
                controller: nameC,
                label: 'Gym Name',
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter gym name' : null,
              ),
              const SizedBox(height: 10),
              glassyField(
                controller: locC,
                label: 'Location',
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter location' : null,
              ),
              const SizedBox(height: 10),
              glassyField(
                controller: capC,
                label: 'Capacity',
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Enter capacity' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2A2F3A),
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: const Text('Add'),
        ),
      ],
    ),
  );
}
