import 'dart:io';
import 'dart:math' as math; // radial layout
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import 'profile_page.dart';
import 'dashboard.dart';
import 'user_view_page.dart';

class HomePage extends StatefulWidget {
  final String fireBaseId; // stable key from Fire table

  const HomePage({super.key, required this.fireBaseId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _gymNameController = TextEditingController();
  final TextEditingController _gymLocationController = TextEditingController();
  final TextEditingController _gymCapacityController = TextEditingController();

  late Box gymsBox;
  List<Map<String, dynamic>> userGyms = [];

  supa.User? _user;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    gymsBox = Hive.box('gymsBox');
    _user = supa.Supabase.instance.client.auth.currentUser;
    _loadGyms(); // fast local load
    _syncGyms(); // then reconcile with Supabase
  }

  // ------------------ LOCAL (Hive) ------------------

  void _loadGyms() {
    final key = widget.fireBaseId;
    final List stored = gymsBox.get(key, defaultValue: []);
    userGyms = stored
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {});
  }

  Future<void> _saveGymsToHive(List<Map<String, dynamic>> gyms) async {
    await gymsBox.put(widget.fireBaseId, gyms);
  }

  // ------------------ REMOTE (Supabase) ------------------

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _fetchRemoteGyms() async {
    final rows = await _client
        .from('Gyms')
        .select('GymID,GymName,Location,Capacity,FireBaseID,created_at')
        .eq('FireBaseID', widget.fireBaseId)
        .order('created_at', ascending: true);

    return (rows as List)
        .map((r) => {
              'GymID': r['GymID'] as String?,
              'name': r['GymName'] as String? ?? '',
              'location': r['Location'] as String? ?? '',
              'capacity': (r['Capacity'] is int)
                  ? r['Capacity'] as int
                  : int.tryParse('${r['Capacity']}') ?? 0,
            })
        .toList();
  }

