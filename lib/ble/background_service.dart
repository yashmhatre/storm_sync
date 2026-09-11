import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../audio/thunder_player.dart';
import '../model/app_settings.dart';
import 'storm_service.dart';

/// Actions triggered from lock screen / notification drawer buttons.
enum NotificationAction {
  strikeNear('action_strike_near', 'Strike'),
  sheet('action_sheet', 'Sheet'),
  glow('action_glow', 'Glow'),
  off('action_off', 'Off');

  const NotificationAction(this.id, this.label);
  final String id;
  final String label;

  static NotificationAction? fromId(String? id) {
    if (id == null) return null;
    for (final action in NotificationAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// Maintains a persistent notification with quick-action lightning controls
/// to keep the app and BLE link prioritized by the Android OS in the background.
class BackgroundRemoteService {
  BackgroundRemoteService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  static const int _notificationId = 1001;
  static const String _channelId = 'strom_sync_bg_remote';
  static const String _channelName = 'StromSync Background Remote';
  static const String _channelDescription =
      'Persistent notification controls to trigger lightning while minimized.';

  bool get isInitialized => _initialized;

  /// Initializes local notifications with lock-screen action support.
  Future<void> initialize({
    void Function(NotificationAction action)? onActionSelected,
  }) async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final action = NotificationAction.fromId(response.actionId);
        if (action != null && onActionSelected != null) {
          onActionSelected(action);
        }
      },
    );

    _initialized = true;
  }

  /// Dispatches a notification action to the corresponding hardware and audio services.
  void dispatchAction({
    required NotificationAction action,
    required StormService stormService,
    required ThunderPlayer thunderPlayer,
    required AppSettings appSettings,
  }) {
    switch (action) {
      case NotificationAction.strikeNear:
        stormService.send('STRIKE 230');
        final delay = appSettings.audioDelayFor(ThunderDistance.close.distanceDelayMs);
        thunderPlayer.playAfter(ThunderDistance.close, delay);
      case NotificationAction.sheet:
        stormService.send('SHEET');
        final delay = appSettings.audioDelayFor(ThunderDistance.far.distanceDelayMs);
        thunderPlayer.playAfter(ThunderDistance.far, delay);
      case NotificationAction.glow:
        stormService.setMode('GLOW');
      case NotificationAction.off:
        stormService.setMode('OFF');
    }
  }

  /// Updates or dismisses the persistent notification depending on BLE connection status.
  Future<void> updateNotification({
    required bool isConnected,
    required String? mode,
    required String statusText,
  }) async {
    if (!_initialized) return;

    if (!isConnected) {
      // If disconnected or idle, dismiss notification
      await _plugin.cancel(id: _notificationId);
      return;
    }

    final modeLabel = mode?.isNotEmpty == true ? mode! : 'ACTIVE';
    final title = 'StromSync • $modeLabel';
    final body = 'Connected: $statusText';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low, // Do not chime repeatedly on state syncs
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      category: AndroidNotificationCategory.service,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'action_strike_near',
          '⚡ Strike',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'action_sheet',
          '☁ Sheet',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'action_glow',
          '✨ Glow',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          'action_off',
          '⏻ Off',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }

  /// Clears the notification on app termination.
  Future<void> cancel() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _notificationId);
  }
}
