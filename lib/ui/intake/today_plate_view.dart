import 'package:canting/services/intake_statistics.dart';
import 'package:canting/state/app_state.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class TodayPlateView extends StatefulWidget {
  const TodayPlateView({super.key});
  @override
  State<TodayPlateView> createState() => _TodayPlateViewState();
}

class _TodayPlateViewState extends State<TodayPlateView> {
  late Future<TodayIntakeStats> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() => _future = context.read<AppState>().intakeStatistics.today();
  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) => FutureBuilder<TodayIntakeStats>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const PixelPanel(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
      }
      if (snapshot.hasError) return PixelPanel(child: _MessageState(message: '今日餐盘加载失败', action: _retry));
      final stats = snapshot.data!;
      return Column(children: [
        PixelPanel(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), child: Column(children: [for (final stat in stats.categories.values) _CategoryRow(stat: stat)])),
        if (stats.stale) const Padding(padding: EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: Text('记录刚发生变化，当前结果可能需要刷新'))),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => context.push('/rolling_7d'), icon: const Icon(Icons.insights_outlined), label: const Text('查看本周进度'))),
      ]);
    },
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.stat});
  final IntakeCategoryStat stat;
  static const labels = {'grain': '谷物', 'tuber': '薯类', 'vegetable': '蔬菜', 'fruit': '水果', 'animal_food': '鱼禽肉蛋', 'dairy': '奶类', 'soy': '大豆', 'nut': '坚果', 'cooking_oil': '烹调油', 'salt': '食盐'};
  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  String _amount() => stat.amount == null ? (stat.completeness == 'missing' ? '未记录' : '未知') : '${_n(stat.amount!)}${stat.unit}';
  String _actual() {
    if (stat.actualKnownByUnit.isEmpty) return '';
    final entries = stat.actualKnownByUnit.entries.map((entry) => '${_n(entry.value)}${entry.key}').join('、');
    return '已记录$entries；折合';
  }
  String _target() { final min = stat.target.min, max = stat.target.max; if (min != null && max != null) return '${_n(min)}～${_n(max)}${stat.unit}'; if (min != null) return '至少${_n(min)}${stat.unit}'; if (max != null) return '不超过${_n(max)}${stat.unit}'; return '暂无参考'; }
  String _status() => switch (stat.status) {'below' => '需补充', 'near' => '接近下限', 'met' => '已达标', 'high' => '偏多', _ => stat.completeness == 'missing' ? '未记录' : '暂不能判断'};
  @override
  Widget build(BuildContext context) { final theme = Theme.of(context); final color = stat.status == 'met' ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant; return Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 76, child: Text(labels[stat.category] ?? stat.category, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (_actual().isNotEmpty) Text('${_actual()} ${_amount()}'), if (_actual().isEmpty) Text(_amount()), Text('参考 ${_target()}', style: theme.textTheme.labelSmall), const SizedBox(height: 3), Text(_status(), style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700))])), if (stat.gap != null) Text('缺${_n(stat.gap!)}${stat.unit}', style: theme.textTheme.labelSmall?.copyWith(color: color))])); }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.action});
  final String message;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_off_outlined, size: 36, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 8), Text(message), TextButton(onPressed: action, child: const Text('重试'))]);
}
