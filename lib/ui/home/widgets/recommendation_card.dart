import 'package:canting/core_engine.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 下一餐推荐卡片：真实 RecommendationEngine 结果（时间 + 主推缺口 + 理由）。
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    required this.onTap,
  });

  final Recommendation? recommendation;
  final VoidCallback onTap;

  static const _categoryLabels = {
    'grains': '主食',
    'vegetables': '蔬菜',
    'fruits': '水果',
    'protein': '蛋白质',
    'protein_soy': '豆制品',
  };

  static const _mealTypeLabels = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
  };

  static String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recommendation = this.recommendation;
    final primary = recommendation?.primary.firstOrNull;
    final timeText = recommendation == null
        ? '准备中'
        : '${_timeLabel(recommendation.suggestedTime)} · '
            '${_mealTypeLabels[recommendation.suggestedMealType] ?? "加餐"}';
    final title = primary == null
        ? '看看下一餐吃什么'
        : '补一补${_categoryLabels[primary.primaryCategory] ?? "搭配"}';

    return PixelPanel(
      onTap: onTap,
      color: scheme.secondaryContainer.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.58 : 0.72,
      ),
      padding: const EdgeInsets.all(15),
      semanticLabel: '查看下一餐推荐',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PixelIconTile(
            icon: Icons.restaurant_menu,
            size: 46,
            color: scheme.tertiaryContainer,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '下一餐 $timeText',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  recommendation == null
                      ? '记录引擎装配好了就给你出主意'
                      : title,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  recommendation == null
                      ? '先去记一笔今天吃的吧'
                      : (recommendation.reason.isEmpty
                          ? '按今天的缺口挑的搭配'
                          : recommendation.reason),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest.withValues(alpha: 0.72),
              border: Border.all(color: scheme.outline),
            ),
            child: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}
