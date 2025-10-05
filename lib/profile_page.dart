import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'renew_subscription_page.dart';
import 'package:intl/intl.dart'; // <-- added for pretty dates

class ProfilePage extends StatefulWidget {
  final String? fireBaseId;
  const ProfilePage({super.key, this.fireBaseId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();
  static const String _appVersion = 'v1.0.0';
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  supa.User? _user;
  String? _fireBaseId;
  String? _photoDisplayUrl; // for UI (signed/public)
  String? _photoStoragePath; // we save this to Fire.PhotoURL
  File? _localImageFile;

  String _subscriptionLabel = '—'; // system-generated

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

    final email = _user!.email ?? '';
    _emailController.text = email;
    _fireBaseId = widget.fireBaseId;

    try {
      Map<String, dynamic>? row;

      if (_fireBaseId != null && _fireBaseId!.isNotEmpty) {
        row = await client
            .from('Fire')
            .select('FireBaseID, Name, Location, EmailID, PhotoURL')
            .eq('FireBaseID', _fireBaseId!)
            .maybeSingle();
      } else if (email.isNotEmpty) {
        row = await client
            .from('Fire')
            .select('FireBaseID, Name, Location, EmailID, PhotoURL')
            .eq('EmailID', email)
            .maybeSingle();
        if (row != null) _fireBaseId = row['FireBaseID'] as String?;
      }

      final md = _user!.userMetadata ?? {};
      final metaName = (md['name'] as String?) ?? '';
      final metaAvatar =
          (md['avatar_url'] as String?) ?? (md['picture'] as String?);

      _nameController.text =
          ((row?['Name'] as String?)?.trim().isNotEmpty ?? false)
          ? (row!['Name'] as String)
          : metaName;

      _locationController.text = (row?['Location'] as String?) ?? '';
      _emailController.text = (row?['EmailID'] as String?) ?? email;

      final rawPhoto = (row?['PhotoURL'] as String?);
      if (rawPhoto != null && rawPhoto.trim().isNotEmpty) {
        _photoStoragePath = rawPhoto.trim();
        _photoDisplayUrl = await _resolveDisplayUrlFromPath(_photoStoragePath!);
      } else {
        _photoDisplayUrl = metaAvatar;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load Fire row: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    // Updated: compute subscription label from Payments
    _computeSubscriptionLabel();
  }

  // --- helper to add months like calendar logic (handles month-end) ---
  DateTime _addMonths(DateTime dt, int months) {
    final y = dt.year + ((dt.month - 1 + months) ~/ 12);
    final m = (dt.month - 1 + months) % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = dt.day > lastDay ? lastDay : dt.day;
    return DateTime(
      y,
      m,
      d,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }

  Future<void> _computeSubscriptionLabel() async {
    try {
      if (_fireBaseId == null || _fireBaseId!.isEmpty) return;
      final client = supa.Supabase.instance.client;

      // Pull latest successful payment for this user
      final latest = await client
          .from('Payments')
          .select('created_at, Months, Plan, Status')
          .eq('FireBaseID', _fireBaseId!)
          .eq('Status', 'success')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      String label = 'Free (no active plan)';
      if (latest != null) {
        final createdAtStr = latest['created_at']?.toString();
        final months = (latest['Months'] ?? 1) as int;
        final plan = (latest['Plan'] as String?)?.trim();

        final createdAt = createdAtStr != null
            ? DateTime.tryParse(createdAtStr)
            : null;
        if (createdAt != null) {
          final expiresAt = _addMonths(createdAt.toLocal(), months);
          final now = DateTime.now();
          if (now.isBefore(expiresAt)) {
            final df = DateFormat('d MMM yyyy');
            final until = df.format(expiresAt);
            label =
                '${(plan == null || plan.isEmpty) ? 'Active' : plan} · $until';
          } else {
            // expired -> keep as Free or show expired date if you prefer
            label = 'Free (no active plan)';
          }
        }
      }

      if (mounted) setState(() => _subscriptionLabel = label);
    } catch (e) {
      // leave default if anything fails
      debugPrint('⚠️ Failed to compute subscription label: $e');
    }
  }

  Future<String?> _resolveDisplayUrlFromPath(String pathOrUrl) async {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }
    try {
      final storage = supa.Supabase.instance.client.storage.from('avatars');
      final signed = await storage.createSignedUrl(pathOrUrl, 3600);
      final url = (signed as dynamic).signedUrl as String?;
      return url ?? storage.getPublicUrl(pathOrUrl);
    } catch (_) {
      return supa.Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(pathOrUrl);
    }
  }

  Future<void> _choosePhoto() async {
    if (!_isEditing) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(
              icon: Icons.photo,
              label: 'Choose from Gallery',
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.gallery);
              },
            ),
            _sheetTile(
              icon: Icons.photo_camera,
              label: 'Take a Photo',
              onTap: () async {
                Navigator.pop(context);
                await _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _localImageFile = File(picked.path));
    }
  }

  Future<(String? displayUrl, String? storagePath)>
  _uploadAvatarIfNeeded() async {
    if (_localImageFile == null || _fireBaseId == null) return (null, null);
    try {
      final client = supa.Supabase.instance.client;
      final storage = client.storage.from('avatars');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${_fireBaseId!}/avatar_$ts.jpg';

      await storage.upload(
        path,
        _localImageFile!,
        fileOptions: const supa.FileOptions(cacheControl: '3600', upsert: true),
      );

      String? displayUrl;
      try {
        final signed = await storage.createSignedUrl(path, 3600);
        displayUrl = (signed as dynamic).signedUrl as String?;
      } catch (_) {
        displayUrl = storage.getPublicUrl(path);
      }
      return (displayUrl, path);
    } catch (e) {
      debugPrint('❌ Avatar upload failed: $e');
      return (null, null);
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null || _fireBaseId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not signed in.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final client = supa.Supabase.instance.client;
      final name = _nameController.text.trim();
      final location = _locationController.text.trim();
      final emailId = _emailController.text
          .trim(); // read-only UI, but we still persist if changed programmatically

      final (displayUrl, storagePath) = await _uploadAvatarIfNeeded();
      if (displayUrl != null) _photoDisplayUrl = displayUrl;
      if (storagePath != null) _photoStoragePath = storagePath;

      final md = <String, dynamic>{'name': name};
      if (_photoDisplayUrl != null && _photoDisplayUrl!.isNotEmpty) {
        md['avatar_url'] = _photoDisplayUrl!;
      }
      await client.auth.updateUser(supa.UserAttributes(data: md));

      final updateMap = <String, dynamic>{
        'Name': name,
        'Location': location,
        'EmailID': emailId,
      };
      if (_photoStoragePath != null && _photoStoragePath!.isNotEmpty) {
        updateMap['PhotoURL'] = _photoStoragePath!;
      }

      await client
          .from('Fire')
          .update(updateMap)
          .eq('FireBaseID', _fireBaseId!);

      if (mounted) {
        setState(() {
          _isEditing = false;
          _localImageFile = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved ✅')));
      }
    } catch (e) {
      final msg = e.toString();
      final pretty = msg.contains('duplicate key') || msg.contains('unique')
          ? 'EmailID already exists for another user.'
          : 'Failed to save profile: $msg';
      debugPrint('❌ Save profile failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(pretty)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  ImageProvider<Object>? _currentAvatarProvider() {
    if (_localImageFile != null) return FileImage(_localImageFile!);
    if (_photoDisplayUrl != null && _photoDisplayUrl!.isNotEmpty) {
      return NetworkImage(_photoDisplayUrl!);
    }
    return null;
  }

  void _cancelEditsAndReload() {
    setState(() {
      _isEditing = false;
      _localImageFile = null;
    });
    _initAndLoad();
  }

  // ---------- external actions ----------
  Future<void> _launchEmail({
    String to = 'anitronassam@gmail.com',
    String subject = '',
    String body = '',
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: {
        if (subject.isNotEmpty) 'subject': subject,
        if (body.isNotEmpty) 'body': body,
      },
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _launchWhatsApp(String phone, {String message = 'Hi'}) async {
    // expect full international format like +917099187140
    final enc = Uri.encodeComponent(message);
    final wa = Uri.parse('whatsapp://send?phone=$phone&text=$enc');
    if (await canLaunchUrl(wa)) {
      await launchUrl(wa, mode: LaunchMode.externalApplication);
      return;
    }
    final wab = Uri.parse('whatsapp-business://send?phone=$phone&text=$enc');
    if (await canLaunchUrl(wab)) {
      await launchUrl(wab, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse(
      'https://wa.me/${phone.replaceAll('+', '')}?text=$enc',
    );
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFF0F1116);

    final titleActions = <Widget>[
      if (_isEditing) ...[
        IconButton(
          tooltip: 'Save',
          onPressed: _isSaving ? null : _saveProfile,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Cancel',
          onPressed: _isSaving ? null : _cancelEditsAndReload,
          icon: const Icon(Icons.close, color: Colors.white),
        ),
      ] else ...[
        IconButton(
          tooltip: 'Edit',
          onPressed: () => setState(() => _isEditing = true),
          icon: const Icon(Icons.edit, color: Colors.white),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: _logout,
          icon: const Icon(Icons.logout, color: Colors.white),
        ),
      ],
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'User Profile',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: titleActions,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
          ? const Center(
              child: Text(
                'No user is logged in.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : SafeArea(
              top: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // --- HEADER (avatar + name small) ---
                    _HeaderSection(
                      isEditing: _isEditing,
                      onChangePhoto: _choosePhoto,
                      avatar: _currentAvatarProvider(),
                      displayName: _nameController.text.trim().isEmpty
                          ? 'User'
                          : _nameController.text.trim(),
                    ),
                    const SizedBox(height: 14),

                    // --- PROFILE FIELDS (compact) ---
                    _Card(
                      child: Column(
                        children: [
                          _field(
                            label: 'Name',
                            controller: _nameController,
                            icon: Icons.person,
                            editable: _isEditing && !_isSaving,
                          ),
                          _field(
                            label: 'EmailID',
                            controller: _emailController,
                            icon: Icons.alternate_email,
                            editable: false, // READ-ONLY
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _field(
                            label: 'Location',
                            controller: _locationController,
                            icon: Icons.location_on_outlined,
                            editable: _isEditing && !_isSaving,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- APP SETTINGS ---
                    // --- APP SETTINGS ---
                    _Card(
                      title: 'App Settings',
                      child: Column(
                        children: [
                          _settingsTile(
                            icon: Icons.support_agent_outlined,
                            label: 'Help & Support',
                            onTap: () => _openHelpSupportSheet(),
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.bug_report_outlined,
                            label: 'Report an issue',
                            onTap: () => _launchEmail(
                              subject:
                                  'Issue report from ${_nameController.text.trim().isEmpty ? 'User' : _nameController.text.trim()}',
                              body: 'Describe the issue here...',
                            ),
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.workspace_premium_outlined,
                            label: 'Your subscription',
                            trailing: Text(
                              _subscriptionLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF161922),
                                  title: const Text(
                                    'Subscription',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Current plan: $_subscriptionLabel',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          _divider(),
                          _settingsTile(
                            icon: Icons.autorenew_outlined,
                            label: 'Renew / Update Subscription',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RenewSubscriptionPage(
                                    fireBaseId:
                                        _fireBaseId, // we’ll resolve gyms from this
                                    // preselectedGymId: '...optional...', // pass if you have a selected gym
                                  ),
                                ),
                              );
                            },
                          ),
                          _divider(),
                          // NEW: Version row (non-tappable)
                          _settingsTile(
                            icon: Icons.info_outline,
                            label: 'Version',
                            trailing: const Text(
                              'v1.0.0',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool editable = true,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        enabled: editable,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.white70, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          filled: true,
          fillColor: const Color(0x141A1C23),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.10),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      dense: true,
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing:
          trailing ?? const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));

  void _openHelpSupportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Help & Support',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            _sheetTile(
              icon: Icons.email_outlined,
              label: 'Email support',
              onTap: () {
                Navigator.pop(context);
                _launchEmail(
                  subject: 'Support request',
                  body: 'Hi team,\n\nI need help with...',
                );
              },
            ),
            _sheetTile(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              onTap: () {
                Navigator.pop(context);
                _launchWhatsApp(
                  '+917099187140',
                  message: 'Hi, I need support.',
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final bool isEditing;
  final VoidCallback onChangePhoto;
  final ImageProvider<Object>? avatar;
  final String displayName;

  const _HeaderSection({
    required this.isEditing,
    required this.onChangePhoto,
    required this.avatar,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final sub = TextStyle(
      color: Colors.white.withValues(alpha: 0.7),
      fontSize: 12.5,
    );

    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundImage: avatar,
              backgroundColor: const Color(0xFF2A2F3A),
              child: avatar == null
                  ? const Icon(Icons.person, size: 44, color: Colors.white70)
                  : null,
            ),
            if (isEditing)
              Positioned(
                right: 0,
                bottom: 0,
                child: InkWell(
                  onTap: onChangePhoto,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        if (isEditing) ...[
          const SizedBox(height: 4),
          Text('Tap the camera to change photo', style: sub),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Card({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0x191A1C23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}
