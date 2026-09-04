import 'package:canting/core_engine.dart';
import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/ui/recommendation/platform_buttons.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 推荐菜品卡片：菜名 + 分类/油量标签 + 外卖平台按钮组。
class RecommendedDishCard extends StatelessWidget {
  const RecommendedDishCard({
    super.key,
    required this.suggestion,
    required this.platforms,
    required this.onJump,
    this.isPrimary = false,
  });

  final DishSuggestion suggestion;
  final List<DeliveryPlatform> platforms;
  final void Function(DeliveryPlatform platform, String keyword) onJump;

  /// 主推菜显示「主推」角标。
  final bool isPrimary;

  static const _categoryLabels = {
    'grains': '主食',
    'vegetables': '蔬菜',
    'fruits': '水果',
    'protein': '动物蛋白',
    'protein_soy': '大豆坚果',
  };

  static const _oilLabels = {
    'low': '清爽低油',
    'mid_high': '油量适中',
    'high': '油偏大',
    'extreme': '重油',
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
                      '${_categoryLabels[suggestion.primaryCategory] ?? "均衡搭配"}'
                      ' · ${_oilLabels[suggestion.oilLevel] ?? "家常"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlatformButtons(
            platforms: platforms,
            keyword: suggestion.searchKeyword,
            onJump: onJump,
          ),
        ],
      ),
    );
  }
}
