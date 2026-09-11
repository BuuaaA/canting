import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryPlatform {
  const DeliveryPlatform({
    required this.id,
    required this.label,
    required this.brandColor,
    required this.fallbackUrl,
    this.scheme,
    this.supportsKeyword = false,
  });

  final String id;
  final String label;
  final int brandColor;
  final String fallbackUrl;
  final String? scheme;
  final bool supportsKeyword;
}

enum DeliveryInstallation { installed, notInstalled, unknown }

class DeliveryPlatformState {
  const DeliveryPlatformState({
    required this.platformId,
    required this.installation,
    required this.source,
    this.checkedAt,
  });

  final String platformId;
  final DeliveryInstallation installation;
  final String source;
  final DateTime? checkedAt;

  String get wireInstallation => switch (installation) {
    DeliveryInstallation.installed => 'installed',
    DeliveryInstallation.notInstalled => 'not_installed',
    DeliveryInstallation.unknown => 'unknown',
  };
}

class DeliveryLinkTarget {
  const DeliveryLinkTarget({
    required this.kind,
    required this.uri,
    required this.platformId,
    required this.supportsKeyword,
  });

  final String kind;
  final Uri uri;
  final String platformId;
  final bool supportsKeyword;
}

class DeliveryLinkResolution {
  const DeliveryLinkResolution({
    required this.platformId,
    required this.target,
    required this.fallbackTargets,
    required this.reason,
  });

  final String? platformId;
  final DeliveryLinkTarget? target;
  final List<DeliveryLinkTarget> fallbackTargets;
  final String reason;

  List<DeliveryLinkTarget> get allTargets => [
    ...(target == null ? const <DeliveryLinkTarget>[] : [target!]),
    ...fallbackTargets,
  ];
}

class DeliveryJumpResult {
  const DeliveryJumpResult({
    required this.success,
    required this.usedUri,
    required this.usedFallback,
    required this.attempts,
  });

  final bool success;
  final Uri? usedUri;
  final bool usedFallback;
  final List<Uri> attempts;
}

abstract class DeliveryPlatformConfigStore {
  Future<List<String>> loadOrderedPlatformIds();
  Future<void> saveOrderedPlatformIds(List<String> ids);
  Future<String?> loadPreferredPlatformId() async => null;
  Future<void> savePreferredPlatformId(String? id) async {}
}

class DefaultDeliveryPlatformConfig implements DeliveryPlatformConfigStore {
  const DefaultDeliveryPlatformConfig();

  @override
  Future<List<String>> loadOrderedPlatformIds() async =>
      DeliveryJumpService.platforms.map((platform) => platform.id).toList();

  @override
  Future<void> saveOrderedPlatformIds(List<String> ids) async {}

  @override
  Future<String?> loadPreferredPlatformId() async => null;

  @override
  Future<void> savePreferredPlatformId(String? id) async {}
}

class DeliveryPlatformSetting {
  const DeliveryPlatformSetting({required this.id, required this.enabled});

  final String id;
  final bool enabled;
}

class DeliveryPlatformPrefsStore implements DeliveryPlatformConfigStore {
  const DeliveryPlatformPrefsStore();

  static const _orderKey = 'delivery_platform_order';
  static const _disabledKey = 'delivery_platform_disabled';
  static const _preferredKey = 'delivery_platform_preferred';

  static List<DeliveryPlatformSetting> _defaultSettings() => [
    for (final platform in DeliveryJumpService.platforms)
      DeliveryPlatformSetting(id: platform.id, enabled: true),
  ];