  Future<void> _logout() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
    try {
      final google = GoogleSignIn();
      await google.disconnect();
      await google.signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _pushUnsyncedLocalToRemote(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) async {
    String _key(Map g) =>
        '${(g['name'] ?? '').toString().trim().toLowerCase()}|${(g['location'] ?? '').toString().trim().toLowerCase()}';

    final remoteByKey = <String, Map<String, dynamic>>{
      for (final r in remote) _key(r): r,
    };

    for (final g in local) {
      final hasId = (g['GymID'] is String) && (g['GymID'] as String).isNotEmpty;
      final k = _key(g);
      if (hasId) continue;

      final match = remoteByKey[k];
      if (match != null && (match['GymID'] as String?)?.isNotEmpty == true) {
        g['GymID'] = match['GymID'];
        continue;
      }

      try {
        final inserted = await _client
            .from('Gyms')
            .insert({
              'GymName': g['name'] ?? '',
              'Location': g['location'] ?? '',
              'Capacity': g['capacity'] ?? 0,
              'FireBaseID': widget.fireBaseId,
            })
            .select('GymID')
            .single();

        final newId = inserted['GymID'] as String?;
        if (newId != null && newId.isNotEmpty) {
          g['GymID'] = newId;
          final canonical = {
            'GymID': newId,
            'name': g['name'],
            'location': g['location'],
            'capacity': g['capacity'] ?? 0,
          };
          remote.add(canonical);
          remoteByKey[k] = canonical;
        }
      } catch (e) {
        debugPrint('⚠️ Could not push unsynced gym "${g['name']}": $e');
      }
    }
  }

  Future<void> _syncGyms() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final local = List<Map<String, dynamic>>.from(userGyms);
      var remote = await _fetchRemoteGyms();

      await _pushUnsyncedLocalToRemote(local, remote);

      remote = await _fetchRemoteGyms();

      userGyms = _dedupByIdOrKey(remote);
      await _saveGymsToHive(userGyms);
      setState(() {});
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  List<Map<String, dynamic>> _dedupByIdOrKey(List<Map<String, dynamic>> list) {
    final seenIds = <String>{};
    final seenKeys = <String>{};
    String key(Map g) =>
        '${(g['name'] ?? '').toString().trim().toLowerCase()}|${(g['location'] ?? '').toString().trim().toLowerCase()}';

    final out = <Map<String, dynamic>>[];
    for (final g in list) {
      final id = g['GymID'] as String?;
      if (id != null && id.isNotEmpty) {
        if (seenIds.add(id)) out.add(Map<String, dynamic>.from(g));
        continue;
      }
      final k = key(g);
      if (seenKeys.add(k)) out.add(Map<String, dynamic>.from(g));
    }
    return out;
  }

  // ------------------ NAVIGATION HELPERS ------------------

  void _navigateToDashboard(Map<String, dynamic> gym) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(
          gymName: gym['name'] ?? '',
          gymLocation: gym['location'] ?? '',
          gymCapacity: gym['capacity'] ?? 0,
          gymId: gym['GymID'] as String?,
        ),
      ),
    );
  }

  void _navigateToUserView(Map<String, dynamic> gym) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserViewPage(
          gymName: gym['name'] ?? '',
          gymLocation: gym['location'] ?? '',
          gymCapacity: gym['capacity'] ?? 0,
          gymId: gym['GymID'] as String?,
        ),
      ),
    );
  }

  Future<String?> _ensureGymId(Map<String, dynamic> gym) async {
    final dynamic existing = gym['GymID'];
    if (existing is String && existing.isNotEmpty) return existing;

    final name = (gym['name'] ?? '').toString();
    final loc = (gym['location'] ?? '').toString();
    if (name.isEmpty) return null;

    final List<dynamic> rows = await _client
        .from('Gyms')
        .select('GymID')
        .eq('FireBaseID', widget.fireBaseId)
        .eq('GymName', name)
        .eq('Location', loc)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isNotEmpty) {
      final id = rows.first['GymID'] as String?;
      if (id != null && id.isNotEmpty) {
        gym['GymID'] = id;
        await _saveGymsToHive(userGyms);
        return id;
      }
    }
    return null;
  }

  // ------------------ CREATE / UPDATE / DELETE Gyms ------------------

  // FIXED: cleanly separate CREATE vs EDIT (no extra insert on edit)
  Future<void> _saveGym({int? index}) async {
    if (!_formKey.currentState!.validate()) return;

    final gymData = <String, dynamic>{
      'name': _gymNameController.text.trim(),
      'location': _gymLocationController.text.trim(),
      'capacity': int.tryParse(_gymCapacityController.text.trim()) ?? 0,
    };

    try {
      if (index == null) {
        // ---------- CREATE ----------
        final response = await _client
            .from('Gyms')
            .insert({
              'GymName': gymData['name'],
              'Location': gymData['location'],
              'Capacity': gymData['capacity'],
              'FireBaseID': widget.fireBaseId,
            })
            .select('GymID')
            .single();

        if (response != null) {
          gymData['GymID'] = response['GymID'];
        }
        userGyms.add(gymData);
      } else {
        // ---------- EDIT ----------
        final existing = userGyms[index];
        final String? id = existing['GymID'] as String?;

        if (id != null && id.isNotEmpty) {
          // Remote record exists -> UPDATE only
          await _client.from('Gyms').update({
            'GymName': gymData['name'],
            'Location': gymData['location'],
            'Capacity': gymData['capacity'],
          }).eq('GymID', id);

          gymData['GymID'] = id; // retain id locally
          userGyms[index] = gymData;
        } else {
          // Local-only (unsynced) -> INSERT once and backfill GymID
          final response = await _client
              .from('Gyms')
              .insert({
                'GymName': gymData['name'],
                'Location': gymData['location'],
                'Capacity': gymData['capacity'],
                'FireBaseID': widget.fireBaseId,
              })
              .select('GymID')
              .single();

          if (response != null) {
            gymData['GymID'] = response['GymID'];
          }
          userGyms[index] = gymData;
        }
      }

      await _saveGymsToHive(userGyms);
      _gymNameController.clear();
      _gymLocationController.clear();
      _gymCapacityController.clear();

      if (mounted) Navigator.of(context).pop();

      // Re-sync so other devices see changes and local cache is fresh
      await _syncGyms();
    } catch (e) {
      debugPrint("❌ Supabase insert/update failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save gym: $e")),
        );
      }
    }
  }

  Future<void> _deleteGym(int index) async {
    final g = userGyms[index];
    final id = g['GymID'] as String?;
    try {
      if (id != null && id.isNotEmpty) {
        await _client.from('Gyms').delete().eq('GymID', id);
      } else {
        await _client
            .from('Gyms')
            .delete()
            .eq('FireBaseID', widget.fireBaseId)
            .eq('GymName', g['name'] ?? '')
            .eq('Location', g['location'] ?? '');
      }
    } catch (e) {
      debugPrint('⚠️ Remote delete failed (continuing with local): $e');
    }
    userGyms.removeAt(index);
    await _saveGymsToHive(userGyms);
    setState(() {});
  }

  // ------------------ UI: forms & dialogs ------------------

  void _showGymForm({int? index}) {
    if (index != null) {
      _gymNameController.text = userGyms[index]['name'] ?? '';
      _gymLocationController.text = userGyms[index]['location'] ?? '';
      _gymCapacityController.text =
          (userGyms[index]['capacity'] ?? 0).toString();
    } else {
      _gymNameController.clear();
      _gymLocationController.clear();
      _gymCapacityController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: Text(index == null ? 'Add Gym' : 'Edit Gym',
            style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _glassyField(
                  controller: _gymNameController,
                  label: 'Gym Name',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter gym name' : null,
                ),
                const SizedBox(height: 10),
                _glassyField(
                  controller: _gymLocationController,
                  label: 'Location',
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter location' : null,
                ),
                const SizedBox(height: 10),
                _glassyField(
                  controller: _gymCapacityController,
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
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2F3A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => _saveGym(index: index),
            child: Text(index == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  // ======= Add Customer dialog (with avatar picker & upload to 'avatars') =======
  void _showAddCustomerForm(Map<String, dynamic> gym) async {
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
        ImageSource source, void Function(void Function()) setLocal) async {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not pick image: $e')),
          );
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
                title: const Text('Choose from Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, setLocal);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.white),
                title: const Text('Take a Photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera, setLocal);
                },
              ),
              if (avatarFile != null)
                ListTile(
                  leading:
                      const Icon(Icons.delete_outline, color: Colors.white),
                  title: const Text('Remove photo',
                      style: TextStyle(color: Colors.white)),
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
        void Function(void Function()) setLocal) async {
      if (avatarFile == null || avatarPublicUrl != null) return;
      try {
        setLocal(() => uploadingAvatar = true);

        final bytes = await avatarFile!.readAsBytes();
        final storage = _client.storage.from('avatars');

        final ts = DateTime.now().millisecondsSinceEpoch;
        final safeId =
            widget.fireBaseId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
        final ext = avatarFile!.path.split('.').last.toLowerCase();
        final path = 'users/$safeId/$ts.${ext.isEmpty ? 'jpg' : ext}';

        await storage.uploadBinary(
          path,
          bytes,
          fileOptions:
              const supa.FileOptions(cacheControl: '3600', upsert: true),
        );

        final publicUrl = storage.getPublicUrl(path);
        setLocal(() {
          avatarPublicUrl = publicUrl;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Avatar upload failed: $e')),
          );
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
          title:
              const Text('Add Customer', style: TextStyle(color: Colors.white)),
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
                      backgroundImage:
                          (avatarFile != null) ? FileImage(avatarFile!) : null,
                      child: (avatarFile == null)
                          ? const Icon(Icons.person,
                              size: 42, color: Colors.white70)
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
                    _glassyField(
                        controller: nameC, label: 'Name', validator: _req),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: ageC,
                      label: 'Age',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                        controller: addressC, label: 'Address', maxLines: 3),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: weightC,
                      label: 'Weight (kg)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: heightC,
                      label: 'Height (cm)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: bmiC,
                      label: 'BMI (auto)',
                      readOnly: true,
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                        controller: gymHistoryC,
                        label: 'GymHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),
                    _glassyField(
                        controller: targetC, label: 'Target', maxLines: 3),
                    const SizedBox(height: 10),
                    _glassyField(
                        controller: healthHistoryC,
                        label: 'HealthHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),
                    _glassyField(
                        controller: supplementHistoryC,
                        label: 'SupplementHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),
                    _glassDropdown<String>(
                      label: 'Membership',
                      value: null,
                      items: const ['Standard', 'Premium', 'VIP'],
                      onChanged: (v) =>
                          setLocal(() => membershipC.text = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    _glassDropdown<String>(
                      label: 'ExercizeType',
                      value: null,
                      items: const [
                        'Strength',
                        'Cardio',
                        'CrossFit',
                        'Yoga',
                        'Mixed'
                      ],
                      onChanged: (v) =>
                          setLocal(() => exercizeTypeC.text = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    _glassDropdown<String>(
                      label: 'Sex',
                      value: null,
                      items: const ['Male', 'Female', 'Other'],
                      onChanged: (v) => setLocal(() => sexC.text = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: emailC,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
                      controller: joinDateC,
                      label: 'JoinDate (YYYY-MM-DD)',
                      readOnly: true,
                      onTap: pickJoinDate,
                      suffixIcon: const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(height: 10),
                    _glassyField(
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
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70)),
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
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Couldn't resolve GymID. Try re-saving the gym.")));
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
                    'FireBaseID': widget.fireBaseId,
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
                    'Email':
                        emailC.text.trim().isEmpty ? null : emailC.text.trim(),
                    'JoinDate': joinDateC.text.trim().isEmpty
                        ? null
                        : joinDateC.text.trim(),
                    'Phone':
                        phoneC.text.trim().isEmpty ? null : phoneC.text.trim(),
                    if (avatarPublicUrl != null && avatarPublicUrl!.isNotEmpty)
                      'PhotoURL': avatarPublicUrl,
                  };

                  final inserted = await _client
                      .from('Users')
                      .insert(payload)
                      .select('UserID')
                      .single();

                  if (mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Customer added (UserID: ${inserted['UserID'] ?? 'new'})'),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Add customer failed: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
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
  // ======= END Add Customer dialog =======

  // ------------------ UI ------------------

  @override
  Widget build(BuildContext context) {
    final photoUrl = _avatarUrl(_user);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const Text("Gym Manager"),
        actions: [
          IconButton(
            tooltip: 'Sync',
            icon: _syncing
                ? const SizedBox(
                    height: 22, width: 22, child: CircularProgressIndicator())
                : const Icon(Icons.refresh),
            onPressed: _syncing ? null : _syncGyms,
          ),
          if (photoUrl != null && photoUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()));
                },
                child: CircleAvatar(backgroundImage: NetworkImage(photoUrl)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()));
              },
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _syncGyms,
        child: userGyms.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 180),
                  Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2F3A),
                          foregroundColor: Colors.white),
                      onPressed: () => _showGymForm(),
                      child: const Text("Add First Gym"),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(12.0),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Add Another Gym"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2F3A),
                          foregroundColor: Colors.white),
                      onPressed: () => _showGymForm(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------- HORIZONTAL SCROLLER of full-width gym cards ----------
                  SizedBox(
                    height: 240, // card height
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenW = MediaQuery.of(context).size.width;
                        const horizontalPadding = 24.0; // outer padding approx
                        final cardW = screenW - horizontalPadding;

                        return ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: userGyms.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final gym = userGyms[index];
                            return SizedBox(
                              width: cardW,
                              child: _buildGymCard(context, gym, index),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ========================== GYM CARD ==========================

  Widget _buildGymCard(
      BuildContext context, Map<String, dynamic> gym, int index) {
    // =====================================================================
    // ==== CIRCLE & RADIAL SETTINGS (single place to tweak the arc/size) ===
    const double anchorIconSize = 36; // dumbbell circle diameter
    const double anchorRightPadding =
        142; // move anchor LEFT by increasing this
    const double arcRadius = 80; // distance from anchor to actions
    const double actionCircleSize = 36; // action circle diameter
    const double actionIconSize = 18; // icon glyph size
    const double actionLabelGap = 7; // gap between circle and label (row)
    // right-side half-circle sweep (top-right -> bottom-right)
    const List<double> arcAnglesDeg = [280, 325, 360, 35, 80];
    // =====================================================================

    final actions = <_ActionSpec>[
      _ActionSpec(
        icon: Icons.delete,
        label: 'Delete Gym',
        bg: const Color(0xFFE53935), // red
        onTap: () => _deleteGym(index),
      ),
      _ActionSpec(
        icon: Icons.edit,
        label: 'Edit Gym',
        bg: const Color(0xFFFFCA28), // yellow
        onTap: () => _showGymForm(index: index),
      ),
      _ActionSpec(
        icon: Icons.person_add_alt_1,
        label: 'Add User',
        bg: const Color(0xFF66BB6A), // green
        onTap: () => _showAddCustomerForm(gym),
      ),
      _ActionSpec(
        icon: Icons.dashboard_outlined,
        label: 'Dashboard',
        bg: Colors.white, // white
        onTap: () => _navigateToDashboard(gym),
      ),
      _ActionSpec(
        icon: Icons.group_outlined,
        label: 'Users',
        bg: Colors.purpleAccent, // white
        onTap: () => _navigateToUserView(gym),
      ),
    ];

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            // ---------- Anchor position: center-right & vertically centered ----------
            final anchor = Offset(
              w - anchorRightPadding - anchorIconSize / 2,
              h / 2,
            );

            // ---------- Left info block (centered vertically, left-aligned) ----------
            final content = Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 120.0),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment.center, // vertical middle
                        crossAxisAlignment: CrossAxisAlignment.start, // left
                        children: [
                          // (pinned "Gym" label moved to top-left; removed here)
                          // const SizedBox(height: 10) -- keep spacing consistent
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
                                fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Capacity: ${gym['capacity'] ?? 0}",
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );

            // ---------- Pinned "Gym" label at top-left ----------
            final pinnedGymLabel = Positioned(
              left: 12,
              top: 12,
              child: Row(
                children: const [
                  Icon(Icons.fitness_center,
                      color: Color(0xFF4F9CF9), size: 16),
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

            // ---------- Dumbbell Anchor ----------
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
                child: const Icon(Icons.fitness_center,
                    color: Colors.white, size: 24),
              ),
            );

            // ---------- Actions arranged in right-side half circle ----------
            final radial = <Widget>[];
            for (var i = 0; i < actions.length; i++) {
              final spec = actions[i];
              final theta = arcAnglesDeg[i] * math.pi / 180.0;

              final cx = anchor.dx + arcRadius * math.cos(theta);
              final cy = anchor.dy + arcRadius * math.sin(theta);

              radial.add(Positioned(
                left: cx - actionCircleSize / 2,
                top: cy - actionCircleSize / 2,
                child: _ActionButton(
                  icon: spec.icon,
                  label: spec.label,
                  bg: spec.bg,
                  circleSize: actionCircleSize,
                  iconSize: actionIconSize,
                  labelGap: actionLabelGap,
                  onTap: spec.onTap,
                ),
              ));
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                content,
                pinnedGymLabel, // <— pinned at top-left
                anchorWidget,
                ...radial,
              ],
            );
          },
        ),
      ),
    );
  }

  String? _avatarUrl(supa.User? u) {
    final md = u?.userMetadata ?? {};
    final fromAvatar = md['avatar_url'];
    final fromPicture = md['picture'];
    if (fromAvatar is String && fromAvatar.isNotEmpty) return fromAvatar;
    if (fromPicture is String && fromPicture.isNotEmpty) return fromPicture;
    return null;
  }

  // ---- UI helpers ----

  Widget _glassyField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2F3A))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4F9CF9))),
      ),
      validator: validator,
    );
  }

  Widget _glassDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items
          .map(
            (e) => DropdownMenuItem<T>(
              value: e,
              child: Text(
                e.toString(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF111214),
      iconEnabledColor: Colors.white70,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2F3A))),
        focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4F9CF9))),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(20, 255, 255, 255),
            Color.fromARGB(5, 255, 255, 255)
          ],
        ),
        border: Border.all(
            color: const Color.fromARGB(30, 255, 255, 255), width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color.fromARGB(120, 0, 0, 0),
              blurRadius: 10,
              offset: Offset(4, 6))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child:
              Container(color: const Color.fromARGB(25, 0, 0, 0), child: child),
        ),
      ),
    );
  }
}

// ---------- Radial Actions model & UI ----------

class _ActionSpec {
  final IconData icon;
  final String label;
  final Color bg;
  final VoidCallback onTap;
  _ActionSpec({
    required this.icon,
    required this.label,
    required this.bg,
    required this.onTap,
  });
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final double circleSize;
  final double iconSize;
  final double labelGap;
  final VoidCallback onTap;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.bg,
    required this.circleSize,
    required this.iconSize,
    required this.labelGap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(circleSize / 2),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: bg,
              shape: const CircleBorder(),
              elevation: 2,
              child: SizedBox(
                width: circleSize,
                height: circleSize,
                child: Icon(icon, size: iconSize, color: Colors.black),
              ),
            ),
            SizedBox(width: labelGap),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
