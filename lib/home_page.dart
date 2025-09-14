import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:google_sign_in/google_sign_in.dart';

import 'profile_page.dart';
import 'gym_card.dart'; // GymCard + showAddGymDialog
import 'trainers_card.dart'; // TrainersCard
import 'muscle_map.dart';

class HomePage extends StatefulWidget {
  final String fireBaseId;

  const HomePage({super.key, required this.fireBaseId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Box gymsBox;
  List<Map<String, dynamic>> userGyms = [];

  supa.User? _user;
  bool _syncing = false;

  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    gymsBox = Hive.box('gymsBox');
    _user = _client.auth.currentUser;
    _loadGyms();
    _syncGyms();
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
  Future<List<Map<String, dynamic>>> _fetchRemoteGyms() async {
    final rows = await _client
        .from('Gyms')
        .select('GymID,GymName,Location,Capacity,FireBaseID,created_at')
        .eq('FireBaseID', widget.fireBaseId)
        .order('created_at', ascending: true);

    return (rows as List)
        .map(
          (r) => {
            'GymID': r['GymID'] as String?,
            'name': r['GymName'] as String? ?? '',
            'location': r['Location'] as String? ?? '',
            'capacity': (r['Capacity'] is int)
                ? r['Capacity'] as int
                : int.tryParse('${r['Capacity']}') ?? 0,
          },
        )
        .toList();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
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

  String? _avatarUrl(supa.User? u) {
    final md = u?.userMetadata ?? {};
    final fromAvatar = md['avatar_url'];
    final fromPicture = md['picture'];
    if (fromAvatar is String && fromAvatar.isNotEmpty) return fromAvatar;
    if (fromPicture is String && fromPicture.isNotEmpty) return fromPicture;
    return null;
  }

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
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.refresh),
            onPressed: _syncing ? null : _syncGyms,
          ),
          if (photoUrl != null && photoUrl.isNotEmpty)
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
                child: CircleAvatar(backgroundImage: NetworkImage(photoUrl)),
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
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => showAddGymDialog(
                        context: context,
                        client: _client,
                        fireBaseId: widget.fireBaseId,
                        allGyms: userGyms,
                        gymsBox: gymsBox,
                        onReplaceGyms: (g) => setState(() => userGyms = g),
                        onAfterChange: _syncGyms,
                      ),
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
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => showAddGymDialog(
                        context: context,
                        client: _client,
                        fireBaseId: widget.fireBaseId,
                        allGyms: userGyms,
                        gymsBox: gymsBox,
                        onReplaceGyms: (g) => setState(() => userGyms = g),
                        onAfterChange: _syncGyms,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------- HORIZONTAL SCROLLER of full-width gym cards ----------
                  SizedBox(
                    height: 240,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenW = MediaQuery.of(context).size.width;
                        const horizontalPadding = 24.0;
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
                              child: GymCard(
                                gym: gym,
                                index: index,
                                allGyms: userGyms,
                                fireBaseId: widget.fireBaseId,
                                gymsBox: gymsBox,
                                client: _client,
                                onReplaceGyms: (g) =>
                                    setState(() => userGyms = g),
                                onAfterChange: _syncGyms,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ---------- Trainers card (single wide) ----------
                  SizedBox(
                    height: 160,
                    child: TrainersCard(
                      fireBaseId: widget.fireBaseId,
                      client: _client,
                      gymsWithId: userGyms
                          .where(
                            (g) =>
                                (g['GymID'] is String) &&
                                (g['GymID'] as String).isNotEmpty,
                          )
                          .map((g) => Map<String, dynamic>.from(g))
                          .toList(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ---------- Muscle Map card (single wide) ----------
                  SizedBox(
                    height: 160,
                    child: MuscleMapCard(fireBaseId: widget.fireBaseId),
                  ),
                ],
              ),
      ),
    );
  }
}
