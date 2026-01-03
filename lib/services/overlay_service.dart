import 'dart:async';
import 'dart:ui';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  bool _isOverlayActive = false;
  StreamSubscription? _dataSubscription;

  // Overlay window size (larger than bubble to provide buffer zone)
  static const int overlaySize = 100;

  // Callback for when overlay sends data to main app
  Function(Map<String, dynamic>)? onOverlayData;

  bool get isOverlayActive => _isOverlayActive;

  /// Check if overlay permission is granted
  Future<bool> checkPermission() async {
    return await FlutterOverlayWindow.isPermissionGranted();
  }

  /// Request overlay permission from user
  Future<bool> requestPermission() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      // Wait a bit and check again
      await Future.delayed(const Duration(seconds: 1));
      return await FlutterOverlayWindow.isPermissionGranted();
    }
    return granted;
  }

  /// Start the floating overlay
  Future<bool> startOverlay() async {
    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        print('[OverlayService] No overlay permission');
        return false;
      }

      if (_isOverlayActive) {
        print('[OverlayService] Overlay already active');
        return true;
      }

      // Use PositionGravity.right to position on right edge automatically
      // This lets the system handle the positioning correctly
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'Neurix Voice',
        overlayContent: 'Tap to speak',
        flag: OverlayFlag.defaultFlag,
        visibility: NotificationVisibility.visibilityPublic,
        positionGravity: PositionGravity.right,
        height: overlaySize,
        width: overlaySize,
      );

      _isOverlayActive = true;
      _startListeningForData();

      print('[OverlayService] Overlay started');
      return true;
    } catch (e) {
      print('[OverlayService] Error starting overlay: $e');
      return false;
    }
  }

  /// Stop the floating overlay
  Future<void> stopOverlay() async {
    try {
      if (!_isOverlayActive) return;

      await FlutterOverlayWindow.closeOverlay();
      _isOverlayActive = false;
      _dataSubscription?.cancel();
      _dataSubscription = null;

      print('[OverlayService] Overlay stopped');
    } catch (e) {
      print('[OverlayService] Error stopping overlay: $e');
    }
  }

  /// Toggle overlay on/off
  Future<bool> toggleOverlay() async {
    if (_isOverlayActive) {
      await stopOverlay();
      return false;
    } else {
      return await startOverlay();
    }
  }

  /// Listen for data from overlay
  void _startListeningForData() {
    _dataSubscription = FlutterOverlayWindow.overlayListener.listen((data) {
      print('[OverlayService] Received data from overlay: $data');
      if (data is Map<String, dynamic> && onOverlayData != null) {
        onOverlayData!(data);
      }
    });
  }

  /// Send response back to overlay
  Future<void> sendResponseToOverlay(String response) async {
    try {
      await FlutterOverlayWindow.shareData({
        'type': 'response',
        'text': response,
      });
    } catch (e) {
      print('[OverlayService] Error sending response to overlay: $e');
    }
  }

  /// Resize overlay window (for expanded/collapsed states)
  Future<void> resizeOverlay({required bool expanded}) async {
    try {
      if (expanded) {
        await FlutterOverlayWindow.resizeOverlay(300, 200, true);
      } else {
        await FlutterOverlayWindow.resizeOverlay(100, 100, true);
      }
    } catch (e) {
      print('[OverlayService] Error resizing overlay: $e');
    }
  }

  /// Check if overlay is currently showing
  Future<bool> isOverlayShowing() async {
    return await FlutterOverlayWindow.isActive();
  }

  /// Dispose resources
  void dispose() {
    _dataSubscription?.cancel();
    _dataSubscription = null;
  }
}
