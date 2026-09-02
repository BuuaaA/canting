import 'dart:math' as math;

import 'package:canting/ui/theme/app_theme.dart';
import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class NutritionRingChart extends StatelessWidget {
  const NutritionRingChart({
    super.key,
    required this.overall,
    required this.values,
  });

  final double overall;
  final Map<String, double> values;

  static const _categories = [
    (
      key: 'grains',
      label: '主食',
      icon: Icons.rice_bowl_outlined,
      color: Color(0xFFD99B35),
    ),
    (
      key: 'vegetables',
      label: '蔬菜',
      icon: Icons.eco_outlined,
      color: Color(0xFF5D8B45),
    ),
    (
      key: 'fruits',
      label: '水果',
      icon: Icons.apple_outlined,
      color: Color(0xFFC85D4B),
    ),
    (
      key: 'protein',
      label: '蛋白质',
      icon: Icons.egg_alt_outlined,
      color: Color(0xFF4E8291),
    ),
    (
      key: 'protein_soy',
      label: '豆类坚果',
      icon: Icons.spa_outlined,
      color: Color(0xFF95643E),
    ),
    (
      key: 'oil',
      label: '油脂',
      icon: Icons.water_drop_outlined,
      color: Color(0xFFD47C38),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PixelPanel(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 15),
      child: Semantics(
        label:
            '今日膳食结构，整体完成 ${(overall * 100).round()}%，'
            '${_categories.map((item) => '${item.label}${((values[item.key] ?? 0) * 100).round()}%').join('，')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PixelIconTile(
                  icon: Icons.grid_view_rounded,
                  size: 38,
                  color: scheme.primaryContainer,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今日餐盘', style: theme.textTheme.titleMedium),
                      Text(
                        _overallMessage(overall),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final chartSize = constraints.maxWidth < 400 ? 124.0 : 140.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: chartSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: Size.square(chartSize),
                            painter: _NutritionRingPainter(
                              values: [
                                for (final category in _categories)
                                  values[category.key] ?? 0,
                              ],
                              colors: [
                                for (final category in _categories)
                                  category.color,
                              ],
                              outlineColor: scheme.outline,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(overall * 100).round()}%',
                                style: AppTheme.pixelText(
                                  context,
                                  fontSize: chartSize < 130 ? 15 : 17,
                                  color: completionColor(overall),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '整体',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          for (final category in _categories)
                            _LegendRow(
                              label: category.label,
                              icon: category.icon,
                              value: values[category.key] ?? 0,
                              color: category.color,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _overallMessage(double value) {
    if (value >= 0.9) return '六格快收集齐了';
    if (value >= 0.6) return '今天的进度不错';
    if (value > 0) return '再完成几格吧';
    return '从第一餐开始收集';
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
  });

  final String label;
  final IconData icon;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(
              icon,
              size: 9,
              color:
                  ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${(value * 100).round()}%',
            style: AppTheme.pixelText(context, fontSize: 7, color: color),
          ),
        ],
      ),
    );
  }
}

class _NutritionRingPainter extends CustomPainter {
  const _NutritionRingPainter({
    required this.values,
    required this.colors,
    required this.outlineColor,
  });

  final List<double> values;
  final List<Color> colors;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final strokeWidth = size.shortestSide * 0.18;
    final radius = (size.shortestSide - strokeWidth) / 2 - 3;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final segment = math.pi * 2 / values.length;
    const gap = math.pi / 42;
    var start = -math.pi / 2;

    for (var index = 0; index < values.length; index++) {
      final sweep = segment - gap;
      final backgroundPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = colors[index].withValues(alpha: 0.18);
      final valuePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = colors[index];

      canvas.drawArc(rect, start, sweep, false, backgroundPaint);
      canvas.drawArc(
        rect,
        start,
        sweep * values[index].clamp(0.0, 1.0),
        false,
        valuePaint,
      );
      start += segment;
    }

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = outlineColor;
    canvas.drawCircle(center, radius + strokeWidth / 2, outlinePaint);
    canvas.drawCircle(center, radius - strokeWidth / 2, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _NutritionRingPainter oldDelegate) {
    if (oldDelegate.outlineColor != outlineColor ||
        oldDelegate.values.length != values.length) {
      return true;
    }
    for (var index = 0; index < values.length; index++) {
      if (oldDelegate.values[index] != values[index] ||
          oldDelegate.colors[index] != colors[index]) {
        return true;
      }
    }
    return false;
  }
}

Color completionColor(double value) {
  if (value >= 0.8) return const Color(0xFF39734A);
  if (value >= 0.5) return const Color(0xFFC88F28);
  return const Color(0xFFD9694C);
}
