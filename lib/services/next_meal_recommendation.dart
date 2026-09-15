import 'dart:async';
import 'dart:convert';

import 'intake_statistics.dart';

typedef NextMealRemoteCall = Future<String> Function(NextMealRequest request);
typedef NextMealFeedbackSink = Future<void> Function(NextMealFeedback event);
typedef NextMealEventSink = Future<void> Function(Map<String, dynamic> event);

/// Shared upper bound for one recommendation attempt, including one bounded
/// invalid-JSON retry. The adapter and service use the same budget.
const nextMealCallBudget = Duration(seconds: 25);

class NextMealRemoteException implements Exception {
  const NextMealRemoteException(this.reasonCode, [this.statusCode]);
  final String reasonCode;
  final int? statusCode;
}

const _mealTypes = {'breakfast', 'lunch', 'dinner', 'snack'};
const _categories = {
  'grain',
  'tuber',
  'vegetable',
  'fruit',
  'animal_food',
  'dairy',
  'soy',
  'nut',
  'cooking_oil',
  'salt',
};

/// The only data sent to a future recommendation gateway.
/// It deliberately contains summary statistics, never MealRecord or OCR data.
class NextMealRequest {
  const NextMealRequest({
    required this.requestId,
    required this.today,
    required this.rolling7d,
    required this.nextMealType,
    this.dietaryExclusions = const [],
    this.budget,
    this.city,
    this.availablePlatforms = const [],
    this.excludeDishNames = const [],
  });

  final String requestId;
  final TodayIntakeStats today;
  final Rolling7dIntakeStats rolling7d;
  final String nextMealType;
  final List<String> dietaryExclusions;
  final double? budget;
  final String? city;
  final List<String> availablePlatforms;
  final List<String> excludeDishNames;

  int get dataRevision => today.revision;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'dataRevision': dataRevision,
    'nextMealType': nextMealType,
    'today': today.toJson(),
    'rolling7d': rolling7d.toJson(),
    'dietaryExclusions': dietaryExclusions,
    'budget': budget,
    'city': city,
    'availablePlatforms': availablePlatforms,
    'excludeDishNames': excludeDishNames.take(3).toList(),
  };
}

class NextMealSuggestion {
  const NextMealSuggestion({
    required this.dishName,
    required this.searchKeyword,
    required this.primaryCategory,
    required this.estimatedServing,
    required this.reason,
  });

  final String dishName;
  final String searchKeyword;
  final String primaryCategory;
  final String estimatedServing;
  final String reason;

  Map<String, dynamic> toJson() => {
    'dishName': dishName,
    'searchKeyword': searchKeyword,
    'primaryCategory': primaryCategory,
    'estimatedServing': estimatedServing,
    'reason': reason,
  };

  factory NextMealSuggestion.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('suggestion field is missing');
      }
      return value.trim();
    }

    final category = text('primaryCategory');
    if (!_categories.contains(category)) {
      throw FormatException('unknown recommendation category: $category');
    }
    return NextMealSuggestion(
      dishName: text('dishName'),
      searchKeyword: text('searchKeyword'),
      primaryCategory: category,
      estimatedServing: text('estimatedServing'),
      reason: text('reason'),
    );
  }
}

class NextMealGuidance {
  const NextMealGuidance({
    required this.primary,
    required this.oilSalt,
    required this.reduceStaple,
  });

  final String primary;
  final String oilSalt;
  final String reduceStaple;

  Map<String, dynamic> toJson() => {
    'primary': primary,
    'oilSalt': oilSalt,
    'reduceStaple': reduceStaple,
  };

  factory NextMealGuidance.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('guidance field is missing');
      }
      return value.trim();
    }

    return NextMealGuidance(
      primary: text('primary'),
      oilSalt: text('oilSalt'),
      reduceStaple: text('reduceStaple'),
    );
  }
}

