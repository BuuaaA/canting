import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cached = state.nextMealResult;
    return FutureBuilder<NextMealResult>(
      future: state.loadNextMealRecommendation(),
      builder: (context, snapshot) {
        final result = snapshot.data ?? cached;
        final suggestion = result?.suggestions.firstOrNull;
        final reason =
            suggestion?.reason ??
            (result?.reasonCode == 'no_safe_candidate'
                ? '当前没有可靠的安全候选，进入详情可重试'
                : '正在根据已记录餐食准备建议');
        return PixelPanel(
          onTap: onTap,
          color: scheme.secondaryContainer.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.58
                : 0.72,
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
                    Text(
                      '下一餐',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      suggestion == null
                          ? '下一餐可选'
                          : '下一餐可选 · ${suggestion.dishName}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (result?.source == 'local_rule')
                      Text(
                        result?.reasonCode == 'unconfigured'
                            ? '当前使用本地推荐'
                            : '网络恢复后可重试',
                        style: theme.textTheme.bodySmall,
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
      },
    );
  }
}
