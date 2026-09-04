import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = DeliveryPlatformPrefsStore();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeliveryPlatformPrefsStore（外卖平台配置持久化）', () {
    test('未落盘时返回默认配置：四平台全启用、固定优先级', () async {
      final settings = await store.loadSettings();

      expect(settings.map((item) => item.id).toList(), [
        'meituan_waimai',
        'meituan',
        'eleme',
        'jd_waimai',
      ]);
      expect(settings.map((item) => item.enabled), everyElement(isTrue));
      expect(await store.loadOrderedPlatformIds(), [
        'meituan_waimai',
        'meituan',
        'eleme',
        'jd_waimai',
      ]);
    });

    test('saveSettings 落盘后 loadSettings 原样读回（顺序 + 启用状态）', () async {
      await store.saveSettings(const [
        DeliveryPlatformSetting(id: 'eleme', enabled: true),
        DeliveryPlatformSetting(id: 'jd_waimai', enabled: false),
        DeliveryPlatformSetting(id: 'meituan_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'meituan', enabled: false),
      ]);

      final settings = await store.loadSettings();

      expect(settings.map((item) => item.id).toList(), [
        'eleme',
        'jd_waimai',
        'meituan_waimai',
        'meituan',
      ]);
      expect(
        settings.map((item) => item.enabled).toList(),
        [true, false, true, false],
      );
    });

    test('loadOrderedPlatformIds 只返回启用平台并保持顺序', () async {
      await store.saveSettings(const [
        DeliveryPlatformSetting(id: 'jd_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'eleme', enabled: false),
        DeliveryPlatformSetting(id: 'meituan_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'meituan', enabled: false),
      ]);

      expect(await store.loadOrderedPlatformIds(), [
        'jd_waimai',
        'meituan_waimai',
      ]);
    });

    test('存储里的未知平台 id 被忽略，新平台 id 追加到末尾', () async {
      // 模拟旧版本落盘（含已下线平台）与 App 更新新增平台的混合场景。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('delivery_platform_order', [
        'legacy_platform',
        'eleme',
        'brand_new_platform',
      ]);
      await prefs.setStringList('delivery_platform_disabled', []);

      final settings = await store.loadSettings();

      expect(settings.map((item) => item.id).toList(), [
        'eleme',
        // 未出现在存储顺序里的已知平台按默认顺序补在末尾。
        'meituan_waimai',
        'meituan',
        'jd_waimai',
      ]);
      expect(settings.map((item) => item.enabled), everyElement(isTrue));
    });

    test('saveOrderedPlatformIds：未列出的平台视为停用并保持原有相对顺序', () async {
      await store.saveSettings(const [
        DeliveryPlatformSetting(id: 'jd_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'eleme', enabled: true),
        DeliveryPlatformSetting(id: 'meituan_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'meituan', enabled: true),
      ]);

      await store.saveOrderedPlatformIds(['meituan', 'meituan_waimai']);

      final settings = await store.loadSettings();
      expect(settings.map((item) => item.id).toList(), [
        'meituan',
        'meituan_waimai',
        // 未列出的 eleme / jd_waimai 保留原有相对顺序（jd 在前），排在末尾。
        'jd_waimai',
        'eleme',
      ]);
      expect(
        settings.map((item) => item.enabled).toList(),
        [true, true, false, false],
      );
      expect(await store.loadOrderedPlatformIds(), [
        'meituan',
        'meituan_waimai',
      ]);
    });

    test('跳转服务注入 prefs store 后按用户配置返回启用平台', () async {
      await store.saveSettings(const [
        DeliveryPlatformSetting(id: 'eleme', enabled: true),
        DeliveryPlatformSetting(id: 'meituan_waimai', enabled: true),
        DeliveryPlatformSetting(id: 'meituan', enabled: false),
        DeliveryPlatformSetting(id: 'jd_waimai', enabled: false),
      ]);

      final service = DeliveryJumpService(configStore: store);
      final platforms = await service.loadEnabledPlatforms();

      expect(platforms.map((platform) => platform.id).toList(), [
        'eleme',
        'meituan_waimai',
      ]);
    });

    testWidgets('prefs 不可用时回退默认配置（不抛异常）', (tester) async {
      // 不设置 mock 初始值：getInstance 抛 MissingPluginException，
      // store 必须吞掉并回退默认配置（设置页/推荐页在异常环境仍可用）。
      final settings = await store.loadSettings();

      expect(settings.map((item) => item.id).toList(), [
        'meituan_waimai',
        'meituan',
        'eleme',
        'jd_waimai',
      ]);
      expect(settings.map((item) => item.enabled), everyElement(isTrue));
    });
  });
}
