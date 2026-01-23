import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';

class UpgradeScreen extends StatefulWidget {
  final String? limitReachedType; // 'memory' or 'reminder' if shown due to limit

  const UpgradeScreen({super.key, this.limitReachedType});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    // Ensure subscription service is initialized
    SubscriptionService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ChangeNotifierProvider.value(
        value: SubscriptionService(),
        child: Consumer<SubscriptionService>(
          builder: (context, subscription, child) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Header
                  const Icon(
                    Icons.workspace_premium,
                    size: 80,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Upgrade to Pro',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Limit reached message
                  if (widget.limitReachedType != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.limitReachedType == 'memory'
                                  ? 'You\'ve reached the free limit of ${SubscriptionLimits.freeMemories} memories'
                                  : 'You\'ve reached the free limit of ${SubscriptionLimits.freeReminders} reminders',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    const Text(
                      'Unlock unlimited memories and reminders',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Features comparison
                  _buildFeaturesCard(),
                  const SizedBox(height: 32),

                  // Pricing options
                  if (subscription.status == SubscriptionStatus.loading)
                    const CircularProgressIndicator(color: Colors.green)
                  else if (subscription.isPro)
                    _buildAlreadyProCard()
                  else
                    _buildPricingOptions(subscription),

                  const SizedBox(height: 16),

                  // Error message
                  if (subscription.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        subscription.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Restore purchases
                  if (!subscription.isPro)
                    TextButton(
                      onPressed: () async {
                        await subscription.restorePurchases();
                        if (mounted && subscription.isPro) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Subscription restored!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Restore Purchases',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Terms and privacy
                  const Text(
                    'Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in your Play Store settings.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFeaturesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildFeatureRow(
            'Memories',
            '${SubscriptionLimits.freeMemories}',
            'Unlimited',
          ),
          const Divider(color: Colors.grey, height: 24),
          _buildFeatureRow(
            'Reminders',
            '${SubscriptionLimits.freeReminders}',
            'Unlimited',
          ),
          const Divider(color: Colors.grey, height: 24),
          _buildFeatureRow(
            'Voice Commands',
            'Yes',
            'Yes',
          ),
          const Divider(color: Colors.grey, height: 24),
          _buildFeatureRow(
            'Cloud Sync',
            'Yes',
            'Yes',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String feature, String free, String pro) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            feature,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            free,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (pro == 'Unlimited')
                const Icon(Icons.all_inclusive, color: Colors.green, size: 18)
              else
                const Icon(Icons.check, color: Colors.green, size: 18),
              const SizedBox(width: 4),
              Text(
                pro == 'Unlimited' ? '' : pro,
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPricingOptions(SubscriptionService subscription) {
    final monthlyProduct = subscription.monthlyProduct;
    final yearlyProduct = subscription.yearlyProduct;

    // If products are not loaded from store, show placeholder prices
    final monthlyPrice = monthlyProduct?.price ?? '\$1.99/month';
    final yearlyPrice = yearlyProduct?.price ?? '\$14.99/year';

    return Column(
      children: [
        // Yearly - Best value
        _buildPricingCard(
          title: 'Yearly',
          price: yearlyPrice,
          subtitle: 'Best value - Save 37%',
          isRecommended: true,
          onTap: () => _handlePurchase(subscription, yearlyProduct),
        ),
        const SizedBox(height: 12),

        // Monthly
        _buildPricingCard(
          title: 'Monthly',
          price: monthlyPrice,
          subtitle: 'Cancel anytime',
          isRecommended: false,
          onTap: () => _handlePurchase(subscription, monthlyProduct),
        ),
      ],
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String subtitle,
    required bool isRecommended,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isPurchasing ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRecommended ? Colors.green.withOpacity(0.1) : Colors.grey[900],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended ? Colors.green : Colors.grey[700]!,
            width: isRecommended ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isRecommended ? Colors.green : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'BEST VALUE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(
                color: isRecommended ? Colors.green : Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              color: isRecommended ? Colors.green : Colors.grey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlreadyProCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'You\'re a Pro!',
            style: TextStyle(
              color: Colors.green,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enjoy unlimited memories and reminders',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Back to App',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePurchase(
    SubscriptionService subscription,
    dynamic product,
  ) async {
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product not available. Please try again later.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isPurchasing = true);

    try {
      final success = await subscription.purchaseSubscription(product);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Processing purchase...'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }
}
