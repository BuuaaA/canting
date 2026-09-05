import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/main.dart';
import 'package:canting/services/notification_service.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/ocr/in_app_ocr_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
    File('assets/data/dietary_guidelines.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

UserProfile _profile() {
  final now = DateTime(2026, 9, 4);
  return UserProfile(
    gender: 'female',
    age: 28,
    heightCm: 165,
    weightKg: 55,
    dietGoal: 'balanced',
    activityLevel: 'light',
    breakfastTime: '08:00',
    lunchTime: '12:00',
    dinnerTime: '18:30',
    dayStartTime: '01:00',
    onboardingCompleted: true,
    createdAt: now,
    updatedAt: now,
  );
}

FoodDatabase _seedFoodDatabase() => FoodDatabase.fromJson(
  dishesJson: File('assets/data/dishes.json').readAsStringSync(),
  categoriesJson: File('assets/data/categories.json').readAsStringSync(),
);

Future<(AppState, DatabaseHelper)> _buildState() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize(seedData: _seedFoodDatabase());
  final state = AppState(databaseHelper: helper, guidelines: _guidelines());
  await state.loadFromDatabase();
  await state.completeOnboarding(
    profile: _profile(),
    petType: 'cat',
    petName: '小挑食',
  );
  return (state, helper);
}

/// image_picker 平台接口 fake：返回注入的路径（或 null=取消），可注入异常。
class _FakeImagePickerPlatform extends ImagePickerPlatform {
  _FakeImagePickerPlatform({this.path, this.error});

  final String? path;
  final Object? error;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (error != null) {
      throw error!;
    }
    return path == null ? null : XFile(path!);
  }
}

/// path_provider 平台接口 fake：临时目录用注入值。
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.temporaryPath);

  final String temporaryPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;
}

/// 安装平台 fake，测试结束后恢复原实现。
void _installPlatformFakes({
  required String tempDirPath,
  required String? pickedPath,
  Object? pickerError,
}) {
  final originalPicker = ImagePickerPlatform.instance;
  final originalPathProvider = PathProviderPlatform.instance;
  ImagePickerPlatform.instance = _FakeImagePickerPlatform(
    path: pickedPath,
    error: pickerError,
  );
  PathProviderPlatform.instance = _FakePathProviderPlatform(tempDirPath);
  addTearDown(() {
    ImagePickerPlatform.instance = originalPicker;
    PathProviderPlatform.instance = originalPathProvider;
  });
}

