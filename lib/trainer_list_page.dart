import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

class TrainerListPage extends StatefulWidget {
  final String fireBaseId;
  const TrainerListPage({super.key, required this.fireBaseId});

  @override
  State<TrainerListPage> createState() => _TrainerListPageState();
}

class _TrainerListPageState extends State<TrainerListPage> {
  final _client = supa.Supabase.instance.client;

  bool _loading = true;
  String? _error;

  /// raw trainer rows
  List<Map<String, dynamic>> _trainers = [];

  /// trainerId -> list of gym names
  final Map<String, List<String>> _trainerGyms = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1) trainers owned by this FirebaseID
      final rows = await _client
          .from('Trainer')
          .select(
              'TrainerID, Name, Age, Qualification, PhotoURL, JoiningDate, Height, Weight, BMI, created_at')
          .eq('FirebaseID', widget.fireBaseId)
          .order('created_at', ascending: true);

      final trainers = List<Map<String, dynamic>>.from(rows as List);

      // 2) links from TrainerGyms for these trainers
      final trainerIds = trainers
          .map((t) => (t['TrainerID'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      List tg = [];
      if (trainerIds.isNotEmpty) {
        // ---- FIX: use PostgREST 'in' filter string instead of .in_()
        final quoted = trainerIds.map((e) => '"$e"').join(',');
        tg = await _client
            .from('TrainerGyms')
            .select('TrainerID,GymID')
            .filter('TrainerID', 'in', '($quoted)');
      }

      // 3) fetch gym names for those gym IDs
      final gymIds = (tg as List)
          .map((e) => (e['GymID'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      Map<String, String> gymNameById = {};
      if (gymIds.isNotEmpty) {
        // ---- FIX: same here, use .filter('GymID','in','("a","b")')
        final quoted = gymIds.map((e) => '"$e"').join(',');
        final gyms = await _client
            .from('Gyms')
            .select('GymID,GymName')
            .filter('GymID', 'in', '($quoted)');

        for (final g in (gyms as List)) {
          final id = g['GymID'] as String?;
          final name = (g['GymName'] ?? '') as String;
          if (id != null && id.isNotEmpty) {
            gymNameById[id] = name;
          }
        }
      }

      // 4) build trainerId -> gym names
      _trainerGyms.clear();
      for (final link in (tg as List)) {
        final tId = link['TrainerID'] as String?;
        final gId = link['GymID'] as String?;
        if (tId == null || gId == null) continue;
        final name = gymNameById[gId] ?? 'Unknown gym';
        _trainerGyms.putIfAbsent(tId, () => []).add(name);
      }

      setState(() {
        _trainers = trainers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load trainers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(String trainerId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        content: Text(
          'Delete trainer "$name"?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      // If your TrainerGyms has ON DELETE CASCADE (recommended), this is enough:
      await _client
          .from('Trainer')
          .delete()
          .eq('TrainerID', trainerId)
          .select();

      // Local refresh
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "$name"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const Text('Trainers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                )
              : _trainers.isEmpty
                  ? const Center(
                      child: Text('No trainers yet.',
                          style: TextStyle(color: Colors.white70)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _trainers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _trainers[i];
                        final id = (t['TrainerID'] as String?) ?? '';
                        final name = (t['Name'] ?? '-') as String;
                        final qual = (t['Qualification'] ?? '') as String;
                        final photo = (t['PhotoURL'] ?? '') as String;
                        final gyms = _trainerGyms[id] ?? const [];

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1C23),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF2A2F3A),
                              backgroundImage: (photo.isNotEmpty)
                                  ? NetworkImage(photo)
                                  : null,
                              child: (photo.isEmpty)
                                  ? const Icon(Icons.person,
                                      color: Colors.white70)
                                  : null,
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (qual.isNotEmpty)
                                  Text(qual,
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                if (gyms.isNotEmpty) const SizedBox(height: 6),
                                if (gyms.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: gyms
                                        .map((g) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF111214),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                    color:
                                                        const Color(0x22FFFFFF),
                                                    width: 1),
                                              ),
                                              child: Text(
                                                g,
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              color: const Color(0xFF1A1C23),
                              iconColor: Colors.white,
                              onSelected: (v) async {
                                if (v == 'delete') {
                                  await _confirmDelete(id, name);
                                } else if (v == 'edit') {
                                  // TODO: wire to an edit dialog (prefill & update)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Edit coming soon')),
                                  );
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit',
                                      style: TextStyle(color: Colors.white)),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
