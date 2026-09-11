import 'package:canting/services/intake_statistics.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/intake/intake_view_events.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class Rolling7dPage extends StatefulWidget {
  const Rolling7dPage({super.key});
  @override
  State<Rolling7dPage> createState() => _Rolling7dPageState();
}

class _Rolling7dPageState extends State<Rolling7dPage> {
  late Future<Rolling7dIntakeStats> _future;
  late int _revision;
  late AppState _state;
  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _revision = _state.dataRevision;
    _state.addListener(_onStateChange);
    _load();
    IntakeViewEvents.emit(
      'rolling_7d_view',
      fallback: _state.recordIntakeViewEvent,
    );
  }

  void _load() {
    _future = context.read<AppState>().intakeStatistics.rolling7d();
  }

  void _retry() => setState(_load);
  void _onStateChange() {
    if (!mounted || _state.dataRevision == _revision) return;
    _revision = _state.dataRevision;
    setState(_load);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PixelAppBar(title: '7 日进度'),
    body: PixelBackdrop(
      child: PixelContentWidth(
        expandHeight: true,
        child: FutureBuilder<Rolling7dIntakeStats>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Retry(message: '加载失败，重试', onPressed: _retry);
            }
            final stats = snapshot.data!;
            if (stats.stale) {
              return _Retry(message: '记录已更新，刷新统计', onPressed: _retry);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  '${stats.startDate} ～ ${stats.endDate}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text('最近 7 个当地日；各项均标明可计算的记录日数。'),
                const SizedBox(height: 14),
                _WeeklyMetrics(stats: stats),
                const SizedBox(height: 22),
                const PixelSectionHeader(
                  title: '每日明细',
                  icon: Icons.view_day_outlined,
                ),
                const SizedBox(height: 10),
                for (final day in stats.days) _DayTile(day: day),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onPressed});
  final String message;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.refresh),
      label: Text(message),
    ),
  );
}

