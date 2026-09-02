import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RecommendationDetailPage extends StatelessWidget {
  const RecommendationDetailPage({super.key});

  static const _dishes = [
    (name: '蒜蓉西兰花', reason: '蔬菜充足，适合补上今天的缺口', icon: Icons.eco_outlined),
    (name: '香菇青菜', reason: '口味清爽，搭配主食刚刚好', icon: Icons.ramen_dining_outlined),
    (name: '鸡胸肉时蔬碗', reason: '同时补充蔬菜和优质蛋白质', icon: Icons.lunch_dining_outlined),
  ];

  Future<void> _openDeliveryApp(
    BuildContext context, {
    required String app,
    required String keyword,
  }) async {
    final uri = app == 'meituan'
        ? Uri(
            scheme: 'meituan',
            host: 'waimai.meituan.com',
            path: '/search',
            queryParameters: {'keyword': keyword},
          )
        : Uri(
            scheme: 'eleme',
            host: 'search',
            queryParameters: {'keyword': keyword},
          );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没有找到${app == 'meituan' ? '美团' : '饿了么'}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: const PixelAppBar(title: '下一餐推荐', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              PixelPanel(
                color: scheme.primaryContainer,
                borderColor: scheme.primary,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    PixelIconTile(
                      icon: Icons.schedule,
                      size: 44,
                      color: scheme.secondaryContainer,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('建议时间', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 3),
                          Text('18:30 · 晚餐', style: theme.textTheme.titleLarge),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '小挑食想吃菜菜了',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '今天蔬菜还差一点，下面这些搭配都可以。',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              for (final dish in _dishes) ...[
                PixelPanel(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      PixelIconTile(
                        icon: dish.icon,
                        size: 46,
                        color: scheme.tertiaryContainer,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dish.name, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 3),
                            Text(
                              dish.reason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 16),
              Text('去外卖平台搜索', style: theme.textTheme.titleLarge),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openDeliveryApp(
                        context,
                        app: 'meituan',
                        keyword: _dishes.first.name,
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('美团'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openDeliveryApp(
                        context,
                        app: 'eleme',
                        keyword: _dishes.first.name,
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('饿了么'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
