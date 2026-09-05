import 'dart:async';
import 'dart:convert';

import 'package:canting/core_engine.dart';
import 'package:canting/native/ios_native_bridge.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/router/app_router.dart';
import 'package:canting/services/notification_service.dart';
import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final databaseHelper = DatabaseHelper.instance;
  await databaseHelper.initialize(seedData: await _loadSeedFoodDatabase());
  // 通知开关启动恢复（识别结果 / 用餐提醒 / 缺口提醒统一落盘 shared_preferences）。
  final switches = await NotificationSwitchPrefs.load();
  NotificationService.recognitionEnabled = switches.recognitionEnabled;
  final appState = AppState(
    databaseHelper: databaseHelper,
    guidelines: await _loadDietaryGuidelines(),
    persistNotificationSwitches: ({bool? mealReminder, bool? gapReminder}) {
      unawaited(
        NotificationSwitchPrefs.save(
          mealReminder: mealReminder,
          gapReminder: gapReminder,
        ),
      );
    },
  );
  await appState.loadFromDatabase();
  // 提醒开关在 runApp 前直接恢复（main 里已按持久化值初始化 pet 等）。
  appState
    ..mealReminder = switches.mealReminder
    ..gapReminder = switches.gapReminder;
  // 本地通知基础设施（模块 13）：初始化失败不阻塞 APP 启动。
  try {
    await NotificationService.init();
  } catch (error) {
    debugPrint('Notification init failed: $error');
  }
  runApp(CantingApp(appState: appState));
}

Future<FoodDatabase> _loadSeedFoodDatabase() async {
  final dishesJson = await rootBundle.loadString('assets/data/dishes.json');
  final categoriesJson = await rootBundle.loadString(
    'assets/data/categories.json',
  );
  return FoodDatabase.fromJson(
    dishesJson: dishesJson,
    categoriesJson: categoriesJson,
  );
}

Future<DietaryGuidelines> _loadDietaryGuidelines() async {
  final guidelinesJson = await rootBundle.loadString(
    'assets/data/dietary_guidelines.json',
  );
  return DietaryGuidelines.fromJson(
    (jsonDecode(guidelinesJson) as Map).cast<String, dynamic>(),
  );
}

class CantingApp extends StatefulWidget {
  const CantingApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<CantingApp> createState() => _CantingAppState();
}

class _CantingAppState extends State<CantingApp> with WidgetsBindingObserver {
  late final GoRouter _router = AppRouter.create(widget.appState);
  late final AndroidNativeBridge _nativeBridge = AndroidNativeBridge();
  // 分享图与 APP 内拍照/相册识别共用同一条 OCR 管线（模块 14）。
  late final OcrPipeline _ocrPipeline = OcrPipeline(appState: widget.appState);
  String? _lastOpenedIOSMealID;
  bool _checkingIOSShare = false;
  Timer? _calendarTimer;
  DateTime _recordDay = DateTime.now();
  StreamSubscription<String>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _calendarTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      if (now.year != _recordDay.year ||
          now.month != _recordDay.month ||
          now.day != _recordDay.day) {
        _recordDay = now;
        unawaited(widget.appState.resumeRecords());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_nativeBridge.initialize(onSharedImage: _handleSharedImage));
      unawaited(_openPendingIOSMeal());
    });
    // 点击通知的跳转（模块 13）：识别成功 → 今日首页，识别失败 → 记录页。
    _notificationTapSub = NotificationService.onTap.listen(
      _handleNotificationTap,
    );
  }

  void _handleNotificationTap(String payload) {
    switch (payload) {
      case NotificationService.payloadFailure:
        _router.go('/record_detail');
      case NotificationService.payloadSuccess:
      default:
        _router.go('/home');
    }
  }

  Future<void> _handleSharedImage(String imageUri) async {
    if (!mounted ||
        !await widget.appState.mayReplaceRecognition() ||
        !mounted) {
      await _nativeBridge.releaseImage(imageUri);
      return;
    }
    _ocrPipeline.begin(imageUri);
    _router.go('/record_detail?source=share');
    await _ocrPipeline.recognize(imageUri);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.appState.resumeRecords());
      unawaited(_openPendingIOSMeal());
    }
  }

  Future<void> _openPendingIOSMeal() async {
    if (_checkingIOSShare) return;
    _checkingIOSShare = true;
    try {
      final draft = await IOSNativeBridge.instance.getPendingSharedMeal();
      if (!mounted || draft == null || draft.mealId == _lastOpenedIOSMealID) {
        return;
      }
      _lastOpenedIOSMealID = draft.mealId;
      final imageURI = draft.imageUri ?? 'ios-app-group:${draft.mealId}';
      widget.appState.startSharedRecognition(imageURI);
      widget.appState.completeSharedRecognition(
        imageUri: imageURI,
        merchant: draft.merchant,
        dishes: draft.dishes
            .map(
              (dish) => MealDish(
                name: dish.name,
                quantity: dish.quantity.toDouble(),
                portionSize: dish.portionSize,
              ),
            )
            .toList(growable: false),
      );
      if (mounted) {
        _router.go(
          '/record_detail?source=share&mealId=${Uri.encodeQueryComponent(draft.mealId)}',
        );
      }
      try {
        final acknowledged = await IOSNativeBridge.instance
            .acknowledgeSharedMeal(draft.mealId);
        if (!acknowledged) {
          debugPrint('Shared meal acknowledgement did not match the meal ID');
        }
      } on PlatformException catch (error) {
        debugPrint('Unable to acknowledge iOS shared meal: ${error.message}');
      }
    } on PlatformException catch (error) {
      debugPrint('Unable to open iOS shared meal: ${error.message}');
    } catch (error) {
      debugPrint('Unable to parse iOS shared meal: $error');
    } finally {
      _checkingIOSShare = false;
    }
  }

  @override
  void dispose() {
    _calendarTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notificationTapSub?.cancel());
    unawaited(_nativeBridge.dispose());
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.appState,
      child: MaterialApp.router(
        title: '餐盘',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
      ),
    );
  }
}
