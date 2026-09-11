import 'package:canting/services/intake_statistics.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/intake/rolling_7d_page.dart';
import 'package:canting/ui/intake/today_plate_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeStatistics extends IntakeStatisticsService {
  _FakeStatistics(super.state);
  int todayCalls = 0;
  int rollingCalls = 0;
  static const _target = IntakeTarget(min: 200, max: 300);
  IntakeCategoryStat _category(String key) => IntakeCategoryStat(
    category: key,
    amount: null,
    knownSubtotal: 0,
    completeness: 'missing',
    target: _target,
    status: null,
    gap: null,
  );
  IntakeDayStat _day(String date) => IntakeDayStat(
    date: date,
    completeness: 'missing',
    categories: {
      for (final key in const [
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
      ])
        key: _category(key),
    },
    foodVariety: null,
    fishCount: null,
    fishCountCompleteness: 'unknown',
  );
  @override
  Future<TodayIntakeStats> today({DateTime? date}) async {
    todayCalls++;
    return TodayIntakeStats(
      date: '2026-09-12',
      revision: 0,
      categories: {
        for (final key in const [
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
        ])
          key: _category(key),
      },
      completeness: 'missing',
    );
  }

  @override
  Future<Rolling7dIntakeStats> rolling7d({DateTime? date}) async {
    rollingCalls++;
    return Rolling7dIntakeStats(
      startDate: '2026-09-06',
      endDate: '2026-09-12',
      revision: 0,
      days: [
        for (var i = 0; i < 7; i++)
          _day('2026-09-${(i + 6).toString().padLeft(2, '0')}'),
      ],
      averages: const {},
      foodVarietyAverage: null,
      foodVarietyDenominator: 0,
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
  }
}

class _FakeState extends AppState {
  _FakeState() : super() {
    _stats = _FakeStatistics(this);
  }
  late final _FakeStatistics _stats;
  @override
  IntakeStatisticsService get intakeStatistics => _stats;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  testWidgets('today plate keeps ten categories readable at 320px', (
    tester,
  ) async {
    final state = _FakeState();
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: TodayPlateView())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('查看本周进度'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(state.intakeViewEvents, contains('today_plate_view'));
    final calls = state._stats.todayCalls;
    state.dataRevision = 1;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(state._stats.todayCalls, greaterThan(calls));
    expect(
      state.intakeViewEvents.where((event) => event == 'today_plate_view'),
      hasLength(1),
    );
    await tester.binding.setSurfaceSize(null);
    state.dispose();
  });

  testWidgets('rolling page shows window and daily detail entries', (
    tester,
  ) async {
    final state = _FakeState();
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Rolling7dPage(),
              ),
              GoRoute(
                path: '/rolling_7d/day',
                builder: (_, route) => Rolling7dDayDetailPage(
                  date: DateTime.parse(route.uri.queryParameters['date']!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-09-06 ～ 2026-09-12'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('每日明细'), findsOneWidget);
    expect(find.text('2026-09-06'), findsOneWidget);
    expect(state.intakeViewEvents, contains('rolling_7d_view'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('2026-09-06'));
    await tester.pumpAndSettle();
    expect(state.intakeViewEvents, contains('rolling_7d_day_detail_view'));
    await tester.binding.setSurfaceSize(null);
    state.dispose();
  });
}
