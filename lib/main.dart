import 'dart:async';

import 'package:canting/native/ios_native_bridge.dart';
import 'package:canting/platform/android_native_bridge.dart';
import 'package:canting/router/app_router.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CantingApp(appState: AppState()));
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
  String? _lastOpenedIOSMealID;
  bool _checkingIOSShare = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_nativeBridge.initialize(onSharedImage: _handleSharedImage));
      unawaited(_openPendingIOSMeal());
    });
  }

  Future<void> _handleSharedImage(String imageUri) async {
    widget.appState.startSharedRecognition(imageUri);
    _router.go('/record_detail?source=share');
    try {
      final recognition = await _nativeBridge.recognizeImage(imageUri);
      widget.appState.completeSharedRecognition(
        imageUri: imageUri,
        merchant: recognition.merchant,
        dishes: recognition.dishes
            .map((dish) => MockDish(name: dish.name, quantity: dish.quantity))
            .toList(growable: false),
      );
    } on PlatformException catch (error) {
      widget.appState.failSharedRecognition(
        imageUri: imageUri,
        message: error.code == 'OCR_UNAVAILABLE'
            ? '当前设备无法使用文字识别，请手动添加菜品'
            : '这张图没看清，请手动添加菜品',
      );
    } catch (_) {
      widget.appState.failSharedRecognition(
        imageUri: imageUri,
        message: '这张图没看清，请手动添加菜品',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
              (dish) => MockDish(
                name: dish.name,
                quantity: dish.quantity,
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
    WidgetsBinding.instance.removeObserver(this);
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
