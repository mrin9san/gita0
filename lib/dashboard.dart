import 'package:flutter/material.dart';
import 'dart:math'; // Add this import for pi constant

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
  // Random student data
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

  @override
  Widget build(BuildContext context) {
    // Calculate stats for pie charts
    int paidCount = students.where((s) => s['feeStatus'] == 'Paid').length;
    int unpaidCount = students.length - paidCount;

    int presentCount =
        students.where((s) => s['attendance'] == 'Present').length;
    int absentCount = students.length - presentCount;

    // Data for payment status chart
    List<ChartData> paymentData = [
      ChartData('Paid', paidCount, Colors.green),
      ChartData('Unpaid', unpaidCount, Colors.red),
    ];

    // Data for attendance chart
    List<ChartData> attendanceData = [
      ChartData('Present', presentCount, Colors.blue),
      ChartData('Absent', absentCount, Colors.orange),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E11),
        elevation: 0,
        title: Text('${widget.gymName} - Dashboard'),
        leading: Container(), // Empty leading to move actions to right
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
                child: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24.0,
                ),
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
            // Gym info
            Text(
              'Location: ${widget.gymLocation}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Capacity: ${widget.gymCapacity} students',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),

            // Pie charts row
            Row(
              children: [
                // Payment status pie chart
                Expanded(
                  child: _buildPieChart(
                    paymentData,
                    'Payment Status',
                  ),
                ),
                const SizedBox(width: 16),

                // Attendance pie chart
                Expanded(
                  child: _buildPieChart(
                    attendanceData,
                    'Attendance',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Students table header
            const Text(
              'Student Information',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            // Students table
            Expanded(
              child: _buildStudentTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(List<ChartData> data, String title) {
    double total = data.fold(0, (sum, item) => sum + item.y);
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
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            width: 150,
            child: CustomPaint(
              painter: PieChartPainter(data: data, total: total),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: data.map((item) {
              return Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    color: item.color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${item.x}: ${item.y}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentTable() {
    // Define table columns
    List<String> columns = [
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
            columns: columns.map((column) {
              return DataColumn(
                label: Text(
                  column,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
            rows: students.map((student) {
              return DataRow(
                cells: [
                  DataCell(Text(
                    student['name'],
                    style: const TextStyle(color: Colors.white70),
                  )),
                  DataCell(Text(
                    student['membership'],
                    style: const TextStyle(color: Colors.white70),
                  )),
                  DataCell(Text(
                    student['joinDate'],
                    style: const TextStyle(color: Colors.white70),
                  )),
                  DataCell(Text(
                    student['feeStatus'],
                    style: TextStyle(
                      color: student['feeStatus'] == 'Paid'
                          ? Colors.green
                          : Colors.red,
                    ),
                  )),
                  DataCell(Text(
                    student['attendance'],
                    style: TextStyle(
                      color: student['attendance'] == 'Present'
                          ? Colors.blue
                          : Colors.orange,
                    ),
                  )),
                  DataCell(Text(
                    student['phone'],
                    style: const TextStyle(color: Colors.white70),
                  )),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// Helper class for chart data
class ChartData {
  final String x;
  final int y;
  final Color color;

  ChartData(this.x, this.y, this.color);
}

// Custom Painter for Pie Chart
class PieChartPainter extends CustomPainter {
  final List<ChartData> data;
  final double total;

  PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    double startAngle = -pi / 2; // Start at the top

    for (var item in data) {
      final sweepAngle = 2 * pi * (item.y / total);
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

    // Draw center circle for donut effect
    paint.color = const Color(0xFF1A1C23);
    canvas.drawCircle(center, radius * 0.6, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
