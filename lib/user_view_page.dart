import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

class UserViewPage extends StatefulWidget {
  final String gymName;
  final String gymLocation;
  final int gymCapacity;
  final String? gymId;

  const UserViewPage({
    super.key,
    required this.gymName,
    required this.gymLocation,
    required this.gymCapacity,
    this.gymId,
  });

  @override
  State<UserViewPage> createState() => _UserViewPageState();
}

class _UserViewPageState extends State<UserViewPage> {
  static const String _tableName = 'Users';

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filtered = [];

  bool _loading = true;
  bool _resolvingGymId = false;
  String? _error;
  String? _gymId;

  // Search
  String _searchQuery = "";

  // hide backend/uuid fields from search
  static const Set<String> _hiddenColsLower = {
    'gymid',
    'firebaseid',
    'userid',
    'financeid',
    'id',
    'uuid',
    'created_at',
  };

  // field that we will attach the resolved URL to each row
  static const String _resolvedKey = '_photo_resolved';

  @override
  void initState() {
    super.initState();
    _gymId = widget.gymId;
    if (_gymId == null || _gymId!.isEmpty) {
      _resolveGymIdByNameLocation().then((_) => _fetchUsers());
    } else {
      _fetchUsers();
    }
  }

  Future<void> _resolveGymIdByNameLocation() async {
    setState(() {
      _resolvingGymId = true;
      _error = null;
    });
    try {
      final res = await supa.Supabase.instance.client
          .from('Gyms')
          .select('GymID')
          .eq('GymName', widget.gymName)
          .eq('Location', widget.gymLocation)
          .order('created_at', ascending: false)
          .limit(1);

      if (res is List && res.isNotEmpty) {
        _gymId = (res.first['GymID'] as String?) ?? '';
      } else {
        _error =
            'Could not resolve GymID for "${widget.gymName}" at "${widget.gymLocation}".';
      }
    } catch (e) {
      _error = 'Error resolving GymID: $e';
    } finally {
      setState(() {
        _resolvingGymId = false;
      });
    }
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List data;

      if (_gymId != null && _gymId!.isNotEmpty) {
        data = await supa.Supabase.instance.client
            .from(_tableName)
            .select('*')
            .eq('GymID', _gymId!);
      } else {
        data = const [];
        _error ??=
            'No GymID available to filter Users. (Could not resolve gym by name/location.)';
      }

      final list = List<Map<String, dynamic>>.from(data);

      // Resolve photos to usable URLs (signed if needed)
      await _augmentResolvedPhotoUrls(list);

      setState(() {
        _rows = list;
        _filtered = List<Map<String, dynamic>>.from(_rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            'Failed to load from table $_tableName. ${e.runtimeType}: $e\nTip: Verify table name/case, RLS SELECT policy, and that GymID filter is valid.';
        _loading = false;
      });
    }
  }

  /// Attach a displayable URL to each row under [_resolvedKey].
  /// If the stored value looks like an http(s) URL -> use directly.
  /// If it looks like a storage path -> create a signed URL from 'avatars' bucket.
  Future<void> _augmentResolvedPhotoUrls(
      List<Map<String, dynamic>> rows) async {
    final storage = supa.Supabase.instance.client.storage.from('avatars');

    for (final row in rows) {
      final raw = _rawPhotoField(row);
      if (raw == null) {
        row[_resolvedKey] = null;
        continue;
      }
      final s = raw.trim();
      if (s.isEmpty) {
        row[_resolvedKey] = null;
        continue;
      }

      if (s.startsWith('http://') || s.startsWith('https://')) {
        // looks like a public URL
        row[_resolvedKey] = s;
        continue;
      }

      // treat as storage path, e.g. users/<uid>/<ts>.jpg
      try {
        final signed = await storage.createSignedUrl(s, 3600); // 1h
        // Supabase 2.x returns a SignedUrl with .signedUrl
        final url = (signed as dynamic).signedUrl as String?;
        row[_resolvedKey] = url ?? s; // fallback to raw
      } catch (_) {
        // fallback to a public url (works if bucket is public)
        row[_resolvedKey] = storage.getPublicUrl(s);
      }
    }
  }

  /// Read a likely photo field from the row.
  String? _rawPhotoField(Map<String, dynamic> row) {
    for (final key in const [
      'PhotoURL',
      'PhotoUrl',
      'AvatarURL',
      'AvatarUrl',
      'Photo',
      'Avatar',
      'PhotoPath',
      'AvatarPath',
    ]) {
      final v = row[key];
      if (v == null) continue;
      final s = v.toString();
      if (s.trim().isNotEmpty) return s;
    }
    return null;
  }

