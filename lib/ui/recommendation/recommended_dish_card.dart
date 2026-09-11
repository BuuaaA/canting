import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class RecommendedDishCard extends StatelessWidget {
  const RecommendedDishCard({
    super.key,
    required this.suggestion,
    required this.platforms,
    required this.onJump,
    this.isPrimary = false,
  });

  final NextMealSuggestion suggestion;
  final List<DeliveryPlatform> platforms;
  final void Function(DeliveryPlatform platform, String keyword) onJump;
  final bool isPrimary;

  static const _labels = {
    'grain': '主食',
    'tuber': '薯类',
    'vegetable': '蔬菜',
    'fruit': '水果',
    'animal_food': '动物性食物',
    'dairy': '奶类',
    'soy': '豆类',
    'nut': '坚果',
    'cooking_oil': '油',
    'salt': '盐',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PixelIconTile(
                icon: Icons.restaurant_outlined,
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
                        Flexible(
                          child: Text(
                            suggestion.dishName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (isPrimary) ...[
                          const SizedBox(width: 6),
                          PixelBadge(
                            label: '主推',
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_labels[suggestion.primaryCategory] ?? "搭配"} · ${suggestion.estimatedServing}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(suggestion.reason, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
            onPressed: () => onJump(
              (platforms.isEmpty ? DeliveryJumpService.platforms : platforms)
                  .first,
              suggestion.searchKeyword,
            ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('去外卖平台看看'),
            ),
          ),
        ],
      ),
    );
  }
}
