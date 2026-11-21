import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '/func/export.dart';
import 'package:workmanager/workmanager.dart';
import '../cloud/cloud_service.dart';

class NotificationClass {
  static void initializeNotif() {
    AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelGroupKey: 'basic_channel_group',
          channelKey: 'basic_channel',
          channelName: 'Basic Notifications',
          channelDescription: 'Channel used by Trackgree notifications',
          defaultColor: AppTheme.seed,
          channelShowBadge: true,
          ledColor: Colors.white,
        ),
      ],
      channelGroups: [
        NotificationChannelGroup(
          channelGroupName: 'Basic Group',
          channelGroupKey: 'basic_channel_group',
        ),
      ],
      debug: false,
    );
  }

  static void askPermission(BuildContext context) async {
    try {
      final isAllowed = await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    } catch (_) {
      // Notifications indisponibles (ex. tests) : sans conséquence.
    }
  }

  static DateTime? _lastNotificationTime;

  static Future<void> openNotif(String title, String message) async {
    final now = DateTime.now();
    if (_lastNotificationTime != null &&
        now.difference(_lastNotificationTime!) < Duration(seconds: 5)) {
      return;
    }
    _lastNotificationTime = now;
    int randomId = now.millisecondsSinceEpoch.remainder(100000);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: randomId,
        channelKey: 'basic_channel',
        title: title,
        body: message,
        bigPicture: 'asset://assets/livia.png',
        notificationLayout: NotificationLayout.Inbox,
      ),
      actionButtons: [],
    );
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  final DatabaseHelper dbHelper = DatabaseHelper();
  Workmanager().executeTask((taskName, inputData) async {
    switch (taskName) {
      case "welcome-event":
        await dbHelper.checkExpiredDebt();
        // Synchro / sauvegarde automatiques en arrière-plan.
        await CloudService.instance.autoRun();
        break;
    }
    return Future.value(true);
  });
}

Future<void> initBackgroundFetch() async {
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "app.eden.manager",
    "welcome-event",
    frequency: const Duration(hours: 5),
  );
  Workmanager().registerOneOffTask("app.eden.manager", "welcome-event");
}

Future permissionContact() async {
  final hasPermission = await FlutterContacts.requestPermission();

  if (hasPermission) {
    print("✅ HAS CONTACT PERMISSION");
  } else {
    print("❌ PERMISSION DENIED");
  }
}