class NextMealResult {
  const NextMealResult({
    required this.requestId,
    required this.dataRevision,
    required this.source,
    required this.status,
    required this.reasonCode,
    required this.suggestions,
    required this.guidance,
    this.contextKey,
  });

  final String requestId;
  final int dataRevision;
  final String source; // ai or local_rule
  final String status; // success, degraded, failed
  final String reasonCode;
  final List<NextMealSuggestion> suggestions;
  final NextMealGuidance guidance;

  /// Date/meal-slot identity used by UI caches; null is allowed for old test
  /// and adapter results that predate the context guard.
  final String? contextKey;

  bool get isUsable => status != 'failed' && suggestions.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'dataRevision': dataRevision,
    'source': source,
    'status': status,
    'reasonCode': reasonCode,
    'suggestions': suggestions.map((s) => s.toJson()).toList(),
    'guidance': guidance.toJson(),
  };

  static NextMealResult failed(NextMealRequest request, String reasonCode) {
    final inputIssue =
        reasonCode == 'invalid_input' ||
        reasonCode == 'date_mismatch' ||
        reasonCode == 'revision_mismatch';
    return NextMealResult(
      requestId: request.requestId,
      dataRevision: request.dataRevision,
      source: 'local_rule',
      status: 'failed',
      reasonCode: reasonCode,
      suggestions: const [],
      guidance: NextMealGuidance(
        primary: inputIssue
            ? '推荐输入不完整或前后不一致，暂不展示下一餐建议。'
            : '当前统计不是最新，暂不展示下一餐建议。',
        oilSalt: inputIssue ? '请先检查本地统计输入。' : '请先刷新本地统计。',
        reduceStaple: '不根据未知数据推断份量。',
      ),
      contextKey: _contextKey(request),
    );
  }

  static String _contextKey(NextMealRequest request) =>
      '${request.today.date}|${request.nextMealType}';
}

enum NextMealFeedbackAction { accept, ignore, refresh }

class NextMealFeedback {
  const NextMealFeedback({
    required this.requestId,
    required this.action,
    required this.dishNames,
    this.acceptanceBasis,
  });

  final String requestId;
  final NextMealFeedbackAction action;
  final List<String> dishNames;
  final String? acceptanceBasis;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'action': action.name,
    'dishNames': dishNames.take(3).toList(),
    if (acceptanceBasis != null) 'acceptanceBasis': acceptanceBasis,
  };
}

/// Validates an optional remote response and falls back to deterministic rules.
/// The remote callback is never called unless [remote] is explicitly supplied.
class NextMealRecommendationService {
  NextMealRecommendationService({
    this.remote,
    this.timeout = nextMealCallBudget,
    this.feedbackSink,
    this.eventSink,
  });

  final NextMealRemoteCall? remote;
  final Duration timeout;
  final NextMealFeedbackSink? feedbackSink;
  final NextMealEventSink? eventSink;
  final Set<String> _acceptedRequestIds = {};
  final Set<String> _acceptingRequestIds = {};

  Future<NextMealResult> nextMeal(NextMealRequest request) async {
    final validationIssue = _validateRequest(request);
    await _emit({
      'event': 'next_meal_request',
      'requestId': request.requestId,
      'dataRevision': request.dataRevision,
      'nextMealType': request.nextMealType,
    });
    late final NextMealResult result;
    if (validationIssue != null) {
      result = NextMealResult.failed(request, validationIssue);
    } else if (request.today.stale || request.rolling7d.stale) {
      result = NextMealResult.failed(request, 'stale_input');
    } else if (remote == null) {
      result = _local(request, 'unconfigured');
    } else {
      result = await _remoteOrLocal(request);
    }
    await _emit({
      'event': 'next_meal_result',
      'requestId': result.requestId,
      'dataRevision': result.dataRevision,
      'source': result.source,
      'status': result.status,
      'reasonCode': result.reasonCode,
      'suggestionCount': result.suggestions.length,
    });
    return result;
  }

