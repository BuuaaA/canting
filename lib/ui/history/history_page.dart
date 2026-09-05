import 'package:canting/core_engine.dart';
import 'package:canting/pet/vitality_calculator.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/history/calendar_view.dart';
import 'package:canting/ui/history/day_detail.dart';
import 'package:canting/ui/history/history_stats.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late DateTime _visibleMonth;
  Map<DateTime, int> _monthScores = const {};
  List<MealRecord> _monthMealsRaw = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    Future.microtask(_loadVisibleMonth);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  Future<void> _loadVisibleMonth() async {
    final state = context.read<AppState>();
    final start = DateTime(_visibleMonth.year, _visibleMonth.month);
    final end = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    try {
      final meals = await state.queryMealsInRange(start, end);
      if (!mounted) {
        return;
      }
      setState(() {
        _monthMealsRaw = meals;
        _monthScores = HistoryStats.dayScoresForMeals(meals, state.dailyIntake);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    // 不能切换到未来月份。
    if (next.isAfter(currentMonth)) {
      return;
    }
    setState(() {
      _visibleMonth = next;
      _loading = true;
    });
    Future.microtask(_loadVisibleMonth);
  }

  Future<void> _showDay(DateTime date) async {
    final state = context.read<AppState>();
    state.selectDate(date);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        maxWidth: 680,
      ),
      builder: (sheetContext) => DayDetail(
        date: date,
        meals: state.mealsFor(date),
        dailyIntake: state.dailyIntake,
        dayScore: _monthScores[DateTime(date.year, date.month, date.day)],
        petName: state.pet.petName,
        onMealTap: (meal) {
          Navigator.pop(sheetContext);
          context.push('/record_detail?mealId=${meal.mealId}');
        },
        onMealDelete: (meal) async {
          final confirmed = await showDialog<bool>(
            context: sheetContext,
            builder: (dialogContext) => AlertDialog(
              title: const Text('删除这条餐食记录？'),
              content: const Text('删除后活力值会按记录时的规则回退，成长值不会减少。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await state.deleteMeal(meal.mealId);
          }
        },
        onAdd: () {
          Navigator.pop(sheetContext);
          // 模块 09：只能补录最近 7 天内的记录。
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final dayStart = DateTime(date.year, date.month, date.day);
          final oldestAllowed = todayStart.subtract(const Duration(days: 6));
          if (dayStart.isBefore(oldestAllowed)) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('只能补录最近 7 天内的记录')));
            return;
          }
          context.push('/record_detail?date=${date.toIso8601String()}');
        },
      ),
    );
    // 删除 / 补录后刷新月度得分与周统计。
    if (mounted) {
      await _loadVisibleMonth();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = state.selectedDate;
    final selectedScore =
        _monthScores[DateTime(selected.year, selected.month, selected.day)];
    final selectedGrade = gradeForScore(selectedScore);
    final meals = state.mealsFor(selected);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const PixelAppBar(title: '历史记录'),
      body: PixelBackdrop(
        child: PixelContentWidth(
          expandHeight: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${_visibleMonth.year}年 ${_visibleMonth.month}月',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _isCurrentMonth ? '已是当前月份' : '下个月',
                    onPressed: _isCurrentMonth ? null : () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PixelPanel(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : CalendarView(
                        month: _visibleMonth,
                        selectedDate: selected,
                        scoreForDate: (date) =>
                            _monthScores[DateTime(
                              date.year,
                              date.month,
                              date.day,
                            )],
                        onSelected: (date) => _showDay(date),
                      ),
              ),
              const SizedBox(height: 14),
              const _QualityLegend(),
              const SizedBox(height: 26),
              PixelSectionHeader(title: '本周统计', icon: Icons.insights_outlined),
              const SizedBox(height: 9),
              PixelPanel(
                padding: const EdgeInsets.all(14),
                child: _WeekStatsPanel(
                  stats: HistoryStats.weekStats(
                    meals: _monthMealsRaw,
                    target: state.dailyIntake,
                    selected: selected,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: PixelSectionHeader(
                      title: '${selected.month}月${selected.day}日',
                      icon: Icons.event_note_outlined,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showDay(selected),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('详情'),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              PixelPanel(
                color: qualityColor(selectedGrade).withValues(alpha: 0.12),
                borderColor: qualityColor(selectedGrade),
                padding: const EdgeInsets.all(14),
                onTap: () => _showDay(selected),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: qualityColor(selectedGrade),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selectedScore == null
                            ? '这天没有记录，伙伴在等你'
                            : '饮食质量 $selectedScore · ${meals.length} 餐记录',
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (meals.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_note_outlined,
                        size: 46,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 10),
                      const Text('这天还没有餐次记录'),
                    ],
                  ),
                )
              else
                PixelPanel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < meals.length; index++) ...[
                        ListTile(
                          onTap: () => context.push(
                            '/record_detail?mealId=${meals[index].mealId}',
                          ),
                          leading: const PixelIconTile(
                            icon: Icons.restaurant_outlined,
                            size: 40,
                          ),
                          title: Text(
                            meals[index].dishes
                                .map((dish) => dish.name)
                                .join('、'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(meals[index].merchant ?? ''),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                        if (index != meals.length - 1)
                          const Divider(indent: 64),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekStatsPanel extends StatelessWidget {
  const _WeekStatsPanel({required this.stats});

  final WeekStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: '平均完成度',
                value: '${(stats.averageCompletion * 100).round()}%',
              ),
            ),
            Expanded(
              child: _Metric(label: '食物种类', value: '${stats.dishVariety} 种'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '坚果周进度 '
                    '${stats.soyServings.toStringAsFixed(1)}/'
                    '${stats.soyWeeklyTarget.toStringAsFixed(0)} 份',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: stats.soyProgress,
                      minHeight: 7,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('活力值趋势（一 → 日）', style: theme.textTheme.labelMedium),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var index = 0; index < stats.vitalityTrend.length; index++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == stats.vitalityTrend.length - 1 ? 0 : 6,
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: qualityColor(
                            gradeForScore(stats.vitalityTrend[index]),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${index + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QualityLegend extends StatelessWidget {
  const _QualityLegend();

  @override
  Widget build(BuildContext context) {
    const items = [
      (label: '吃得不错', grade: DietQualityGrade.good),
      (label: '一般', grade: DietQualityGrade.ok),
      (label: '不太好', grade: DietQualityGrade.bad),
      (label: '无记录', grade: DietQualityGrade.none),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: qualityColor(item.grade),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(item.label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}
