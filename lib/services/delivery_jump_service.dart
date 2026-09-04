import 'dart:convert';

import 'package:url_launcher/url_launcher.dart';

/// 外卖平台定义：URL scheme + H5 兜底链接 + 品牌色。
class DeliveryPlatform {
  const DeliveryPlatform({
    required this.id,
    required this.label,
    required this.brandColor,
    required this.fallbackUrl,
  });

  /// 稳定代码：meituan_waimai / meituan / eleme / jd_waimai。
  final String id;
  final String label;

  /// 品牌色（ARGB 值），按钮背景用。
  final int brandColor;

  /// 未安装 APP 时的 H5 兜底链接。
  final String fallbackUrl;
}

/// 外卖跳转结果：实际拉起了哪个链接、是否成功。
class DeliveryJumpResult {
  const DeliveryJumpResult({
    required this.success,
    required this.usedUri,
    required this.usedFallback,
  });

  final bool success;
  final Uri usedUri;

  /// true = 走了 H5 兜底（APP 未安装或 scheme 拉起失败）。
  final bool usedFallback;
}

/// 平台启用状态与顺序的持久化接口。
///
/// V1.0 今晚使用 [DefaultDeliveryPlatformConfig]（全部启用、固定优先级）；
/// SharedPreferences 持久化与设置页 UI 为遗留项，接口签名已留好，
/// 后续实现只需替换注入的 store，不改调用方。
abstract class DeliveryPlatformConfigStore {
  /// 按展示顺序返回启用的平台 id 列表。
  Future<List<String>> loadOrderedPlatformIds();

  /// 保存启用平台及顺序。
  Future<void> saveOrderedPlatformIds(List<String> ids);
}

/// 默认配置：四个平台全启用，固定优先级（美团外卖 > 美团 > 饿了么 > 京东）。
class DefaultDeliveryPlatformConfig implements DeliveryPlatformConfigStore {
  const DefaultDeliveryPlatformConfig();

  @override
  Future<List<String>> loadOrderedPlatformIds() async =>
      DeliveryJumpService.platforms.map((platform) => platform.id).toList();

  @override
  Future<void> saveOrderedPlatformIds(List<String> ids) async {
    // 默认实现不持久化（遗留项：SharedPreferences）。
  }
}

typedef _UriCanLaunch = Future<bool> Function(Uri uri);
typedef _UriLaunch = Future<bool> Function(Uri uri, {LaunchMode mode});

/// 外卖平台搜索跳转：已安装走 URL scheme 拉起，失败或未安装回落 H5。
///
/// MVP 时期美团跳转失效的根因有两个，本次均已修复：
/// 1. scheme 用错（`meituan://`），实际应为 `meituanwaimai://`（美团外卖）
///    与 `imeituan://`（美团 APP）；
/// 2. Android 11+ 包可见性限制：manifest 缺少对应 scheme 的 `<queries>`
///    声明时 canLaunchUrl 恒为 false（已在 AndroidManifest.xml 补上）。
class DeliveryJumpService {
  DeliveryJumpService({
    this.configStore = const DefaultDeliveryPlatformConfig(),
    Future<bool> Function(Uri uri)? canLaunch,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launch,
  }) : _canLaunch = canLaunch ?? _defaultCanLaunch,
       _launch = launch ?? _defaultLaunch;

  final DeliveryPlatformConfigStore configStore;

  final _UriCanLaunch _canLaunch;
  final _UriLaunch _launch;

  /// 支持的平台，数组顺序即默认优先级。
  static const List<DeliveryPlatform> platforms = [
    DeliveryPlatform(
      id: 'meituan_waimai',
      label: '美团外卖',
      brandColor: 0xFFFFC300,
      fallbackUrl: 'https://waimai.meituan.com',
    ),
    DeliveryPlatform(
      id: 'meituan',
      label: '美团',
      brandColor: 0xFFFF6633,
      fallbackUrl: 'https://www.meituan.com',
    ),
    DeliveryPlatform(
      id: 'eleme',
      label: '饿了么',
      brandColor: 0xFF0097FF,
      fallbackUrl: 'https://h5.ele.me',
    ),
    DeliveryPlatform(
      id: 'jd_waimai',
      label: '京东外卖',
      brandColor: 0xFFE1251B,
      fallbackUrl: 'https://www.jd.com',
    ),
  ];

  /// 全部平台 id（供配置接口的默认实现使用）。
  static List<String> get allPlatformIds =>
      platforms.map((platform) => platform.id).toList();

  /// 当前启用的平台（按配置顺序）。今晚的默认配置=全启用+固定顺序。
  Future<List<DeliveryPlatform>> loadEnabledPlatforms() async {
    final ids = await configStore.loadOrderedPlatformIds();
    final byId = {for (final platform in platforms) platform.id: platform};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 构造拉起外卖 APP 的 scheme 链接。
  static Uri buildSchemeUri(DeliveryPlatform platform, String keyword) =>
      switch (platform.id) {
        'meituan_waimai' => Uri(
          scheme: 'meituanwaimai',
          host: 'waimai.meituan.com',
          path: '/search',
          queryParameters: {'query': keyword},
        ),
        'meituan' => Uri(
          scheme: 'imeituan',
          host: 'www.meituan.com',
          path: '/search',
          queryParameters: {'q': keyword},
        ),
        'eleme' => Uri(
          scheme: 'eleme',
          host: 'search',
          queryParameters: {'keyword': keyword},
        ),
        'jd_waimai' => Uri(
          // Dart Uri 会把 scheme 归一化为小写（RFC 3986 scheme 不分大小写），
          // 京东外卖实际拉起时使用小写 openapp.jdmobile://，与 manifest
          // <queries> 声明保持一致。
          scheme: 'openapp.jdmobile',
          host: 'virtual',
          queryParameters: {
            'params': jsonEncode({
              'category': 'jump',
              'des': 'searchMall',
              'keyword': keyword,
            }),
          },
        ),
        _ => throw ArgumentError.value(
          platform.id,
          'platform.id',
          'unknown delivery platform',
        ),
      };

  /// 构造 H5 兜底链接。
  static Uri buildFallbackUri(DeliveryPlatform platform) =>
      Uri.parse(platform.fallbackUrl);

  /// 跳转到平台内搜索 [keyword]。返回实际使用的链接与是否成功。
  Future<DeliveryJumpResult> jumpToSearch(
    DeliveryPlatform platform,
    String keyword,
  ) async {
    final schemeUri = buildSchemeUri(platform, keyword);
    var launched = false;
    if (await _canLaunch(schemeUri)) {
      launched = await _launch(schemeUri, mode: LaunchMode.externalApplication);
    }
    if (launched) {
      return DeliveryJumpResult(
        success: true,
        usedUri: schemeUri,
        usedFallback: false,
      );
    }

    // 未安装 APP 或 scheme 拉起失败 → H5 兜底。
    final fallbackUri = buildFallbackUri(platform);
    launched = await _launch(fallbackUri, mode: LaunchMode.externalApplication);
    return DeliveryJumpResult(
      success: launched,
      usedUri: fallbackUri,
      usedFallback: true,
    );
  }

  static Future<bool> _defaultCanLaunch(Uri uri) => canLaunchUrl(uri);

  static Future<bool> _defaultLaunch(Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) =>
      launchUrl(uri, mode: mode);
}