  Future<NextMealResult> _remoteOrLocal(NextMealRequest request) async {
    final stopwatch = Stopwatch()..start();
    Duration remaining() {
      final left = timeout - stopwatch.elapsed;
      return left.isNegative ? Duration.zero : left;
    }

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final raw = await remote!(request).timeout(remaining());
          return _parseRemote(request, raw);
        } on FormatException {
          if (attempt == 1) rethrow;
        }
      }
    } on TimeoutException {
      return _local(request, 'timeout');
    } on FormatException {
      return _local(request, 'invalid_json');
    } on NextMealRemoteException catch (error) {
      return _local(request, error.reasonCode);
    } catch (_) {
      return _local(request, 'remote_unavailable');
    }
    return _local(request, 'remote_unavailable');
  }

  Future<void> _emit(Map<String, dynamic> event) async {
    try {
      await eventSink?.call(Map.unmodifiable(event));
    } catch (_) {
      // Audit persistence is best effort and must never block recommendations.
    }
  }

  Future<void> recordFeedback({
    required NextMealResult result,
    required NextMealFeedbackAction action,
    String? acceptanceBasis,
  }) async {
    if (feedbackSink == null || !result.isUsable) return;
    if (action == NextMealFeedbackAction.accept &&
        acceptanceBasis != 'platform_open_accepted') {
      throw ArgumentError.value(
        acceptanceBasis,
        'acceptanceBasis',
        'accept requires platform_open_accepted',
      );
    }
    if (action == NextMealFeedbackAction.accept) {
      if (_acceptedRequestIds.contains(result.requestId) ||
          !_acceptingRequestIds.add(result.requestId)) {
        return;
      }
    }
    try {
      await feedbackSink!(
        NextMealFeedback(
          requestId: result.requestId,
          action: action,
          dishNames: result.suggestions.map((s) => s.dishName).toList(),
          acceptanceBasis: acceptanceBasis,
        ),
      );
      if (action == NextMealFeedbackAction.accept) {
        if (_acceptedRequestIds.length >= 128) {
          _acceptedRequestIds.remove(_acceptedRequestIds.first);
        }
        _acceptedRequestIds.add(result.requestId);
      }
    } catch (_) {
      // A failed local write must not block opening the platform.
    } finally {
      _acceptingRequestIds.remove(result.requestId);
    }
  }

  NextMealResult _parseRemote(NextMealRequest request, String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('response is not an object');
    }
    final map = decoded.cast<String, dynamic>();
    final rawSuggestions = map['suggestions'];
    final rawGuidance = map['guidance'];
    if (rawSuggestions is! List || rawGuidance is! Map) {
      throw const FormatException('response fields are missing');
    }
    final suggestions = rawSuggestions
        .map((item) {
          if (item is! Map) {
            throw const FormatException('invalid suggestion');
          }
          return NextMealSuggestion.fromJson(item.cast<String, dynamic>());
        })
        .toList(growable: false);
    _validateSuggestions(request, suggestions);
    final guidance = NextMealGuidance.fromJson(
      rawGuidance.cast<String, dynamic>(),
    );
    return NextMealResult(
      requestId: request.requestId,
      dataRevision: request.dataRevision,
      source: 'ai',
      status: 'success',
      reasonCode: 'ai_validated',
      suggestions: suggestions,
      guidance: guidance,
      contextKey: '${request.today.date}|${request.nextMealType}',
    );
  }

  NextMealResult _local(NextMealRequest request, String reasonCode) {
    final priorities = _deficitCategories(request);
    final grainHigh = request.today.categories['grain']?.status == 'high';
    final candidates = <_LocalCandidate>[
      const _LocalCandidate(
        '西兰花鸡胸肉饭',
        '西兰花鸡胸肉 少油少盐',
        'vegetable',
        '蔬菜约一小盘，鸡胸肉约一掌心（估算）',
        '优先补足蔬菜，搭配明确的非油炸蛋白。',
      ),
      const _LocalCandidate(
        '清蒸鱼配时蔬',
        '清蒸鱼 时蔬 少油',
        'animal_food',
        '鱼肉约一掌心、时蔬约一小盘（估算）',
        '用清蒸做法补充动物性食物，减少油盐。',
      ),
      const _LocalCandidate(
        '番茄鸡蛋荞麦面',
        '番茄鸡蛋荞麦面 少油',
        'grain',
        '荞麦面一份、番茄鸡蛋适量（估算）',
        '普通搭配建议；份量按常规估算。',
      ),
      const _LocalCandidate(
        '原味酸奶配苹果',
        '原味酸奶 苹果 无糖',
        'fruit',
        '原味酸奶一杯、苹果一小个（估算）',
        '补充水果；选择无糖原味，避免含糖饮料。',
      ),
    ];
    candidates.sort((a, b) {
      final ai = priorities.indexOf(a.category);
      final bi = priorities.indexOf(b.category);
      return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
    });
    final knownGapCategories = priorities.toSet();
    final selected = candidates
        .where((candidate) {
          final haystack = '${candidate.dishName} ${candidate.searchKeyword}'
              .toLowerCase();
          return !_matchesAny(haystack, request.excludeDishNames) &&
              !_matchesAny(haystack, request.dietaryExclusions);
        })
        .take(3)
        .map((candidate) {
          final suggestion = candidate.toSuggestion();
          if (knownGapCategories.contains(suggestion.primaryCategory) ||
              (grainHigh && suggestion.primaryCategory == 'grain')) {
            if (grainHigh && suggestion.primaryCategory == 'grain') {
              return NextMealSuggestion(
                dishName: suggestion.dishName,
                searchKeyword: suggestion.searchKeyword,
                primaryCategory: suggestion.primaryCategory,
                estimatedServing: '荞麦面小份、番茄鸡蛋适量（估算）',
                reason: '已记录主食偏多，下一餐建议选择小份。',
              );
            }
            return suggestion;
          }
          return NextMealSuggestion(
            dishName: suggestion.dishName,
            searchKeyword: suggestion.searchKeyword,
            primaryCategory: suggestion.primaryCategory,
            estimatedServing: suggestion.estimatedServing,
            reason: '当前没有该类别的可靠缺口，按普通搭配提供。',
          );
        })
        .toList();
    final result = NextMealResult(
      requestId: request.requestId,
      dataRevision: request.dataRevision,
      source: 'local_rule',
      status: selected.isEmpty ? 'failed' : 'degraded',
      reasonCode: selected.isEmpty ? 'no_safe_candidate' : reasonCode,
      suggestions: selected,
      guidance: NextMealGuidance(
        primary: knownGapCategories.contains('vegetable')
            ? '优先补足已知蔬菜缺口。'
            : '按已知记录提供普通搭配；未知类别不按零摄入处理。',
        oilSalt: '优先清蒸、白灼或少油少盐做法。',
        reduceStaple: knownGapCategories.contains('grain')
            ? '根据已知主食记录选择合适份量；未知时不强行减量。'
            : '当前没有可靠的主食缺口或偏多信息，不额外调整主食。',
      ),
      contextKey: '${request.today.date}|${request.nextMealType}',
    );
    return result;
  }

  List<String> _deficitCategories(NextMealRequest request) {
    final known = <String, double>{};
    for (final entry in request.today.categories.entries) {
      final gap = entry.value.gap;
      if (gap != null && gap > 0) known[entry.key] = gap;
    }
    for (final entry in request.rolling7d.averages.entries) {
      final average = entry.value.average;
      final min = entry.value.target.min;
      if (average != null && min != null && average < min) {
        known[entry.key] = (known[entry.key] ?? 0) + (min - average);
      }
    }
    final result = known.keys.toList()
      ..sort((a, b) => known[b]!.compareTo(known[a]!));
    return result;
  }

  static String? _validateRequest(NextMealRequest request) {
    if (request.requestId.trim().isEmpty) {
      return 'invalid_input';
    }
    if (!_mealTypes.contains(request.nextMealType)) {
      return 'invalid_input';
    }
    if (request.dataRevision < 0) {
      return 'invalid_input';
    }
    if (request.today.revision != request.rolling7d.revision) {
      return 'revision_mismatch';
    }
    if (request.today.date != request.rolling7d.endDate) {
      return 'date_mismatch';
    }
    if (request.budget != null &&
        (!request.budget!.isFinite || request.budget! < 0)) {
      return 'invalid_input';
    }
    return null;
  }

  static void _validateSuggestions(
    NextMealRequest request,
    List<NextMealSuggestion> suggestions,
  ) {
    if (suggestions.length < 2 || suggestions.length > 3) {
      throw const FormatException('recommendations must contain 2 or 3 items');
    }
    final names = <String>{};
    for (final suggestion in suggestions) {
      if (!names.add(suggestion.dishName)) {
        throw const FormatException('duplicate dish');
      }
      final text = '${suggestion.dishName} ${suggestion.searchKeyword}'
          .toLowerCase();
      if (text.contains('多吃蔬菜') ||
          text.contains('¥') ||
          text.contains('价格') ||
          text.contains('库存') ||
          text.contains('商家')) {
        throw const FormatException('unsafe or non-dish output');
      }
      if (request.dietaryExclusions.any(
        (excluded) => _matchesAny(text, [excluded]),
      )) {
        throw const FormatException('recommendation violates exclusion');
      }
      if (request.excludeDishNames.any(
        (excluded) => _matchesAny(text, [excluded]),
      )) {
        throw const FormatException('recommendation repeats excluded dish');
      }
    }
  }

  static bool _matchesAny(String text, Iterable<String> exclusions) {
    final lower = text.toLowerCase();
    for (final exclusion in exclusions) {
      final value = exclusion.trim().toLowerCase();
      if (value.isEmpty) continue;
      final tokens = <String>{value};
      if (value.contains('素食') || value.contains('vegetarian')) {
        tokens.addAll(const [
          '鱼',
          '鸡',
          '牛',
          '猪',
          '肉',
          'fish',
          'chicken',
          'beef',
          'pork',
        ]);
      }
      if (value.contains('纯素') ||
          value.contains('vegan') ||
          value.contains('plant-based')) {
        tokens.addAll(const [
          '鱼',
          '鸡',
          '牛',
          '猪',
          '肉',
          '蛋',
          '奶',
          '酸奶',
          '乳',
          'fish',
          'chicken',
          'beef',
          'pork',
          'egg',
          'milk',
          'yogurt',
          'dairy',
        ]);
      }
      if (value.contains('鱼') || value.contains('fish')) {
        tokens.addAll(const ['鱼', '鲈', '虾', '蟹', 'fish', 'shrimp', 'crab']);
      }
      if (value.contains('牛奶') ||
          value.contains('乳制品') ||
          value.contains('奶制品') ||
          value.contains('dairy') ||
          value.contains('milk')) {
        tokens.addAll(const ['奶', '酸奶', '牛奶', '乳', 'yogurt', 'milk', 'dairy']);
      }
      if (tokens.any(lower.contains)) return true;
    }
    return false;
  }
}

class _LocalCandidate {
  const _LocalCandidate(
    this.dishName,
    this.searchKeyword,
    this.category,
    this.serving,
    this.reason,
  );
  final String dishName, searchKeyword, category, serving, reason;

  NextMealSuggestion toSuggestion() => NextMealSuggestion(
    dishName: dishName,
    searchKeyword: searchKeyword,
    primaryCategory: category,
    estimatedServing: serving,
    reason: reason,
  );
}
