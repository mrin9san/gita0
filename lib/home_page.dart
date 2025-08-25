import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  final User user;
  const HomePage({super.key, required this.user});

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

  void _saveGym({int? index}) {
    if (_formKey.currentState!.validate()) {
      final gymData = <String, dynamic>{
        'name': _gymNameController.text.trim(),
        'location': _gymLocationController.text.trim(),
        'capacity': int.tryParse(_gymCapacityController.text.trim()) ?? 0,
      };

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
      Navigator.of(context).pop();
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
        title: Text(
          index == null ? 'Add Gym' : 'Edit Gym',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _gymNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Gym Name',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter gym name' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _gymLocationController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter location' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _gymCapacityController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Capacity',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter capacity' : null,
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

  void _deleteGym(int index) {
    userGyms.removeAt(index);
    gymsBox.put(widget.user.uid, userGyms);
    setState(() {});
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const Text("Gym Manager"),
        actions: [
          if (widget.user.photoURL != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
                child: CircleAvatar(
                  backgroundImage: NetworkImage(widget.user.photoURL!),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfilePage()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: userGyms.isEmpty
          ? Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2F3A),
                  foregroundColor: Colors.white,
                ),
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
                    Color(0xFF0F1115),
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
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _showGymForm(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 3 / 3, // More square aspect ratio
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
                                    // Header with icon
                                    Row(
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
                                    const SizedBox(height: 8),

                                    // Scrollable content area
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
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
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
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
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

                                    // Fixed action buttons at the bottom
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.white70, size: 18),
                                          onPressed: () =>
                                              _showGymForm(index: index),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.white70, size: 18),
                                          onPressed: () => _deleteGym(index),
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
            Color.fromARGB(5, 255, 255, 255),
          ],
        ),
        border: Border.all(
          color: const Color.fromARGB(30, 255, 255, 255),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(120, 0, 0, 0),
            blurRadius: 10,
            offset: Offset(4, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: const Color.fromARGB(25, 0, 0, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}
