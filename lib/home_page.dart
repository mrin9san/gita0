import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import 'profile_page.dart';
import 'dashboard.dart';

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
  StreamSubscription<List<Map<String, dynamic>>>? _gymsSub;

  String? _loadError;

  @override
  void initState() {
    super.initState();
    gymsBox = Hive.box('gymsBox');
    _user = supa.Supabase.instance.client.auth.currentUser;

    // 1) Show cached quickly
    _loadGymsLocal();
    // 2) Live subscribe to server (authoritative)
    _subscribeGyms();
  }

  @override
  void dispose() {
    _gymsSub?.cancel();
    super.dispose();
  }

  // ---------- Data coordination ----------

  void _loadGymsLocal() {
    final key = widget.fireBaseId;
    final List stored = gymsBox.get(key, defaultValue: []);
    userGyms = stored
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {}); // show cache immediately
  }

  void _subscribeGyms() {
    final client = supa.Supabase.instance.client;

    _gymsSub = client
        .from('Gyms')
        .stream(primaryKey: ['GymID'])
        .eq('FireBaseID', widget.fireBaseId)
        // .order('created_at', ascending: true) // optional; can omit on streams
        .listen((rows) {
          // Normalize server rows into UI/Hive shape
          final normalized = rows.map<Map<String, dynamic>>((r) {
            return {
              'GymID': r['GymID'],
              'name': r['GymName'],
              'location': r['Location'],
              'capacity': r['Capacity'] ?? 0,
            };
          }).toList();

          setState(() {
            _loadError = null;
            userGyms = normalized;
          });
          // Overwrite cache with server truth
          gymsBox.put(widget.fireBaseId, userGyms);
        }, onError: (e) {
          setState(() {
            _loadError = 'Realtime error: $e';
          });
        });
  }

  Future<void> _saveGym({int? index}) async {
    if (!_formKey.currentState!.validate()) return;

    final name = _gymNameController.text.trim();
    final loc = _gymLocationController.text.trim();
    final cap = int.tryParse(_gymCapacityController.text.trim()) ?? 0;

    try {
      String? gymId;

      // EDIT path: if we have an index with a GymID -> UPDATE
      if (index != null) {
        final dynamic existingId = userGyms[index]['GymID'];
        if (existingId is String && existingId.isNotEmpty) {
          gymId = existingId;

          await supa.Supabase.instance.client
              .from('Gyms')
              .update({
                'GymName': name,
                'Location': loc,
                'Capacity': cap,
              })
              .eq('GymID', gymId)
              .select('GymID')
              .single();

          // ✅ Optimistic UI update
          userGyms[index] = {
            ...userGyms[index],
            'name': name,
            'location': loc,
            'capacity': cap,
          };
          gymsBox.put(widget.fireBaseId, userGyms);
          setState(() {});
        }
      }

      // ADD path: no GymID -> INSERT
      if (gymId == null) {
        final inserted = await supa.Supabase.instance.client
            .from('Gyms')
            .insert({
              'GymName': name,
              'Location': loc,
              'Capacity': cap,
              'FireBaseID': widget.fireBaseId,
            })
            .select('GymID,GymName,Location,Capacity')
            .single();

        // ✅ Optimistic append
        userGyms.add({
          'GymID': inserted['GymID'],
          'name': inserted['GymName'],
          'location': inserted['Location'],
          'capacity': inserted['Capacity'] ?? 0,
        });
        gymsBox.put(widget.fireBaseId, userGyms);
        setState(() {});
      }

      // Clear form & close dialog; stream will reconcile later if needed
      _gymNameController.clear();
      _gymLocationController.clear();
      _gymCapacityController.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint("❌ Supabase save failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save gym in Supabase: $e")),
        );
      }
    }
  }

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

  Future<void> _deleteGym(int index) async {
    final dynamic gymId = userGyms[index]['GymID'];
    if (gymId == null || gymId.toString().isEmpty) {
      // If no server id, just remove local (rare with streams)
      userGyms.removeAt(index);
      gymsBox.put(widget.fireBaseId, userGyms);
      setState(() {});
      return;
    }

    try {
      await supa.Supabase.instance.client
          .from('Gyms')
          .delete()
          .eq('GymID', gymId);
      // Stream will update UI when delete event arrives
    } catch (e) {
      debugPrint('❌ Failed to delete on server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete on server: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      await supa.Supabase.instance.client.auth.signOut();
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

  /// If local gym map lacks GymID, fetch it from Supabase by (FireBaseID + GymName + Location)
  Future<String?> _ensureGymId(Map<String, dynamic> gym) async {
    final dynamic existing = gym['GymID'];
    if (existing is String && existing.isNotEmpty) return existing;

    final name = (gym['name'] ?? '').toString();
    final loc = (gym['location'] ?? '').toString();
    if (name.isEmpty) return null;

    final List<dynamic> rows = await supa.Supabase.instance.client
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
        gymsBox.put(widget.fireBaseId, userGyms);
        return id;
      }
    }
    return null;
  }

  // ======= Add Customer dialog (with photo pick/camera + upload) =======
  void _showAddCustomerForm(Map<String, dynamic> gym) async {
    final formKey = GlobalKey<FormState>();

    // Controllers
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

    // Dropdown state
    String? sexValue;
    String? membershipValue;
    String? exerciseValue;

    // Photo state
    final picker = ImagePicker();
    File? photoFile;

    // Auto-calc BMI
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
    Future<void> pickJoinDate(BuildContext context) async {
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pickFromGallery() async {
            final x = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
              maxWidth: 1600,
            );
            if (x != null) {
              setLocal(() {
                photoFile = File(x.path);
              });
            }
          }

          Future<void> pickFromCamera() async {
            final x = await picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 85,
              maxWidth: 1600,
            );
            if (x != null) {
              setLocal(() {
                photoFile = File(x.path);
              });
            }
          }

          Future<String?> uploadPhotoIfNeeded() async {
            if (photoFile == null) return null;
            try {
              final client = supa.Supabase.instance.client;
              final now = DateTime.now().millisecondsSinceEpoch;
              final path = 'users/${widget.fireBaseId}/$now.jpg';
              await client.storage.from('avatars').upload(
                    path,
                    photoFile!,
                    fileOptions: const supa.FileOptions(
                      cacheControl: '3600',
                      upsert: true,
                      contentType: 'image/jpeg',
                    ),
                  );
              final publicUrl =
                  client.storage.from('avatars').getPublicUrl(path);
              return publicUrl;
            } catch (e) {
              debugPrint('❌ Upload photo failed: $e');
              return null;
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF111214),
            title: const Text('Add Customer',
                style: TextStyle(color: Colors.white)),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
                maxWidth: MediaQuery.of(context).size.width * 0.95,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      // Avatar preview + buttons
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage: photoFile != null
                                ? FileImage(photoFile!)
                                : null,
                            child: photoFile == null
                                ? const Icon(Icons.person, size: 30)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: pickFromGallery,
                                  icon: const Icon(Icons.photo),
                                  label: const Text('Gallery'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: pickFromCamera,
                                  icon: const Icon(Icons.photo_camera),
                                  label: const Text('Camera'),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          controller: bmiC,
                          label: 'BMI (auto)',
                          readOnly: true),
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

                      _glassyField(
                        controller: heightC,
                        label: 'Height (cm)',
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(recalcBmi),
                      ),
                      const SizedBox(height: 10),

                      _glassDropdown<String>(
                        label: 'Membership',
                        value: membershipValue,
                        items: const ['Standard', 'Premium', 'VIP'],
                        onChanged: (v) => setLocal(() {
                          membershipValue = v;
                          membershipC.text = v ?? '';
                        }),
                      ),
                      const SizedBox(height: 10),

                      _glassDropdown<String>(
                        label: 'ExercizeType',
                        value: exerciseValue,
                        items: const [
                          'Strength',
                          'Cardio',
                          'CrossFit',
                          'Yoga',
                          'Mixed'
                        ],
                        onChanged: (v) => setLocal(() {
                          exerciseValue = v;
                          exercizeTypeC.text = v ?? '';
                        }),
                      ),
                      const SizedBox(height: 10),

                      _glassDropdown<String>(
                        label: 'Sex',
                        value: sexValue,
                        items: const ['Male', 'Female', 'Other'],
                        onChanged: (v) => setLocal(() {
                          sexValue = v;
                          sexC.text = v ?? '';
                        }),
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
                        onTap: () => pickJoinDate(ctx),
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
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2F3A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  // Ensure GymID
                  final gymId = await _ensureGymId(gym);
                  if (gymId == null || gymId.isEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                "Couldn't resolve GymID. Try re-saving the gym.")),
                      );
                    }
                    return;
                  }

                  try {
                    // 1) Upload photo if any
                    final photoUrl = await uploadPhotoIfNeeded();

                    int? _toInt(TextEditingController c) =>
                        c.text.trim().isEmpty
                            ? null
                            : int.tryParse(c.text.trim());

                    // 2) Build payload (include PhotoURL if we got one)
                    final payload = {
                      'GymID': gymId,
                      'FireBaseID': widget.fireBaseId, // stable FK
                      'PhotoURL':
                          (photoUrl?.isNotEmpty ?? false) ? photoUrl : null,

                      'Name': nameC.text.trim(),
                      'Age': _toInt(ageC),
                      'Address': addressC.text.trim().isEmpty
                          ? null
                          : addressC.text.trim(),
                      'Weight': _toInt(weightC),
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
                      'SupplementHistory':
                          supplementHistoryC.text.trim().isEmpty
                              ? null
                              : supplementHistoryC.text.trim(),
                      'Height': _toInt(heightC),
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
                    };

                    await supa.Supabase.instance.client
                        .from('Users')
                        .insert(payload)
                        .select('UserID')
                        .single();

                    if (mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Customer added')),
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
          );
        },
      ),
    );
  }
  // ======= END Add Customer dialog =======

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
          if (photoUrl != null && photoUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProfilePage(fireBaseId: widget.fireBaseId),
                    ),
                  );
                },
                child: CircleAvatar(backgroundImage: NetworkImage(photoUrl)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(fireBaseId: widget.fireBaseId),
                  ),
                );
              },
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          if (_loadError != null)
            Container(
              width: double.infinity,
              color: Colors.red.withOpacity(0.08),
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          Expanded(
            child: userGyms.isEmpty
                ? Center(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A2F3A),
                          foregroundColor: Colors.white),
                      onPressed: _showGymForm,
                      child: const Text("Add First Gym"),
                    ),
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0D0E11),
                          Color(0xFF111318),
                          Color(0xFF0F1115)
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text("Add Another Gym"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2A2F3A),
                                foregroundColor: Colors.white),
                            onPressed: _showGymForm,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 3 / 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: userGyms.length,
                            itemBuilder: (context, index) {
                              final gym = userGyms[index];
                              return _GlassCard(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.fitness_center,
                                                  color: Color(0xFF4F9CF9),
                                                  size: 16),
                                              const SizedBox(width: 4),
                                              const Text(
                                                "Gym",
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                  letterSpacing: 0.6,
                                                ),
                                              ),
                                              const Spacer(),
                                              TextButton.icon(
                                                onPressed: () =>
                                                    _navigateToDashboard(gym),
                                                icon: const Icon(
                                                    Icons.visibility,
                                                    size: 18),
                                                label: const Text('View'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  textStyle: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: SingleChildScrollView(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    gym['name'] ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    "Location:",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                    ),
                                                  ),
                                                  Text(
                                                    gym['location'] ?? '',
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white70),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    "Capacity: ${gym['capacity'] ?? 0}",
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white70),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              IconButton(
                                                tooltip: 'Edit Gym',
                                                icon: const Icon(Icons.edit,
                                                    color: Colors.white70,
                                                    size: 18),
                                                onPressed: () =>
                                                    _showGymForm(index: index),
                                              ),
                                              IconButton(
                                                tooltip: 'Delete Gym',
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.white70,
                                                    size: 18),
                                                onPressed: () =>
                                                    _deleteGym(index),
                                              ),
                                              IconButton(
                                                tooltip: 'Add Customer',
                                                icon: const Icon(
                                                    Icons.person_add_alt_1,
                                                    color: Colors.white70,
                                                    size: 18),
                                                onPressed: () =>
                                                    _showAddCustomerForm(gym),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
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

  // ---------- UI helpers ----------

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
        suffixIcon: suffixIcon,
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
      decoration: const InputDecoration(
        labelText: 'Select',
        labelStyle: TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2F3A))),
        focusedBorder: OutlineInputBorder(
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
