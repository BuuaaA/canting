import 'dart:async';

import 'package:canting/services/delivery_jump_service.dart';
import 'package:canting/services/next_meal_recommendation.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/recommendation/recommended_dish_card.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RecommendationDetailPage extends StatefulWidget {
  const RecommendationDetailPage({super.key, this.jumpService});

  final DeliveryJumpService? jumpService;

  @override
  State<RecommendationDetailPage> createState() =>
      _RecommendationDetailPageState();
}

class _RecommendationDetailPageState extends State<RecommendationDetailPage> {
  late final DeliveryJumpService _jumpService =
      widget.jumpService ?? DeliveryJumpService();
  final Set<String> _shownDishNames = <String>{};
  List<DeliveryPlatform> _platforms = DeliveryJumpService.platforms;
  Future<NextMealResult>? _future;
  NextMealResult? _lastUsable;
  int _loadSerial = 0;
  bool _platformsLoaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _loadSerial++;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_platformsLoaded) {
      _platformsLoaded = true;
      _startLoad();
      _jumpService.loadEnabledPlatforms().then((value) {
        if (mounted) setState(() => _platforms = value);
      });
    }
  }

  Future<NextMealResult> _startLoad({bool force = false}) {
    final state = context.read<AppState>();
    final serial = ++_loadSerial;
    final future = state.loadNextMealRecommendation(
      excludeDishNames: _shownDishNames,
      force: force,
    );
    _future = future;
    future.then(
      (result) {
        if (!mounted) return;
        if (serial == _loadSerial &&
            result.isUsable &&
            result.dataRevision == state.dataRevision) {
          _lastUsable = result;
        }
        setState(() {});
      },
      onError: (Object _, StackTrace _) {
        if (mounted && serial == _loadSerial) setState(() {});
      },
    );
    return future;
  }

  NextMealResult? _result(
    AsyncSnapshot<NextMealResult> snapshot,
    AppState state,
  ) {
    final usable = _lastUsable ?? state.nextMealResult;
    if (usable != null && usable.dataRevision == state.dataRevision) {
      return usable;
    }
    final candidate = snapshot.data;
    return candidate?.dataRevision == state.dataRevision ? candidate : null;
  }

  Future<void> _changeBatch(NextMealFeedbackAction action) async {
    if (_busy) return;
    final state = context.read<AppState>();
    final current = _lastUsable ?? state.nextMealResult;
    if (current == null || !current.isUsable) {
      _startLoad(force: true);
      return;
    }
    _busy = true;
    try {
      await state.nextMealService.recordFeedback(
        result: current,
        action: action,
      );
      _shownDishNames
        ..clear()
        ..addAll(current.suggestions.map((s) => s.dishName));
      if (mounted) setState(() {});
      await _startLoad(force: true);
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _jump(DeliveryPlatform platform, String keyword) async {
    final messenger = ScaffoldMessenger.of(context);
    final recommendation =
        _lastUsable ?? context.read<AppState>().nextMealResult;
    final result = await _jumpService.jumpToSearch(platform, keyword);
    if (!mounted) return;
    if (result.success) {
      if (recommendation != null) {
        // The service de-duplicates accept by requestId; opening remains non-blocking.
        unawaited(
          context.read<AppState>().nextMealService.recordFeedback(
            result: recommendation,
            action: NextMealFeedbackAction.accept,
            acceptanceBasis: 'platform_open_accepted',
          ),
        );
      }
      if (result.usedFallback) {
        messenger.showSnackBar(const SnackBar(content: Text('已打开外卖网页版')));
      }
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('没能打开${platform.label}，可以稍后再试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: const PixelAppBar(title: '下一餐推荐', leading: BackButton()),
      body: PixelBackdrop(
        child: PixelContentWidth(
          child: FutureBuilder<NextMealResult>(
            future: _future,
            builder: (context, snapshot) {
              final result = _result(snapshot, state);
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              if (result == null) {
                return _MessagePanel(
                  title: loading ? '正在生成下一餐建议' : '暂时没有可展示的推荐',
                  message: loading ? '依据本地今日和最近 7 日记录计算中' : '可重试；未知数据不会被当作零摄入。',
                  onRetry: loading ? null : () => _startLoad(force: true),
                );
              }
              final all = result.suggestions;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _GuidancePanel(result: result),
                  if (loading) const LinearProgressIndicator(),
                  const SizedBox(height: 18),
                  if (all.isEmpty)
                    _MessagePanel(
                      title: '当前没有可靠的安全候选',
                      message: '可稍后重试。',
                      onRetry: () => _startLoad(force: true),
                    )
                  else ...[
                    Text('推荐菜品', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    ...all.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RecommendedDishCard(
                          suggestion: entry.value,
                          platforms: _platforms,
                          onJump: _jump,
                          isPrimary: entry.key == 0,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _changeBatch(
                                    NextMealFeedbackAction.refresh,
                                  ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('换一批'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _changeBatch(
                                    NextMealFeedbackAction.ignore,
                                  ),
                            icon: const Icon(Icons.thumb_down_outlined),
                            label: const Text('不感兴趣'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({required this.result});
  final NextMealResult result;

  @override
  Widget build(BuildContext context) => PixelPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.source == 'local_rule' ? '当前使用本地推荐' : '下一餐建议',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(result.guidance.primary),
        Text(result.guidance.oilSalt),
        Text(result.guidance.reduceStaple),
        if (result.reasonCode == 'unconfigured')
          const Text('当前使用本地推荐；网络恢复后可生成更具体推荐'),
        if (result.reasonCode == 'timeout' ||
            result.reasonCode == 'remote_unavailable' ||
            result.reasonCode == 'invalid_json')
          const Text('远端推荐暂不可用，可稍后重试'),
        if (result.reasonCode == 'no_safe_candidate')
          const Text('当前没有可靠的安全候选，可稍后重试'),
      ],
    ),
  );
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.title,
    required this.message,
    this.onRetry,
  });
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('推荐菜品'),
        const SizedBox(height: 10),
        PixelPanel(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(message),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
