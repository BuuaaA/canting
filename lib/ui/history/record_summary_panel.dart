import 'package:canting/core/exposure.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:canting/core/record_window.dart';
import 'package:canting/state/app_state.dart';

class RecordSummaryPanel extends StatefulWidget {
  const RecordSummaryPanel({super.key, this.date});
  final DateTime? date;
  @override
  State<RecordSummaryPanel> createState() => _RecordSummaryPanelState();
}

class _RecordSummaryPanelState extends State<RecordSummaryPanel> {
  int days = 7;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final date = widget.date ?? state.clock();
    final w = state.windowFor(date, days);
    if (w == null) scheduleMicrotask(() => state.loadRecordWindows(date));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('最近7天')),
                ButtonSegment(value: 28, label: Text('最近28天')),
              ],
              selected: {days},
              onSelectionChanged: (v) => setState(() => days = v.single),
            ),
            const SizedBox(height: 8),
            if (w == null)
              const Text('正在读取记录…')
            else if (w.dataStatus == 'error') ...[
              const Text('记录读取失败，暂不判断缺口或趋势'),
              TextButton(
                onPressed: () => state.loadRecordWindows(date),
                child: const Text('重试'),
              ),
            ] else ...[
              Text(w.coverageText),
              for (final e in Exposure.counts(w.meals).entries)
                Text('${Exposure.labels[e.key]}：记录中出现${e.value}餐（按餐食ID计数）'),
              if (w.recordedDays > 0 && !w.hasKnownContributions)
                const Text('暂无可估算贡献，未知条目已保留'),
              if (w.recordedDays == 0)
                const Text('暂无可用记录，暂不判断结构或达标')
              else
                const Text('已知部分小计（估算份数）；未知不是零摄入'),
              if (w.hasKnownContributions)
                for (final e in w.knownSubtotal.byCategory.entries)
                  Text(
                    '${const {'grains': '主食', 'vegetables': '蔬菜', 'fruits': '水果', 'protein': '动物蛋白', 'protein_soy': '大豆坚果', 'oil': '油脂'}[e.key]}：${e.value.toStringAsFixed(1)}',
                  ),
              if (days == 28) ...[
                const Text('仅展示已记录餐食结构，暂不判断改善趋势；28天差额不分摊到下一餐。'),
                for (var i = 0; i < 4; i++)
                  Builder(
                    builder: (_) {
                      final d = localDay(date);
                      final end = DateTime(d.year, d.month, d.day - 7 * i);
                      final week = RecordWindow.build(
                        w.meals,
                        days: 7,
                        asOf: end,
                      );
                      return Text(
                        '${week.windowStart.month}/${week.windowStart.day}–${end.month}/${end.day}：记录${week.recordedDays}天，部分未知${week.partialDays}天',
                      );
                    },
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
