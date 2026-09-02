import 'package:canting/state/app_state.dart';
import 'package:canting/ui/history/calendar_view.dart';
import 'package:canting/ui/history/day_detail.dart';
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
  }

  void _showDay(DateTime date) {
    final state = context.read<AppState>();
    state.selectDate(date);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        maxWidth: 680,
      ),
      builder: (sheetContext) => DayDetail(
        date: date,
        completion: state.completionForDate(date),
        vitality: state.vitalityForDate(date),
        meals: state.mealsFor(date),
        onMealTap: (meal) {
          Navigator.pop(sheetContext);
          context.push('/record_detail?mealId=${meal.id}');
        },
        onAdd: () {
          Navigator.pop(sheetContext);
          context.push('/record_detail?date=${date.toIso8601String()}');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = state.selectedDate;
    final vitality = state.vitalityForDate(selected);
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
                    tooltip: '下个月',
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PixelPanel(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                child: CalendarView(
                  month: _visibleMonth,
                  selectedDate: selected,
                  vitalityForDate: state.vitalityForDate,
                  onSelected: _showDay,
                ),
              ),
              const SizedBox(height: 14),
              const _VitalityLegend(),
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
                color: vitalityColor(vitality).withValues(alpha: 0.12),
                borderColor: vitalityColor(vitality),
                padding: const EdgeInsets.all(14),
                onTap: () => _showDay(selected),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: vitalityColor(vitality),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vitality == null
                            ? '这天没有记录，伙伴在等你'
                            : '伙伴平均活力 $vitality · ${meals.length} 餐记录',
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
                            '/record_detail?mealId=${meals[index].id}',
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
                          subtitle: Text(meals[index].merchant),
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

class _VitalityLegend extends StatelessWidget {
  const _VitalityLegend();

  @override
  Widget build(BuildContext context) {
    const items = [
      (label: '元气', value: 88),
      (label: '不错', value: 65),
      (label: '有点蔫', value: 35),
      (label: '期待照顾', value: 20),
      (label: '无记录', value: null),
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
                  color: vitalityColor(item.value),
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
