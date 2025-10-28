// trainer_roster_page.dart
import 'dart:async';
import 'dart:typed_data'; // NEW
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

// NEW: PDF export + saving
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_saver/file_saver.dart';

/// View mode + range mode
enum _ViewMode { list, calendar }

enum _RangeMode { week, month }

/// Bulk primary-edit modes
enum _PrimaryBulkMode { replace, append, remove, clear }

class _PrimaryBulkResult {
  final List<String> ids;
  final _PrimaryBulkMode mode;
  const _PrimaryBulkResult(this.ids, this.mode);
}

class TrainerRosterPage extends StatefulWidget {
  final String fireBaseId;
  final supa.SupabaseClient client;
  final List<Map<String, dynamic>> gymsWithId;

  const TrainerRosterPage({
    super.key,
    required this.fireBaseId,
    required this.client,
    required this.gymsWithId,
  });

  @override
  State<TrainerRosterPage> createState() => _TrainerRosterPageState();
}

class _TrainerRosterPageState extends State<TrainerRosterPage> {
  // ── Config / state ──────────────────────────────────────────────────────
  final List<_ShiftTemplate> _defaultShifts = const [
    _ShiftTemplate(name: 'Morning', start: '06:00', end: '12:00'),
    _ShiftTemplate(name: 'Afternoon', start: '12:00', end: '18:00'),
    _ShiftTemplate(name: 'Evening', start: '18:00', end: '23:00'),
  ];

  _ViewMode _viewMode = _ViewMode.calendar;
  _RangeMode _rangeMode = _RangeMode.week;

  late String _selectedGymId;
  late DateTime _rangeStart; // Monday for week, first of month for month
  late List<DateTime> _visibleDates;

  // All slots live here, keyed by "YYYY-MM-DD|shiftIndex"
  final Map<String, _SlotData> _slots = {};

  // Trainers allowed in selected gym
  List<_Trainer> _trainers = [];

  // Selection for bulk edit: set of slot keys
  final Set<String> _selectedKeys = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _overlapWarnings = [];

