import 'package:canting/state/app_state.dart';
import 'package:canting/ui/history/calendar_view.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class DayDetail extends StatelessWidget {
  const DayDetail({
    super.key,
    required this.date,
    required this.completion,
    required this.vitality,
    required this.meals,
    required this.onMealTap,
    required this.onAdd,
  });

  final DateTime date;
  final double completion;
  final int? vitality;
  final List<MockMeal> meals;
  final ValueChanged<MockMeal> onMealTap;
  final VoidCallback onAdd;

  static const _categories = [
    (label: '主食', icon: Icons.rice_bowl_outlined, factor: 0.95),
    (label: '蔬菜', icon: Icons.eco_outlined, factor: 0.72),
    (label: '水果', icon: Icons.apple_outlined, factor: 0.58),
    (label: '蛋白质', icon: Icons.egg_alt_outlined, factor: 1.05),
    (label: '大豆坚果', icon: Icons.spa_outlined, factor: 0.82),
    (label: '油脂', icon: Icons.water_drop_outlined, factor: 1.12),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${date.month}月${date.day}日',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(completion * 100).round()}%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(_evaluation(completion)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 8.0;
                      final itemWidth =
                          (constraints.maxWidth - spacing * 2) / 3;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (final category in _categories)
                            _CategoryChip(
                              width: itemWidth,
                              label: category.label,
                              icon: category.icon,
                              value: (completion * category.factor).clamp(
                                0.0,
                                1.3,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  PixelPanel(
                    color: vitalityColor(vitality).withValues(alpha: 0.14),
                    borderColor: vitalityColor(vitality),
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: vitalityColor(vitality),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vitality == null
                                    ? '这天没有活力记录'
                                    : '平均活力 $vitality',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                vitality == null
                                    ? '小挑食想你啦'
                                    : _petDialogue(vitality!),
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const PixelSectionHeader(
                    title: '当日记录',
                    icon: Icons.receipt_long_outlined,
                  ),
                  const SizedBox(height: 8),
                  if (meals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        '这天还没有餐次记录',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    for (final meal in meals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => onMealTap(meal),
                        leading: const Icon(Icons.restaurant_outlined),
                        title: Text(
                          meal.dishes.map((dish) => dish.name).join('、'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${meal.time.hour.toString().padLeft(2, '0')}:'
                          '${meal.time.minute.toString().padLeft(2, '0')}'
                          ' · ${meal.merchant}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('添加这天的记录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _evaluation(double value) {
    if (value >= 0.9) return '今天搭配得很棒';
    if (value >= 0.7) return '整体挺均衡';
    if (value >= 0.5) return '还有一点可以补';
    return '慢慢来，下一餐再补补';
  }

  static String _petDialogue(int value) {
    if (value >= 80) return '今天元气满满！';
    if (value >= 50) return '今天状态不错～';
    if (value >= 25) return '再陪陪我吧';
    return '期待你的照顾';
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.width,
    required this.label,
    required this.icon,
    required this.value,
  });

  final double width;
  final String label;
  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: scheme.outline, width: 2),
        boxShadow: [
          BoxShadow(
            color: scheme.outline.withValues(alpha: 0.35),
            offset: const Offset(2, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 21, color: scheme.primary),
          const SizedBox(height: 5),
          Text(label, maxLines: 1),
          Text(
            '${(value * 100).round()}%',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
