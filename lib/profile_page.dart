import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:google_sign_in/google_sign_in.dart';

/// Firebase-free profile page that:
/// - Uses a stable FireBaseID (FK for Gyms/Users)
/// - Loads/Saves Name & Location in `Fire` (by FireBaseID)
/// - (Optional) Uploads avatar to Storage bucket `avatars` and saves PhotoURL
class ProfilePage extends StatefulWidget {
  final String? fireBaseId; // Pass from HomePage for best results

  const ProfilePage({super.key, this.fireBaseId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  supa.User? _user;
  String? _fireBaseId; // resolved Fire.FireBaseID
  String? _photoUrl; // Fire.PhotoURL or auth.user_metadata.avatar_url
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    final client = supa.Supabase.instance.client;
    _user = client.auth.currentUser;

    if (_user == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Basic auth info
    final email = _user!.email ?? '';
    _emailController.text = email;

    // Prefer the fireBaseId provided by caller
    _fireBaseId = widget.fireBaseId;

    try {
      Map<String, dynamic>? row;

      if (_fireBaseId != null && _fireBaseId!.isNotEmpty) {
        row = await client
            .from('Fire')
            .select('FireBaseID, Name, Location, PhotoURL')
            .eq('FireBaseID', _fireBaseId!)
            .maybeSingle();
      } else if (email.isNotEmpty) {
        row = await client
            .from('Fire')
            .select('FireBaseID, Name, Location, PhotoURL')
            .eq('EmailID', email)
            .maybeSingle();
        if (row != null) _fireBaseId = row['FireBaseID'] as String?;
      }

      // Fill fields
      final md = _user!.userMetadata ?? {};
      final metaName = (md['name'] as String?) ?? '';
      final metaAvatar =
          (md['avatar_url'] as String?) ?? (md['picture'] as String?);

      _nameController.text =
          (row?['Name'] as String?)?.trim().isNotEmpty == true
              ? (row!['Name'] as String)
              : metaName;

      _locationController.text = (row?['Location'] as String?) ?? '';
      _photoUrl = (row?['PhotoURL'] as String?) ?? metaAvatar;
    } catch (e) {
      debugPrint('⚠️ Failed to load Fire row: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  /// Uploads avatar to `avatars/<FireBaseID>/avatar.jpg` (upsert).
  /// Returns public URL (if bucket is public) or null on failure.
  Future<String?> _uploadAvatarIfNeeded() async {
    if (_imageFile == null || _fireBaseId == null) return null;
    try {
      final client = supa.Supabase.instance.client;
      final path = '${_fireBaseId!}/avatar.jpg';

      await client.storage.from('avatars').upload(
            path,
            _imageFile!,
            fileOptions: const supa.FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      final publicUrl = client.storage.from('avatars').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Avatar upload failed: $e');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null || _fireBaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final client = supa.Supabase.instance.client;
      final name = _nameController.text.trim();
      final location = _locationController.text.trim();

      // 1) Upload avatar (optional)
      final uploadedUrl = await _uploadAvatarIfNeeded();
      if (uploadedUrl != null) {
        _photoUrl = uploadedUrl;
      }

      // 2) Update auth user metadata (name + avatar_url)
      final data = <String, dynamic>{'name': name};
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        data['avatar_url'] = _photoUrl!;
      }
      await client.auth.updateUser(supa.UserAttributes(data: data));

      // 3) Update Fire row (NEVER update FireBaseID)
      final updateMap = <String, dynamic>{
        'Name': name,
        'Location': location,
      };
      if (_photoUrl != null && _photoUrl!.isNotEmpty) {
        updateMap['PhotoURL'] = _photoUrl!;
      }

      await client
          .from('Fire')
          .update(updateMap)
          .eq('FireBaseID', _fireBaseId!);

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved ✅')),
        );
      }
    } catch (e) {
      debugPrint('❌ Save profile failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _logout() async {
    // Supabase session
    try {
      await supa.Supabase.instance.client.auth.signOut();
    } catch (_) {}

    // Google account cache -> force account chooser next login
    try {
      final google = GoogleSignIn();
      await google.disconnect();
      await google.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  ImageProvider<Object>? _currentAvatarProvider() {
    if (_imageFile != null) return FileImage(_imageFile!);
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return NetworkImage(_photoUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Profile')),
        body: const Center(child: Text('No user is logged in.')),
      );
    }

    final avatar = _currentAvatarProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: avatar,
                      child: avatar == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    if (_isEditing)
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
              _infoField('Name', _nameController, editable: true),
              _infoField('Email', _emailController, editable: false),
              _infoField('Location', _locationController, editable: true),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: Icon(_isEditing ? Icons.save : Icons.edit),
                label: Text(_isEditing
                    ? (_isSaving ? 'Saving...' : 'Save')
                    : 'Edit Profile'),
                onPressed: () async {
                  if (_isEditing) {
                    await _saveProfile();
                  } else {
                    setState(() => _isEditing = true);
                  }
                },
              ),
            ],
          ),
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
        enabled: editable && _isEditing,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