  supa.SupabaseClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _selectedGymId = widget.gymsWithId.isNotEmpty
        ? widget.gymsWithId.first['GymID'] as String
        : '';
    _rangeStart = _mondayOf(DateTime.now());
    _recomputeVisibleDates();
    _loadRange();
  }

  // ── Helpers: dates / keys ───────────────────────────────────────────────
  DateTime _mondayOf(DateTime d) => DateTime(
    d.year,
    d.month,
    d.day,
  ).subtract(Duration(days: (d.weekday - DateTime.monday) % 7));

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _keyOf(DateTime d, int s) => '${_fmtDate(d)}|$s';

  (String dateStr, int s) _splitKey(String k) {
    final i = k.lastIndexOf('|');
    return (k.substring(0, i), int.parse(k.substring(i + 1)));
  }

  void _recomputeVisibleDates() {
    if (_rangeMode == _RangeMode.week) {
      final monday = _mondayOf(_rangeStart);
      _rangeStart = monday;
      _visibleDates = List.generate(7, (i) => monday.add(Duration(days: i)));
    } else {
      final first = DateTime(_rangeStart.year, _rangeStart.month, 1);
      final end = DateTime(_rangeStart.year, _rangeStart.month + 1, 0);
      _rangeStart = first;
      _visibleDates = List.generate(
        end.day,
        (i) => DateTime(first.year, first.month, i + 1),
      );
    }
  }

  _SlotData _getOrMake(DateTime d, int s) {
    final k = _keyOf(d, s);
    return _slots[k] ??= _SlotData(
      start: _defaultShifts[s].start,
      end: _defaultShifts[s].end,
      primaryTrainerIds: [],
      backupTrainerId: null,
      notes: '',
    );
  }

  // ── Data I/O ────────────────────────────────────────────────────────────
  Future<void> _loadRange() async {
    if (_selectedGymId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No synced gyms found.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selectedKeys.clear();
      _overlapWarnings.clear();
    });

    try {
      // Trainers for this user allowed at selected gym
      final tRows = await _client
          .from('Trainer')
          .select('TrainerID, Name')
          .eq('AuthUserID', widget.fireBaseId);

      final tgRows = await _client
          .from('TrainerGyms')
          .select('TrainerID')
          .eq('GymID', _selectedGymId);

      final allowed = (tgRows as List)
          .map((r) => r['TrainerID'] as String)
          .toSet();

      _trainers =
          (tRows as List)
              .map(
                (r) => _Trainer(
                  id: r['TrainerID'] as String,
                  name: (r['Name'] as String?)?.trim().isNotEmpty == true
                      ? (r['Name'] as String)
                      : 'Unnamed',
                ),
              )
              .where((t) => allowed.contains(t.id))
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      // Load roster rows for the whole range
      final startStr = _fmtDate(_visibleDates.first);
      final endStr = _fmtDate(_visibleDates.last);

      final rows = await _client
          .from('TrainerRoster')
          .select(
            'Date, StartTime, EndTime, PrimaryTrainerIDs, BackupTrainerID, Notes',
          )
          .eq('AuthUserID', widget.fireBaseId)
          .eq('GymID', _selectedGymId)
          .gte('Date', startStr)
          .lte('Date', endStr);

      // Reset & fill slots with defaults
      _slots.clear();
      for (final d in _visibleDates) {
        for (var s = 0; s < _defaultShifts.length; s++) {
          _getOrMake(d, s);
        }
      }

      // Attach rows into nearest matching shift by (StartTime, EndTime)
      for (final r in (rows as List)) {
        final date = DateTime.parse(r['Date'] as String);
        final st = (r['StartTime'] ?? '') as String;
        final et = (r['EndTime'] ?? '') as String;

        int bestS = 0;
        int bestScore = -1;
        for (var s = 0; s < _defaultShifts.length; s++) {
          int score = 0;
          if (_defaultShifts[s].start == st) score += 2;
          if (_defaultShifts[s].end == et) score += 2;
          if (score > bestScore) {
            bestScore = score;
            bestS = s;
          }
        }

        final list =
            (r['PrimaryTrainerIDs'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
        final sd = _getOrMake(date, bestS);
        _slots[_keyOf(date, bestS)] = sd.copyWith(
          start: st.isNotEmpty ? st : sd.start,
          end: et.isNotEmpty ? et : sd.end,
          primaryTrainerIds: List<String>.from(list),
          backupTrainerId: (r['BackupTrainerID'] as String?),
          notes: (r['Notes'] as String?) ?? '',
        );
      }

      _computeOverlaps();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load roster: $e';
      });
    }
  }

  Future<void> _saveRange() async {
    if (_selectedGymId.isEmpty) return;
    setState(() => _saving = true);
    try {
      final start = _fmtDate(_visibleDates.first);
      final end = _fmtDate(_visibleDates.last);

      // Clear existing rows in the range
      await _client
          .from('TrainerRoster')
          .delete()
          .eq('AuthUserID', widget.fireBaseId)
          .eq('GymID', _selectedGymId)
          .gte('Date', start)
          .lte('Date', end);

      // Insert non-empty slots
      final rows = <Map<String, dynamic>>[];
      for (final d in _visibleDates) {
        final dateStr = _fmtDate(d);
        for (var s = 0; s < _defaultShifts.length; s++) {
          final k = _keyOf(d, s);
          final slot = _slots[k];
          if (slot == null) continue;
          if (slot.primaryTrainerIds.isEmpty) continue;

          rows.add({
            'AuthUserID': widget.fireBaseId,
            'GymID': _selectedGymId,
            'Date': dateStr,
            'StartTime': slot.start,
            'EndTime': slot.end,
            'PrimaryTrainerIDs': slot.primaryTrainerIds,
            'BackupTrainerID': slot.backupTrainerId,
            'Notes': slot.notes.isEmpty ? null : slot.notes,
          });
        }
      }
      if (rows.isNotEmpty) {
        await _client.from('TrainerRoster').insert(rows);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Roster saved ✔')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Overlaps ────────────────────────────────────────────────────────────
  int _timeToMinutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  void _computeOverlaps() {
    final warnings = <String>[];

    for (final d in _visibleDates) {
      final map = <String, List<_Range>>{};
      for (var s = 0; s < _defaultShifts.length; s++) {
        final k = _keyOf(d, s);
        final slot = _slots[k];
        if (slot == null) continue;
        final r = _Range(_timeToMinutes(slot.start), _timeToMinutes(slot.end));
        for (final tid in slot.primaryTrainerIds) {
          map.putIfAbsent(tid, () => []).add(r);
        }
        if (slot.backupTrainerId != null) {
          map
              .putIfAbsent(slot.backupTrainerId!, () => [])
              .add(r.copyWith(tag: 'backup'));
        }
      }
      map.forEach((tid, ranges) {
        ranges.sort((a, b) => a.start.compareTo(b.start));
        for (int i = 1; i < ranges.length; i++) {
          if (ranges[i].start < ranges[i - 1].end) {
            warnings.add(
              '${_trainerName(tid)} has overlapping assignments on ${_fmtDate(d)}',
            );
            break;
          }
        }
      });
    }

    _overlapWarnings = warnings.toSet().toList();
  }

  String _trainerName(String id) => _trainers
      .firstWhere(
        (t) => t.id == id,
        orElse: () => _Trainer(id: id, name: 'Unknown'),
      )
      .name;

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0D0E11);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Trainer Roster'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            onPressed: _saving ? null : _saveRange,
          ),
          // NEW: Download PDF
          IconButton(
            tooltip: 'Download PDF',
            icon: const Icon(Icons.download),
            onPressed: _saving ? null : _exportPdf,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
              ),
            )
          : Column(
              children: [
                _topBar(), // gym picker + reload
                _controlsBar(), // moved from AppBar to avoid overflow
                if (_overlapWarnings.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.all(10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A1C1C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x55FF6B6B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Conflicts detected',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._overlapWarnings.map(
                          (w) => Text(
                            '• $w',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 1, color: Color(0xFF1B1E24)),
                Expanded(
                  child: _viewMode == _ViewMode.list
                      ? _listView()
                      : _calendarView(),
                ),
              ],
            ),
      bottomNavigationBar: _selectedKeys.isEmpty ? null : _bulkBar(),
    );
  }

  // ── Top bar: gym + reload ───────────────────────────────────────────────
  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: const Color(0xFF0D0E11),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF12151B),
              value: _selectedGymId.isEmpty ? null : _selectedGymId,
              items: widget.gymsWithId.map((g) {
                final id = g['GymID'] as String;
                final label = '${g['name'] ?? 'Gym'} • ${g['location'] ?? ''}';
                return DropdownMenuItem(
                  value: id,
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
              decoration: const InputDecoration(
                labelText: 'Gym',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                ),
              ),
              onChanged: (v) async {
                if (v == null) return;
                setState(() => _selectedGymId = v);
                await _loadRange();
              },
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Reload', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF2A2F3A)),
              backgroundColor: const Color(0x201A1C23),
            ),
            onPressed: _loadRange,
          ),
        ],
      ),
    );
  }

  // ── Controls bar moved from AppBar ──────────────────────────────────────
  Widget _controlsBar() {
    final dateLabel = (_rangeMode == _RangeMode.week)
        ? '${_fmtDate(_visibleDates.first)}  →  ${_fmtDate(_visibleDates.last)}'
        : '${_rangeStart.year}-${_rangeStart.month.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF0D0E11),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            _segmented(
              items: const ['List', 'Calendar'],
              index: _viewMode.index,
              onChanged: (i) => setState(() => _viewMode = _ViewMode.values[i]),
            ),
            _segmented(
              items: const ['Week', 'Month'],
              index: _rangeMode.index,
              onChanged: (i) async {
                _rangeMode = _RangeMode.values[i];
                _recomputeVisibleDates();
                await _loadRange();
                setState(() {});
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_left, color: Colors.white70),
              label: const Text('Prev', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2A2F3A)),
              ),
              onPressed: () async {
                if (_rangeMode == _RangeMode.week) {
                  _rangeStart = _rangeStart.subtract(const Duration(days: 7));
                } else {
                  _rangeStart = DateTime(
                    _rangeStart.year,
                    _rangeStart.month - 1,
                    1,
                  );
                }
                _recomputeVisibleDates();
                await _loadRange();
              },
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF12151B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1B1E24)),
              ),
              child: Text(
                dateLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_right, color: Colors.white70),
              label: const Text('Next', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2A2F3A)),
              ),
              onPressed: () async {
                if (_rangeMode == _RangeMode.week) {
                  _rangeStart = _rangeStart.add(const Duration(days: 7));
                } else {
                  _rangeStart = DateTime(
                    _rangeStart.year,
                    _rangeStart.month + 1,
                    1,
                  );
                }
                _recomputeVisibleDates();
                await _loadRange();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── LIST VIEW ───────────────────────────────────────────────────────────
  Widget _listView() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _visibleDates.length,
      itemBuilder: (_, i) {
        final d = _visibleDates[i];
        final dateStr = _fmtDate(d);
        final weekday = [
          'Mon',
          'Tue',
          'Wed',
          'Thu',
          'Fri',
          'Sat',
          'Sun',
        ][d.weekday - 1];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF12151B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1B1E24)),
          ),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  '$weekday • $dateStr',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1B1E24)),
              ...List.generate(
                _defaultShifts.length,
                (s) => _listShiftTile(d, s),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _listShiftTile(DateTime d, int s) {
    final k = _keyOf(d, s);
    final slot = _getOrMake(d, s);
    final shiftName = _defaultShifts[s].name;
    final primaryNames = slot.primaryTrainerIds
        .map((id) => _trainerName(id))
        .toList();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      title: Text(
        '$shiftName • ${slot.start}–${slot.end}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        [
          if (primaryNames.isNotEmpty) 'Primary: ${primaryNames.join(', ')}',
          if (slot.backupTrainerId != null)
            'Backup: ${_trainerName(slot.backupTrainerId!)}',
        ].join('   •   '),
        style: const TextStyle(color: Colors.white70),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: _selectedKeys.contains(k),
            onChanged: (v) => setState(() {
              if (v == true) {
                _selectedKeys.add(k);
              } else {
                _selectedKeys.remove(k);
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white70),
            onPressed: () => _editSingle(d, s),
          ),
        ],
      ),
    );
  }

  // ── CALENDAR VIEW (robust nested scrolling) ─────────────────────────────
  Widget _calendarView() {
    const headerDateW = 110.0;
    const cellW = 180.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Build header row
        final header = Row(
          children: [
            _dateHeaderCell('Date', width: headerDateW),
            ...List.generate(
              _defaultShifts.length,
              (s) => _headerCell(_defaultShifts[s].name, width: cellW),
            ),
          ],
        );

        // Build all day rows
        final body = Column(
          children: _visibleDates
              .map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      _dateCell(d, width: headerDateW),
                      ...List.generate(
                        _defaultShifts.length,
                        (s) => _slotCell(d, s, width: cellW),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [header, const SizedBox(height: 6), body],
              ),
            ),
          ),
        );
      },
    );
  }

  // Cells
  Widget _dateHeaderCell(String text, {double width = 110}) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF12151B),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF1B1E24)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _headerCell(String text, {double width = 190}) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF12151B),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF1B1E24)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _dateCell(DateTime d, {double width = 110}) {
    final weekday = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ][d.weekday - 1];
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1218),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B1E24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekday,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(_fmtDate(d), style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              // Select entire day
              setState(() {
                for (var s = 0; s < _defaultShifts.length; s++) {
                  _selectedKeys.add(_keyOf(d, s));
                }
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4F9CF9),
            ),
            child: const Text('Select day'),
          ),
        ],
      ),
    );
  }

  Widget _slotCell(DateTime d, int s, {double width = 190}) {
    final k = _keyOf(d, s);
    final slot = _getOrMake(d, s);
    final selected = _selectedKeys.contains(k);
    final primaryNames = slot.primaryTrainerIds.map(_trainerName).toList();

    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedKeys.remove(k);
        } else {
          _selectedKeys.add(k);
        }
      }),
      onLongPress: () => _editSingle(d, s),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF233045) : const Color(0xFF12151B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF4F9CF9) : const Color(0xFF1B1E24),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_defaultShifts[s].name}  •  ${slot.start}-${slot.end}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            if (primaryNames.isEmpty)
              const Text('No primary', style: TextStyle(color: Colors.white54))
            else
              Text(
                primaryNames.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            if (slot.backupTrainerId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_moon,
                      size: 14,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _trainerName(slot.backupTrainerId!),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Single-slot editor ──────────────────────────────────────────────────
  Future<void> _editSingle(DateTime d, int s) async {
    final k = _keyOf(d, s);
    final slot = _getOrMake(d, s);

    final primary = slot.primaryTrainerIds.toSet();
    String? backup = slot.backupTrainerId;
    String start = slot.start;
    String end = slot.end;
    final notesC = TextEditingController(text: slot.notes);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12151B),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 8,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Times
                    Row(
                      children: [
                        Expanded(
                          child: _timeField('Start', start, () async {
                            final t = await _pickTime(ctx, start);
                            if (t != null) setLocal(() => start = t);
                          }),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _timeField('End', end, () async {
                            final t = await _pickTime(ctx, end);
                            if (t != null) setLocal(() => end = t);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Primary multi-select
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Primary trainers',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _trainers.map((t) {
                        final sel = primary.contains(t.id);
                        return FilterChip(
                          label: Text(t.name),
                          selected: sel,
                          onSelected: (val) {
                            setLocal(() {
                              if (val) {
                                primary.add(t.id);
                                if (backup == t.id) backup = null;
                              } else {
                                primary.remove(t.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    // Backup
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Backup trainer (optional)',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: backup ?? '',
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1A1F2A),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text(
                            'None',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        ..._trainers
                            .where((t) => !primary.contains(t.id))
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  t.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                      ],
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                        ),
                      ),
                      onChanged: (v) => setLocal(
                        () => backup = (v == null || v.isEmpty) ? null : v,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Notes
                    TextField(
                      controller: notesC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Notes (optional)',
                        hintStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Clear',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2A2F3A)),
                          ),
                          onPressed: () {
                            primary.clear();
                            backup = null;
                            notesC.text = '';
                            setLocal(() {});
                          },
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Save slot'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A2F3A),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (_timeToMinutes(end) <= _timeToMinutes(start)) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'End time must be after start time',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (primary.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Select at least one primary trainer',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx, true);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      setState(() {
        _slots[k] = _getOrMake(d, s).copyWith(
          start: start,
          end: end,
          primaryTrainerIds: primary.toList(),
          backupTrainerId: backup,
          notes: notesC.text.trim(),
        );
        _computeOverlaps();
      });
    }
  }

  Widget _timeField(String label, String value, VoidCallback onPick) {
    return GestureDetector(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF2A2F3A)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4F9CF9)),
          ),
        ),
        child: Text(value, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<String?> _pickTime(BuildContext ctx, String current) async {
    final parts = current.split(':');
    final init = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    final t = await showTimePicker(context: ctx, initialTime: init);
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // ── Bulk selection bar ──────────────────────────────────────────────────
  Widget _bulkBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF101318),
          boxShadow: [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 6,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              '${_selectedKeys.length} selected',
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Set primary',
              icon: const Icon(Icons.people_alt, color: Colors.white),
              onPressed: _bulkSetPrimary,
            ),
            IconButton(
              tooltip: 'Set backup',
              icon: const Icon(Icons.shield_moon, color: Colors.white),
              onPressed: _bulkSetBackup,
            ),
            IconButton(
              tooltip: 'Set times',
              icon: const Icon(Icons.schedule, color: Colors.white),
              onPressed: _bulkSetTimes,
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              onPressed: _bulkClear,
            ),
            TextButton(
              onPressed: () => setState(() => _selectedKeys.clear()),
              child: const Text(
                'Deselect',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === BULK: PRIMARY (Replace / Append / Remove / Clear) ==================
  Future<void> _bulkSetPrimary() async {
    final res = await _pickPrimaryMulti();
    if (res == null) return;

    final chosen = res.ids.toSet();
    final mode = res.mode;

    setState(() {
      for (final k in _selectedKeys) {
        final (dateStr, s) = _splitKey(k);
        final d = DateTime.parse(dateStr);
        final prev = _getOrMake(d, s);

        final current = prev.primaryTrainerIds.toSet();

        List<String> newPrimaries;
        switch (mode) {
          case _PrimaryBulkMode.replace:
            newPrimaries = chosen.toList();
            break;
          case _PrimaryBulkMode.append:
            newPrimaries = {...current, ...chosen}.toList();
            break;
          case _PrimaryBulkMode.remove:
            newPrimaries = current.difference(chosen).toList();
            break;
          case _PrimaryBulkMode.clear:
            newPrimaries = <String>[];
            break;
        }

        if (prev.backupTrainerId != null) {
          newPrimaries.removeWhere((id) => id == prev.backupTrainerId);
        }

        _slots[k] = prev.copyWith(primaryTrainerIds: newPrimaries);
      }
      _computeOverlaps();
    });
  }

  Future<_PrimaryBulkResult?> _pickPrimaryMulti() async {
    final chosen = <String>{};
    int modeIndex = 0; // 0=Replace, 1=Append, 2=Remove
    bool clearAll = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF12151B),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 10,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bulk: Primary trainers',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Mode toggle
                  const Text(
                    'Mode',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Replace'),
                        selected: modeIndex == 0,
                        onSelected: (_) => setLocal(() => modeIndex = 0),
                        selectedColor: const Color(0xFF2A2F3A),
                        labelStyle: TextStyle(
                          color: modeIndex == 0 ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      ChoiceChip(
                        label: const Text('Append'),
                        selected: modeIndex == 1,
                        onSelected: (_) => setLocal(() => modeIndex = 1),
                        selectedColor: const Color(0xFF2A2F3A),
                        labelStyle: TextStyle(
                          color: modeIndex == 1 ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      ChoiceChip(
                        label: const Text('Remove'),
                        selected: modeIndex == 2,
                        onSelected: (_) => setLocal(() => modeIndex = 2),
                        selectedColor: const Color(0xFF2A2F3A),
                        labelStyle: TextStyle(
                          color: modeIndex == 2 ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: Colors.transparent,
                        side: const BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Text(
                    'Select trainers',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _trainers.map((t) {
                      final sel = chosen.contains(t.id);
                      return FilterChip(
                        label: Text(t.name),
                        selected: sel,
                        onSelected: (v) => setLocal(() {
                          if (v) {
                            chosen.add(t.id);
                          } else {
                            chosen.remove(t.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),
                  Row(
                    children: [
                      // Clear all primaries
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.backspace_outlined,
                          color: Colors.white70,
                        ),
                        label: const Text(
                          'Clear all primaries',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF2A2F3A)),
                        ),
                        onPressed: () {
                          clearAll = true;
                          Navigator.pop(ctx, true);
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (!clearAll && modeIndex != 2 && chosen.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Pick at least one trainer'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (ok == true) {
      if (clearAll) return const _PrimaryBulkResult([], _PrimaryBulkMode.clear);
      final mode = _PrimaryBulkMode.values[modeIndex];
      return _PrimaryBulkResult(chosen.toList(), mode);
    }
    return null;
  }

  // === BULK: BACKUP =======================================================
  Future<void> _bulkSetBackup() async {
    final backup = await _pickBackupSingle();
    if (backup == null) return; // null = cancel, '' = None

    setState(() {
      for (final k in _selectedKeys) {
        final (dateStr, s) = _splitKey(k);
        final d = DateTime.parse(dateStr);
        final prev = _getOrMake(d, s);
        var newBackup = (backup.isEmpty) ? null : backup;
        // Ensure backup not in primary list
        final prim = prev.primaryTrainerIds
            .where((id) => id != newBackup)
            .toList();
        _slots[k] = prev.copyWith(
          primaryTrainerIds: prim,
          backupTrainerId: newBackup,
        );
      }
      _computeOverlaps();
    });
  }

  Future<String?> _pickBackupSingle() async {
    String val = '';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF12151B),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select backup trainer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: val,
                    dropdownColor: const Color(0xFF1A1F2A),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text(
                          'None',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      ..._trainers.map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            t.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2A2F3A)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF4F9CF9)),
                      ),
                    ),
                    onChanged: (v) => setLocal(() => val = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    return ok == true ? val : null;
  }

  // === BULK: TIMES ========================================================
  Future<void> _bulkSetTimes() async {
    // Ask for one start + one end, apply to all
    String start = _defaultShifts.first.start;
    String end = _defaultShifts.last.end;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111214),
        title: const Text(
          'Set times for selected',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _timeField('Start', start, () async {
              final t = await _pickTime(ctx, start);
              if (t != null) {
                start = t;
                (ctx as Element).markNeedsBuild();
              }
            }),
            const SizedBox(height: 10),
            _timeField('End', end, () async {
              final t = await _pickTime(ctx, end);
              if (t != null) {
                end = t;
                (ctx as Element).markNeedsBuild();
              }
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_timeToMinutes(end) <= _timeToMinutes(start)) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      for (final k in _selectedKeys) {
        final (dateStr, s) = _splitKey(k);
        final d = DateTime.parse(dateStr);
        final prev = _getOrMake(d, s);
        _slots[k] = prev.copyWith(start: start, end: end);
      }
      _computeOverlaps();
    });
  }

  // === BULK: CLEAR EVERYTHING IN CELLS ====================================
  Future<void> _bulkClear() async {
    setState(() {
      for (final k in _selectedKeys) {
        _slots[k] = _slots[k]!.copyWith(
          primaryTrainerIds: [],
          backupTrainerId: null,
          notes: '',
        );
      }
      _computeOverlaps();
    });
  }

  // ── Small UI helpers ────────────────────────────────────────────────────
  Widget _segmented({
    required List<String> items,
    required int index,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF12151B),
        border: Border.all(color: const Color(0xFF1B1E24)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(items[i]),
                selected: index == i,
                onSelected: (_) => onChanged(i),
                selectedColor: const Color(0xFF2A2F3A),
                labelStyle: TextStyle(
                  color: index == i ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
                backgroundColor: Colors.transparent,
                side: const BorderSide(color: Color(0xFF2A2F3A)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────── PDF EXPORT (NEW) ──────────────────────────────

  Future<void> _exportPdf() async {
    try {
      final bytes = await _buildRosterPdf();

      final gym = widget.gymsWithId.firstWhere(
        (g) => (g['GymID'] as String) == _selectedGymId,
        orElse: () => <String, dynamic>{},
      );
      final gymName = (gym['name'] ?? 'Gym').toString();
      final safeGym = gymName.replaceAll(RegExp(r'[^\w\-]+'), '_');

      final filename = (_rangeMode == _RangeMode.week)
          ? 'trainer_roster_${safeGym}_${_fmtDate(_visibleDates.first)}_${_fmtDate(_visibleDates.last)}.pdf'
          : 'trainer_roster_${safeGym}_${_rangeStart.year}-${_rangeStart.month.toString().padLeft(2, '0')}.pdf';

      await FileSaver.instance.saveFile(
        name: filename,
        bytes: bytes,
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads as $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<Uint8List> _buildRosterPdf() async {
    final pdf = pw.Document();

    final gym = widget.gymsWithId.firstWhere(
      (g) => (g['GymID'] as String) == _selectedGymId,
      orElse: () => <String, dynamic>{},
    );
    final gymName = (gym['name'] ?? 'Gym').toString();
    final gymLoc = (gym['location'] ?? '').toString();

    final dateLabel = (_rangeMode == _RangeMode.week)
        ? '${_fmtDate(_visibleDates.first)} → ${_fmtDate(_visibleDates.last)}'
        : '${_rangeStart.year}-${_rangeStart.month.toString().padLeft(2, '0')}';

    // Build a table-friendly snapshot of what’s currently on screen
    // (Exclude empty shifts: i.e., no primary, no backup, no notes)
    final rowsPerDay = <String, List<List<String>>>{}; // date -> rows
    for (final d in _visibleDates) {
      final dayRows = <List<String>>[];
      for (var s = 0; s < _defaultShifts.length; s++) {
        final slot = _getOrMake(d, s);
        final primaryNames = slot.primaryTrainerIds.map(_trainerName).toList();
        final backup = slot.backupTrainerId == null
            ? ''
            : _trainerName(slot.backupTrainerId!);
        final notes = slot.notes.trim();

        final isEmpty = primaryNames.isEmpty && backup.isEmpty && notes.isEmpty;
        if (isEmpty) {
          // Skip empty shifts in PDF
          continue;
        }

        dayRows.add([
          _defaultShifts[s].name,
          '${slot.start}-${slot.end}',
          primaryNames.isEmpty ? '—' : primaryNames.join(', '),
          backup.isEmpty ? '—' : backup,
          notes.isEmpty ? '—' : notes,
        ]);
      }
      rowsPerDay[_fmtDate(d)] = dayRows;
    }

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 28),
          theme: pw.ThemeData.withFont(
            base: pw.Font.helvetica(),
            bold: pw.Font.helveticaBold(),
          ),
        ),
        build: (ctx) {
          return [
            // Header
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Trainer Roster',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '$gymName${gymLoc.isNotEmpty ? ' • $gymLoc' : ''}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(dateLabel, style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 10),

            // Day-by-day tables
            ...rowsPerDay.entries.map((entry) {
              final date = entry.key;
              final rows = entry.value;

              // Show weekday label next to the date
              final weekday = () {
                final d = DateTime.parse(date);
                const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return names[d.weekday - 1];
              }();

              if (rows.isEmpty) {
                // If no shifts (because excluded), skip rendering the day section.
                return pw.SizedBox();
              }

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '$date ($weekday)',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(80),
                      1: const pw.FixedColumnWidth(70),
                      // others auto
                    },
                    children: [
                      // header row
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        children: [
                          _cell('Shift', bold: true),
                          _cell('Time', bold: true),
                          _cell('Primary', bold: true),
                          _cell('Backup', bold: true),
                          _cell('Notes', bold: true),
                        ],
                      ),
                      // data rows
                      ...rows.map(
                        (r) => pw.TableRow(
                          children: [
                            _cell(r[0]),
                            _cell(r[1]),
                            _cell(r[2]),
                            _cell(r[3]),
                            _cell(r[4]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ];
        },
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Generated ${DateTime.now()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}

// ── Models ────────────────────────────────────────────────────────────────
class _Trainer {
  final String id;
  final String name;
  _Trainer({required this.id, required this.name});
}

class _ShiftTemplate {
  final String name;
  final String start; // 'HH:mm'
  final String end; // 'HH:mm'
  const _ShiftTemplate({
    required this.name,
    required this.start,
    required this.end,
  });
}

class _SlotData {
  final String start;
  final String end;
  final List<String> primaryTrainerIds;
  final String? backupTrainerId;
  final String notes;
  _SlotData({
    required this.start,
    required this.end,
    required this.primaryTrainerIds,
    required this.backupTrainerId,
    required this.notes,
  });

  _SlotData copyWith({
    String? start,
    String? end,
    List<String>? primaryTrainerIds,
    String? backupTrainerId,
    String? notes,
  }) {
    return _SlotData(
      start: start ?? this.start,
      end: end ?? this.end,
      primaryTrainerIds: primaryTrainerIds ?? this.primaryTrainerIds,
      backupTrainerId: backupTrainerId ?? this.backupTrainerId,
      notes: notes ?? this.notes,
    );
  }
}

class _Range {
  final int start;
  final int end;
  final String? tag;
  _Range(this.start, this.end, {this.tag});
  _Range copyWith({int? start, int? end, String? tag}) =>
      _Range(start ?? this.start, end ?? this.end, tag: tag ?? this.tag);
}
