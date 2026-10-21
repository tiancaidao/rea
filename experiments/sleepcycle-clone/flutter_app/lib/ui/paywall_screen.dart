import 'package:flutter/material.dart';
import '../data/api_client.dart';

/// Server-driven paywall: products come from the backend (/v1/paywall), mirroring
/// the original's "dynamic paywall". Purchase would go through StoreKit / Play
/// Billing via the in_app_purchase package; here the button is a mock.
class PaywallScreen extends StatelessWidget {
  final SleepApi api;
  const PaywallScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: api.paywallProducts(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 8),
              Text('Unlock premium',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Snore analysis, sleep aid, trends and more.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              for (final p in products)
                Card(
                  color: (p['highlight'] == true)
                      ? const Color(0xFF26306A)
                      : null,
                  child: ListTile(
                    title: Text(p['title'] as String),
                    subtitle: Text((p['trialDays'] as int) > 0
                        ? '${p['trialDays']}-day free trial'
                        : 'No trial'),
                    trailing: Text(p['price'] as String,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Mock purchase: ${p['sku']}')),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Real purchases use StoreKit (iOS) / Play Billing (Android) via '
                'the in_app_purchase package, validated server-side.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}
