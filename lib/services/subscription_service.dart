import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription tier limits
class SubscriptionLimits {
  static const int freeMemories = 2;
  static const int freeReminders = 2;
  static const int proMemories = -1; // -1 = unlimited
  static const int proReminders = -1; // -1 = unlimited
}

/// Product IDs for Google Play / App Store
class SubscriptionProductIds {
  static const String monthlySubscription = 'neurix_pro_monthly';
  static const String yearlySubscription = 'neurix_pro_yearly';

  static const Set<String> allProducts = {
    monthlySubscription,
    yearlySubscription,
  };
}

/// Subscription status
enum SubscriptionStatus {
  free,
  pro,
  loading,
}

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _isAvailable = false;
  bool _isInitialized = false;
  SubscriptionStatus _status = SubscriptionStatus.loading;
  List<ProductDetails> _products = [];
  String? _errorMessage;

  // Getters
  bool get isAvailable => _isAvailable;
  bool get isPro => _status == SubscriptionStatus.pro;
  bool get isFree => _status == SubscriptionStatus.free;
  SubscriptionStatus get status => _status;
  List<ProductDetails> get products => _products;
  String? get errorMessage => _errorMessage;

  /// Get memory limit based on subscription
  int get memoryLimit => isPro ? SubscriptionLimits.proMemories : SubscriptionLimits.freeMemories;

  /// Get reminder limit based on subscription
  int get reminderLimit => isPro ? SubscriptionLimits.proReminders : SubscriptionLimits.freeReminders;

  /// Check if user can add more memories
  bool canAddMemory(int currentCount) {
    if (isPro) return true;
    return currentCount < SubscriptionLimits.freeMemories;
  }

  /// Check if user can add more reminders
  bool canAddReminder(int currentCount) {
    if (isPro) return true;
    return currentCount < SubscriptionLimits.freeReminders;
  }

  /// Initialize the subscription service
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('[SubscriptionService] Initializing...');

    // Check if in-app purchases are available
    _isAvailable = await _inAppPurchase.isAvailable();

    if (!_isAvailable) {
      print('[SubscriptionService] In-app purchases not available');
      _status = SubscriptionStatus.free;
      _isInitialized = true;
      notifyListeners();
      return;
    }

    // Listen to purchase updates
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: _onPurchaseStreamDone,
      onError: _onPurchaseError,
    );

    // Load products
    await _loadProducts();

    // Restore purchases to check subscription status
    await restorePurchases();

    _isInitialized = true;
    print('[SubscriptionService] Initialized - Status: $_status');
  }

  Future<void> _loadProducts() async {
    print('[SubscriptionService] Loading products...');

    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(
      SubscriptionProductIds.allProducts,
    );

    if (response.error != null) {
      print('[SubscriptionService] Error loading products: ${response.error}');
      _errorMessage = response.error?.message;
    }

    if (response.notFoundIDs.isNotEmpty) {
      print('[SubscriptionService] Products not found: ${response.notFoundIDs}');
    }

    _products = response.productDetails;
    print('[SubscriptionService] Loaded ${_products.length} products');

    for (final product in _products) {
      print('[SubscriptionService] Product: ${product.id} - ${product.price}');
    }

    notifyListeners();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    print('[SubscriptionService] Purchase update: ${purchaseDetailsList.length} items');

    for (final purchase in purchaseDetailsList) {
      _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    print('[SubscriptionService] Handling purchase: ${purchase.productID} - ${purchase.status}');

    switch (purchase.status) {
      case PurchaseStatus.pending:
        // Show loading indicator
        _status = SubscriptionStatus.loading;
        notifyListeners();
        break;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // Verify and deliver the product
        final valid = await _verifyPurchase(purchase);
        if (valid) {
          await _deliverProduct(purchase);
        }

        // Complete the purchase
        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
        break;

      case PurchaseStatus.error:
        print('[SubscriptionService] Purchase error: ${purchase.error}');
        _errorMessage = purchase.error?.message;
        _status = SubscriptionStatus.free;
        notifyListeners();

        if (purchase.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchase);
        }
        break;

      case PurchaseStatus.canceled:
        print('[SubscriptionService] Purchase canceled');
        _status = SubscriptionStatus.free;
        notifyListeners();
        break;
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    // For production, you should verify the purchase with your backend server
    // For now, we'll trust the purchase locally
    print('[SubscriptionService] Verifying purchase: ${purchase.productID}');
    return true;
  }

  Future<void> _deliverProduct(PurchaseDetails purchase) async {
    print('[SubscriptionService] Delivering product: ${purchase.productID}');

    // Save subscription status locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro', true);
    await prefs.setString('subscription_product_id', purchase.productID);

    _status = SubscriptionStatus.pro;
    _errorMessage = null;
    notifyListeners();

    print('[SubscriptionService] User upgraded to Pro!');
  }

  void _onPurchaseStreamDone() {
    print('[SubscriptionService] Purchase stream done');
    _subscription?.cancel();
  }

  void _onPurchaseError(dynamic error) {
    print('[SubscriptionService] Purchase stream error: $error');
    _errorMessage = error.toString();
    notifyListeners();
  }

  /// Purchase a subscription
  Future<bool> purchaseSubscription(ProductDetails product) async {
    print('[SubscriptionService] Purchasing: ${product.id}');

    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
    );

    try {
      final success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      return success;
    } catch (e) {
      print('[SubscriptionService] Purchase error: $e');
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    print('[SubscriptionService] Restoring purchases...');

    // First check local cache
    final prefs = await SharedPreferences.getInstance();
    final isPro = prefs.getBool('is_pro') ?? false;

    if (isPro) {
      _status = SubscriptionStatus.pro;
      notifyListeners();
      print('[SubscriptionService] Found cached Pro status');
    } else {
      _status = SubscriptionStatus.free;
      notifyListeners();
    }

    // Then restore from store
    if (_isAvailable) {
      try {
        await _inAppPurchase.restorePurchases();
      } catch (e) {
        print('[SubscriptionService] Restore error: $e');
      }
    }
  }

  /// Get the monthly subscription product
  ProductDetails? get monthlyProduct {
    try {
      return _products.firstWhere(
        (p) => p.id == SubscriptionProductIds.monthlySubscription,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get the yearly subscription product
  ProductDetails? get yearlyProduct {
    try {
      return _products.firstWhere(
        (p) => p.id == SubscriptionProductIds.yearlySubscription,
      );
    } catch (_) {
      return null;
    }
  }

  /// Clear subscription (for testing)
  Future<void> clearSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('is_pro');
    await prefs.remove('subscription_product_id');
    _status = SubscriptionStatus.free;
    notifyListeners();
    print('[SubscriptionService] Subscription cleared');
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