  Future<List<DeliveryPlatformSetting>> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = prefs.getStringList(_orderKey) ?? const [];
      final disabled = (prefs.getStringList(_disabledKey) ?? const []).toSet();
      final knownIds = DeliveryJumpService.allPlatformIds;
      final orderedIds = [
        ...order.where(knownIds.contains),
        ...knownIds.where((id) => !order.contains(id)),
      ];
      if (orderedIds.isEmpty) return _defaultSettings();
      return [
        for (final id in orderedIds)
          DeliveryPlatformSetting(id: id, enabled: !disabled.contains(id)),
      ];
    } catch (_) {
      return _defaultSettings();
    }
  }

  Future<void> saveSettings(List<DeliveryPlatformSetting> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, [
      for (final item in settings) item.id,
    ]);
    await prefs.setStringList(_disabledKey, [
      for (final item in settings)
        if (!item.enabled) item.id,
    ]);
  }

  @override
  Future<List<String>> loadOrderedPlatformIds() async => [
    for (final item in await loadSettings())
      if (item.enabled) item.id,
  ];

  @override
  Future<void> saveOrderedPlatformIds(List<String> ids) async {
    final settings = await loadSettings();
    final known = {for (final item in settings) item.id: item};
    final enabled = ids.toSet();
    await saveSettings([
      for (final id in ids)
        if (known.containsKey(id))
          DeliveryPlatformSetting(id: id, enabled: true),
      for (final item in settings)
        if (!enabled.contains(item.id)) item,
    ]);
  }

  @override
  Future<String?> loadPreferredPlatformId() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_preferredKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePreferredPlatformId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_preferredKey);
    } else {
      await prefs.setString(_preferredKey, id);
    }
  }
}

typedef UriCanLaunch = Future<bool> Function(Uri uri);
typedef UriLaunch = Future<bool> Function(Uri uri, {LaunchMode mode});

class DeliveryJumpService {
  DeliveryJumpService({
    this.configStore = const DeliveryPlatformPrefsStore(),
    UriCanLaunch? canLaunch,
    UriLaunch? launch,
  }) : _canLaunch = canLaunch ?? canLaunchUrl,
       _launch = launch ?? launchUrl;

  final DeliveryPlatformConfigStore configStore;
  final UriCanLaunch _canLaunch;
  final UriLaunch _launch;

  /// Only these three are shown to users. Other ids are internal candidates.
  static const List<DeliveryPlatform> platforms = [
    DeliveryPlatform(
      id: 'jd_waimai',
      label: '京东外卖',
      brandColor: 0xFFE1251B,
      fallbackUrl: 'https://www.jd.com',
    ),
    DeliveryPlatform(
      id: 'taobao_shangou',
      label: '淘宝闪购',
      brandColor: 0xFFFF6200,
      fallbackUrl: 'https://www.taobao.com',
    ),
    DeliveryPlatform(
      id: 'meituan_waimai',
      label: '美团外卖',
      brandColor: 0xFFFFC300,
      fallbackUrl: 'https://waimai.meituan.com/mobile/download/',
      scheme: 'meituanwaimai',
      supportsKeyword: true,
    ),
  ];

  static const _candidateOrder = [
    'jd_waimai_app',
    'taobao_shangou_app',
    'meituan_waimai',
    'jd',
    'taobao',
  ];

  static List<String> get allPlatformIds =>
      platforms.map((platform) => platform.id).toList();

  static DeliveryPlatform? platformById(String id) =>
      platforms.where((platform) => platform.id == id).firstOrNull;

