import 'package:flutter/material.dart';
import 'dart:math'; // For pie chart angles
import 'package:intl/intl.dart'; // for short date labels

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
  // Original Student Data
  final List<Map<String, dynamic>> students = [
    {
      'name': 'Roktim Konch',
      'membership': 'Premium',
      'joinDate': '2023-01-15',
      'feeStatus': 'Paid',
      'attendance': 'Present',
      'phone': '555-1234'
    },
    {
      'name': 'Lakhya Konwar',
      'membership': 'Standard',
      'joinDate': '2023-02-20',
      'feeStatus': 'Unpaid',
      'attendance': 'Absent',
      'phone': '555-5678'
    },
    {
      'name': 'Mrinmoy SAndilya',
      'membership': 'Premium',
      'joinDate': '2023-03-10',
      'feeStatus': 'Paid',
      'attendance': 'Present',
      'phone': '555-9012'
    },
    {
      'name': 'The Undertaker',
      'membership': 'Standard',
      'joinDate': '2023-04-05',
      'feeStatus': 'Paid',
      'attendance': 'Present',
      'phone': '555-3456'
    },
    {
      'name': 'Modi Ji',
      'membership': 'Premium',
      'joinDate': '2023-05-12',
      'feeStatus': 'Unpaid',
      'attendance': 'Absent',
      'phone': '555-7890'
    },
    {
      'name': 'Trump President',
      'membership': 'Standard',
      'joinDate': '2023-06-18',
      'feeStatus': 'Paid',
      'attendance': 'Present',
      'phone': '555-2345'
    },
    {
      'name': 'xyx xyz',
      'membership': 'Premium',
      'joinDate': '2023-07-22',
      'feeStatus': 'Unpaid',
      'attendance': 'Present',
      'phone': '555-6789'
    },
    {
      'name': 'Blah Blah',
      'membership': 'Standard',
      'joinDate': '2023-08-30',
      'feeStatus': 'Paid',
      'attendance': 'Absent',
      'phone': '555-0123'
    },
    {
      'name': 'Blah 1',
      'membership': 'Premium',
      'joinDate': '2023-09-05',
      'feeStatus': 'Paid',
      'attendance': 'Present',
      'phone': '555-4567'
    },
    {
      'name': 'VC',
      'membership': 'Standard',
      'joinDate': '2023-10-11',
      'feeStatus': 'Unpaid',
      'attendance': 'Absent',
      'phone': '555-8901'
    },
  ];

  // Filtered Students
  List<Map<String, dynamic>> filteredStudents = [];

  // Filters
  String searchQuery = "";
  String feeFilter = "All";
  String attendanceFilter = "All";
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    filteredStudents = students;
  }

  // Apply filters together
  void applyFilters() {
    setState(() {
      filteredStudents = students.where((student) {
        final nameMatch =
            student['name'].toLowerCase().contains(searchQuery.toLowerCase());

        final feeMatch =
            (feeFilter == "All" || student['feeStatus'] == feeFilter);

        final attendanceMatch = (attendanceFilter == "All" ||
            student['attendance'] == attendanceFilter);

        final joinDate = DateTime.parse(student['joinDate']);
        final dateMatch = (startDate == null && endDate == null) ||
            (startDate != null &&
                endDate != null &&
                joinDate
                    .isAfter(startDate!.subtract(const Duration(days: 1))) &&
                joinDate.isBefore(endDate!.add(const Duration(days: 1))));

        return nameMatch && feeMatch && attendanceMatch && dateMatch;
      }).toList();
    });
  }

  // Short label for date button (prevents overflow)
  String _dateLabel() {
    if (startDate != null && endDate != null) {
      final f = DateFormat('dd MMM yy');
      return '${f.format(startDate!)} – ${f.format(endDate!)}';
    }
    return 'Filter by Date';
  }

  // Pick Date Range
  Future<void> pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime(2030),
      initialDateRange: startDate != null && endDate != null
          ? DateTimeRange(start: startDate!, end: endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
        applyFilters();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pie Chart Data
    final paidCount =
        filteredStudents.where((s) => s['feeStatus'] == 'Paid').length;
    final unpaidCount = filteredStudents.length - paidCount;

    final presentCount =
        filteredStudents.where((s) => s['attendance'] == 'Present').length;
    final absentCount = filteredStudents.length - presentCount;

    final paymentData = [
      ChartData('Paid', paidCount, Colors.green),
      ChartData('Unpaid', unpaidCount, Colors.red),
    ];

    final attendanceData = [
      ChartData('Present', presentCount, Colors.blue),
      ChartData('Absent', absentCount, Colors.orange),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: Text('${widget.gymName} - Dashboard'),
        leading: Container(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2F3A),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 24.0),
              ),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Go Back',
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gym Info
            Text('Location: ${widget.gymLocation}',
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text('Capacity: ${widget.gymCapacity} students',
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),

            // 🔎 Search
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search by name...",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1A1C23),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
              ),
              onChanged: (value) {
                searchQuery = value;
                applyFilters();
              },
            ),
            const SizedBox(height: 10),

            // ✅ Overflow-proof filters bar (with Clear Date button)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Fee Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1C23),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: feeFilter,
                      dropdownColor: const Color(0xFF1A1C23),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox.shrink(),
                      items: ["All", "Paid", "Unpaid"]
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) {
                        feeFilter = value!;
                        applyFilters();
                      },
                    ),
                  ),

                  // Attendance Filter
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1C23),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: attendanceFilter,
                      dropdownColor: const Color(0xFF1A1C23),
                      style: const TextStyle(color: Colors.white),
                      underline: const SizedBox.shrink(),
                      items: ["All", "Present", "Absent"]
                          .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (value) {
                        attendanceFilter = value!;
                        applyFilters();
                      },
                    ),
                  ),

                  // Date Range Picker + Clear Button (shows ✖ only when selected)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(minWidth: 160, maxWidth: 240),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1C23),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onPressed: pickDateRange,
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
                      ),
                      if (startDate != null && endDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white),
                          tooltip: "Clear Date Filter",
                          onPressed: () {
                            setState(() {
                              startDate = null;
                              endDate = null;
                              applyFilters();
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Pie Charts Row
            Row(
              children: [
                Expanded(child: _buildPieChart(paymentData, 'Payment Status')),
                const SizedBox(width: 16),
                Expanded(child: _buildPieChart(attendanceData, 'Attendance')),
              ],
            ),

            const SizedBox(height: 20),

            const Text(
              "Student Information",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Expanded(child: _buildStudentTable()),
          ],
        ),
      ),
    );
  }

  // Build Pie Chart
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
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: 150,
            child: CustomPaint(
              painter: PieChartPainter(data: data, total: total.toDouble()),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: data
                .map((item) => Row(
                      children: [
                        Container(width: 12, height: 12, color: item.color),
                        const SizedBox(width: 5),
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

  // Build Student Table
  Widget _buildStudentTable() {
    final columns = [
      'Name',
      'Membership',
      'Join Date',
      'Fee Status',
      'Attendance',
      'Phone'
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C23),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: columns
                .map(
                  (column) => DataColumn(
                    label: Text(
                      column,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                )
                .toList(),
            rows: filteredStudents.map((student) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(student['name'],
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  DataCell(
                    Text(student['membership'],
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  DataCell(
                    Text(student['joinDate'],
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  DataCell(
                    Text(
                      student['feeStatus'],
                      style: TextStyle(
                        color: student['feeStatus'] == 'Paid'
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      student['attendance'],
                      style: TextStyle(
                        color: student['attendance'] == 'Present'
                            ? Colors.blue
                            : Colors.orange,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(student['phone'],
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// Chart Data Model
class ChartData {
  final String x;
  final int y;
  final Color color;
  ChartData(this.x, this.y, this.color);
}

// Pie Chart Painter
class PieChartPainter extends CustomPainter {
  final List<ChartData> data;
  final double total;
  PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    // Avoid division by zero if total is 0
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
      final sweepAngle = 2 * pi * (item.y / total);
      paint.color = item.color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          startAngle, sweepAngle, true, paint);
      startAngle += sweepAngle;
    }

    // Donut hole
    paint.color = const Color(0xFF1A1C23);
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
