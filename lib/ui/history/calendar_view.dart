import 'package:canting/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';

class CalendarView extends StatelessWidget {
  const CalendarView({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.vitalityForDate,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final int? Function(DateTime date) vitalityForDate;
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
                  vitality: vitalityForDate(date),
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
    required this.vitality,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final int? vitality;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return InkResponse(
      onTap: onTap,
      radius: 25,
      child: Semantics(
        label:
            '${date.month}月${date.day}日，'
            '${vitality == null ? '无记录' : '宠物活力$vitality'}',
        selected: selected,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
                border: isToday && !selected
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
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
                color: vitalityColor(vitality),
                border: Border.all(
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

Color vitalityColor(int? vitality) {
  if (vitality == null) return const Color(0xFFB8BDBA);
  if (vitality >= 80) return const Color(0xFF3A8D67);
  if (vitality >= 50) return const Color(0xFFE4B13D);
  if (vitality >= 25) return const Color(0xFFE77E45);
  return const Color(0xFFD6534D);
}
