import 'package:canting/core_engine.dart';
import 'package:canting/pet/vitality_calculator.dart';
import 'package:canting/ui/history/calendar_view.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 单日详情（模块 9）：当日膳食结构 + 宠物状态 + 餐食列表（可查看/删除）。
class DayDetail extends StatelessWidget {
  const DayDetail({
    super.key,
    required this.date,
    required this.meals,
    required this.dailyIntake,
    required this.dayScore,
    required this.petName,
    required this.onMealTap,
    required this.onMealDelete,
    required this.onAdd,
  });

  final DateTime date;
  final List<MealRecord> meals;
  final DailyIntake dailyIntake;
  final int? dayScore;
  final String petName;
  final ValueChanged<MealRecord> onMealTap;
  final ValueChanged<MealRecord> onMealDelete;
  final VoidCallback onAdd;

  static const _categories = [
    (key: 'grains', label: '主食', icon: Icons.rice_bowl_outlined),
    (key: 'vegetables', label: '蔬菜', icon: Icons.eco_outlined),
    (key: 'fruits', label: '水果', icon: Icons.apple_outlined),
    (key: 'protein', label: '蛋白质', icon: Icons.egg_alt_outlined),
    (key: 'protein_soy', label: '大豆坚果', icon: Icons.spa_outlined),
    (key: 'oil', label: '油脂', icon: Icons.water_drop_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eaten = meals.fold(
      Portions.zero,
      (total, meal) => total + meal.portionsTotal,
    );
    final completion = CompletionCalculator().calculate(
      eatenPortions: eaten,
      dailyIntake: dailyIntake,
    );
    final complete = meals.every((m) => m.structureComplete);
    final grade = gradeForScore(dayScore);

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
                        '${(completion.overall * 100).round()}%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          complete ? _evaluation(completion.overall) : '估算不完整',
                        ),
                      ),
                    ],
                  ),
                  if (!complete) const Text('已记录，饮食结构估算不完整。以下仅为已知贡献小计。'),
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
                              value: completion.byCategory[category.key] ?? 0,
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  PixelPanel(
                    color: qualityColor(grade).withValues(alpha: 0.14),
                    borderColor: qualityColor(grade),
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: qualityColor(grade),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                !complete
                                    ? '饮食质量暂不评价'
                                    : dayScore == null
                                    ? '$petName在等你记录'
                                    : '$petName的饮食质量 $dayScore',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                !complete
                                    ? '含未知贡献商品'
                                    : dayScore == null
                                    ? '这天没有记录，补录一下吧'
                                    : _qualityLabel(grade),
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
                    title: '当日餐食',
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
                          '${meal.timestamp.hour.toString().padLeft(2, '0')}:'
                          '${meal.timestamp.minute.toString().padLeft(2, '0')}'
                          ' · ${meal.merchant ?? ''}'
                          ' · ${meal.structureComplete ? "完成 ${(meal.completionRate * 100).round()}%" : "估算不完整"}',
                        ),
                        trailing: IconButton(
                          tooltip: '删除这条记录',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => onMealDelete(meal),
                        ),
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
                label: const Text('补录这天的记录'),
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

  static String _qualityLabel(DietQualityGrade grade) => switch (grade) {
    DietQualityGrade.good => '吃得不错，继续保持～',
    DietQualityGrade.ok => '一般般，下一餐补补',
    DietQualityGrade.bad => '不太好，要均衡饮食哦',
    DietQualityGrade.none => '没有记录',
  };
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
