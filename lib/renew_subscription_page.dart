import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

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
  // Plans (amount in paise) + duration (months)
  static const Map<String, int> _planPricePaise = {
    'Starter (Monthly)': 19900, // ₹199.00
    'Pro (Monthly)': 49900, // ₹499.00
  };
  static const Map<String, int> _planDurationMonths = {
    'Starter (Monthly)': 1,
    'Pro (Monthly)': 1,
  };

  // Razorpay (TEST key ONLY on client)
  static const String _razorpayTestKeyId = 'rzp_test_RHY5l3aNeamrB8';
  late final Razorpay _razorpay;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _gyms = [];
  String? _selectedGymId;

  String _selectedPlan = _planPricePaise.keys.first;

  String? _prefillEmail;
  String? _prefillPhone;

  static const bool _logPaymentsToSupabase = true;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError)
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    _loadGyms();
    _loadPrefillUser();
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadPrefillUser() async {
    try {
      if (widget.fireBaseId == null || widget.fireBaseId!.isEmpty) return;
      final client = supa.Supabase.instance.client;
      final List<dynamic> data = await client
          .from('Fire')
          .select('EmailID, Phone')
          .eq('FireBaseID', widget.fireBaseId!)
          .limit(1);
      if (data.isNotEmpty) {
        final row = Map<String, dynamic>.from(data.first);
        setState(() {
          _prefillEmail = (row['EmailID'] as String?)?.trim();
          _prefillPhone = (row['Phone'] as String?)?.trim();
        });
      }
    } catch (_) {
      // optional prefill; ignore errors
    }
  }

  Future<void> _loadGyms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = supa.Supabase.instance.client;
      List<dynamic> data;

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

      _gyms = List<Map<String, dynamic>>.from(data);

      if (_gyms.isNotEmpty) {
        _selectedGymId = widget.preselectedGymId?.isNotEmpty == true
            ? widget.preselectedGymId
            : _gyms.first['GymID'] as String?;
      } else {
        _error = 'No gyms found for this account.';
      }
    } catch (e) {
      _error = 'Failed to load gyms: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openRazorpayCheckout() {
    if (_selectedGymId == null || _selectedGymId!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a Gym.')));
      return;
    }

    final amountPaise = _planPricePaise[_selectedPlan]!;
    final months = _planDurationMonths[_selectedPlan] ?? 1;

    final options = {
      'key': _razorpayTestKeyId,
      'amount': amountPaise, // paise
      'currency': 'INR',
      'name': 'Gym Manager',
      'description': '$_selectedPlan • $_selectedGymId • ${months}m',
      'timeout': 120,
      'send_sms_hash': true,
      'retry': {'enabled': true, 'max_count': 1},
      'prefill': {'email': _prefillEmail ?? '', 'contact': _prefillPhone ?? ''},
      'notes': {
        'gym_id': _selectedGymId!,
        'plan': _selectedPlan,
        'months': months.toString(),
        'firebase_id': widget.fireBaseId ?? '',
        'env': 'test',
      },
      'theme': {'color': '#3B82F6'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open Razorpay: $e')));
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse r) async {
    if (_logPaymentsToSupabase) {
      try {
        final client = supa.Supabase.instance.client;
        await client.from('Payments').insert({
          'GymID': _selectedGymId,
          'FireBaseID': widget.fireBaseId,
          'Plan': _selectedPlan,
          'AmountPaise': _planPricePaise[_selectedPlan],
          'Months': _planDurationMonths[_selectedPlan],
          'RazorpayPaymentId': r.paymentId,
          'RazorpayOrderId': r.orderId,
          'RazorpaySignature': r.signature,
          'Mode': 'TEST',
          'Status': 'success',
        });
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text('Success', style: TextStyle(color: Colors.white)),
        content: Text(
          'Payment ID: ${r.paymentId ?? "-"}\nOrder ID: ${r.orderId ?? "-"}',
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

  Future<void> _onPaymentError(PaymentFailureResponse r) async {
    final reason = (r.message != null && r.message!.isNotEmpty)
        ? r.message
        : 'Unknown error';

    if (_logPaymentsToSupabase) {
      try {
        final client = supa.Supabase.instance.client;
        await client.from('Payments').insert({
          'GymID': _selectedGymId,
          'FireBaseID': widget.fireBaseId,
          'Plan': _selectedPlan,
          'AmountPaise': _planPricePaise[_selectedPlan],
          'Months': _planDurationMonths[_selectedPlan],
          'RazorpayErrorCode': r.code,
          'RazorpayErrorMessage': reason,
          'Mode': 'TEST',
          'Status': 'failed',
        });
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: const Text(
          'Payment failed',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Code: ${r.code}\nMessage: $reason',
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

  void _onExternalWallet(ExternalWalletResponse r) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet selected: ${r.walletName}')),
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
                        color: const Color(0xFFFFFFFF).withOpacity(0.06),
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
                          onChanged: (v) => setState(() => _selectedGymId = v),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0x141A1C23),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: const Color(
                                  0xFFFFFFFF,
                                ).withOpacity(0.10),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: const Color(
                                  0xFFFFFFFF,
                                ).withOpacity(0.08),
                              ),
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
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
                        color: const Color(0xFFFFFFFF).withOpacity(0.06),
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

                  // Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openRazorpayCheckout,
                      icon: const Icon(Icons.payment),
                      label: const Text('Pay with Razorpay (TEST)'),
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
