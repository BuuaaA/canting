import 'package:canting/core_engine.dart';
import 'package:canting/ui/home/widgets/nutrition_ring_chart.dart';
import 'package:canting/ui/theme/app_theme.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

/// 分类进度条列表：完成度 + 真实摄入/目标份数。
class FoodProgressList extends StatelessWidget {
  const FoodProgressList({
    super.key,
    required this.values,
    this.current,
    this.target,
  });

  /// 各分类完成度（0~1）。
  final Map<String, double> values;

  /// 已摄入份数；为 null 时不显示「摄入/目标」列。
  final Portions? current;

  /// 目标份数。
  final Portions? target;

  static const _items = [
    (key: 'grains', label: '主食', icon: Icons.rice_bowl_outlined),
    (key: 'vegetables', label: '蔬菜', icon: Icons.eco_outlined),
    (key: 'fruits', label: '水果', icon: Icons.apple_outlined),
    (key: 'protein', label: '鱼肉蛋奶', icon: Icons.egg_alt_outlined),
    (key: 'protein_soy', label: '大豆坚果', icon: Icons.spa_outlined),
    (key: 'oil', label: '油脂', icon: Icons.water_drop_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final showServings = current != null && target != null;
    return PixelPanel(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Column(
        children: [
          for (var index = 0; index < _items.length; index++) ...[
            _FoodProgressRow(
              label: _items[index].label,
              icon: _items[index].icon,
              value: values[_items[index].key] ?? 0,
              current: showServings ? current!.valueFor(_items[index].key) : null,
              target: showServings ? target!.valueFor(_items[index].key) : null,
            ),
            if (index != _items.length - 1) const PixelDivider(),
          ],
        ],
      ),
    );
  }
}

class _FoodProgressRow extends StatelessWidget {
  const _FoodProgressRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.current,
    required this.target,
  });

  final String label;
  final IconData icon;
  final double value;
  final double? current;
  final double? target;

  static String _formatServings(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final color = completionColor(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PixelProgressBar(
              value: value,
              segments: 8,
              height: 9,
              color: color,
              semanticLabel: '$label完成${(value * 100).round()}%',
            ),
          ),
          if (current != null && target != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: Text(
                '${_formatServings(current!)}/${_formatServings(target!)}份',
                textAlign: TextAlign.end,
                style: AppTheme.pixelText(
                  context,
                  fontSize: 7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 43,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: AppTheme.pixelText(context, fontSize: 7, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
