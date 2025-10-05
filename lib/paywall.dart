import 'package:flutter/material.dart';
import 'renew_subscription_page.dart';

class PaywallPage extends StatelessWidget {
  final String fireBaseId;
  final DateTime? expiresAt;
  final VoidCallback? onClose;

  const PaywallPage({
    super.key,
    required this.fireBaseId,
    this.expiresAt,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final expiredText = expiresAt != null
        ? 'Your access expired on ${expiresAt!.toLocal().toString().split(".").first}.'
        : 'You don’t have an active subscription.';

    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1116),
        title: const Text('Unlock Gym0'),
        actions: [
          if (onClose != null)
            IconButton(icon: const Icon(Icons.close), onPressed: onClose),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF151922),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x22FFFFFF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.white70),
                const SizedBox(height: 16),
                const Text(
                  'Subscription required',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  expiredText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    _FeatureDot(text: 'Unlimited gym management'),
                    SizedBox(width: 12),
                    _FeatureDot(text: 'Trainer roster & tools'),
                    SizedBox(width: 12),
                    _FeatureDot(text: 'Priority support'),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment),
                    label: const Text('Renew / Subscribe'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RenewSubscriptionPage(fireBaseId: fireBaseId),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F8EF7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureDot extends StatelessWidget {
  final String text;
  const _FeatureDot({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.check_circle_outline, size: 18, color: Colors.white70),
        SizedBox(width: 6),
      ],
    );
  }
}
