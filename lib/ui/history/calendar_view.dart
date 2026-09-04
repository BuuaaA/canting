import 'package:canting/pet/vitality_calculator.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// 按饮食质量评级取色（模块 9）：
/// 好=绿、一般=黄、差=红、无记录=灰。
Color qualityColor(DietQualityGrade grade) => switch (grade) {
  DietQualityGrade.good => const Color(0xFF3A8D67),
  DietQualityGrade.ok => const Color(0xFFE4B13D),
  DietQualityGrade.bad => const Color(0xFFD6534D),
  DietQualityGrade.none => const Color(0xFFB8BDBA),
};

/// 按分数取质量评级；null 表示无记录。
DietQualityGrade gradeForScore(int? score) =>
    VitalityCalculator.gradeOf(score);

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.scoreForDate,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedDate;

  /// 返回某天的饮食质量得分；null 表示当天无记录。
  final int? Function(DateTime date) scoreForDate;
  final ValueChanged<DateTime> onSelected;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leading = firstDay.weekday - 1;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      children: [
        Row(
          children: [
            for (final weekday in _weekdays)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      weekday,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = constraints.maxWidth / 7;
            final cellHeight = cellWidth.clamp(44.0, 54.0);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: cellWidth / cellHeight,
              ),
              itemBuilder: (context, index) {
                final day = index - leading + 1;
                if (day < 1 || day > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(month.year, month.month, day);
                return _CalendarDay(
                  date: date,
                  selected: DateUtils.isSameDay(date, selectedDate),
                  grade: gradeForScore(scoreForDate(date)),
                  onTap: () => onSelected(date),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.grade,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final DietQualityGrade grade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final quality = qualityColor(grade);
    final hasRecord = grade != DietQualityGrade.none;
    return InkResponse(
      onTap: onTap,
      radius: 25,
      child: Semantics(
        label:
            '${date.month}月${date.day}日，'
            '${switch (grade) {
              DietQualityGrade.good => '吃得不错',
              DietQualityGrade.ok => '一般',
              DietQualityGrade.bad => '不太好',
              DietQualityGrade.none => '无记录',
            }}',
        selected: selected,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // 每日底色表示饮食质量；选中态保持主色。
                color: selected
                    ? scheme.primary
                    : hasRecord
                    ? quality.withValues(alpha: 0.22)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: isToday && !selected
                      ? scheme.primary
                      : selected
                      ? scheme.primary
                      : hasRecord
                      ? quality
                      : scheme.outline.withValues(alpha: 0.4),
                  width: isToday || selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: scheme.outline.withValues(alpha: 0.45),
                          offset: const Offset(2, 2),
                          blurRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                '${date.day}',
                style: AppTheme.pixelText(
                  context,
                  fontSize: 8,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: isToday || selected
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: quality,
                shape: BoxShape.circle,
                border: hasRecord
                    ? null
                    : Border.all(
                        color: scheme.outline.withValues(alpha: 0.7),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
