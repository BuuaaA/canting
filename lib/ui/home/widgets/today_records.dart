import 'package:canting/core_engine.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class TodayRecords extends StatelessWidget {
  const TodayRecords({
    super.key,
    required this.meals,
    required this.onMealTap,
    required this.onDelete,
    required this.onAdd,
  });

  final List<MealRecord> meals;
  final ValueChanged<MealRecord> onMealTap;
  final ValueChanged<String> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) {
      return PixelPanel(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(
              Icons.no_meals_outlined,
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('今天还没记录哦', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('手动添加'),
            ),
          ],
        ),
      );
    }

    final sorted = [...meals]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return PixelPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < sorted.length; index++) ...[
            _MealRow(
              meal: sorted[index],
              onTap: () => onMealTap(sorted[index]),
              onDelete: () => onDelete(sorted[index].mealId),
            ),
            if (index != sorted.length - 1)
              const Divider(height: 1, indent: 68),
          ],
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({
    required this.meal,
    required this.onTap,
    required this.onDelete,
  });

  final MealRecord meal;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(meal.mealId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这条记录？'),
          content: const Text('删除后会同步调整伙伴活力值。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      background: ColoredBox(
        color: scheme.errorContainer,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: PixelIconTile(
          icon: _mealIcon(meal.mealType),
          size: 42,
          color: scheme.primaryContainer,
        ),
        title: Text(
          meal.dishes.map((dish) => dish.name).join('、'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_mealTypeLabel(meal.mealType)} · ${_timeLabel(meal.timestamp)}${meal.structureComplete ? "" : " · 估算不完整"}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  static IconData _mealIcon(String value) => switch (value) {
    'breakfast' => Icons.free_breakfast_outlined,
    'lunch' => Icons.lunch_dining_outlined,
    'dinner' => Icons.dinner_dining_outlined,
    _ => Icons.cookie_outlined,
  };

  static String _mealTypeLabel(String value) => switch (value) {
    'breakfast' => '早餐',
    'lunch' => '午餐',
    'dinner' => '晚餐',
    _ => '加餐',
  };

  static String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}
