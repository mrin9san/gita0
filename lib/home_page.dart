import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final User? user = FirebaseAuth.instance.currentUser;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _gymNameController = TextEditingController();
  final TextEditingController _gymLocationController = TextEditingController();
  final TextEditingController _gymCapacityController = TextEditingController();

  late Box gymsBox;
  List<Map<String, dynamic>> userGyms = [];

  @override
  void initState() {
    super.initState();
    gymsBox = Hive.box('gymsBox'); // must match main.dart
    _loadGyms();
  }

  void _loadGyms() {
    if (user != null) {
      final List stored = gymsBox.get(user!.uid, defaultValue: []);
      userGyms = stored
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    setState(() {});
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

      gymsBox.put(user!.uid, userGyms);
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
        title: Text(index == null ? 'Add Gym' : 'Edit Gym'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _gymNameController,
                decoration: const InputDecoration(labelText: 'Gym Name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter gym name' : null,
              ),
              TextFormField(
                controller: _gymLocationController,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter location' : null,
              ),
              TextFormField(
                controller: _gymCapacityController,
                decoration: const InputDecoration(labelText: 'Capacity'),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter capacity' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveGym(index: index),
            child: Text(index == null ? 'Add' : 'Update'),
          ),
        ],
      ),
    );
  }

  void _deleteGym(int index) {
    userGyms.removeAt(index);
    gymsBox.put(user!.uid, userGyms);
    setState(() {});
  }

  Future<void> _logout() async {
    // Firebase sign out
    await FirebaseAuth.instance.signOut();
    // Google sign out (so the chooser appears next time)
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = user;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Gym Manager"),
        actions: [
          // Profile avatar → ProfilePage
          if (currentUser != null && currentUser.photoURL != null)
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
                  backgroundImage: NetworkImage(currentUser.photoURL!),
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
      body: currentUser == null
          ? const Center(child: Text("No user logged in"))
          : userGyms.isEmpty
              ? Center(
                  child: ElevatedButton(
                    onPressed: () => _showGymForm(),
                    child: const Text("Add First Gym"),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => _showGymForm(),
                        child: const Text("Add Another Gym"),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 3 / 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: userGyms.length,
                          itemBuilder: (context, index) {
                            final gym = userGyms[index];
                            return Card(
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        gym['name'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                          "Location: ${gym['location'] ?? ''}"),
                                      Text("Capacity: ${gym['capacity'] ?? 0}"),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () =>
                                                _showGymForm(index: index),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () => _deleteGym(index),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
