import 'package:canting/core_engine.dart';
import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<(AppState, DatabaseHelper)> _buildState() async {
  sqfliteFfiInit();
  final helper = DatabaseHelper(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: inMemoryDatabasePath,
  );
  await helper.initialize();
  final state = AppState(databaseHelper: helper);
  await state.loadFromDatabase();
  return (state, helper);
}

Widget _wrap(AppState state) => ChangeNotifierProvider.value(
  value: state,
  child: const MaterialApp(home: SettingsPage()),
);

Finder _switchOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  matching: find.byType(Switch),
);

Finder _moveButtonOf(String label, String tooltip) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
  matching: find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('设置页展示四个外卖平台，默认全启用、固定顺序', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    // 放大视口让下方的外卖平台分组全部构建（ListView 懒加载）。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(state));
    await tester.pump();
    await tester.pump();

    for (final label in ['美团外卖', '美团', '饿了么', '京东外卖']) {
      expect(find.text(label), findsOneWidget);
      final sw = tester.widget<Switch>(_switchOf(label));
      expect(sw.value, isTrue, reason: '$label 默认启用');
    }
    // 默认顺序下第一行的「上移」和最后一行的「下移」不可用。
    expect(
      tester.widget<IconButton>(_moveButtonOf('美团外卖', '上移')).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(_moveButtonOf('京东外卖', '下移')).onPressed,
      isNull,
    );
  });

  testWidgets('停用京东外卖后落盘，跳转服务只返回剩余启用平台', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(state));
    await tester.pump();
    await tester.pump();

    await tester.tap(_switchOf('京东外卖'));
    await tester.pump();
    await tester.pump();

    final sw = tester.widget<Switch>(_switchOf('京东外卖'));
    expect(sw.value, isFalse);

    // 与推荐页跳转同一条读取链路：DeliveryJumpService + prefs store。
    final platforms = await DeliveryJumpService(
      configStore: const DeliveryPlatformPrefsStore(),
    ).loadEnabledPlatforms();
    expect(platforms.map((platform) => platform.id).toList(), [
      'meituan_waimai',
      'meituan',
      'eleme',
    ]);
  });

  testWidgets('上移京东外卖后落盘新顺序，跳转顺序随之变化', (tester) async {
    final (state, helper) = await _buildState();
    addTearDown(helper.close);

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(state));
    await tester.pump();
    await tester.pump();

    await tester.tap(_moveButtonOf('京东外卖', '上移'));
    await tester.pump();
    await tester.pump();

    final settings = await const DeliveryPlatformPrefsStore().loadSettings();
    expect(settings.map((item) => item.id).toList(), [
      'meituan_waimai',
      'meituan',
      'jd_waimai',
      'eleme',
    ]);

    final platforms = await DeliveryJumpService(
      configStore: const DeliveryPlatformPrefsStore(),
    ).loadEnabledPlatforms();
    expect(platforms.map((platform) => platform.id).toList(), [
      'meituan_waimai',
      'meituan',
      'jd_waimai',
      'eleme',
    ]);
  });
}
