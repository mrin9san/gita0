import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  bool isEditing = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    if (user != null) {
      _nameController.text = user!.displayName ?? "";
      _locationController.text = ""; // You can load saved location from DB
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
      // TODO: Upload image to storage & update user.photoURL
    }
  }

  Future<void> _saveProfile() async {
    if (user != null) {
      await user!.updateDisplayName(_nameController.text);
      // TODO: Save location to Firestore/RealtimeDB if needed
      // TODO: Upload profile picture and call user.updatePhotoURL(url)

      setState(() {
        isEditing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("User Profile")),
        body: const Center(child: Text("No user is logged in.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("User Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Profile Picture
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: _imageFile != null
                        ? FileImage(_imageFile!)
                        : (user!.photoURL != null
                            ? NetworkImage(user!.photoURL!)
                            : null) as ImageProvider<Object>?,
                    child: user!.photoURL == null && _imageFile == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                  if (isEditing)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.camera_alt, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Name
            _infoField("Name", _nameController, editable: true),

            // Email (read-only)
            _infoField("Email", TextEditingController(text: user!.email ?? ""),
                editable: false),

            // Location
            _infoField("Location", _locationController, editable: true),

            const SizedBox(height: 20),

            // Edit / Save Button
            ElevatedButton.icon(
              icon: Icon(isEditing ? Icons.save : Icons.edit),
              label: Text(isEditing ? "Save" : "Edit Profile"),
              onPressed: () {
                if (isEditing) {
                  _saveProfile();
                } else {
                  setState(() {
                    isEditing = true;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoField(String label, TextEditingController controller,
      {required bool editable}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        enabled: editable && isEditing,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