  Future<List<DeliveryPlatform>> loadEnabledPlatforms() async {
    final ids = await configStore.loadOrderedPlatformIds();
    final byId = {for (final platform in platforms) platform.id: platform};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Uri? buildAppUri(String platformId, String keyword) {
    if (platformId != 'meituan_waimai') return null;
    return Uri(
      scheme: 'meituanwaimai',
      host: 'waimai.meituan.com',
      path: '/search',
      queryParameters: {'query': keyword},
    );
  }

  static Uri buildFallbackUri(DeliveryPlatform platform, [String? keyword]) =>
      Uri.parse(platform.fallbackUrl);

  Future<Map<String, DeliveryPlatformState>> detectPlatforms() async {
    final now = DateTime.now();
    final cached = await loadCachedStates();
    final states = <String, DeliveryPlatformState>{};
    for (final id in _candidateOrder) {
      final uri = id == 'meituan_waimai' ? buildAppUri(id, '餐盘') : null;
      DeliveryPlatformState state;
      if (uri == null) {
        state =
            cached[id] ??
            const DeliveryPlatformState(
              platformId: '',
              installation: DeliveryInstallation.unknown,
              source: 'unknown_unverified_entry',
            );
        state = DeliveryPlatformState(
          platformId: id,
          installation: state.installation,
          source: state.source,
          checkedAt: state.checkedAt,
        );
      } else {
        try {
          state = DeliveryPlatformState(
            platformId: id,
            installation: await _detect(uri),
            source: 'device',
            checkedAt: now,
          );
        } catch (_) {
          state =
              cached[id] ??
              DeliveryPlatformState(
                platformId: id,
                installation: DeliveryInstallation.unknown,
                source: 'device_check_failed',
              );
          if (cached[id] != null) {
            state = DeliveryPlatformState(
              platformId: id,
              installation: state.installation,
              source: 'cache_after_device_failure',
              checkedAt: state.checkedAt,
            );
          }
        }
      }
      states[id] = state;
    }
    await _saveStates(states);
    await _recordEvent('delivery_platform_detect', {
      'states': {
        for (final e in states.entries) e.key: e.value.wireInstallation,
      },
      'source': 'device',
    });
    return states;
  }

  Future<Map<String, DeliveryPlatformState>> loadCachedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statesKey);
      if (raw == null) return {};
      final map = jsonDecode(raw) as Map;
      return {
        for (final e in map.entries)
          e.key as String: _stateFromJson(
            e.key as String,
            (e.value as Map).cast<String, dynamic>(),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<DeliveryLinkResolution> resolveLink({
    required String keyword,
    String? preferredPlatformId,
    Map<String, DeliveryPlatformState>? states,
  }) async {
    final actualStates = states ?? await loadCachedStates();
    final preferred =
        preferredPlatformId ?? await configStore.loadPreferredPlatformId();
    final enabledIds = (await configStore.loadOrderedPlatformIds()).toSet();
    final candidates = _orderedTargets(
      preferred,
      actualStates,
      keyword,
      enabledIds,
    );
    if (candidates.isEmpty) {
      return DeliveryLinkResolution(
        platformId: null,
        target: null,
        fallbackTargets: const [],
        reason: 'NO_VERIFIED_APP_LINK',
      );
    }
    return DeliveryLinkResolution(
      platformId: candidates.first.platformId,
      target: candidates.first,
      fallbackTargets: candidates.skip(1).toList(growable: false),
      reason: candidates.first.kind == 'app' ? 'APP_AVAILABLE' : 'WEB_FALLBACK',
    );
  }

  Future<DeliveryJumpResult> jumpToSearch(
    DeliveryPlatform platform,
    String keyword,
  ) async {
    final resolution = await resolveLink(
      keyword: keyword,
      preferredPlatformId: platform.id,
    );
    final attempts = <Uri>[];
    final targets = [
      if (platform.scheme != null &&
          (await configStore.loadOrderedPlatformIds()).contains(platform.id) &&
          !resolution.allTargets.any(
            (target) =>
                target.kind == 'app' && target.platformId == platform.id,
          ))
        _appTarget(platform, buildAppUri(platform.id, keyword)!),
      ...resolution.allTargets,
    ];
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      attempts.add(target.uri);
      var accepted = false;
      try {
        accepted = target.kind == 'app'
            ? await _canLaunch(target.uri) &&
                  await _launch(
                    target.uri,
                    mode: LaunchMode.externalApplication,
                  )
            : await _launch(target.uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        accepted = false;
      }
      await _recordEvent('delivery_platform_open', {
        'platformId': target.platformId,
        'target': target.uri.toString(),
        'kind': target.kind,
        'result': accepted ? 'accepted' : 'failed',
        'acceptanceBasis': accepted ? 'platform_open_accepted' : null,
      });
      if (accepted) {
        if (index > 0) {
          await _recordEvent('delivery_platform_fallback', {
            'platformId': target.platformId,
            'result': 'accepted',
            'attempts': attempts.length,
          });
        }
        return DeliveryJumpResult(
          success: true,
          usedUri: target.uri,
          usedFallback: target.kind != 'app',
          attempts: attempts,
        );
      }
      if (index < targets.length - 1) {
        await _recordEvent('delivery_platform_fallback', {
          'platformId': target.platformId,
          'result': 'failed',
          'target': target.uri.toString(),
        });
      }
    }
    return DeliveryJumpResult(
      success: false,
      usedUri: attempts.isEmpty ? null : attempts.last,
      usedFallback: attempts.length > 1,
      attempts: attempts,
    );
  }

  List<DeliveryLinkTarget> _orderedTargets(
    String? preferred,
    Map<String, DeliveryPlatformState> states,
    String keyword,
    Set<String> enabledIds,
  ) {
    final ids = <String>[];
    for (final candidate in _candidateOrder) {
      final id = _visiblePlatformId(candidate);
      if (id != null && enabledIds.contains(id) && !ids.contains(id)) {
        ids.add(id);
      }
    }
    void append(String id, List<DeliveryLinkTarget> output) {
      final platform = platformById(id);
      if (platform == null) {
        return;
      }
      final state = states[id];
      if (platform.scheme != null &&
          state?.installation == DeliveryInstallation.installed) {
        final uri = buildAppUri(id, keyword);
        if (uri != null) output.add(_appTarget(platform, uri));
      }
      output.add(_webTarget(platform, keyword));
    }

    if (preferred != null && ids.contains(preferred)) {
      final preferredTargets = <DeliveryLinkTarget>[];
      append(preferred, preferredTargets);
      final rest = <DeliveryLinkTarget>[];
      final remaining = ids.where((id) => id != preferred);
      for (final id in remaining) {
        append(id, rest);
      }
      return [...preferredTargets, ...rest];
    }
    final appTargets = <DeliveryLinkTarget>[];
    final webTargets = <DeliveryLinkTarget>[];
    for (final id in ids) {
      final platform = platformById(id);
      if (platform == null) {
        continue;
      }
      final state = states[id];
      if (platform.scheme != null &&
          state?.installation == DeliveryInstallation.installed) {
        final uri = buildAppUri(id, keyword);
        if (uri != null) appTargets.add(_appTarget(platform, uri));
      }
      webTargets.add(_webTarget(platform, keyword));
    }
    return [...appTargets, ...webTargets];
  }

  String? _visiblePlatformId(String candidate) => switch (candidate) {
    'jd_waimai_app' || 'jd' => 'jd_waimai',
    'taobao_shangou_app' || 'taobao' => 'taobao_shangou',
    'meituan_waimai' => 'meituan_waimai',
    _ => null,
  };

  DeliveryLinkTarget _appTarget(DeliveryPlatform p, Uri uri) =>
      DeliveryLinkTarget(
        kind: 'app',
        uri: uri,
        platformId: p.id,
        supportsKeyword: p.supportsKeyword,
      );

  DeliveryLinkTarget _webTarget(DeliveryPlatform p, String keyword) =>
      DeliveryLinkTarget(
        kind: 'web',
        uri: buildFallbackUri(p, keyword),
        platformId: p.id,
        supportsKeyword: false,
      );

  Future<DeliveryInstallation> _detect(Uri uri) async {
    return await _canLaunch(uri)
        ? DeliveryInstallation.installed
        : DeliveryInstallation.notInstalled;
  }

  static const _statesKey = 'delivery_platform_states';
  static const _eventsKey = 'delivery_platform_events';

  Future<void> _saveStates(Map<String, DeliveryPlatformState> states) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _statesKey,
        jsonEncode({
          for (final e in states.entries)
            e.key: {
              'installation': e.value.wireInstallation,
              'source': e.value.source,
              'checkedAt': e.value.checkedAt?.toIso8601String(),
            },
        }),
      );
    } catch (_) {}
  }

  DeliveryPlatformState _stateFromJson(String id, Map<String, dynamic> value) =>
      DeliveryPlatformState(
        platformId: id,
        installation: switch (value['installation']) {
          'installed' => DeliveryInstallation.installed,
          'not_installed' => DeliveryInstallation.notInstalled,
          _ => DeliveryInstallation.unknown,
        },
        source: value['source'] as String? ?? 'cache',
        checkedAt: DateTime.tryParse(value['checkedAt'] as String? ?? ''),
      );

  Future<void> _recordEvent(String name, Map<String, Object?> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = prefs.getStringList(_eventsKey) ?? const [];
      final retained = events.length > 100
          ? events.sublist(events.length - 100)
          : events;
      await prefs.setStringList(_eventsKey, [
        ...retained,
        jsonEncode({
          'event': name,
          'occurredAt': DateTime.now().toIso8601String(),
          ...data,
        }),
      ]);
    } catch (_) {}
  }
}
