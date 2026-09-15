import 'dart:async';
import 'dart:convert';

import 'package:canting/core_engine.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/recommendation/recommendation_detail_page.dart';
import 'package:canting/ui/home/widgets/recommendation_card.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('推荐上下文日期与统计结果使用相同的补零格式', () {
    for (final date in [DateTime(2026, 9, 5, 18), DateTime(2026, 11, 5, 18)]) {
      final state = _TestAppState(clock: () => date);
      addTearDown(state.dispose);
      expect(
        state.recommendationContextKey(),
        '${date.toIso8601String().substring(0, 10)}|dinner',
      );
    }
  });

  testWidgets('真实推荐服务返回的 AI 菜品在单数字月份显示到详情页', (tester) async {
    final state = _TestAppState(
      nextMealService: NextMealRecommendationService(
        remote: (_) async => jsonEncode({
          'suggestions': [
            for (final name in ['清炒西兰花', '番茄炒鸡蛋'])
              {
                'dishName': name,
                'searchKeyword': '$name 少油少盐',
                'primaryCategory': 'vegetable',
                'estimatedServing': '一小盘（估算）',
                'reason': '搭配蔬菜，份量为估算。',
              },
          ],
          'guidance': {
            'primary': '按常规搭配，未知摄入不作确定推断。',
            'oilSalt': '少油少盐。',
            'reduceStaple': '主食按常规份量。',
          },
        }),
      ),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const RecommendationDetailPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(state.nextMealResult?.source, 'ai');
    expect(state.nextMealResult?.reasonCode, 'ai_validated');
    expect(find.text('清炒西兰花'), findsOneWidget);
    expect(find.text('暂时没有可展示的推荐'), findsNothing);
    expect(state.nextMealResult?.contextKey, state.recommendationContextKey());
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页换批和不感兴趣：pending锁、失败保留旧候选并关联反馈', (tester) async {
    final feedback = <NextMealFeedback>[];
    final service = NextMealRecommendationService(
      feedbackSink: (event) async => feedback.add(event),
    );
    final state = _TestAppState(nextMealService: service);
    addTearDown(state.dispose);

    final first = Completer<NextMealResult>();
    final second = Completer<NextMealResult>();
    final excluded = <Set<String>>[];
    var calls = 0;
    Future<NextMealResult> loader(Set<String> names) {
      excluded.add({...names});
      calls++;
      return calls == 1 ? first.future : second.future;
    }

    final dish = _result(state, requestId: 'A', dishName: '候选 A');
    final failed = NextMealResult.failed(
      NextMealRequest(
        requestId: 'failed',
        today: _today(),
        rolling7d: _rolling(),
        nextMealType: 'dinner',
      ),
      'remote_unavailable',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: RecommendationDetailPage(recommendationLoader: loader),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    first.complete(dish);
    await tester.pumpAndSettle();

    await tester.tap(find.text('换一批'));
    await tester.pump();
    expect(feedback.single.action, NextMealFeedbackAction.refresh);
    expect(feedback.single.requestId, 'A');
    expect(excluded.last, {'候选 A'});
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '换一批'))
          .onPressed,
      isNull,
    );

    second.complete(failed);
    await tester.pumpAndSettle();
    expect(find.text('候选 A'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('不感兴趣'), 400);
    await tester.tap(find.text('不感兴趣'));
    await tester.pump();
    expect(
      feedback.where((event) => event.action == NextMealFeedbackAction.ignore),
      hasLength(1),
    );
    expect(feedback.last.requestId, 'A');
    expect(excluded.last, {'候选 A'});
    expect(tester.takeException(), isNull);
  });

  test('AppState 推荐 Future：首次统计异常可重试，旧 force 结果不覆盖新结果', () async {
    final state = _TestAppState();
    addTearDown(state.dispose);
    state.stats.failFirstToday = true;

    await expectLater(
      state.loadNextMealRecommendation(),
      throwsA(isA<StateError>()),
    );
    final retried = await state.loadNextMealRecommendation();
    expect(retried.isUsable, isTrue);

    final remoteService = _ControlledRecommendationService();
    final raceState = _TestAppState(nextMealService: remoteService);
    addTearDown(raceState.dispose);
    final oldFuture = raceState.loadNextMealRecommendation(force: true);
    final freshFuture = raceState.loadNextMealRecommendation(force: true);
    while (remoteService.calls < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    remoteService.fresh.complete(
      _result(raceState, requestId: 'new', dishName: '新结果'),
    );
    final freshResult = await freshFuture;
    remoteService.old.complete(
      _result(raceState, requestId: 'old', dishName: '旧结果'),
    );
    await oldFuture;
    expect(freshResult.suggestions.first.dishName, '新结果');
    expect(raceState.nextMealResult?.suggestions.first.dishName, '新结果');
  });

  testWidgets('跨日或餐次变化时不显示同 revision 的旧推荐', (tester) async {
    var now = DateTime(2026, 9, 12, 10);
    final state = _TestAppState(clock: () => now);
    addTearDown(state.dispose);
    final first = Completer<NextMealResult>();
    final second = Completer<NextMealResult>();
    var calls = 0;
    Future<NextMealResult> loader(Set<String> _) =>
        ++calls == 1 ? first.future : second.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: RecommendationDetailPage(recommendationLoader: loader),
        ),
      ),
    );
    first.complete(_result(state, requestId: 'day-1', dishName: '昨日推荐'));
    await tester.pumpAndSettle();
    expect(find.text('昨日推荐'), findsOneWidget);

    now = DateTime(2026, 9, 13, 10);
    state.notifyListeners();
    await tester.pump();
    expect(find.text('昨日推荐'), findsNothing);
    second.complete(NextMealResult.failed(
      NextMealRequest(
        requestId: 'day-2',
        today: _today(),
        rolling7d: _rolling(),
        nextMealType: 'breakfast',
      ),
      'remote_unavailable',
    ));
    await tester.pumpAndSettle();
    expect(find.text('昨日推荐'), findsNothing);
  });

  testWidgets('详情页跨餐次时不显示同 revision 的旧推荐', (tester) async {
    var now = DateTime(2026, 9, 12, 10);
    final state = _TestAppState(clock: () => now);
    addTearDown(state.dispose);
    final first = Completer<NextMealResult>();
    final second = Completer<NextMealResult>();
    var calls = 0;
    Future<NextMealResult> loader(Set<String> _) =>
        ++calls == 1 ? first.future : second.future;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: RecommendationDetailPage(recommendationLoader: loader),
        ),
      ),
    );
    first.complete(_result(state, requestId: 'meal-1', dishName: '早餐推荐'));
    await tester.pumpAndSettle();
    expect(find.text('早餐推荐'), findsOneWidget);

    now = DateTime(2026, 9, 12, 12);
    state.notifyListeners();
    await tester.pump();
    expect(find.text('早餐推荐'), findsNothing);
    expect(calls, 2);
    second.complete(
      NextMealResult.failed(
        NextMealRequest(
          requestId: 'meal-2',
          today: _today(),
          rolling7d: _rolling(),
          nextMealType: 'lunch',
        ),
        'remote_unavailable',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('早餐推荐'), findsNothing);
  });

  testWidgets('首页推荐卡片在无 state 通知时按渲染瞬间的餐次过滤旧结果', (tester) async {
    var now = DateTime(2026, 9, 12, 10);
    final first = Completer<NextMealResult>();
    final second = Completer<NextMealResult>();
    var calls = 0;
    final state = _TestAppState(
      clock: () => now,
      recommendationLoader: () => ++calls == 1 ? first.future : second.future,
    );
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeNotifierProvider<AppState>.value(
          value: state,
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                RecommendationCard(onTap: () {}),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('重绘卡片'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    first.complete(_result(state, requestId: 'home-1', dishName: '早餐推荐'));
    await tester.pumpAndSettle();
    expect(find.textContaining('早餐推荐'), findsOneWidget);

    now = DateTime(2026, 9, 12, 12);
    await tester.tap(find.text('重绘卡片'));
    await tester.pump();
    expect(find.textContaining('早餐推荐'), findsNothing);
    expect(calls, 2);
    second.complete(
      NextMealResult.failed(
        NextMealRequest(
          requestId: 'home-2',
          today: _today(),
          rolling7d: _rolling(),
          nextMealType: 'lunch',
        ),
        'remote_unavailable',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('早餐推荐'), findsNothing);
  });
}

NextMealResult _result(
  _TestAppState state, {
  required String requestId,
  required String dishName,
}) => NextMealResult(
  requestId: requestId,
  dataRevision: state.dataRevision,
  source: 'local_rule',
  status: 'degraded',
  reasonCode: 'unconfigured',
  suggestions: [
    NextMealSuggestion(
      dishName: dishName,
      searchKeyword: dishName,
      primaryCategory: 'vegetable',
      estimatedServing: '一小盘',
      reason: '补足蔬菜。',
    ),
  ],
  guidance: const NextMealGuidance(
    primary: '优先补足蔬菜。',
    oilSalt: '少油少盐。',
    reduceStaple: '主食按常规份量。',
  ),
  contextKey: state.recommendationContextKey(),
);

TodayIntakeStats _today() => TodayIntakeStats(
  date: '2026-09-12',
  revision: 0,
  stale: false,
  completeness: 'complete',
  categories: const {},
);

Rolling7dIntakeStats _rolling() => Rolling7dIntakeStats(
  startDate: '2026-09-06',
  endDate: '2026-09-12',
  revision: 0,
  stale: false,
  days: const [],
  averages: const {},
  foodVarietyAverage: null,
  foodVarietyDenominator: null,
  fishCount: null,
  fishGrams: null,
  nutGrams: null,
  dairyMetDays: 0,
  dairyKnownDays: 0,
  dairyUnknownDays: 7,
  soyMetDays: 0,
  soyKnownDays: 0,
  soyUnknownDays: 7,
  fishCompleteness: 'unknown',
  fishCountCompleteness: 'unknown',
  nutCompleteness: 'unknown',
);

class _TestAppState extends AppState {
  _TestAppState({
    super.nextMealService,
    DateTime Function()? clock,
    this.recommendationLoader,
  })
    : super(
        databaseHelper: DatabaseHelper(
          factory: databaseFactoryFfiNoIsolate,
          databasePath: inMemoryDatabasePath,
        ),
        clock: clock ?? (() => DateTime(2026, 9, 12, 18)),
      );

  final Future<NextMealResult> Function()? recommendationLoader;

  @override
  Future<NextMealResult> loadNextMealRecommendation({
    DateTime? date,
    Set<String> excludeDishNames = const {},
    bool force = false,
  }) => recommendationLoader?.call() ??
      super.loadNextMealRecommendation(
        date: date,
        excludeDishNames: excludeDishNames,
        force: force,
      );

  late final _FakeStatistics stats = _FakeStatistics(this);

  @override
  IntakeStatisticsService get intakeStatistics => stats;
}

class _FakeStatistics extends IntakeStatisticsService {
  _FakeStatistics(super.state);
  bool failFirstToday = false;
  bool _failed = false;

  @override
  Future<TodayIntakeStats> today({DateTime? date}) async {
    if (failFirstToday && !_failed) {
      _failed = true;
      throw StateError('synthetic statistics failure');
    }
    return _today();
  }

  @override
  Future<Rolling7dIntakeStats> rolling7d({DateTime? date}) async => _rolling();
}

class _ControlledRecommendationService extends NextMealRecommendationService {
  final old = Completer<NextMealResult>();
  final fresh = Completer<NextMealResult>();
  int calls = 0;

  @override
  Future<NextMealResult> nextMeal(NextMealRequest request) {
    calls++;
    return calls == 1 ? old.future : fresh.future;
  }
}
