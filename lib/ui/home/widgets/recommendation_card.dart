import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      onTap: onTap,
      color: scheme.secondaryContainer.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.58 : 0.72,
      ),
      padding: const EdgeInsets.all(15),
      semanticLabel: '查看今日晚餐推荐',
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
                      '下一餐 18:30',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('帮小挑食补补蔬菜', style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  '推荐一份清爽绿叶菜',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
