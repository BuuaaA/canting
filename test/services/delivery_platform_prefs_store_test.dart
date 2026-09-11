import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = DeliveryPlatformPrefsStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认只有三个可见平台且全部启用', () async {
    final settings = await store.loadSettings();
    expect(settings.map((item) => item.id), [
      'jd_waimai',
      'taobao_shangou',
      'meituan_waimai',
    ]);
    expect(settings.map((item) => item.enabled), everyElement(isTrue));
  });

  test('旧默认值包含的饿了么和普通美团会被过滤，不清除其他设置', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('delivery_platform_order', [
      'eleme',
      'meituan',
      'meituan_waimai',
    ]);
    await prefs.setStringList('delivery_platform_disabled', ['meituan_waimai']);
    final settings = await store.loadSettings();
    expect(settings.map((item) => item.id), [
      'meituan_waimai',
      'jd_waimai',
      'taobao_shangou',
    ]);
    expect(settings.last.enabled, isTrue);
    expect(settings.first.enabled, isFalse);
  });

  test('手动默认平台单独落盘', () async {
    await store.savePreferredPlatformId('taobao_shangou');
    expect(await store.loadPreferredPlatformId(), 'taobao_shangou');
    await store.savePreferredPlatformId(null);
    expect(await store.loadPreferredPlatformId(), isNull);
  });

  test('停用和排序只影响三类可见平台', () async {
    await store.saveSettings(const [
      DeliveryPlatformSetting(id: 'meituan_waimai', enabled: true),
      DeliveryPlatformSetting(id: 'jd_waimai', enabled: false),
      DeliveryPlatformSetting(id: 'taobao_shangou', enabled: true),
    ]);
    expect(await store.loadOrderedPlatformIds(), [
      'meituan_waimai',
      'taobao_shangou',
    ]);
  });
}
