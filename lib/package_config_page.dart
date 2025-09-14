import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

import 'glass_ui.dart';

class PackageConfigPage extends StatefulWidget {
  final String fireBaseId;
  const PackageConfigPage({super.key, required this.fireBaseId});

  @override
  State<PackageConfigPage> createState() => _PackageConfigPageState();
}

class _PackageConfigPageState extends State<PackageConfigPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = [];

  get _client => supa.Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _client
          .from('Packages')
          .select(
            'PackageID, Name, Type, DurationMonths, Price, Features, IsActive, IsDefault, created_at',
          )
          .eq('FireBaseID', widget.fireBaseId)
          .order('created_at', ascending: true);

      setState(() {
        _packages = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      });
    } catch (e) {
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
        });
    }
  }

  Future<void> _deletePackage(String id) async {
    try {
      await _client.from('Packages').delete().eq('PackageID', id);
      await _loadPackages();
    } catch (e) {
      _snack('Failed to delete: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _restoreDefaults() async {
    final defaults = _defaultPackages();
    try {
      // Only insert ones missing by Name (per FireBaseID).
      final existingNames = _packages
          .map((p) => (p['Name'] ?? '').toString())
          .toSet();
      final toInsert = defaults
          .where((d) => !existingNames.contains(d['Name']))
          .toList();

      if (toInsert.isEmpty) {
        _snack('Defaults already present.');
        return;
      }
      for (final row in toInsert) {
        row['FireBaseID'] = widget.fireBaseId;
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
        'DurationMonths': null, // rolling
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

  Future<void> _openEditor({Map<String, dynamic>? pkg}) async {
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
                ),
                const SizedBox(height: 10),
                glassyField(
                  controller: priceC,
                  label: 'Price',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _req,
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
                  await _client
                      .from('Packages')
                      .update(payload)
                      .eq('PackageID', pkg!['PackageID']);
                } else {
                  payload['FireBaseID'] = widget.fireBaseId;
                  await _client.from('Packages').insert(payload);
                }
                if (context.mounted) Navigator.of(ctx).pop();
                await _loadPackages();
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
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        title: const Text('Configure Packages'),
        backgroundColor: const Color(0xFF0D0E11),
        actions: [
          IconButton(
            tooltip: 'Restore defaults',
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restore),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadPackages,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        label: const Text('Add Package'),
        icon: const Icon(Icons.add),
      ),
      body: _loading
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
                      ? (p['Features'] as List)
                      : [];

                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
                                  'Price: ₹${(price ?? 0).toString()}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: -6,
                                  children: [
                                    for (final f in features)
                                      Chip(
                                        label: Text(f.toString()),
                                        visualDensity: VisualDensity.compact,
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
                                                onPressed: () => Navigator.pop(
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
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFE53935,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: () => Navigator.pop(
                                                  context,
                                                  true,
                                                ),
                                                child: const Text('Delete'),
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
              'Add your first package or restore the defaults to get started.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _restoreDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Restore default packages'),
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
