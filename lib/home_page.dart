import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
    gymsBox = Hive.box('gymsBox');
    _loadGyms();
  }

  void _loadGyms() {
    if (user != null) {
      final List storedGyms = gymsBox.get(user!.uid, defaultValue: []);
      // Convert each map to Map<String, dynamic>
      userGyms = storedGyms.map<Map<String, dynamic>>((gym) {
        return Map<String, dynamic>.from(gym);
      }).toList();
    }
    setState(() {});
  }

  void _saveGym({int? index}) {
    if (_formKey.currentState!.validate()) {
      Map<String, dynamic> gymData = {
        'name': _gymNameController.text,
        'location': _gymLocationController.text,
        'capacity': int.tryParse(_gymCapacityController.text) ?? 0,
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
      _gymNameController.text = userGyms[index]['name'];
      _gymLocationController.text = userGyms[index]['location'];
      _gymCapacityController.text = userGyms[index]['capacity'].toString();
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
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter gym name' : null,
              ),
              TextFormField(
                controller: _gymLocationController,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter location' : null,
              ),
              TextFormField(
                controller: _gymCapacityController,
                decoration: const InputDecoration(labelText: 'Capacity'),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter capacity' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => _saveGym(index: index),
              child: Text(index == null ? 'Add' : 'Update')),
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
    if (user != null) {
      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      // Sign out from Google
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();

      // Optional: Clear user's gyms from Hive
      // gymsBox.delete(user!.uid);

      // Navigate to login page
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, "/", (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use local variable for null-safety promotion
    final currentUser = user;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
        actions: [
          // Profile picture
          if (currentUser != null && currentUser.photoURL != null)
            Padding(
              padding: const EdgeInsets.only(right: 10.0),
              child: CircleAvatar(
                backgroundImage: NetworkImage(currentUser.photoURL!),
              ),
            ),
          // Logout button
          if (currentUser != null)
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      gym['name'],
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text("Location: ${gym['location']}"),
                                    Text("Capacity: ${gym['capacity']}"),
                                    const Spacer(),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
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
                                    )
                                  ],
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
