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
    return FutureBuilder<NextMealResult>(
      future: state.loadNextMealRecommendation(),
      builder: (context, snapshot) {
        final contextKey = state.recommendationContextKey();
        final cached = state.nextMealResult;
        final result = (snapshot.data?.dataRevision == state.dataRevision &&
                (snapshot.data?.contextKey == null ||
                    snapshot.data?.contextKey == contextKey)
                ? snapshot.data
                : null) ??
            (cached?.dataRevision == state.dataRevision &&
                    (cached?.contextKey == null ||
                        cached?.contextKey == contextKey)
                ? cached
                : null);
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
                        _hint(result!.reasonCode),
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

  String _hint(String reasonCode) => switch (reasonCode) {
    'unconfigured' => '当前使用本地推荐；网络恢复后可生成更具体推荐',
    'timeout' || 'remote_unavailable' || 'invalid_json' => '远端推荐暂不可用，可稍后重试',
    'no_safe_candidate' => '当前没有可靠的安全候选，可稍后重试',
    'stale_input' => '统计已更新，请重新生成建议',
    _ => '推荐暂不可用，可稍后重试',
  };
}
