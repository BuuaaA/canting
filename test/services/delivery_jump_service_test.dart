import 'dart:convert';

import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  test('只展示三类平台，旧饿了么和普通美团不再出现', () {
    expect(DeliveryJumpService.allPlatformIds, [
      'jd_waimai',
      'taobao_shangou',
      'meituan_waimai',
    ]);
  });

  test('美团公开源码入口对关键词进行 URI 编码，网页只声明下载页', () {
    final service = DeliveryJumpService();
    final uri = service.buildAppUri('meituan_waimai', '蒜蓉 西兰花')!;
    expect(uri.scheme, 'meituanwaimai');
    expect(uri.queryParameters['query'], '蒜蓉 西兰花');
    expect(
      DeliveryJumpService.buildFallbackUri(DeliveryJumpService.platforms[2])
          .toString(),
      'https://waimai.meituan.com/mobile/download/',
    );
  });

  test('全部无可核验 App 时，解析到有限网页链并且不循环', () async {
    final states = <String, DeliveryPlatformState>{
      for (final id in const [
        'jd_waimai_app',
        'taobao_shangou_app',
        'meituan_waimai',
        'jd',
        'taobao',
      ])
        id: DeliveryPlatformState(
          platformId: id,
          installation: DeliveryInstallation.unknown,
          source: 'test',
        ),
    };
    final resolution = await DeliveryJumpService().resolveLink(
      keyword: '清蒸鱼',
      states: states,
    );
    expect(resolution.target!.kind, 'web');
    expect(resolution.allTargets.map((target) => target.platformId), [
      'jd_waimai',
      'taobao_shangou',
      'meituan_waimai',
    ]);
  });

  test('已安装美团时，App 目标排在所有网页兜底之前', () async {
    final resolution = await DeliveryJumpService().resolveLink(
      keyword: '鱼',
      states: const {
        'meituan_waimai': DeliveryPlatformState(
          platformId: 'meituan_waimai',
          installation: DeliveryInstallation.installed,
          source: 'test',
        ),
      },
    );
    expect(resolution.target!.kind, 'app');
    expect(resolution.target!.uri.queryParameters['query'], '鱼');
    expect(resolution.allTargets.first.platformId, 'meituan_waimai');
  });

  test('App 拉起失败后沿有限链降级到网页并记录调用顺序', () async {
    final calls = <Uri>[];
    final service = DeliveryJumpService(
      canLaunch: (_) async => true,
      launch: (uri, {mode = LaunchMode.platformDefault}) async {
        calls.add(uri);
        return calls.length == 2;
      },
    );
    final result = await service.jumpToSearch(
      DeliveryJumpService.platforms[2],
      '鱼 汤',
    );
    expect(result.success, isTrue);
    expect(result.usedFallback, isTrue);
    expect(calls.length, 2);
    expect(calls.first.scheme, 'meituanwaimai');
    expect(calls.last.scheme, 'https');
  });

  test('检测失败返回 unknown，不伪造为未安装', () async {
    final service = DeliveryJumpService(
      canLaunch: (_) async => throw StateError('platform unavailable'),
    );
    final states = await service.detectPlatforms();
    expect(
      states['meituan_waimai']!.installation,
      DeliveryInstallation.unknown,
    );
    expect(states['jd_waimai_app']!.installation, DeliveryInstallation.unknown);
  });

  test('停用平台不会进入 resolveLink，手动默认也不能重新启用', () async {
    final store = _ConfigStore(ids: ['meituan_waimai'], preferred: 'jd_waimai');
    final resolution = await DeliveryJumpService(configStore: store)
        .resolveLink(
          keyword: '鱼',
          states: const {
            'meituan_waimai': DeliveryPlatformState(
              platformId: 'meituan_waimai',
              installation: DeliveryInstallation.installed,
              source: 'test',
            ),
          },
        );
    expect(resolution.allTargets.map((target) => target.platformId), [
      'meituan_waimai',
      'meituan_waimai',
    ]);
    expect(resolution.target!.kind, 'app');
  });

  test('canLaunch/launch 插件异常也会继续有限降级', () async {
    final calls = <Uri>[];
    final service = DeliveryJumpService(
      canLaunch: (_) async => throw StateError('plugin missing'),
      launch: (uri, {mode = LaunchMode.platformDefault}) async {
        calls.add(uri);
        return true;
      },
    );
    final result = await service.jumpToSearch(
      DeliveryJumpService.platforms[2],
      '鱼',
    );
    expect(result.success, isTrue);
    expect(result.usedUri!.scheme, 'https');
    expect(calls.length, 1);
  });

  test('检测插件异常保留旧缓存并标记 cache_after_device_failure', () async {
    SharedPreferences.setMockInitialValues({
      'delivery_platform_states': jsonEncode({
        'meituan_waimai': {
          'installation': 'installed',
          'source': 'device',
          'checkedAt': '2026-09-10T10:00:00Z',
        },
      }),
    });
    final states = await DeliveryJumpService(
      canLaunch: (_) async => throw StateError('plugin missing'),
    ).detectPlatforms();
    expect(
      states['meituan_waimai']!.installation,
      DeliveryInstallation.installed,
    );
    expect(states['meituan_waimai']!.source, 'cache_after_device_failure');
    expect(
      states['meituan_waimai']!.checkedAt,
      DateTime.parse('2026-09-10T10:00:00Z'),
    );
  });
}

class _ConfigStore implements DeliveryPlatformConfigStore {
  _ConfigStore({required this.ids, this.preferred});

  final List<String> ids;
  final String? preferred;

  @override
  Future<List<String>> loadOrderedPlatformIds() async => ids;

  @override
  Future<void> saveOrderedPlatformIds(List<String> ids) async {}

  @override
  Future<String?> loadPreferredPlatformId() async => preferred;

  @override
  Future<void> savePreferredPlatformId(String? id) async {}
}
