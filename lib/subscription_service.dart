import 'package:supabase_flutter/supabase_flutter.dart' as supa;

class SubscriptionStatus {
  final bool active;
  final DateTime? expiresAt;
  final String message;
  const SubscriptionStatus({
    required this.active,
    this.expiresAt,
    this.message = '',
  });
}

DateTime _addMonths(DateTime dt, int months) {
  final int y = dt.year + ((dt.month - 1 + months) ~/ 12);
  final int m = (dt.month - 1 + months) % 12 + 1;
  final int d = dt.day;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(
    y,
    m,
    d > lastDay ? lastDay : d,
    dt.hour,
    dt.minute,
    dt.second,
    dt.millisecond,
    dt.microsecond,
  );
}

/// Uses latest successful row in `Payments` to compute expiry: created_at + Months.
Future<SubscriptionStatus> fetchSubscriptionStatus(
  String fireBaseId, {
  String? gymId,
}) async {
  try {
    final client = supa.Supabase.instance.client;

    List data;
    if (gymId != null && gymId.isNotEmpty) {
      // Build the fully-filtered query in one chain
      data = await client
          .from('Payments')
          .select('created_at, Months, Status')
          .eq('FireBaseID', fireBaseId)
          .eq('Status', 'success')
          .eq('GymID', gymId)
          .order('created_at', ascending: false)
          .limit(1);
    } else {
      data = await client
          .from('Payments')
          .select('created_at, Months, Status')
          .eq('FireBaseID', fireBaseId)
          .eq('Status', 'success')
          .order('created_at', ascending: false)
          .limit(1);
    }

    if (data.isEmpty) {
      return const SubscriptionStatus(
        active: false,
        message: 'No successful payments found.',
      );
    }

    final row = data.first as Map<String, dynamic>;
    final createdAtStr = row['created_at']?.toString();
    final months = (row['Months'] ?? 1) as int;

    if (createdAtStr == null) {
      return const SubscriptionStatus(
        active: false,
        message: 'Payment record missing created_at.',
      );
    }
    final createdAt = DateTime.tryParse(createdAtStr)?.toLocal();
    if (createdAt == null) {
      return const SubscriptionStatus(
        active: false,
        message: 'Could not parse created_at.',
      );
    }

    final expiresAt = _addMonths(createdAt, months);
    final now = DateTime.now();
    final active = now.isBefore(expiresAt);
    return SubscriptionStatus(
      active: active,
      expiresAt: expiresAt,
      message: active ? 'Active' : 'Expired',
    );
  } catch (e) {
    return SubscriptionStatus(
      active: false,
      message: 'Error checking subscription: $e',
    );
  }
}
