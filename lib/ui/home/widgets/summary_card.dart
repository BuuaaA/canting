import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.mealCount,
    this.structureComplete = true,
    required this.completionByCategory,
  });

  final bool structureComplete;
  final int mealCount;
  final Map<String, double> completionByCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      color: scheme.tertiaryContainer,
      borderColor: scheme.tertiary,
      padding: const EdgeInsets.all(13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelIconTile(
            icon: Icons.wb_sunny_outlined,
            size: 38,
            color: scheme.secondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日小结',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _summary(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _summary() {
    if (!structureComplete) return '已记录，饮食结构估算不完整';
    if (mealCount == 0) {
      return '今天还没记录，截个外卖订单图分享给餐盘吧';
    }
    if (completionByCategory.values.every((value) => value >= 0.9)) {
      return '今天六类食物都照顾到了，很棒';
    }
    if (completionByCategory.values.every((value) => value >= 0.7)) {
      return '今天吃得挺均衡，继续保持';
    }
    if ((completionByCategory['vegetables'] ?? 0) < 0.4) {
      return '今天蔬菜还差不少，下顿多吃点青菜';
    }
    return '整体搭配不错，水果还可以补一点。';
  }
}
