import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一条本地通知的展示内容与点击载荷。
///
/// 内容构造是纯函数（见 [NotificationService.buildSuccessContent] 与
/// [NotificationService.buildFailureContent]），可脱离平台通道单元测试。
class NotificationContent {
  const NotificationContent({
    required this.title,
    required this.body,
    required this.payload,
  });

  final String title;
  final String body;

  /// 点击通知时回传给 APP 的标记，用于决定跳转目标。
  final String payload;
}

/// 本地通知基础设施（模块 13）。
///
/// V1.0 只做识别结果通知（成功 / 失败）；真正的 OCR 事件触发在 Phase 4 接入，
/// 任意处调用 [showRecognitionSuccess] / [showRecognitionFailure] 即可发出。
/// 用餐提醒 / 缺口提醒渠道（reminders）在 init 时一并创建，供 V1.1 使用。
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 通知点击事件广播流；payload 见 [payloadSuccess] / [payloadFailure]。
  static final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  /// 点击识别成功通知后的跳转标记（跳今日首页）。
  static const String payloadSuccess = 'recognition_success';

  /// 点击识别失败通知后的跳转标记（跳手动添加页）。
  static const String payloadFailure = 'recognition_failure';

  static const String channelIdRecognition = 'recognition';
  static const String channelNameRecognition = '识别结果';
  static const String channelIdReminders = 'reminders';
  static const String channelNameReminders = '用餐提醒';

  static bool _initialized = false;

  /// 识别结果通知开关（设置页可切换）。
  ///
  /// V1.0 为内存态：进程内生效，与 AppState 的用餐/缺口提醒开关保持同一
  /// 持久化水平；落盘持久化列入遗留问题。
  static bool recognitionEnabled = true;

  static Stream<String> get onTap => _tapController.stream;

  static bool get initialized => _initialized;

  /// 初始化插件并创建 Android 通知渠道。
  ///
  /// [onTap] 为可选的点击回调，注册后与 [onTap] 流同时收到通知点击事件。
  static Future<void> init({void Function(String payload)? onTap}) async {
    if (_initialized) {
      return;
    }
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) {
          return;
        }
        onTap?.call(payload);
        _tapController.add(payload);
      },
    );
    await _createAndroidChannels();
    _initialized = true;
  }

  static Future<void> _createAndroidChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return;
    }
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelIdRecognition,
        channelNameRecognition,
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelIdReminders,
        channelNameReminders,
        importance: Importance.defaultImportance,
      ),
    );
  }

  /// 申请通知权限（Android 13+ / iOS）。已授权或平台不支持时返回 true。
  static Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ??
      false;
    }
    return true;
  }

  /// 构造识别成功通知内容（纯函数）。
  static NotificationContent buildSuccessContent({
    required String mealType,
    required String dishName,
    required String petText,
  }) {
    final trimmedDish = dishName.trim();
    final trimmedPet = petText.trim();
    final body = trimmedPet.isEmpty
        ? trimmedDish
        : '$trimmedDish · $trimmedPet';
    return NotificationContent(
      title: '已记录$mealType',
      body: body,
      payload: payloadSuccess,
    );
  }

  /// 构造识别失败通知内容（纯函数）。
  static NotificationContent buildFailureContent() =>
      const NotificationContent(
        title: '没认出来 🤔',
        body: '这张图没认出来，打开APP手动添加吧',
        payload: payloadFailure,
      );

  /// 展示识别成功通知。开关关闭时不发送。
  static Future<void> showRecognitionSuccess({
    required String mealType,
    required String dishName,
    required String petText,
  }) async {
    if (!recognitionEnabled) {
      return;
    }
    final content = buildSuccessContent(
      mealType: mealType,
      dishName: dishName,
      petText: petText,
    );
    await _show(content);
  }

  /// 展示识别失败通知。开关关闭时不发送。
  static Future<void> showRecognitionFailure() async {
    if (!recognitionEnabled) {
      return;
    }
    await _show(buildFailureContent());
  }

  /// OCR 来源记录保存成功后的确认通知（模块 14 技术决策 3）：
  /// 菜名 + 宠物当日对话台词，走 [showRecognitionSuccess] 且受
  /// recognitionEnabled 开关控制；平台通道异常静默吞掉，不阻塞保存流程。
  ///
  /// [mealType] 传记录里的英文编码（breakfast/lunch/dinner/snack），
  /// 内部映射为中文餐次。识别失败路径不调用本方法（不发通知）。
  static Future<void> showOcrSaveSuccess({
    required String mealType,
    required String dishName,
    required String petText,
  }) async {
    const labels = {
      'breakfast': '早餐',
      'lunch': '午餐',
      'dinner': '晚餐',
      'snack': '加餐',
    };
    try {
      await showRecognitionSuccess(
        mealType: labels[mealType] ?? '加餐',
        dishName: dishName,
        petText: petText,
      );
    } catch (_) {
      // 通知失败不影响保存结果。
    }
  }

  static Future<void> _show(NotificationContent content) async {
    if (!_initialized) {
      await init();
    }
    const androidDetails = AndroidNotificationDetails(
      channelIdRecognition,
      channelNameRecognition,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      content.title,
      content.body,
      details,
      payload: content.payload,
    );
  }

  /// 供测试重置内存状态。
  static void resetForTest() {
    recognitionEnabled = true;
    _initialized = false;
  }

  /// 仅供测试：模拟一次通知点击。
  static void emitTapForTest(String payload) => _tapController.add(payload);
}

/// 三个通知开关的持久化（shared_preferences）：
/// 识别结果（[NotificationService.recognitionEnabled]）、
/// 用餐提醒与缺口提醒（AppState.mealReminder / gapReminder）。
class NotificationSwitchPrefs {
  NotificationSwitchPrefs._();

  static const _recognitionKey = 'notification_recognition_enabled';
  static const _mealReminderKey = 'notification_meal_reminder';
  static const _gapReminderKey = 'notification_gap_reminder';

  /// 读取全部开关；未落盘的键返回默认值（识别通知开，提醒关）。
  static Future<NotificationSwitchSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationSwitchSnapshot(
      recognitionEnabled:
          prefs.getBool(_recognitionKey) ?? NotificationService.recognitionEnabled,
      mealReminder: prefs.getBool(_mealReminderKey) ?? false,
      gapReminder: prefs.getBool(_gapReminderKey) ?? false,
    );
  }

  /// 保存传入的非空开关（只写变化项，互不影响）。
  static Future<void> save({
    bool? recognition,
    bool? mealReminder,
    bool? gapReminder,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (recognition != null) {
      await prefs.setBool(_recognitionKey, recognition);
    }
    if (mealReminder != null) {
      await prefs.setBool(_mealReminderKey, mealReminder);
    }
    if (gapReminder != null) {
      await prefs.setBool(_gapReminderKey, gapReminder);
    }
  }
}

/// 通知开关快照（启动恢复用）。
class NotificationSwitchSnapshot {
  const NotificationSwitchSnapshot({
    required this.recognitionEnabled,
    required this.mealReminder,
    required this.gapReminder,
  });

  final bool recognitionEnabled;
  final bool mealReminder;
  final bool gapReminder;
}