class _WeeklyMetrics extends StatelessWidget {
  const _WeeklyMetrics({required this.stats});
  final Rolling7dIntakeStats stats;
  String n(double? value, String unit) => value == null
      ? '未知'
      : '${value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}$unit';
  String avg(IntakeAverageStat? value) => value?.average == null
      ? '未知'
      : '${n(value!.average, 'g')}（有记录日平均，${value.denominator ?? 0}/7天）';
  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (
        '鱼次数',
        stats.fishCount == null
            ? '未知 · 参考每周至少2次'
            : '${stats.fishCount}次（${stats.fishCountCompleteness == 'complete' ? '完整' : '部分记录'}） · 参考每周至少2次',
      ),
      ('鱼重量', '${n(stats.fishGrams, 'g')} · 参考300～500g/周'),
      (
        '坚果已知小计',
        '${n(stats.nutGrams, 'g')} · ${stats.nutCompleteness == 'complete' ? '完整' : '部分记录'} · 参考50～70g/周',
      ),
      (
        '奶类达标日',
        '${stats.dairyMetDays}/7（已知${stats.dairyKnownDays}天，未知${stats.dairyUnknownDays}天）',
      ),
      (
        '大豆达标日',
        '${stats.soyMetDays}/7（已知${stats.soyKnownDays}天，未知${stats.soyUnknownDays}天）',
      ),
      (
        '食物种类日均',
        stats.foodVarietyAverage == null
            ? '未知（${stats.foodVarietyDenominator ?? 0}/7天）'
            : '${n(stats.foodVarietyAverage, '种')}（有记录日平均，${stats.foodVarietyDenominator ?? 0}/7天）',
      ),
      ('谷物日均', avg(stats.averages['grain'])),
      ('蔬菜日均', avg(stats.averages['vegetable'])),
      ('水果日均', avg(stats.averages['fruit'])),
      ('鱼禽肉蛋日均', avg(stats.averages['animal_food'])),
    ];
    return PixelPanel(
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 86, child: Text(item.$1)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.$2, textAlign: TextAlign.end)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});
  final IntakeDayStat day;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: PixelPanel(
      onTap: () => context.push('/rolling_7d/day?date=${day.date}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(day.date)),
          Text(
            day.completeness == 'missing'
                ? '未记录'
                : day.completeness == 'partial'
                ? '部分记录'
                : '完整记录',
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class Rolling7dDayDetailPage extends StatefulWidget {
  const Rolling7dDayDetailPage({super.key, required this.date});
  final DateTime date;
  @override
  State<Rolling7dDayDetailPage> createState() => _Rolling7dDayDetailPageState();
}

class _Rolling7dDayDetailPageState extends State<Rolling7dDayDetailPage> {
  late Future<({IntakeDayStat day, bool stale})> _future;
  late int _revision;
  late AppState _state;
  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _revision = _state.dataRevision;
    _state.addListener(_onStateChange);
    _load();
    IntakeViewEvents.emit(
      'rolling_7d_day_detail_view',
      fallback: _state.recordIntakeViewEvent,
    );
  }

  void _load() {
    _future = _query();
  }

  Future<({IntakeDayStat day, bool stale})> _query() async {
    final stats = await context.read<AppState>().intakeStatistics.rolling7d(
      date: widget.date,
    );
    return (
      day: stats.days.firstWhere((day) => day.date == _key(widget.date)),
      stale: stats.stale,
    );
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  void _onStateChange() {
    if (!mounted || _state.dataRevision == _revision) return;
    _revision = _state.dataRevision;
    setState(_load);
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PixelAppBar(
      title: '${widget.date.month}月${widget.date.day}日明细',
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: PixelBackdrop(
      child: PixelContentWidth(
        expandHeight: true,
        child: FutureBuilder<({IntakeDayStat day, bool stale})>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _Retry(
                message: '加载失败，重试',
                onPressed: () => setState(_load),
              );
            }
            final result = snapshot.data!;
            if (result.stale) {
              return _Retry(
                message: '记录已更新，刷新统计',
                onPressed: () => setState(_load),
              );
            }
            final day = result.day;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  day.completeness == 'missing'
                      ? '当天没有记录'
                      : '记录状态：${_completeness(day.completeness)}',
                ),
                const SizedBox(height: 12),
                PixelPanel(
                  child: Column(
                    children: [
                      for (final stat in day.categories.values)
                        _DetailRow(stat: stat),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PixelPanel(
                  child: Text(
                    '食物种类：${day.foodVariety?.toString() ?? '未知'}\n鱼次数：${day.fishCount?.toString() ?? '未知'}（${day.fishCountCompleteness == 'complete'
                        ? '完整'
                        : day.fishCountCompleteness == 'partial'
                        ? '部分记录'
                        : '未知'}）',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  String _completeness(String value) => value == 'complete'
      ? '完整记录'
      : value == 'partial'
      ? '部分记录'
      : '未记录';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.stat});
  final IntakeCategoryStat stat;
  static const labels = {
    'grain': '谷物',
    'tuber': '薯类',
    'vegetable': '蔬菜',
    'fruit': '水果',
    'animal_food': '鱼禽肉蛋',
    'dairy': '奶类',
    'soy': '大豆',
    'nut': '坚果',
    'cooking_oil': '烹调油',
    'salt': '食盐',
  };
  String status(String? value, String completeness) => switch (value) {
    'below' => '需补充',
    'near' => '接近下限',
    'met' => '已达标',
    'high' => '偏多',
    _ => completeness == 'missing' ? '未记录' : '暂不能判断',
  };
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(labels[stat.category] ?? stat.category),
    subtitle: Text(
      stat.amount == null
          ? (stat.completeness == 'missing' ? '未记录' : '暂不能比较')
          : '${stat.amount}${stat.unit}',
    ),
    trailing: Text(status(stat.status, stat.completeness)),
  );
}
