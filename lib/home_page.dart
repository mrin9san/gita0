import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_page.dart';
import 'dashboard.dart';

class HomePage extends StatefulWidget {
  final fb.User user;
  final String fireBaseId; // Fire.FireBaseID from login

  const HomePage({super.key, required this.user, required this.fireBaseId});

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

  @override
  void initState() {
    super.initState();
    gymsBox = Hive.box('gymsBox');
    _loadGyms();
  }

  void _loadGyms() {
    final List stored = gymsBox.get(widget.user.uid, defaultValue: []);
    userGyms = stored
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _ensureSupabaseSession() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) return;

    final silent = await GoogleSignIn().signInSilently();
    if (silent == null) return;
    final gAuth = await silent.authentication;
    final idToken = gAuth.idToken;
    if (idToken == null) return;

    await client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: gAuth.accessToken,
    );
  }

  Future<void> _saveGym({int? index}) async {
    if (_formKey.currentState!.validate()) {
      final gymData = <String, dynamic>{
        'name': _gymNameController.text.trim(),
        'location': _gymLocationController.text.trim(),
        'capacity': int.tryParse(_gymCapacityController.text.trim()) ?? 0,
      };

      try {
        await _ensureSupabaseSession();

        final response = await Supabase.instance.client
            .from('Gyms')
            .insert({
              'GymName': gymData['name'],
              'Location': gymData['location'],
              'Capacity': gymData['capacity'],
              'FireBaseID': widget.fireBaseId,
            })
            .select()
            .single();

        if (response != null) {
          gymData['GymID'] = response['GymID'];
        }

        if (index == null) {
          userGyms.add(gymData);
        } else {
          userGyms[index] = gymData;
        }
        gymsBox.put(widget.user.uid, userGyms);

        _gymNameController.clear();
        _gymLocationController.clear();
        _gymCapacityController.clear();

        setState(() {});
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        debugPrint("❌ Supabase insert failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save gym in Supabase: $e")),
          );
        }
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
                foregroundColor: Colors.white),
            onPressed: () => _saveGym(index: index),
            child: Text(index == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  void _deleteGym(int index) {
    userGyms.removeAt(index);
    gymsBox.put(widget.user.uid, userGyms);
    setState(() {});
  }

  Future<void> _logout() async {
    await fb.FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
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

    await _ensureSupabaseSession();

    final name = (gym['name'] ?? '').toString();
    final loc = (gym['location'] ?? '').toString();

    if (name.isEmpty) return null;

    final rows = await Supabase.instance.client
        .from('Gyms')
        .select('GymID')
        .eq('FireBaseID', widget.fireBaseId)
        .eq('GymName', name)
        .eq('Location', loc)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows is List && rows.isNotEmpty) {
      final id = rows.first['GymID'] as String?;
      if (id != null && id.isNotEmpty) {
        gym['GymID'] = id;
        gymsBox.put(widget.user.uid, userGyms);
        return id;
      }
    }
    return null;
  }

  // ======= NEW: Add Customer dialog with auto-BMI + dropdowns + scroll =======
  void _showAddCustomerForm(Map<String, dynamic> gym) async {
    final formKey = GlobalKey<FormState>();

    // Controllers in the EXACT order requested
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
    final membershipC =
        TextEditingController(); // kept for payload, but we’ll use dropdown value
    final exercizeTypeC = TextEditingController(); // ditto
    final sexC = TextEditingController(); // ditto
    final emailC = TextEditingController();
    final joinDateC = TextEditingController();
    final phoneC = TextEditingController();

    // Dropdown state
    String? sexValue;
    String? membershipValue;
    String? exerciseValue;

    // Auto-calc BMI from Weight(kg) and Height(cm)
    void recalcBmi() {
      final w = int.tryParse(weightC.text.trim()); // kg
      final hCm = int.tryParse(heightC.text.trim()); // cm
      if (w != null && hCm != null && hCm > 0) {
        final h = hCm / 100.0;
        final bmi = (w / (h * h)).round(); // integer BMI
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
        joinDateC.text = d.toIso8601String().split('T').first; // YYYY-MM-DD
      }
    }

    String? _req(String? v) => (v?.trim().isEmpty ?? true) ? 'Required' : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF111214),
          title:
              const Text('Add Customer', style: TextStyle(color: Colors.white)),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    // Name
                    _glassyField(
                        controller: nameC, label: 'Name', validator: _req),
                    const SizedBox(height: 10),

                    // Age
                    _glassyField(
                      controller: ageC,
                      label: 'Age',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),

                    // Address
                    _glassyField(
                        controller: addressC, label: 'Address', maxLines: 3),
                    const SizedBox(height: 10),

                    // Weight (kg) -> triggers BMI
                    _glassyField(
                      controller: weightC,
                      label: 'Weight (kg)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),

                    // BMI (auto) read-only
                    _glassyField(
                      controller: bmiC,
                      label: 'BMI (auto)',
                      readOnly: true,
                    ),
                    const SizedBox(height: 10),

                    // GymHistory
                    _glassyField(
                        controller: gymHistoryC,
                        label: 'GymHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),

                    // Target
                    _glassyField(
                        controller: targetC, label: 'Target', maxLines: 3),
                    const SizedBox(height: 10),

                    // HealthHistory
                    _glassyField(
                        controller: healthHistoryC,
                        label: 'HealthHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),

                    // SupplementHistory
                    _glassyField(
                        controller: supplementHistoryC,
                        label: 'SupplementHistory',
                        maxLines: 3),
                    const SizedBox(height: 10),

                    // Height (cm) -> triggers BMI
                    _glassyField(
                      controller: heightC,
                      label: 'Height (cm)',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocal(recalcBmi),
                    ),
                    const SizedBox(height: 10),

                    // Membership (Dropdown)
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

                    // ExercizeType (Dropdown)
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

                    // Sex (Dropdown)
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

                    // Email
                    _glassyField(
                      controller: emailC,
                      label: 'Email',
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),

                    // JoinDate (picker)
                    _glassyField(
                      controller: joinDateC,
                      label: 'JoinDate (YYYY-MM-DD)',
                      readOnly: true,
                      onTap: pickJoinDate,
                      suffixIcon: const Icon(Icons.calendar_today,
                          color: Colors.white70, size: 18),
                    ),
                    const SizedBox(height: 10),

                    // Phone
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

                // Ensure GymID
                final gymId = await _ensureGymId(gym);
                if (gymId == null || gymId.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Couldn't resolve GymID. Try re-saving the gym.")));
                  }
                  return;
                }

                try {
                  await _ensureSupabaseSession();

                  int? _toInt(TextEditingController c) => c.text.trim().isEmpty
                      ? null
                      : int.tryParse(c.text.trim());

                  final payload = {
                    'GymID': gymId,
                    'FireBaseID': widget.fireBaseId,

                    // exact order/keys per your schema
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
                    'SupplementHistory': supplementHistoryC.text.trim().isEmpty
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
                    'Email':
                        emailC.text.trim().isEmpty ? null : emailC.text.trim(),
                    'JoinDate': joinDateC.text.trim().isEmpty
                        ? null
                        : joinDateC.text.trim(),
                    'Phone':
                        phoneC.text.trim().isEmpty ? null : phoneC.text.trim(),
                  };

                  final inserted = await Supabase.instance.client
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
  // ======= END: Add Customer dialog =======

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const Text("Gym Manager"),
        actions: [
          if (widget.user.photoURL != null && widget.user.photoURL!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfilePage()));
                },
                child: CircleAvatar(
                    backgroundImage: NetworkImage(widget.user.photoURL ?? "")),
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
      body: userGyms.isEmpty
          ? Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2F3A),
                    foregroundColor: Colors.white),
                onPressed: () => _showGymForm(),
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
                      onPressed: () => _showGymForm(),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.fitness_center,
                                            color: Color(0xFF4F9CF9), size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          "Gym",
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              letterSpacing: 0.6),
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
                                            GestureDetector(
                                              onTap: () =>
                                                  _navigateToDashboard(gym),
                                              child: Text(
                                                gym['name'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  decoration:
                                                      TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Location:",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white
                                                    .withOpacity(0.7),
                                              ),
                                            ),
                                            Text(
                                              gym['location'] ?? '',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
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
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          tooltip: 'Edit Gym',
                                          icon: const Icon(Icons.edit,
                                              color: Colors.white70, size: 18),
                                          onPressed: () =>
                                              _showGymForm(index: index),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete Gym',
                                          icon: const Icon(Icons.delete,
                                              color: Colors.white70, size: 18),
                                          onPressed: () => _deleteGym(index),
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
    );
  }

  // ---- UI helpers ----

  // glassy text field with optional onChanged hook
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

  // glassy dropdown with consistent styling
  Widget _glassDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
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
