import 'dart:math';
import 'dart:ui' show ImageFilter; // for BackdropFilter
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// Import ONLY Supabase class to avoid pulling in its User type
import 'package:supabase_flutter/supabase_flutter.dart' as supa show Supabase;

// <-- add this import so we can navigate to user view
import 'user_view_page.dart';

class DashboardPage extends StatefulWidget {
  final String gymName;
  final String gymLocation;
  final int gymCapacity;

  /// Preferred so we can filter fast and precisely
  final String? gymId;

  const DashboardPage({
    super.key,
    required this.gymName,
    required this.gymLocation,
    required this.gymCapacity,
    this.gymId,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  static const String _tableName = 'Users';

  // Raw data
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _columns = [];

  bool _loading = true;
  bool _resolvingGymId = false;
  String? _error;
  String? _gymId; // resolved or passed GymID

  // Filters
  String _searchQuery = "";
  DateTime? _startDate;
  DateTime? _endDate;

  // Chart animation
  late final AnimationController _anim;

  /// EXACT display order for table columns
  static const List<String> _priorityOrder = [
    'Name',
    'Age',
    'Sex',
    'Address',
    'Weight',
    'Height',
    'BMI',
    'GymHistory',
    'Target',
    'HealthHistory',
    'SupplementHistory',
    'Membership',
    'ExercizeType',
    'Phone',
    'Email',
    'JoinDate',
  ];

  /// Columns to hide entirely (UUIDs/backend fields, including created_at)
  static const Set<String> _hiddenColsLower = {
    'gymid',
    'firebaseid',
    'userid',
    'financeid',
    'id',
    'uuid',
    'created_at',
  };

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();

    _gymId = widget.gymId;
    if (_gymId == null || _gymId!.isEmpty) {
      _resolveGymIdByNameLocation().then((_) => _fetchUsers());
    } else {
      _fetchUsers();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
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

      // Collect keys from returned rows, excluding hidden (UUID/backend) columns
      final keySet = <String>{};
      for (final row in list) {
        for (final k in row.keys) {
          if (!_isHiddenColumn(k)) keySet.add(k);
        }
      }

      // If no keys (0 rows), show only the priority columns as headers
      final bool noKeys = keySet.isEmpty;
      final orderedCols = noKeys
          ? List<String>.from(_priorityOrder)
          : _orderedColumnsFromKeys(keySet);

      setState(() {
        _rows = list;
        _columns = orderedCols;
        _filtered = List<Map<String, dynamic>>.from(_rows);
        _loading = false;
      });

      // re-play chart animation after data refresh
      _anim.forward(from: 0);
    } catch (e) {
      setState(() {
        _error =
            'Failed to load from table $_tableName. ${e.runtimeType}: $e\nTip: Verify table name/case, RLS SELECT policy, and that GymID filter is valid.';
        _loading = false;
      });
    }
  }

  /// Remove hidden cols and order by explicit priority, then append any remaining (alphabetically)
  List<String> _orderedColumnsFromKeys(Set<String> keySet) {
    final presentPriority = _priorityOrder.where(keySet.contains).toList();

    // remaining (non-priority, non-hidden)
    final remaining = keySet.where((k) => !_priorityOrder.contains(k)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [...presentPriority, ...remaining];
  }

  bool _isHiddenColumn(String name) {
    final l = name.toLowerCase();
    if (_hiddenColsLower.contains(l)) return true;
    // also hide any column that *looks* like an id (but allow Email/EmailID)
    if (l.endsWith('id') && l != 'email' && l != 'emailid') return true;
    return false;
  }

  void _applyFilters() {
    setState(() {
      _filtered = _rows.where((row) {
        // Search across only visible fields
        final q = _searchQuery.trim().toLowerCase();
        final matchesSearch = q.isEmpty
            ? true
            : row.entries.where((e) => !_isHiddenColumn(e.key)).any(
                (e) => (e.value ?? '').toString().toLowerCase().contains(q));

        // Date filter on created_at (even if column is hidden)
        bool matchesDate = true;
        final createdKey = row.keys.firstWhere(
          (k) => k.toLowerCase() == 'created_at',
          orElse: () => '',
        );
        if (_startDate != null && _endDate != null && createdKey.isNotEmpty) {
          final created = _tryParseDate(row[createdKey]);
          if (created != null) {
            matchesDate = created
                    .isAfter(_startDate!.subtract(const Duration(days: 1))) &&
                created.isBefore(_endDate!.add(const Duration(days: 1)));
          } else {
            matchesDate = false;
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
      const Color(0xFF5B8CFF),
      const Color(0xFFFFA05B),
      const Color(0xFF61D095),
      const Color(0xFFFF6B6B),
      const Color(0xFFB086F7),
      const Color(0xFF4ED1CC),
      const Color(0xFFFFD166),
      const Color(0xFFF577B7),
      const Color(0xFF54C5F8),
      const Color(0xFFBCE784),
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
    // choose two categorical fields among Membership, ExercizeType, Sex
    final availableCats = <String>[];
    for (final k in const ['Membership', 'ExercizeType', 'Sex']) {
      if (_columns.contains(k)) availableCats.add(k);
    }
    final String? firstCat = availableCats.isNotEmpty ? availableCats[0] : null;
    final String? secondCat =
        availableCats.length > 1 ? availableCats[1] : null;

    final firstData = firstCat != null
        ? _toChartData(_countsByKey(_filtered, firstCat))
        : <ChartData>[];
    final secondData = secondCat != null
        ? _toChartData(_countsByKey(_filtered, secondCat))
        : <ChartData>[];

    final hasCreatedAt = _rows.isNotEmpty &&
        _rows.first.keys.any((c) => c.toLowerCase() == 'created_at');

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: const SizedBox.shrink(),
        iconTheme:
            const IconThemeData(color: Colors.white), // all appbar icons bright
        leading: IconButton(
          tooltip: 'Home',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.home_outlined, color: Colors.white, size: 26),
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
                          // ======= NEW: Two glossy tab-buttons (Dashboard / User view) =======
                          Row(
                            children: [
                              GlassLabelButton(
                                text: '${widget.gymName} • Dashboard',
                                active: true, // current page
                                onTap: () {
                                  // we're already here; you can also refresh:
                                  _fetchUsers();
                                },
                              ),
                              const SizedBox(width: 8),
                              GlassLabelButton(
                                text: '${widget.gymName} • User view mode',
                                active: false,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => UserViewPage(
                                        gymName: widget.gymName,
                                        gymLocation: widget.gymLocation,
                                        gymCapacity: widget.gymCapacity,
                                        gymId: _gymId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

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
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.white54),
                            ),
                            onChanged: (value) {
                              _searchQuery = value;
                              _applyFilters();
                            },
                          ),
                          const SizedBox(height: 10),

                          // Date filter on created_at (column hidden from table)
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
                                  icon: const Icon(Icons.date_range,
                                      color: Colors.white),
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
                                    icon: const Icon(Icons.clear,
                                        color: Colors.white),
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

                          // Two pie charts (first two available among Membership / ExercizeType / Sex)
                          if (firstCat != null || secondCat != null)
                            Row(
                              children: [
                                if (firstCat != null)
                                  Expanded(
                                    child: AnimatedBuilder(
                                      animation: _anim,
                                      builder: (_, __) => GlassPieCard(
                                        title: firstCat,
                                        data: firstData,
                                        progress: Curves.easeOut
                                            .transform(_anim.value),
                                      ),
                                    ),
                                  ),
                                if (firstCat != null && secondCat != null)
                                  const SizedBox(width: 16),
                                if (secondCat != null)
                                  Expanded(
                                    child: AnimatedBuilder(
                                      animation: _anim,
                                      builder: (_, __) => GlassPieCard(
                                        title: secondCat,
                                        data: secondData,
                                        progress: Curves.easeOut
                                            .transform(_anim.value),
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                          if (firstCat != null || secondCat != null)
                            const SizedBox(height: 20),

                          Text(
                            "Users (${widget.gymName})",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),

                          // Fixed-height, independently scrollable table
                          SizedBox(
                            height: 420,
                            child: _buildUsersTable(scrollable: true),
                          ),
                        ],
                      ),
                    ),
    );
  }

  // Table builder (vertical + horizontal scroll via wrapper)
  Widget _buildUsersTable({bool scrollable = false}) {
    if (_columns.isEmpty) {
      return const Text('No columns found.',
          style: TextStyle(color: Colors.white70));
    }
    if (_rows.isEmpty) {
      return const Text(
        'No rows to display.\n\nIf you expect data:\n• Insert at least one row into public."Users"\n• Check RLS SELECT policy\n• Confirm GymID filter is correct\n',
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
            final isDate = col.toLowerCase() == 'joindate';
            final text =
                isDate ? _formatDateCell(value) : (value?.toString() ?? '-');
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
}

class ChartData {
  final String x;
  final int y;
  final Color color;
  ChartData(this.x, this.y, this.color);
}

/// ======= NEW: Clickable glossy label button (used as tabs) =======
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
    final borderAlpha = active ? 0.35 : 0.18;
    final textColor =
        active ? Colors.white : Colors.white.withValues(alpha: 0.8);
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
                colors: [
                  Color(0x33FFFFFF),
                  Color(0x1AFFFFFF),
                ],
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
                color: textColor,
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

/// A frosted glass card that renders a glossy donut chart + legend
class GlassPieCard extends StatelessWidget {
  final String title;
  final List<ChartData> data;
  final double progress; // 0..1 sweep animation

  const GlassPieCard({
    super.key,
    required this.title,
    required this.data,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final total = data.fold<int>(0, (sum, item) => sum + item.y);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0x33FFFFFF),
                Color(0x1AFFFFFF),
              ],
            ),
            border: Border.all(
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
                width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 170,
                width: 170,
                child: CustomPaint(
                  painter: GlossyDonutPainter(
                    data: data,
                    total: total.toDouble(),
                    progress: progress,
                  ),
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
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  borderRadius: BorderRadius.circular(3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: item.color.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${item.x}: ${item.y}',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ))
                      .toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glossy, animated donut painter with subtle rims & highlight
class GlossyDonutPainter extends CustomPainter {
  final List<ChartData> data;
  final double total;
  final double progress; // 0..1

  GlossyDonutPainter({
    required this.data,
    required this.total,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final innerR = outerR * 0.60; // donut hole radius

    // Background frosted circle (subtle)
    final bgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x22FFFFFF);
    canvas.drawCircle(center, outerR, bgPaint);

    if (total <= 0) {
      // empty ring with rims
      _drawRims(canvas, center, outerR, innerR);
      return;
    }

    // Draw segments with animated sweep
    double startAngle = -pi / 2;
    double remaining = 2 * pi * progress; // animated amount to draw
    final rect = Rect.fromCircle(center: center, radius: outerR);

    for (final item in data) {
      final fullSweep = 2 * pi * (item.y / total);
      final sweep = remaining.clamp(0.0, fullSweep);
      if (sweep <= 0) break;

      final segPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = item.color;

      // draw segment
      canvas.drawArc(rect, startAngle, sweep, true, segPaint);

      // subtle, inner gloss per segment (radial fade)
      final glossPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.20),
            const Color(0x00000000),
          ],
          stops: const [0.0, 1.0],
        ).createShader(rect);
      canvas.saveLayer(rect, Paint());
      canvas.drawArc(rect, startAngle, sweep, true, glossPaint);
      canvas.restore();

      startAngle += sweep;
      remaining -= sweep;

      if (remaining <= 0) break;
    }

    // Hollow center
    final holePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0D0E11);
    canvas.drawCircle(center, innerR, holePaint);

    // rims + highlight
    _drawRims(canvas, center, outerR, innerR);
    _drawTopHighlight(canvas, center, outerR, innerR);
  }

  void _drawRims(Canvas canvas, Offset c, double outerR, double innerR) {
    // Outer rim
    final outerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.15);
    canvas.drawCircle(c, outerR, outerRim);

    // Inner rim
    final innerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.08);
    canvas.drawCircle(c, innerR, innerRim);

    // Soft inner shadow (towards hole)
    final shadowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = const Color(0xFF000000).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(c, innerR + 1.5, shadowPaint);
  }

  void _drawTopHighlight(
      Canvas canvas, Offset c, double outerR, double innerR) {
    // Subtle curved highlight at the top of the donut
    final highlightRect = Rect.fromCircle(center: c, radius: outerR);
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFFFFF).withValues(alpha: 0.35),
          const Color(0xFFFFFFFF).withValues(alpha: 0.08),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.2, 0.6],
      ).createShader(highlightRect);

    final path = Path()
      ..addArc(highlightRect, -pi, pi) // top half
      ..addOval(Rect.fromCircle(center: c, radius: innerR * 0.85))
      ..fillType = PathFillType.evenOdd;

    canvas.saveLayer(highlightRect, Paint());
    canvas.drawPath(path, highlightPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GlossyDonutPainter old) {
    return old.data != data || old.total != total || old.progress != progress;
  }
}