  bool _isHiddenColumn(String name) {
    final l = name.toLowerCase();
    if (_hiddenColsLower.contains(l)) return true;
    if (l.endsWith('id') && l != 'email' && l != 'emailid') return true;
    return false;
  }

  void _applySearch() {
    setState(() {
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) {
        _filtered = List<Map<String, dynamic>>.from(_rows);
        return;
      }
      _filtered = _rows.where((row) {
        return row.entries
            .where((e) => !_isHiddenColumn(e.key))
            .any((e) => (e.value ?? '').toString().toLowerCase().contains(q));
      }).toList();
    });
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.isEmpty ? '' : parts.first[0];
    return '${parts.first.isNotEmpty ? parts.first[0] : ''}${parts.last.isNotEmpty ? parts.last[0] : ''}';
  }

  String? _photoUrl(Map<String, dynamic> row) {
    final resolved = row[_resolvedKey];
    if (resolved != null && resolved.toString().trim().isNotEmpty) {
      return resolved.toString().trim();
    }
    // fallback to raw (http/s url case)
    for (final key in const [
      'PhotoURL',
      'PhotoUrl',
      'AvatarURL',
      'AvatarUrl',
      'Photo',
      'Avatar'
    ]) {
      final v = row[key];
      if (v != null && v.toString().trim().isNotEmpty) {
        final s = v.toString().trim();
        if (s.startsWith('http://') || s.startsWith('https://')) return s;
      }
    }
    return null;
  }

  String _phone(Map<String, dynamic> row) {
    for (final key in const ['Phone', 'Mobile', 'Contact', 'PhoneNumber']) {
      final v = row[key];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '-';
  }

  void _openPhotoViewer(String url, String name) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    clipBehavior: Clip.none,
                    minScale: 0.5,
                    maxScale: 4,
                    child: Hero(
                      tag: url,
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.black26,
                          child: const Text(
                            'Could not load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 16,
                  right: 16,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const SizedBox.shrink(),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _fetchUsers,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _resolvingGymId
          ? const Center(child: CircularProgressIndicator())
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tabs: Dashboard (back) + active User view (highlight)
                          Row(
                            children: [
                              GlassLabelButton(
                                text: '${widget.gymName} • Dashboard',
                                active: false,
                                onTap: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 8),
                              GlassLabelButton(
                                text: '${widget.gymName} • User view mode',
                                active: true,
                                onTap: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Search across all fields (same as dashboard)
                          TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "Search across all fields...",
                              hintStyle: const TextStyle(color: Colors.white54),
                              filled: true,
                              fillColor: const Color(0xFF1A1C23),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.white54),
                            ),
                            onChanged: (value) {
                              _searchQuery = value;
                              _applySearch();
                            },
                          ),
                          const SizedBox(height: 12),

                          // Users list: photo (left) + two lines (name, phone)
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1C23),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: _filtered.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text(
                                      'No users to display.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _filtered.length,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color:
                                          Colors.white.withValues(alpha: 0.08),
                                    ),
                                    itemBuilder: (context, index) {
                                      final row = _filtered[index];
                                      final name =
                                          (row['Name'] ?? '-').toString();
                                      final phone = _phone(row);
                                      final photo = _photoUrl(row);

                                      return ListTile(
                                        onTap: () {
                                          if (photo != null &&
                                              photo.isNotEmpty) {
                                            _openPhotoViewer(photo, name);
                                          }
                                        },
                                        leading: _UserAvatar(
                                          name: name,
                                          photoUrl: photo,
                                          heroTag: photo ?? name,
                                        ),
                                        title: Text(
                                          name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          phone,
                                          style: const TextStyle(
                                              color: Colors.white70),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        dense: false,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
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

/// Active tab = white bg + black text; inactive = glassy
class GlassLabelButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool active;
  const GlassLabelButton({
    super.key,
    required this.text,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    if (active) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEC), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Text(
            '',
            // We'll overlay the label below; alternately you can put [text] here directly.
          ),
        ),
      );
    }

    final borderAlpha = 0.18;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x33FFFFFF), Color(0x1AFFFFFF)],
              ),
              border: Border.all(
                color: const Color(0xFFFFFFFF).withValues(alpha: borderAlpha),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final Object heroTag;
  const _UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    required this.heroTag,
  });

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.isEmpty ? '' : parts.first[0];
    return '${parts.first.isNotEmpty ? parts.first[0] : ''}${parts.last.isNotEmpty ? parts.last[0] : ''}';
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Hero(
        tag: heroTag,
        child: CircleAvatar(
          radius: 20,
          backgroundImage: NetworkImage(photoUrl!),
          backgroundColor: const Color(0xFF2A2F3A),
        ),
      );
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF2A2F3A),
      child: Text(
        _initials(name).toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
