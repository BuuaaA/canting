import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
