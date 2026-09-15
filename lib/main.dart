import 'package:flutter/foundation.dart' show kDebugMode;

import 'dart:async';
import 'dart:convert';

import 'package:canting/core_engine.dart';
import 'package:canting/native/ios_native_bridge.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/router/app_router.dart';
import 'package:canting/services/notification_service.dart';
import 'package:canting/services/ocr_pipeline.dart';
import 'package:canting/services/fc_next_meal_remote.dart';
import 'package:canting/services/recognition_adapter.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

Future<void> main() => runCantingApp();

class DevCredentialSession extends ChangeNotifier {
  String? _token;
  bool _armed = false;

  bool get armed => _armed;

  void arm(String token) {
    final value = token.trim();
    if (value.isEmpty) return;
    if (kDebugMode) {
      debugPrint(
        '[FC CRED] inputLen=${value.length} '
        'leadingBearer=${value.startsWith('Bearer ')} '
        'quotes=${value.contains('"') || value.contains("'")} '
        'edgeWhitespace=${value != token} '
        'plusSlashPadding=${value.contains('+') && value.contains('/') && value.endsWith('=')}',
      );
    }
    _token = value;
    _armed = true;
    notifyListeners();
  }

  CredentialAccess get access => (ref, use) async {
    final token = _token;
    _token = null;
    _armed = false;
    notifyListeners();
    await use(token ?? '');
  };
}

/// Starts the app with an optional development-only runtime credential hook.
///
/// The normal Flutter entrypoint supplies no hook, so production remains local
/// by default. A development host may call this function with a
/// [CredentialAccess] backed by its secure credential broker; the secret is
/// held only for the request and is never part of dart-define or the APK.
Future<void> runCantingApp({CredentialAccess? nextMealCredentialAccess}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final databaseHelper = DatabaseHelper.instance;
  await databaseHelper.initialize(seedData: await _loadSeedFoodDatabase());
  // 通知开关启动恢复（识别结果 / 用餐提醒 / 缺口提醒统一落盘 shared_preferences）。
  final switches = await NotificationSwitchPrefs.load();
  NotificationService.recognitionEnabled = switches.recognitionEnabled;
  final devCredentialSession =
      kDebugMode &&
          const bool.fromEnvironment(
            'CANTING_ENABLE_DEV_FC',
            defaultValue: false,
          ) &&
          nextMealCredentialAccess == null
      ? DevCredentialSession()
      : null;
  // 只从编译配置读取非敏感开关和端点；Bearer 凭据必须由宿主运行时注入，
  // 不提供 dart-define、资源、SharedPreferences 或 APK 内的密钥通道。
  final nextMealRemoteConfiguration = FcNextMealConfiguration(
    endpoint: Uri.tryParse(
      const String.fromEnvironment('CANTING_RECOMMEND_ENDPOINT'),
    ),
    enabled:
        const bool.fromEnvironment(
          'CANTING_RECOMMEND_ENABLED',
          defaultValue: false,
        ) ||
        devCredentialSession != null,
    credentialAccess: nextMealCredentialAccess ?? devCredentialSession?.access,
    httpObserver: kDebugMode
        ? (event) => debugPrint(
            '[FC HTTP] ${event.method} ${event.host}${event.path} '
            'status=${event.statusCode} '
            'credLen=${event.callbackLength}/${event.headerLength} '
            'credSame=${event.credentialConsistent} '
            'leadingBearer=${event.hasLeadingBearer} '
            'quotes=${event.hasQuotes} '
            'edgeWhitespace=${event.hasEdgeWhitespace} '
            'plusSlashPadding=${event.hasPlusSlashPadding} '
            'layer=${event.responseLayer ?? 'unknown'} '
            'requestId=${event.requestId ?? 'none'} '
            'errorCode=${event.errorCode ?? 'none'} '
            'contentType=${event.contentType ?? 'none'} '
            'responseLen=${event.responseLength ?? -1} '
            'errorType=${event.errorType ?? 'none'} '
            'errorMessage=${event.errorMessage ?? 'none'}',
          )
        : null,
  );
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
    nextMealRemoteConfiguration: nextMealRemoteConfiguration,
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
    if (kDebugMode) {
      debugPrint('Notification init failed: $error');
    }
  }
  runApp(
    CantingApp(appState: appState, devCredentialSession: devCredentialSession),
  );
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
  const CantingApp({
    super.key,
    required this.appState,
    this.devCredentialSession,
  });

  final AppState appState;
  final DevCredentialSession? devCredentialSession;

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
          if (kDebugMode) {
            debugPrint('Shared meal acknowledgement did not match the meal ID');
          }
        }
      } on PlatformException catch (error) {
        if (kDebugMode) {
          debugPrint('Unable to acknowledge iOS shared meal: ${error.message}');
        }
      }
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to open iOS shared meal: ${error.message}');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Unable to parse iOS shared meal: $error');
      }
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
        builder: (context, child) => Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (widget.devCredentialSession != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _DevCredentialPanel(
                  session: widget.devCredentialSession!,
                ),
              ),
          ],
        ),
        routerConfig: _router,
      ),
    );
  }
}

class _DevCredentialPanel extends StatefulWidget {
  const _DevCredentialPanel({required this.session});

  final DevCredentialSession session;

  @override
  State<_DevCredentialPanel> createState() => _DevCredentialPanelState();
}

class _DevCredentialPanelState extends State<_DevCredentialPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _arm() {
    widget.session.arm(_controller.text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
    elevation: 8,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '开发联调口令（仅本次请求）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _arm,
            child: Text(widget.session.armed ? '已就绪' : '启用联调'),
          ),
        ],
      ),
    ),
  );
}
