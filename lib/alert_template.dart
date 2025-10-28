import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import 'glass_ui.dart';
import 'app_shell.dart'; // <-- header & footer

class _ChipForDaysLeft extends StatelessWidget {
  final int value;
  const _ChipForDaysLeft({required this.value});

  Color _bg() {
    if (value <= 1) return const Color(0xFFEF5350);
    if (value <= 7) return const Color(0xFFFFA726);
    return const Color(0xFF66BB6A);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$value d',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Page: Configure Alerting Template (GLOBAL)
/// - Applies to ALL users under this AuthUserID
/// - Expiry = JoinDate + 1 month
/// - Choose lead times & channels; see previews of who would be alerted today and in the next 30 days.
class AlertTemplatePage extends StatefulWidget {
  final String fireBaseId;
  const AlertTemplatePage({super.key, required this.fireBaseId});

  @override
  State<AlertTemplatePage> createState() => _AlertTemplatePageState();
}

class _AlertTemplatePageState extends State<AlertTemplatePage> {
  final DateFormat _df = DateFormat('yyyy-MM-dd');

  // Lead times (days before OR on the day)
  final Map<int, bool> _leadDays = {
    21: false,
    14: true,
    7: true,
    3: true,
    1: true,
    0: true, // on the day
  };

  final Set<String> _modes = {'WhatsApp', 'Email', 'SMS'};
  final Set<String> _selectedModes = {'WhatsApp', 'SMS'};
  TimeOfDay _sendTime = const TimeOfDay(hour: 10, minute: 0);

  // Templates (placeholders: {name}, {expiryDate}, {daysLeft}, {gymName})
  final TextEditingController _waTemplate = TextEditingController(
    text:
        'Hi {name}, this is a reminder from {gymName}. Your subscription expires on {expiryDate} ({daysLeft} day(s) left). Please renew to avoid interruption.',
  );
  final TextEditingController _smsTemplate = TextEditingController(
    text:
        'Reminder: {name} subscription ends {expiryDate} ({daysLeft}d). – {gymName}',
  );
  final TextEditingController _emailSubject = TextEditingController(
    text: 'Your {gymName} membership expires on {expiryDate}',
  );
  final TextEditingController _emailBody = TextEditingController(
    text:
        'Hello {name},\\n\\nYour {gymName} subscription is set to expire on {expiryDate} ({daysLeft} day(s) remaining). '
        'Please renew at your earliest convenience to keep access active.\\n\\nThanks,\\n{gymName} Team',
  );

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];

  // Derived previews
  List<Map<String, dynamic>> _matchesToday = [];
  List<Map<String, dynamic>> _matchesNext30 = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = supa.Supabase.instance.client;
      final data = await client
          .from('Users')
          .select('UserID, Name, Phone, Email, JoinDate, GymID, created_at')
          .eq('AuthUserID', widget.fireBaseId)
          .order('created_at', ascending: true);

      _users = List<Map<String, dynamic>>.from(data);
      _recomputePreviews();
    } catch (e) {
      _error = 'Failed to load users: $e';
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        try {
          return DateTime.parse(v.split('T').first);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Expiry = (JoinDate) + 1 month
  DateTime? _expiryDateFor(Map<String, dynamic> user) {
    final join = _parseDate(user['JoinDate']);
    if (join == null) return null;
    final month = join.month + 1;
    final year = join.year + ((month - 1) ~/ 12);
    final newMonth = ((month - 1) % 12) + 1;
    final day = join.day;
    return DateTime(year, newMonth, day);
  }

  int? _daysLeft(DateTime? expiry) {
    if (expiry == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return expiry.difference(today).inDays;
  }

  String _fmt(DateTime? d) => d == null ? '—' : _df.format(d);

  void _recomputePreviews() {
    final selectedLead = _leadDays.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toSet();

    final matchesToday = <Map<String, dynamic>>[];
    final matchesNext = <Map<String, dynamic>>[];

    for (final u in _users) {
      final expiry = _expiryDateFor(u);
      if (expiry == null) continue;
      final daysLeft = _daysLeft(expiry);
      if (daysLeft == null) continue;

      final row = {
        'UserID': u['UserID'],
        'Name': (u['Name'] ?? '').toString(),
        'Phone': (u['Phone'] ?? '').toString(),
        'Email': (u['Email'] ?? '').toString(),
        'JoinDate': _fmt(_parseDate(u['JoinDate'])),
        'ExpiryDate': _fmt(expiry),
        'DaysLeft': daysLeft,
      };

      if (selectedLead.contains(daysLeft)) {
        matchesToday.add(row);
      }

      if (daysLeft >= 0 && daysLeft <= 30 && selectedLead.contains(daysLeft)) {
        matchesNext.add(row);
      }
    }

    matchesToday.sort(
      (a, b) => (a['DaysLeft'] as int).compareTo(b['DaysLeft'] as int),
    );
    matchesNext.sort(
      (a, b) => (a['DaysLeft'] as int).compareTo(b['DaysLeft'] as int),
    );

    setState(() {
      _matchesToday = matchesToday;
      _matchesNext30 = matchesNext;
    });
  }

  String _renderTemplateFor(String template, Map<String, dynamic> u) {
    final name = (u['Name'] ?? 'Member').toString();
    final expiryStr = (u['ExpiryDate'] ?? '—').toString();
    final daysLeft = (u['DaysLeft'] ?? '—').toString();
    const gymName = 'Your Gym';
    return template
        .replaceAll('{name}', name.isEmpty ? 'Member' : name)
        .replaceAll('{gymName}', gymName)
        .replaceAll('{expiryDate}', expiryStr)
        .replaceAll('{daysLeft}', daysLeft);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sendTime,
    );
    if (picked != null) {
      setState(() => _sendTime = picked);
    }
  }

  Future<void> _saveTemplate() async {
    try {
      final box = await Hive.openBox('alertTemplatesBox');
      final payload = {
        'created_at': DateTime.now().toIso8601String(),
        'fireBaseId': widget.fireBaseId,
        'leadDays': _leadDays.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList(),
        'modes': _selectedModes.toList(),
        'sendTime': {'h': _sendTime.hour, 'm': _sendTime.minute},
        'templates': {
          'whatsapp': _waTemplate.text,
          'sms': _smsTemplate.text,
          'emailSubject': _emailSubject.text,
          'emailBody': _emailBody.text,
        },
      };
      final id = await box.add(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Template saved (id: $id)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _showAllUsersPopup() async {
    final list = <Map<String, dynamic>>[];
    for (final u in _users) {
      final expiry = _expiryDateFor(u);
      final daysLeft = _daysLeft(expiry);
      list.add({
        'Name': (u['Name'] ?? '').toString(),
        'Phone': (u['Phone'] ?? '').toString(),
        'Email': (u['Email'] ?? '').toString(),
        'JoinDate': _fmt(_parseDate(u['JoinDate'])),
        'ExpiryDate': _fmt(expiry),
        'DaysLeft': daysLeft,
      });
    }
    list.sort((a, b) {
      final da = a['DaysLeft'] as int?;
      final db = b['DaysLeft'] as int?;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF0B0C0F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500, minWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'All users & days left',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0x332A2F3A)),
                Expanded(
                  child: Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0x332A2F3A)),
                      itemBuilder: (_, i) {
                        final u = list[i];
                        final daysLeft = u['DaysLeft'];
                        return ListTile(
                          dense: true,
                          title: Text(
                            u['Name'] ?? '',
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'Join: ${u['JoinDate']}  •  Expiry: ${u['ExpiryDate']}  •  DaysLeft: ${daysLeft ?? '—'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: daysLeft is int
                              ? _ChipForDaysLeft(value: daysLeft)
                              : const SizedBox.shrink(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _users.length;
    final withJoinDate = _users
        .where((u) => _parseDate(u['JoinDate']) != null)
        .length;

    Map<String, dynamic>? example = _matchesToday.isNotEmpty
        ? _matchesToday.first
        : (_matchesNext30.isNotEmpty ? _matchesNext30.first : null);

    return Scaffold(
      appBar: GlassHeaderBar(
        title: 'Alerting',
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'all_users') _showAllUsersPopup();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'all_users',
                child: Text('All users & days left'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0B0C0F),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Scope & Summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This template applies to ALL users under your account. Subscription expiry = JoinDate + 1 month.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoTile(
                            label: 'Total users',
                            value: '$total',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            label: 'Users with JoinDate',
                            value: '$withJoinDate',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoTile(
                            label: 'Matches today',
                            value: '${_matchesToday.length}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alert lead time (days before/at expiry)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _leadDays.keys.map((d) {
                        final selected = _leadDays[d] ?? false;
                        return ChoiceChip(
                          label: Text(d == 0 ? 'On the day' : '$d days before'),
                          selected: selected,
                          onSelected: (v) {
                            setState(() => _leadDays[d!] = v);
                            _recomputePreviews();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Send at',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _pickTime,
                          child: Text(
                            '${_sendTime.hour.toString().padLeft(2, '0')}:${_sendTime.minute.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alert channels & templates',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _modes.map((m) {
                        final selected = _selectedModes.contains(m);
                        return FilterChip(
                          label: Text(m),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedModes.add(m);
                            } else {
                              _selectedModes.remove(m);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    glassyField(
                      controller: _waTemplate,
                      label: 'WhatsApp Template',
                    ),
                    const SizedBox(height: 12),
                    glassyField(
                      controller: _smsTemplate,
                      label: 'SMS Template',
                    ),
                    const SizedBox(height: 12),
                    glassyField(
                      controller: _emailSubject,
                      label: 'Email Subject',
                    ),
                    const SizedBox(height: 12),
                    glassyField(
                      controller: _emailBody,
                      label: 'Email Body',
                      maxLines: 6,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Placeholders: {name}, {gymName}, {expiryDate}, {daysLeft}',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Matches today',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_matchesToday.isEmpty)
                      const Text(
                        'No users hit the selected lead times today.',
                        style: TextStyle(color: Colors.white70),
                      )
                    else
                      Column(
                        children: _matchesToday.take(50).map((u) {
                          return ListTile(
                            dense: true,
                            title: Text(
                              u['Name'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Join: ${u['JoinDate']}  •  Expiry: ${u['ExpiryDate']}  •  DaysLeft: ${u['DaysLeft']}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next 30 days (based on selected lead times)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_matchesNext30.isEmpty)
                      const Text(
                        'No upcoming matches in the next 30 days.',
                        style: TextStyle(color: Colors.white70),
                      )
                    else
                      Column(
                        children: _matchesNext30.take(50).map((u) {
                          return ListTile(
                            dense: true,
                            title: Text(
                              u['Name'] ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              'Join: ${u['JoinDate']}  •  Expiry: ${u['ExpiryDate']}  •  DaysLeft: ${u['DaysLeft']}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (example != null)
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Channel previews (example user)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedModes.contains('WhatsApp')) ...[
                        const Text(
                          'WhatsApp',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        _PreviewBox(
                          text: _renderTemplateFor(_waTemplate.text, example!),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_selectedModes.contains('SMS')) ...[
                        const Text(
                          'SMS',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        _PreviewBox(
                          text: _renderTemplateFor(_smsTemplate.text, example!),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_selectedModes.contains('Email')) ...[
                        const Text(
                          'Email',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        _PreviewBox(
                          text:
                              'Subject: ${_renderTemplateFor(_emailSubject.text, example!)}\n\n${_renderTemplateFor(_emailBody.text, example!)}',
                        ),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _saveTemplate,
                          icon: const Icon(Icons.save),
                          label: const Text('Save Template'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const GlassFooterBar(), // footer added
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x66161a20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x332A2F3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final String text;
  const _PreviewBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x66161a20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x332A2F3A)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}
