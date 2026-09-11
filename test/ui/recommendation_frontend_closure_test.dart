import 'dart:async';

import 'package:canting/core_engine.dart';
import 'package:canting/services/intake_statistics.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/recommendation/recommendation_detail_page.dart';
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
  _TestAppState({super.nextMealService})
    : super(
        databaseHelper: DatabaseHelper(
          factory: databaseFactoryFfiNoIsolate,
          databasePath: inMemoryDatabasePath,
        ),
        clock: () => DateTime(2026, 9, 12, 18),
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
