import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Razorpay-free placeholder page:
/// - Keeps the same UI: Gym dropdown + Plan radios + "Pay with Razorpay" button
/// - Button now just shows a "Gateway not configured yet" dialog
class RenewSubscriptionPage extends StatefulWidget {
  final String? fireBaseId;
  final String? preselectedGymId;

  const RenewSubscriptionPage({
    super.key,
    this.fireBaseId,
    this.preselectedGymId,
  });

  @override
  State<RenewSubscriptionPage> createState() => _RenewSubscriptionPageState();
}

class _RenewSubscriptionPageState extends State<RenewSubscriptionPage> {
  // Plans (amount in paise) + duration (months) — unchanged
  static const Map<String, int> _planPricePaise = {
    'Starter (Monthly)': 19900, // ₹199.00
    'Pro (Monthly)': 49900, // ₹499.00
  };
  static const Map<String, int> _planDurationMonths = {
    'Starter (Monthly)': 1,
    'Pro (Monthly)': 1,
  };

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _gyms = [];
  String? _selectedGymId;

  String _selectedPlan = _planPricePaise.keys.first;

  @override
  void initState() {
    super.initState();
    _loadGyms();
  }

  Future<void> _loadGyms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = supa.Supabase.instance.client;
      List data;

      if (widget.preselectedGymId != null &&
          widget.preselectedGymId!.isNotEmpty) {
        data = await client
            .from('Gyms')
            .select('GymID, GymName, Location')
            .eq('GymID', widget.preselectedGymId!);
      } else if (widget.fireBaseId != null && widget.fireBaseId!.isNotEmpty) {
        data = await client
            .from('Gyms')
            .select('GymID, GymName, Location')
            .eq('FireBaseID', widget.fireBaseId!);
      } else {
        data = const [];
      }

      final gyms = List<Map<String, dynamic>>.from(data);
      _gyms = gyms;

      // default selection
      if (_gyms.isNotEmpty) {
        if (widget.preselectedGymId != null &&
            widget.preselectedGymId!.isNotEmpty) {
          _selectedGymId = widget.preselectedGymId;
        } else {
          _selectedGymId = _gyms.first['GymID'] as String?;
        }
      } else {
        _error = 'No gyms found for this account.';
      }
    } catch (e) {
      _error = 'Failed to load gyms: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPaymentPlaceholder() {
    if (_selectedGymId == null || _selectedGymId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Gym.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Payment gateway not configured',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'You selected: $_selectedPlan\n\n'
          'Online payments are coming soon. Please configure Razorpay (or mark payment offline) to continue.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1116),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1116),
        elevation: 0,
        title: const Text(
          'Renew / Update Subscription',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gym selector
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0x191A1C23),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Gym',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedGymId,
                              dropdownColor: const Color(0xFF1A1C23),
                              items: _gyms.map((g) {
                                final id = g['GymID'] as String;
                                final name = (g['GymName'] ?? 'Gym') as String;
                                final loc = (g['Location'] ?? '') as String;
                                return DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    '$name • $loc',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedGymId = v),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: const Color(0x141A1C23),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: const Color(0xFFFFFFFF)
                                        .withValues(alpha: 0.10),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: const Color(0xFFFFFFFF)
                                        .withValues(alpha: 0.08),
                                  ),
                                ),
                              ),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Plan selector
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0x191A1C23),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                const Color(0xFFFFFFFF).withValues(alpha: 0.06),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Choose Plan',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ..._planPricePaise.entries.map((e) {
                              final label = e.key;
                              final price = e.value / 100.0;
                              return RadioListTile<String>(
                                dense: true,
                                value: label,
                                groupValue: _selectedPlan,
                                activeColor: Colors.white,
                                onChanged: (v) =>
                                    setState(() => _selectedPlan = v!),
                                title: Text(
                                  '$label — ₹${price.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Button kept, but no gateway calls
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startPaymentPlaceholder,
                          icon: const Icon(Icons.payment),
                          label: const Text('Pay with Razorpay'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
