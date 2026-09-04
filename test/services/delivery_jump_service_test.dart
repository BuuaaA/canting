import 'package:canting/services/delivery_jump_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('URL 构造', () {
    const keyword = '黄焖鸡米饭';

    test('美团外卖 scheme：meituanwaimai:// + query 参数', () {
      final uri = DeliveryJumpService.buildSchemeUri(
        DeliveryJumpService.platforms[0],
        keyword,
      );
      expect(uri.scheme, 'meituanwaimai');
      expect(uri.host, 'waimai.meituan.com');
      expect(uri.path, '/search');
      expect(uri.queryParameters['query'], keyword);
    });

    test('美团 APP scheme：imeituan:// + q 参数', () {
      final uri = DeliveryJumpService.buildSchemeUri(
        DeliveryJumpService.platforms[1],
        keyword,
      );
      expect(uri.scheme, 'imeituan');
      expect(uri.host, 'www.meituan.com');
      expect(uri.path, '/search');
      expect(uri.queryParameters['q'], keyword);
    });

    test('饿了么 scheme：eleme://search?keyword=', () {
      final uri = DeliveryJumpService.buildSchemeUri(
        DeliveryJumpService.platforms[2],
        keyword,
      );
      expect(uri.scheme, 'eleme');
      expect(uri.host, 'search');
      expect(uri.queryParameters['keyword'], keyword);
    });

    test('京东外卖 scheme：openapp.jdmobile://virtual?params={json}', () {
      final uri = DeliveryJumpService.buildSchemeUri(
        DeliveryJumpService.platforms[3],
        keyword,
      );
      // Dart Uri 把 scheme 归一化为小写；京东实际可用形式也是小写。
      expect(uri.scheme, 'openapp.jdmobile');
      expect(uri.host, 'virtual');
      final params = uri.queryParameters['params']!;
      expect(params, contains('"category":"jump"'));
      expect(params, contains('"des":"searchMall"'));
      expect(params, contains('"keyword":"$keyword"'));
    });

    test('H5 兜底链接与文档一致', () {
      expect(
        DeliveryJumpService.buildFallbackUri(
          DeliveryJumpService.platforms[0],
        ).toString(),
        'https://waimai.meituan.com',
      );
      expect(
        DeliveryJumpService.buildFallbackUri(
          DeliveryJumpService.platforms[1],
        ).toString(),
        'https://www.meituan.com',
      );
      expect(
        DeliveryJumpService.buildFallbackUri(
          DeliveryJumpService.platforms[2],
        ).toString(),
        'https://h5.ele.me',
      );
      expect(
        DeliveryJumpService.buildFallbackUri(
          DeliveryJumpService.platforms[3],
        ).toString(),
        'https://www.jd.com',
      );
    });

    test('未知平台 id 抛出 ArgumentError', () {
      const unknown = DeliveryPlatform(
        id: 'unknown',
        label: '未知',
        brandColor: 0xFF000000,
        fallbackUrl: 'https://example.com',
      );
      expect(
        () => DeliveryJumpService.buildSchemeUri(unknown, keyword),
        throwsArgumentError,
      );
    });
  });

  group('jumpToSearch 跳转逻辑', () {
    late LaunchMode? launchedMode;
    late bool canLaunchResult;
    late bool launchResult;

    DeliveryJumpService buildService() => DeliveryJumpService(
      canLaunch: (_) async => canLaunchResult,
      launch: (uri, {mode = LaunchMode.platformDefault}) async {
        launchedMode = mode;
        return launchResult;
      },
    );

    setUp(() {
      launchedMode = null;
      canLaunchResult = true;
      launchResult = true;
    });

    test('已安装：拉起 scheme 链接，走外部应用模式', () async {
      final service = buildService();
      final platform = DeliveryJumpService.platforms[0];

      final result = await service.jumpToSearch(platform, '蒜蓉西兰花');

      expect(result.success, isTrue);
      expect(result.usedFallback, isFalse);
      expect(result.usedUri, DeliveryJumpService.buildSchemeUri(platform, '蒜蓉西兰花'));
      expect(launchedMode, LaunchMode.externalApplication);
    });

    test('未安装：canLaunch 为 false 时回落 H5 链接', () async {
      canLaunchResult = false;
      final service = buildService();
      final platform = DeliveryJumpService.platforms[2];

      final result = await service.jumpToSearch(platform, '凉拌黄瓜');

      expect(result.success, isTrue);
      expect(result.usedFallback, isTrue);
      expect(result.usedUri, DeliveryJumpService.buildFallbackUri(platform));
    });

    test('scheme 拉起失败（返回 false）时也回落 H5', () async {
      canLaunchResult = true;
      launchResult = false;
      final launchCalls = <Uri>[];
      final service = DeliveryJumpService(
        canLaunch: (_) async => true,
        launch: (uri, {mode = LaunchMode.platformDefault}) async {
          launchCalls.add(uri);
          return false;
        },
      );
      final platform = DeliveryJumpService.platforms[1];

      final result = await service.jumpToSearch(platform, '香菇青菜');

      expect(result.success, isFalse);
      expect(result.usedFallback, isTrue);
      expect(launchCalls, hasLength(2));
      expect(launchCalls.first, DeliveryJumpService.buildSchemeUri(platform, '香菇青菜'));
      expect(launchCalls.last, DeliveryJumpService.buildFallbackUri(platform));
    });
  });

  group('平台配置', () {
    test('默认配置：全部启用、固定优先级', () async {
      const service = DefaultDeliveryPlatformConfig();
      final ids = await service.loadOrderedPlatformIds();

      expect(ids, [
        'meituan_waimai',
        'meituan',
        'eleme',
        'jd_waimai',
      ]);
    });

    test('注入的自定义配置决定启用平台与顺序', () async {
      final service = DeliveryJumpService(
        configStore: _FixedConfigStore(['eleme', 'meituan_waimai']),
        canLaunch: (_) async => false,
        launch: (_, {mode = LaunchMode.platformDefault}) async => true,
      );

      final platforms = await service.loadEnabledPlatforms();

      expect(platforms.map((platform) => platform.id).toList(), [
        'eleme',
        'meituan_waimai',
      ]);
    });

    test('配置里的未知平台 id 被忽略', () async {
      final service = DeliveryJumpService(
        configStore: _FixedConfigStore(['eleme', 'not_a_platform']),
        canLaunch: (_) async => false,
        launch: (_, {mode = LaunchMode.platformDefault}) async => true,
      );

      final platforms = await service.loadEnabledPlatforms();

      expect(platforms.map((platform) => platform.id).toList(), ['eleme']);
    });
  });
}

class _FixedConfigStore implements DeliveryPlatformConfigStore {
  const _FixedConfigStore(this.ids);

  final List<String> ids;

  @override
  Future<List<String>> loadOrderedPlatformIds() async => ids;

  @override
  Future<void> saveOrderedPlatformIds(List<String> ids) async {}
}
