import 'package:canting/ui/history/record_summary_panel.dart';
import 'package:canting/core_engine.dart';
import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/recommendation/recommended_dish_card.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 下一餐推荐详情页：推荐时间 + 餐次 + 理由 + 主推/备选菜 + 外卖跳转。
/// 数据来自 RecommendationEngine（经 AppState.recommendationFor），
/// 「换一批」把已展示的菜排除后再取一批。
class RecommendationDetailPage extends StatefulWidget {
  const RecommendationDetailPage({super.key});

  @override
  State<RecommendationDetailPage> createState() =>
      _RecommendationDetailPageState();
}

class _RecommendationDetailPageState extends State<RecommendationDetailPage> {
  final DeliveryJumpService _jumpService = DeliveryJumpService();
  List<DeliveryPlatform> _platforms = DeliveryJumpService.platforms;
  bool _platformsLoaded = false;

  /// 「换一批」已展示过的菜名：从下一批结果里排除。
  final Set<String> _shownDishNames = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_platformsLoaded) {
      _platformsLoaded = true;
      // 平台启用集合与顺序来自用户配置（设置页可改，SharedPreferences 落盘）。
      _jumpService.loadEnabledPlatforms().then((platforms) {
        if (mounted) {
          setState(() => _platforms = platforms);
        }
      });
    }
  }

  void _refreshBatch(List<DishSuggestion> currentSuggestions) {
    setState(() {
      for (final suggestion in currentSuggestions) {
        _shownDishNames.add(suggestion.dishName);
      }
    });
  }

  Future<void> _jump(DeliveryPlatform platform, String keyword) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await _jumpService.jumpToSearch(platform, keyword);
    if (result.success && result.usedFallback) {
      messenger.showSnackBar(
        SnackBar(content: Text('没有找到${platform.label}，已打开网页版')),
      );
    } else if (!result.success) {
      messenger.showSnackBar(
        SnackBar(content: Text('没能打开${platform.label}，可以稍后再试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final now = DateTime.now();
    final recommendation = state.recommendationFor(
      now,
      excludeDishNames: _shownDishNames,
    );

    return Scaffold(
      appBar: const PixelAppBar(title: '下一餐推荐', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: recommendation == null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [
                    PixelPanel(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.restaurant_menu, size: 44),
                          SizedBox(height: 12),
                          Text('推荐引擎还没准备好，稍后再来看看'),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    const RecordSummaryPanel(),
                    _HeaderPanel(
                      recommendation: recommendation,
                      shortfallText: _shortfallText(state, now),
                    ),
                    const SizedBox(height: 22),
                    Text('推荐菜品', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 10),
                    ..._dishCards(recommendation),
                    if (recommendation.primary.isEmpty &&
                        recommendation.alternatives.isEmpty)
                      PixelPanel(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          children: [
                            const Text('可推荐候选不足，暂不提供具体商品'),
                            const SizedBox(height: 10),
                            if (_shownDishNames.isNotEmpty)
                              OutlinedButton(
                                onPressed: () =>
                                    setState(_shownDishNames.clear),
                                child: const Text('重新开始推荐'),
                              ),
                          ],
                        ),
                      )
                    else ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _refreshBatch([
                                ...recommendation.primary,
                                ...recommendation.alternatives,
                              ]),
                              icon: const Icon(Icons.refresh),
                              label: const Text('换一批推荐'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => _refreshBatch([
                                ...recommendation.primary,
                                ...recommendation.alternatives,
                              ]),
                              icon: const Icon(Icons.thumb_down_outlined),
                              label: const Text('不感兴趣'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  /// 顶部缺口说明：「今天蔬菜还差 1.5 份」。
  String? _shortfallText(AppState state, DateTime now) {
    return '仅基于已记录餐食估算，不代表全天摄入；候选先通过安全过滤。';
  }

  List<Widget> _dishCards(Recommendation recommendation) {
    final cards = <Widget>[];
    var index = 0;
    for (final suggestion in [
      ...recommendation.primary,
      ...recommendation.alternatives,
    ]) {
      cards
        ..add(
          RecommendedDishCard(
            suggestion: suggestion,
            platforms: _platforms,
            onJump: _jump,
            isPrimary: index == 0,
          ),
        )
        ..add(const SizedBox(height: 10));
      index++;
    }
    return cards;
  }
}

class _HeaderPanel extends StatelessWidget {
  const _HeaderPanel({required this.recommendation, this.shortfallText});

  final Recommendation recommendation;
  final String? shortfallText;

  static String _timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  static const _mealTypeLabels = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      color: scheme.primaryContainer,
      borderColor: scheme.primary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(
                      '${_timeLabel(recommendation.suggestedTime)} · '
                      '${_mealTypeLabels[recommendation.suggestedMealType] ?? "加餐"}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (shortfallText != null) ...[
            const SizedBox(height: 12),
            Text(
              shortfallText!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            recommendation.reason,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
