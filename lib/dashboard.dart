import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
// Import ONLY Supabase class to avoid pulling in its User type
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

class DashboardPage extends StatefulWidget {
  final String gymName;
  final String gymLocation;
  final int gymCapacity;

  const DashboardPage({
    super.key,
    required this.gymName,
    required this.gymLocation,
    required this.gymCapacity,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const String _tableName = 'Users';

  // Raw data
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _columns = [];

  bool _loading = true;
  String? _error;

  // Filters
  String _searchQuery = "";
  DateTime? _startDate;
  DateTime? _endDate;

  // Preferred order (others get appended)
  static const List<String> _preferredOrder = [
    'UserType',
    'ExercizeType',
    'Sex',
    'Age',
    'Height',
    'Weight',
    'BMI',
    'Address',
    'GymHistory',
    'HealthHistory',
    'SupplementHistory',
    'Target',
  ];

  // Fallback headers (used ONLY when 0 rows so headers still show)
  static const List<String> _fallbackColumns = [
    'Age',
    'Address',
    'Weight',
    'BMI',
    'GymHistory',
    'Target',
    'HealthHistory',
    'SupplementHistory',
    'Height',
    'UserType',
    'ExercizeType',
    'Sex',
  ];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await supa.Supabase.instance.client
          .from(_tableName)
          .select('*'); // SELECT * FROM Users

      final list = List<Map<String, dynamic>>.from(data);

      // Collect keys from returned rows
      final keySet = <String>{};
      for (final row in list) {
        keySet.addAll(row.keys);
      }

      // If no keys (0 rows or blocked), use fallback schema so headers still show
      final bool noKeys = keySet.isEmpty;
      final orderedCols = noKeys
          ? List<String>.from(_fallbackColumns)
          : <String>[
              ..._preferredOrder.where(keySet.contains),
              ...keySet.where((k) => !_preferredOrder.contains(k)).toList()
                ..sort(),
            ];

      setState(() {
        _rows = list;
        _columns = orderedCols;
        _filtered = List<Map<String, dynamic>>.from(_rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error =
            'Failed to load from table $_tableName. ${e.runtimeType}: $e\nTip: Verify table name/case & RLS SELECT policy.';
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _rows.where((row) {
        // Search across all fields
        final q = _searchQuery.trim().toLowerCase();
        final matchesSearch = q.isEmpty
            ? true
            : row.values
                .any((v) => (v ?? '').toString().toLowerCase().contains(q));

        // Date filter on created_at
        bool matchesDate = true;
        if (_startDate != null && _endDate != null) {
          final createdKey = _columns.firstWhere(
            (k) => k.toLowerCase() == 'created_at',
            orElse: () => '',
          );
          if (createdKey.isNotEmpty) {
            final created = _tryParseDate(row[createdKey]);
            if (created != null) {
              matchesDate = created
                      .isAfter(_startDate!.subtract(const Duration(days: 1))) &&
                  created.isBefore(_endDate!.add(const Duration(days: 1)));
            } else {
              matchesDate = false;
            }
          }
        }

        return matchesSearch && matchesDate;
      }).toList();
    });
  }

  DateTime? _tryParseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatDateCell(dynamic value) {
    final dt = _tryParseDate(value);
    if (dt == null) return value?.toString() ?? '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
  }

  String _dateLabel() {
    if (_startDate != null && _endDate != null) {
      final f = DateFormat('dd MMM yy');
      return '${f.format(_startDate!)} – ${f.format(_endDate!)}';
    }
    return 'Filter by created_at';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      _startDate = picked.start;
      _endDate = picked.end;
      _applyFilters();
    }
  }

  Map<String, int> _countsByKey(List<Map<String, dynamic>> data, String key) {
    final map = <String, int>{};
    for (final row in data) {
      final val = (row[key] ?? '').toString().trim();
      final k = val.isEmpty ? '(Empty)' : val;
      map[k] = (map[k] ?? 0) + 1;
    }
    return map;
  }

  List<ChartData> _toChartData(Map<String, int> counts) {
    final palette = <Color>[
      Colors.blue,
      Colors.orange,
      Colors.green,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.amber,
      Colors.pink,
      Colors.cyan,
      Colors.lime,
    ];
    int i = 0;
    return counts.entries.map((e) {
      final color = palette[i % palette.length];
      i++;
      return ChartData(e.key, e.value, color);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final hasCreatedAt = _columns.any((c) => c.toLowerCase() == 'created_at');
    final hasUserType = _columns.contains('UserType');
    final hasSex = _columns.contains('Sex');

    final userTypeData = hasUserType
        ? _toChartData(_countsByKey(_filtered, 'UserType'))
        : <ChartData>[];
    final sexData =
        hasSex ? _toChartData(_countsByKey(_filtered, 'Sex')) : <ChartData>[];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: Text('${widget.gymName} - Dashboard'),
        leading: Container(),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _fetchUsers,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search
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
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white54),
                    ),
                    onChanged: (value) {
                      _searchQuery = value;
                      _applyFilters();
                    },
                  ),
                  const SizedBox(height: 10),

                  // Date filter on created_at
                  if (hasCreatedAt)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1C23),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onPressed: _pickDateRange,
                          icon:
                              const Icon(Icons.date_range, color: Colors.white),
                          label: Text(
                            _dateLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (_startDate != null && _endDate != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            tooltip: "Clear Date Filter",
                            onPressed: () {
                              setState(() {
                                _startDate = null;
                                _endDate = null;
                                _applyFilters();
                              });
                            },
                          ),
                        ],
                      ],
                    ),

                  const SizedBox(height: 12),

                  // Pie charts (show only if those columns exist)
                  if (hasUserType || hasSex)
                    Row(
                      children: [
                        if (hasUserType)
                          Expanded(
                              child:
                                  _buildPieChart(userTypeData, 'User Types')),
                        if (hasUserType && hasSex) const SizedBox(width: 16),
                        if (hasSex)
                          Expanded(
                              child:
                                  _buildPieChart(sexData, 'Sex distribution')),
                      ],
                    ),

                  if (hasUserType || hasSex) const SizedBox(height: 20),

                  const Text(
                    "Users (all columns from Supabase)",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // >>> Fixed-height, independently scrollable table area <<<
                  SizedBox(
                    height: 420, // adjust as you like (previously ~400)
                    child: _buildUsersTable(scrollable: true),
                  ),
                ],
              ),
            ),
    );
  }

  // Table builder (can be placed in fixed-height container for vertical scroll)
  Widget _buildUsersTable({bool scrollable = false}) {
    if (_columns.isEmpty) {
      return const Text('No columns found.',
          style: TextStyle(color: Colors.white70));
    }
    if (_rows.isEmpty) {
      return const Text(
        'No rows to display.\n\nIf you expect data:\n• Insert at least one row into public."Users"\n• Check Row Level Security (RLS) SELECT policy for anon/authenticated\n• Verify table name and case (“Users” vs “users”)\n• Confirm your Supabase URL & anon key in main.dart\n',
        style: TextStyle(color: Colors.white70),
      );
    }

    final table = DataTable(
      columns: _columns
          .map(
            (col) => DataColumn(
              label: Text(
                col,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          )
          .toList(),
      rows: _filtered.map((row) {
        return DataRow(
          cells: _columns.map((col) {
            final value = row[col];
            final isCreated = col.toLowerCase() == 'created_at';
            final text =
                isCreated ? _formatDateCell(value) : (value?.toString() ?? '-');
            return DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140),
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );

    // independent vertical + horizontal scroll (restored)
    if (scrollable) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C23),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            ),
          ),
        ),
      );
    }

    // non-scrollable variant (unused here, kept for flexibility)
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C23),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
    );
  }

  Widget _buildPieChart(List<ChartData> data, String title) {
    final total = data.fold<int>(0, (sum, item) => sum + item.y);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C23),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: 150,
            child: CustomPaint(
              painter: PieChartPainter(data: data, total: total.toDouble()),
            ),
          ),
          const SizedBox(height: 10),
          if (data.isEmpty)
            const Text('(no data)',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: data
                  .map((item) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 12, height: 12, color: item.color),
                          const SizedBox(width: 6),
                          Text('${item.x}: ${item.y}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class ChartData {
  final String x;
  final int y;
  final Color color;
  ChartData(this.x, this.y, this.color);
}

class PieChartPainter extends CustomPainter {
  final List<ChartData> data;
  final double total;
  PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) {
      final paintBg = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF1A1C23);
      final center0 = Offset(size.width / 2, size.height / 2);
      final radius0 = size.width / 2;
      canvas.drawCircle(center0, radius0, paintBg);
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    double startAngle = -pi / 2;
    for (final item in data) {
      final sweepAngle = 2 * pi * (item.y / (total <= 0 ? 1 : total));
      paint.color = item.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }

    // Donut hole
    paint.color = const Color(0xFF0D0E11);
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
