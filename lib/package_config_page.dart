// lib/package_config_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'glass_ui.dart';

class PackageConfigPage extends StatefulWidget {
  /// Pass the stable owner id from Fire.AuthUserID (uuid as text)
  final String fireBaseId;
  const PackageConfigPage({super.key, required this.fireBaseId});

  @override
  State<PackageConfigPage> createState() => _PackageConfigPageState();
}

class _PackageConfigPageState extends State<PackageConfigPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = [];

  supa.RealtimeChannel? _rtChannel;
  supa.SupabaseClient get _client => supa.Supabase.instance.client;

  // PRIMARY owner id we will query by; starts with the prop you pass
  String get _ownerIdProp => widget.fireBaseId;
  String? _effectiveOwnerId; // can be updated after Fire mapping check

  // debug counters
  int _debugAnyCount = -1;
  int _debugOwnerCount = -1;
  String? _debugEmail;
  String? _debugFireMappedId;

  String _formatInr(num amount) {
    final hasFraction = (amount % 1) != 0;
    final fmt = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: hasFraction ? 2 : 0,
    );
    return fmt.format(amount);
  }

  @override
  void initState() {
    super.initState();
    _effectiveOwnerId = _ownerIdProp;
    _debugEmail = _client.auth.currentUser?.email;
    debugPrint('🔑 PackageConfigPage ownerIdProp=${_ownerIdProp}');
    _loadPackages();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }

  void _subscribeRealtime() {
    final tid = _effectiveOwnerId ?? _ownerIdProp;
    _rtChannel = _client
        .channel('public:Packages:$tid')
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.all,
          schema: 'public',
          table: 'Packages',
          filter: supa.PostgresChangeFilter(
            type: supa.PostgresChangeFilterType.eq,
            column: 'AuthUserID',
            value: tid,
          ),
          callback: (_) async => await _loadPackages(),
        )
        .subscribe();
  }

  void _unsubscribeRealtime() {
    if (_rtChannel != null) {
      _client.removeChannel(_rtChannel!);
      _rtChannel = null;
    }
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // (A) probe: are there ANY rows at all?
      final anyRows = await _client
          .from('Packages')
          // NEW
          .select('PackageID')
          .limit(5);
      _debugAnyCount = (anyRows as List).length;

      // (B) try with the passed owner id
      final ownerIdTry = _effectiveOwnerId ?? _ownerIdProp;
      final rowsOwner = await _client
          .from('Packages')
          .select(
            'PackageID, AuthUserID, Name, Type, DurationMonths, Price, Features, IsActive, IsDefault, created_at',
          )
          .eq('AuthUserID', ownerIdTry)
          .order('IsDefault', ascending: false)
          .order('created_at', ascending: true);

      final listOwner = (rowsOwner as List)
          .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      _debugOwnerCount = listOwner.length;

      if (listOwner.isNotEmpty) {
        setState(() {
          _packages = listOwner;
          _effectiveOwnerId = ownerIdTry;
        });
        debugPrint(
          '✅ Loaded ${listOwner.length} packages for $_effectiveOwnerId',
        );
        return;
      }

      // (C) nothing matched ownerIdTry — attempt Fire mapping via email
      final email = _client.auth.currentUser?.email;
      _debugEmail = email;

      if (email != null && email.isNotEmpty) {
        final fireRows = await _client
            .from('Fire')
            .select('AuthUserID')
            .eq('EmailID', email)
            .limit(1);
        if (fireRows is List && fireRows.isNotEmpty) {
          final mappedId = (fireRows.first as Map)['AuthUserID']?.toString();
          _debugFireMappedId = mappedId;

          if (mappedId != null &&
              mappedId.isNotEmpty &&
              mappedId != ownerIdTry) {
            // Try again with Fire-mapped id
            final rowsMapped = await _client
                .from('Packages')
                .select(
                  'PackageID, AuthUserID, Name, Type, DurationMonths, Price, Features, IsActive, IsDefault, created_at',
                )
                .eq('AuthUserID', mappedId)
                .order('IsDefault', ascending: false)
                .order('created_at', ascending: true);

            final listMapped = (rowsMapped as List)
                .map<Map<String, dynamic>>(
                  (r) => Map<String, dynamic>.from(r as Map),
                )
                .toList();

            if (listMapped.isNotEmpty) {
              setState(() {
                _packages = listMapped;
                _effectiveOwnerId =
                    mappedId; // adopt the ID that actually has data
              });
              debugPrint(
                '✅ Loaded ${listMapped.length} packages for Fire-mapped $_effectiveOwnerId',
              );
              // Re-subscribe realtime on the effective id
              _unsubscribeRealtime();
              _subscribeRealtime();
              return;
            }
          }
        }
      }

      // (D) Still empty: set empty state
      setState(() {
        _packages = const [];
      });
      debugPrint(
        '⚠️ No packages found. anyCount=$_debugAnyCount owner=${ownerIdTry} email=$_debugEmail fireMapped=$_debugFireMappedId',
      );
    } catch (e) {
      setState(() {
        _error = '$e';
      });
      debugPrint('❌ _loadPackages error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmRestoreDefaults() async {
    final tid = _effectiveOwnerId ?? _ownerIdProp;

    final defaults = _defaultPackages();
    final existingNames = _packages
        .map((p) => (p['Name'] ?? '').toString())
        .toSet();
    final toInsert = defaults
        .where((d) => !existingNames.contains(d['Name']))
        .toList();

    final count = toInsert.length;
    if (count == 0) {
      _snack('Defaults already present.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: const Text(
          'Restore default packages?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will add $count default package${count == 1 ? '' : 's'} for your account.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2F3A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add defaults'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _restoreDefaultsInternal(tid, toInsert);
    }
  }

  Future<void> _restoreDefaultsInternal(
    String tid,
    List<Map<String, dynamic>> toInsert,
  ) async {
    try {
      for (final row in toInsert) {
        row['AuthUserID'] = tid;
      }
      await _client.from('Packages').insert(toInsert);
      await _loadPackages();
      _snack('Default packages added.');
    } catch (e) {
      _snack('Failed to add defaults: $e');
    }
  }

  List<Map<String, dynamic>> _defaultPackages() {
    return [
      {
        'Name': 'Standard – 1 Month',
        'Type': 'Standard',
        'DurationMonths': 1,
        'Price': 999.00,
        'Features': ['Gym access', 'General floor assistance'],
        'IsActive': true,
        'IsDefault': true,
      },
      {
        'Name': 'Standard – 3 Months',
        'Type': 'Standard',
        'DurationMonths': 3,
        'Price': 2499.00,
        'Features': ['Gym access', 'General floor assistance'],
        'IsActive': true,
        'IsDefault': true,
      },
      {
        'Name': 'Standard – 6 Months',
        'Type': 'Standard',
        'DurationMonths': 6,
        'Price': 4499.00,
        'Features': ['Gym access', 'General floor assistance'],
        'IsActive': true,
        'IsDefault': true,
      },
      {
        'Name': 'Premium Personal Training',
        'Type': 'Premium',
        'DurationMonths': null,
        'Price': 5999.00,
        'Features': [
          '1:1 Coach (3x/week)',
          'Personalized plan',
          'Form correction',
        ],
        'IsActive': true,
        'IsDefault': true,
      },
    ];
  }

  Future<void> _deletePackage(String id) async {
    final tid = _effectiveOwnerId ?? _ownerIdProp;

    final before = List<Map<String, dynamic>>.from(_packages);
    setState(() {
      _packages = _packages.where((p) => p['PackageID'] != id).toList();
    });

    try {
      await _client
          .from('Packages')
          .delete()
          .eq('PackageID', id)
          .eq('AuthUserID', tid);
      await _loadPackages();
    } catch (e) {
      setState(() {
        _packages = before;
      });
      _snack('Failed to delete: $e');
    }
  }

  Future<void> _optimisticUpdate(String id, Map<String, dynamic> patch) async {
    final tid = _effectiveOwnerId ?? _ownerIdProp;

    final idx = _packages.indexWhere((p) => p['PackageID'] == id);
    if (idx == -1) {
      try {
        await _client
            .from('Packages')
            .update(patch)
            .eq('PackageID', id)
            .eq('AuthUserID', tid);
      } catch (e) {
        _snack('Update failed: $e');
      }
      await _loadPackages();
      return;
    }

    final before = List<Map<String, dynamic>>.from(_packages);
    final updated = Map<String, dynamic>.from(_packages[idx])..addAll(patch);

    setState(() {
      final copy = List<Map<String, dynamic>>.from(_packages);
      copy[idx] = updated;
      _packages = copy;
    });

    try {
      await _client
          .from('Packages')
          .update(patch)
          .eq('PackageID', id)
          .eq('AuthUserID', tid);
      await _loadPackages();
    } catch (e) {
      setState(() {
        _packages = before;
      });
      _snack('Update failed: $e');
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? pkg}) async {
    final tid = _effectiveOwnerId ?? _ownerIdProp;

    final isEdit = pkg != null;

    final nameC = TextEditingController(text: pkg?['Name']?.toString() ?? '');
    String type = (pkg?['Type']?.toString().isNotEmpty ?? false)
        ? pkg!['Type'].toString()
        : 'Standard';
    final durationC = TextEditingController(
      text: (pkg?['DurationMonths'] == null) ? '' : '${pkg!['DurationMonths']}',
    );
    final priceC = TextEditingController(
      text: (pkg?['Price']?.toString() ?? ''),
    );
    final featuresC = TextEditingController(
      text: _featuresToText(pkg?['Features']),
    );
    bool isActive = (pkg?['IsActive'] ?? true) == true;

    final formKey = GlobalKey<FormState>();
    String? _req(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;
    String? _reqNum(String? v) {
      if (v == null || v.trim().isEmpty) return 'Required';
      final n = num.tryParse(v.trim());
      if (n == null) return 'Not a number';
      if (n < 0) return 'Must be ≥ 0';
      return null;
    }

    String? _durationCheck(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = int.tryParse(v.trim());
      if (n == null) return 'Enter whole months';
      if (n <= 0) return 'Must be ≥ 1';
      return null;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: Text(
          isEdit ? 'Edit Package' : 'Add Package',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                glassyField(controller: nameC, label: 'Name', validator: _req),
                const SizedBox(height: 10),
                glassDropdown<String>(
                  label: 'Type',
                  value: type,
                  items: const ['Standard', 'Premium'],
                  onChanged: (v) {
                    if (v != null) type = v;
                  },
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: durationC,
                  label: 'Duration (months) — leave empty for flexible',
                  keyboardType: TextInputType.number,
                  validator: _durationCheck,
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: priceC,
                  label: 'Price',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _reqNum,
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: featuresC,
                  label: 'Features (comma separated)',
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: isActive,
                  onChanged: (v) => isActive = v,
                  title: const Text(
                    'Active',
                    style: TextStyle(color: Colors.white),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2A2F3A),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final payload = <String, dynamic>{
                  'Name': nameC.text.trim(),
                  'Type': type,
                  'DurationMonths': durationC.text.trim().isEmpty
                      ? null
                      : int.tryParse(durationC.text.trim()),
                  'Price': double.tryParse(priceC.text.trim()) ?? 0.0,
                  'Features': _textToFeatures(featuresC.text),
                  'IsActive': isActive,
                };

                if (isEdit) {
                  final editId = pkg?['PackageID'] as String?;
                  if (editId != null) {
                    await _optimisticUpdate(editId, payload);
                  } else {
                    _snack('Missing PackageID for update.');
                  }
                } else {
                  payload['AuthUserID'] = tid;
                  await _client.from('Packages').insert(payload);
                  await _loadPackages();
                }

                if (context.mounted) Navigator.of(ctx).pop();
              } catch (e) {
                _snack('Save failed: $e');
              }
            },
            child: Text(isEdit ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  String _featuresToText(dynamic v) {
    if (v == null) return '';
    try {
      final list = (v as List).map((e) => e.toString()).toList();
      return list.join(', ');
    } catch (_) {
      return v.toString();
    }
  }

  List<String> _textToFeatures(String s) {
    return s
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final debugStrip = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Text(
        'ownerProp=${_ownerIdProp}  effective=${_effectiveOwnerId ?? _ownerIdProp}  '
        'any=${_debugAnyCount >= 0 ? _debugAnyCount : '?'}  '
        'match=${_debugOwnerCount >= 0 ? _debugOwnerCount : '?'}  '
        'email=${_debugEmail ?? '-'}  fireMapped=${_debugFireMappedId ?? '-'}',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        title: const Text('Configure Packages'),
        backgroundColor: const Color(0xFF0D0E11),
        actions: [
          IconButton(
            tooltip: 'Reload from Supabase',
            onPressed: _loadPackages,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'restore') _confirmRestoreDefaults();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem<String>(
                value: 'restore',
                child: Text('Restore default packages…'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        label: const Text('Add Package'),
        icon: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          debugStrip, // always visible
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  )
                : _packages.isEmpty
                ? _emptyState()
                : RefreshIndicator(
                    onRefresh: _loadPackages,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (ctx, i) {
                        final p = _packages[i];
                        final id = p['PackageID'] as String?;
                        final name = p['Name']?.toString() ?? '';
                        final type = p['Type']?.toString() ?? '';
                        final dur = p['DurationMonths'];
                        final price = p['Price'];
                        final features = (p['Features'] is List)
                            ? List.of(p['Features'])
                            : const <dynamic>[];

                        return GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2A2F3A),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              type,
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        dur == null
                                            ? 'Flexible duration'
                                            : 'Duration: $dur month${dur == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Price: ${_formatInr((price ?? 0) is num ? (price ?? 0) as num : num.tryParse((price ?? 0).toString()) ?? 0)}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      features.isEmpty
                                          ? const Text(
                                              'No features',
                                              style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12,
                                              ),
                                            )
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: -6,
                                              children: [
                                                for (final f in features)
                                                  Chip(
                                                    label: Text(f.toString()),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: 'Edit',
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () => _openEditor(pkg: p),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: id == null
                                          ? null
                                          : () async {
                                              final ok = await showDialog<bool>(
                                                context: context,
                                                builder: (_) => AlertDialog(
                                                  backgroundColor: const Color(
                                                    0xFF111214,
                                                  ),
                                                  title: const Text(
                                                    'Delete package?',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  content: const Text(
                                                    'This will remove the package. This action cannot be undone.',
                                                    style: TextStyle(
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style:
                                                          ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                  0xFFE53935,
                                                                ),
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        'Delete',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (ok == true) {
                                                await _deletePackage(id);
                                              }
                                            },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemCount: _packages.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No packages yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reload to fetch again, or add/restore packages.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadPackages,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _confirmRestoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Restore default packages…'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Add package'),
            ),
          ],
        ),
      ),
    );
  }
}