String _writeFakeImage() {
  final file = File(
    p.join(
      Directory.systemTemp.path,
      'canting_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  )..writeAsBytesSync(List.filled(16, 1));
  addTearDown(file.deleteSync);
  return file.path;
}

Directory _tempCacheDir() {
  final dir = Directory.systemTemp.createTempSync('canting_cache_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void _mockOcrResult(
  WidgetTester tester, {
  Map<String, Object?>? result,
  Completer<Object?>? neverComplete,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.canting.app/ocr'),
    (call) async {
      if (call.method == 'recognizeImage') {
        if (neverComplete != null) {
          return neverComplete.future;
        }
        return result;
      }
      return null;
    },
  );
}

void _clearOcrMock(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.canting.app/ocr'),
    null,
  );
}

/// 通知插件 mock：记录 show 调用的 (title, body)，返回待断言的记录。
({List<(String, String)> shown}) _mockNotifications(WidgetTester tester) {
  final shown = <(String, String)>[];
  // 测试环境没有 GeneratedPluginRegistrant，需手动注册平台实现，
  // 否则 FlutterLocalNotificationsPlatform.instance 未初始化。
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (call) async {
      switch (call.method) {
        case 'initialize':
          return true;
        case 'createNotificationChannel':
          return null;
        case 'show':
          // flutter_local_notifications 19 传 Map 参数。
          final args =
              (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
          shown.add((
            args['title'] as String? ?? '',
            args['body'] as String? ?? '',
          ));
          return null;
        default:
          return null;
      }
    },
  );
  return (shown: shown);
}

void _clearNotificationMock(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InAppOcrLauncher.copyIntoSharedImages', () {
    test('复制进注入的缓存目录并返回 FileProvider URI', () async {
      final pickedPath = _writeFakeImage();
      final cacheDir = _tempCacheDir();

      final uri = await InAppOcrLauncher.copyIntoSharedImages(
        pickedPath,
        cacheDir: cacheDir,
      );

      expect(
        uri,
        startsWith('content://com.canting.fileprovider/shared_images/'),
      );
      final copied = File(
        p.join(cacheDir.path, 'shared_images', p.basename(uri)),
      );
      expect(copied.existsSync(), isTrue);
    });

    test('无扩展名或非法扩展名一律按 jpg 落盘', () async {
      final source = File(
        p.join(
          Directory.systemTemp.path,
          'canting_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..writeAsBytesSync(List.filled(4, 1));
      addTearDown(source.deleteSync);
      final cacheDir = _tempCacheDir();

      final uri = await InAppOcrLauncher.copyIntoSharedImages(
        source.path,
        cacheDir: cacheDir,
      );

      expect(p.basename(uri), endsWith('.jpg'));
    });
  });

  testWidgets('FAB 弹层展示三项：拍照识别 / 相册选择 / 手动添加', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    _installPlatformFakes(tempDirPath: _tempCacheDir().path, pickedPath: null);

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('拍照识别'), findsOneWidget);
    expect(find.text('相册选择'), findsOneWidget);
    expect(find.text('手动添加'), findsOneWidget);
    expect(find.text('截图识别'), findsNothing);
  });

  testWidgets('取图失败 → 提示获取图片失败并提供手动添加入口', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    _installPlatformFakes(
      tempDirPath: _tempCacheDir().path,
      pickedPath: null,
      pickerError: PlatformException(code: 'PICK_FAILED'),
    );

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('获取图片失败，请重试'), findsOneWidget);
    expect(find.text('手动添加'), findsOneWidget); // SnackBar action
    expect(state.recognitionDraft, isNull); // 没有进入识别状态
  });

  testWidgets('相册选图 → 复制包装 → 识别完成 → 保存 source=ocr 并发确认通知', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    final cacheDir = _tempCacheDir();
    final pickedPath = _writeFakeImage();
    _installPlatformFakes(tempDirPath: cacheDir.path, pickedPath: pickedPath);
    _mockOcrResult(
      tester,
      result: {
        'fullText': '黄焖鸡米饭（大份） x1',
        'engine': 'mlkit_chinese',
        'merchant': '美团外卖·黄焖鸡米饭',
        'dishes': [
          {'name': '黄焖鸡米饭（大份）', 'quantity': 1},
        ],
      },
    );
    addTearDown(() => _clearOcrMock(tester));
    final notifications = _mockNotifications(tester);
    addTearDown(() => _clearNotificationMock(tester));

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('相册选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 进入识别页，URI 已按 FileProvider 规则包装，识别结果已回填。
    expect(find.text('识别结果'), findsOneWidget);
    expect(
      state.recognitionDraft!.imageUri,
      startsWith('content://com.canting.fileprovider/shared_images/'),
    );
    expect(state.recognitionDraft!.dishes, hasLength(1));
    expect(find.text('黄焖鸡米饭（大份）'), findsOneWidget);
    // 图片确实复制进了 cacheDir/shared_images/。
    expect(
      Directory(p.join(cacheDir.path, 'shared_images')).listSync(),
      isNotEmpty,
    );

    await tester.tap(find.text('保存并更新今日结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('明确保留未知并保存'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('餐盘 · 今日'), findsOneWidget);
    final rows = await helper.database.query('meal_records');
    expect(rows, hasLength(1));
    final record = (jsonDecode(rows.single['record_json']! as String) as Map)
        .cast<String, dynamic>();
    expect(record['source'], 'ocr');

    // 任务 3：OCR 保存成功后发确认通知（菜名 + 宠物台词）。
    expect(notifications.shown, hasLength(1));
    final (title, body) = notifications.shown.single;
    expect(title, startsWith('已记录'));
    expect(body, startsWith('黄焖鸡米饭（大份）'));
  });

  testWidgets('识别结果为空 → 页面提示手动添加', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    _installPlatformFakes(
      tempDirPath: _tempCacheDir().path,
      pickedPath: _writeFakeImage(),
    );
    _mockOcrResult(
      tester,
      result: {
        'fullText': '',
        'engine': 'mlkit_chinese',
        'merchant': '',
        'dishes': [],
      },
    );
    addTearDown(() => _clearOcrMock(tester));

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('相册选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('识别结果'), findsOneWidget);
    expect(find.text('没有识别出菜品，请手动添加'), findsOneWidget);
  });

  testWidgets('识别超时（5 秒）→ 提示太慢并给手动添加建议', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    _installPlatformFakes(
      tempDirPath: _tempCacheDir().path,
      pickedPath: _writeFakeImage(),
    );
    _mockOcrResult(tester, neverComplete: Completer<Object?>());
    addTearDown(() => _clearOcrMock(tester));

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('拍照识别'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('识别结果'), findsOneWidget);
    expect(state.recognitionDraft!.isLoading, isTrue);

    // 推进假时钟越过 5 秒超时。
    await tester.pump(const Duration(seconds: 5, milliseconds: 100));
    await tester.pump();

    expect(state.recognitionDraft!.isLoading, isFalse);
    expect(state.recognitionDraft!.error, '识别有点慢，图片可能太复杂，试试手动添加吧');
  });

  testWidgets('识别通知开关关闭时保存成功但不发通知', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);
    NotificationService.recognitionEnabled = false;
    addTearDown(NotificationService.resetForTest);
    _installPlatformFakes(
      tempDirPath: _tempCacheDir().path,
      pickedPath: _writeFakeImage(),
    );
    _mockOcrResult(
      tester,
      result: {
        'fullText': '',
        'engine': 'mlkit_chinese',
        'merchant': '任意商家',
        'dishes': [
          {'name': '番茄炒蛋', 'quantity': 1},
        ],
      },
    );
    addTearDown(() => _clearOcrMock(tester));
    final notifications = _mockNotifications(tester);
    addTearDown(() => _clearNotificationMock(tester));

    await tester.pumpWidget(CantingApp(appState: state));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('记一餐'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('相册选择'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('保存并更新今日结构'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    if (find.text('明确保留未知并保存').evaluate().isNotEmpty) {
      await tester.tap(find.text('明确保留未知并保存'));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('餐盘 · 今日'), findsOneWidget);
    final rows = await helper.database.query('meal_records');
    expect(rows, hasLength(1));
    expect(notifications.shown, isEmpty); // 开关关闭：不发通知
  });
}
