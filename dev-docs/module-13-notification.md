# 模块 13：本地通知

**预估工时**：2h
**依赖**：模块 01
**优先级**：P0

## 功能描述

本地通知系统，V1.0 主要支持识别结果通知（成功/失败）。用餐提醒和缺口延后到 V1.1。

## 技术方案

使用 `flutter_local_notifications` 包实现跨平台本地通知。

## 涉及文件

```
lib/services/
  └── notification_service.dart    — 新建：通知服务
lib/ui/settings/
  └── notification_settings_page.dart — 通知设置页（已有占位）
```

## 通知类型

| 类型 | 触发时机 | V1.0 |
|------|---------|------|
| 识别成功 | 分享扩展识别成功后 | ✅ |
| 识别失败 | 分享扩展识别失败后 | ✅ |
| 用餐提醒 | 到饭点时 | ❌ V1.1 |
| 缺口提醒 | 晚上了某分类还差很多 | ❌ V1.1 |

## NotificationService

```dart
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(settings);
  }

  // 请求权限
  static Future<bool> requestPermissions() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    bool granted = true;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
    }
    if (ios != null) {
      granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    return granted;
  }

  // 识别成功通知
  static Future<void> showRecognitionSuccess({
    required String mealType,
    required String dishName,
    required String petText,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'recognition',
      '识别结果',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '已记录$mealType',
      '$dishName · $petText',
      details,
    );
  }

  // 识别失败通知
  static Future<void> showRecognitionFailure() async {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      '没认出来 🤔',
      '这张图没认出来，打开APP手动添加吧',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'recognition',
          '识别结果',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
```

## 通知渠道（Android）

| 渠道 ID | 名称 | 重要性 | 说明 |
|---------|------|--------|------|
| recognition | 识别结果 | 默认 | 分享扩展识别后的通知 |
| reminders | 用餐提醒 | 中等 | V1.1 实现 |

## 权限申请时机

- **首次打开 APP**：不主动弹权限申请
- **首次使用分享扩展后**：系统自动处理（iOS）
- **在设置页点击通知开关**：如果没有权限，引导申请

**通知引导**：
- 在 onboarding 完成后或合适的时机，展示一个温和的引导卡片
- 文案：「开启通知，识别结果第一时间告诉你～」
- 「开启通知」按钮 → 申请权限
- 用户拒绝后，设置页显示通知未开启状态

## 通知点击行为

- 点击识别成功通知 → 打开 APP → 跳转到今日首页
- 点击识别失败通知 → 打开 APP → 跳转到手动添加记录页

## 与分享扩展的关系

识别成功/失败通知实际上主要由各端原生侧（iOS Share Extension / Android ShareReceiver）直接发送，Flutter 侧的 NotificationService 主要用于：
- 初始化通知渠道
- 权限申请和检查
- APP 内其他通知（后续扩展）
- 通知设置页的开关控制

**设置开关的实现**：
- 开关状态存在 SharedPreferences
- 分享扩展在发通知前读取这个开关
- 关闭时不发通知

## 验收标准

- [ ] 通知初始化正常
- [ ] 权限申请弹窗正常
- [ ] 识别成功通知显示正确内容
- [ ] 识别失败通知显示正确内容
- [ ] 点击通知跳转到正确页面
- [ ] 通知设置开关生效
- [ ] Android 通知渠道正常创建
- [ ] iOS 通知权限状态正确检测
- [ ] 关闭通知后，分享扩展不发通知
