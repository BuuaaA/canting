import 'dart:math' as math;

import 'package:canting/core/balance_ledger.dart';
import 'package:canting/core/models/portions.dart';
import 'package:test/test.dart';

/// BalanceLedger 7 天滚动台账单元测试：
/// 衰减曲线、对冲、跨周滚动窗口滑动、空数据天处理。
void main() {
  // 周目标：油 17.5（日目标 2.5）、蔬菜 31.5（日目标 4.5），
  // 其余给合法值即可（不参与断言）。
  const weeklyTarget = Portions(
    grains: 35,
    vegetables: 31.5,
    fruits: 17.5,
    protein: 24.5,
    proteinSoy: 10.5,
    oil: 17.5,
  );

  group('盈余衰减曲线（吃超次日衰减 50%）', () {
    test('day1 油吃超 2 份 → day2 余 1.0 → day3 余 0.5 → day4 余 0.25', () {
      final day1 = DateTime(2026, 9, 1);
      final feast = const Portions(oil: 4.5); // 日目标 2.5 → 盈余 +2.0

      final atDay1 = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1,
      );
      expect(atDay1.balanceFor('oil').surplus, closeTo(2.0, 1e-9));

      final atDay2 = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 1)),
      );
      expect(atDay2.balanceFor('oil').surplus, closeTo(1.0, 1e-9));

      final atDay3 = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 2)),
      );
      expect(atDay3.balanceFor('oil').surplus, closeTo(0.5, 1e-9));

      final atDay4 = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 3)),
      );
      expect(atDay4.balanceFor('oil').surplus, closeTo(0.25, 1e-9));
    });

    test('盈余与欠账不共存于同一类（当日净额单向）', () {
      final report = BalanceLedger.compute(
        intakeByDay: {
          DateTime(2026, 9, 1): const Portions(oil: 6.5),
        },
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 1),
      );
      final oil = report.balanceFor('oil');
      expect(oil.surplus, closeTo(4.0, 1e-9));
      expect(oil.deficit, 0);
    });
  });

  group('欠账衰减曲线（不足每日衰减 20%）', () {
    test('day1 蔬菜少 3 份 → day2 余 2.4 → day3 余 1.92', () {
      final day1 = DateTime(2026, 9, 1);
      final littleVeg = const Portions(vegetables: 1.5); // 目标 4.5 → -3.0

      final atDay1 = BalanceLedger.compute(
        intakeByDay: {day1: littleVeg},
        weeklyTarget: weeklyTarget,
        now: day1,
      );
      expect(atDay1.balanceFor('vegetables').deficit, closeTo(3.0, 1e-9));

      final atDay2 = BalanceLedger.compute(
        intakeByDay: {day1: littleVeg},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 1)),
      );
      expect(atDay2.balanceFor('vegetables').deficit, closeTo(2.4, 1e-9));

      final atDay3 = BalanceLedger.compute(
        intakeByDay: {day1: littleVeg},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 2)),
      );
      expect(atDay3.balanceFor('vegetables').deficit, closeTo(1.92, 1e-9));
    });

    test('长期不足持续累积（衰减慢于新增）', () {
      final day1 = DateTime(2026, 9, 1);
      final littleVeg = const Portions(vegetables: 1.5);
      final atDay3 = BalanceLedger.compute(
        intakeByDay: {
          day1: littleVeg,
          day1.add(const Duration(days: 1)): littleVeg,
          day1.add(const Duration(days: 2)): littleVeg,
        },
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 2)),
      );
      // day1 -3.0 → day2 结转 2.4 + 新增 3.0 = 5.4 → day3 结转 4.32 + 3.0
      expect(atDay3.balanceFor('vegetables').deficit, closeTo(7.32, 1e-9));
    });
  });

  group('对冲与滚动窗口', () {
    test('昨日欠账被今日吃超部分偿还（先衰减后偿还）', () {
      final day1 = DateTime(2026, 9, 1);
      final report = BalanceLedger.compute(
        intakeByDay: {
          day1: const Portions(vegetables: 1.5), // -3.0
          day1.add(const Duration(days: 1)): const Portions(
            vegetables: 6.0,
          ), // +1.5
        },
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 1)),
      );
      // day2 结转 3.0×0.8=2.4，被 +1.5 偿还后余 0.9。
      expect(report.balanceFor('vegetables').deficit, closeTo(0.9, 1e-9));
      expect(report.balanceFor('vegetables').surplus, 0);
    });

    test('跨周滚动窗口滑动：8 天前的大吃大喝完全滑出', () {
      final day1 = DateTime(2026, 9, 1);
      final feast = const Portions(oil: 6.5);
      final inWindow = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 6)),
      );
      expect(inWindow.balanceFor('oil').surplus, greaterThan(0));

      final outOfWindow = BalanceLedger.compute(
        intakeByDay: {day1: feast},
        weeklyTarget: weeklyTarget,
        now: day1.add(const Duration(days: 7)),
      );
      // 9/1 已在 9/8 的 7 天窗口（9/2..9/8）之外。
      expect(outOfWindow.balanceFor('oil').surplus, 0);
    });

    test('窗口外的摄入键被忽略，缺失的窗口内日期按 0 处理', () {
      final report = BalanceLedger.compute(
        intakeByDay: {
          DateTime(2026, 8, 1): const Portions(oil: 10), // 远在窗口外
          DateTime(2026, 9, 3): const Portions(oil: 4.5),
        },
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 4),
      );
      // 只有 9/3 的 +2.0 计入，且 9/4（空白天）衰减一次。
      expect(report.balanceFor('oil').surplus, closeTo(1.0, 1e-9));
    });
  });

  group('空数据与健壮性', () {
    test('空摄入表 → 全零台账', () {
      final report = BalanceLedger.compute(
        intakeByDay: const {},
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 4),
      );
      expect(report.isEmpty, isTrue);
      for (final category in [
        'grains',
        'vegetables',
        'fruits',
        'protein',
        'protein_soy',
        'oil',
      ]) {
        final balance = report.balanceFor(category);
        expect(balance.surplus, 0);
        expect(balance.deficit, 0);
      }
    });

    test('日目标 = 周目标 ÷ 7（油 17.5/7 = 2.5）', () {
      final report = BalanceLedger.compute(
        intakeByDay: {
          DateTime(2026, 9, 4): const Portions(oil: 2.5),
        },
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 4),
      );
      // 恰好达标 → 无盈余无欠账。
      final oil = report.balanceFor('oil');
      expect(oil.surplus, 0);
      expect(oil.deficit, 0);
    });

    test('浮点尾数不外溢（-0.0 / 尘埃值归零）', () {
      final report = BalanceLedger.compute(
        intakeByDay: {
          DateTime(2026, 9, 4): const Portions(
            oil: 2.5,
            vegetables: 4.5,
            grains: 5,
            fruits: 2.5,
            protein: 3.5,
            proteinSoy: 1.5,
          ),
        },
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 4),
      );
      for (final balance in report.byCategory.values) {
        expect(balance.surplus.isNegative, isFalse);
        expect(balance.deficit.isNegative, isFalse);
      }
    });
  });

  group('BalanceReport 便捷接口', () {
    test('balanceFor 未知分类返回零值，empty 工厂为中性台账', () {
      expect(BalanceReport.empty().balanceFor('oil').surplus, 0);
      expect(BalanceReport.empty().isEmpty, isTrue);
    });

    test('台账收敛性：均匀达标饮食 7 天后台账归零（数学性质冒烟）', () {
      // 每天 4.5 份蔬菜持续 7 天后，任意中间日的结转衰减
      // Σ 3.0×0.8^k 收敛有界；这里只验证确定性（同输入同输出）。
      final intake = {
        for (var i = 0; i < 7; i++)
          DateTime(2026, 9, 1 + i): const Portions(vegetables: 4.5),
      };
      final a = BalanceLedger.compute(
        intakeByDay: intake,
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 7),
      );
      final b = BalanceLedger.compute(
        intakeByDay: intake,
        weeklyTarget: weeklyTarget,
        now: DateTime(2026, 9, 7),
      );
      expect(
        a.balanceFor('vegetables').deficit,
        b.balanceFor('vegetables').deficit,
        reason: '纯函数：同输入必同输出',
      );
      // 每天恰好达标 → 每日净额为 0，无盈亏。
      expect(a.balanceFor('vegetables').deficit, 0);
      expect(
        math.max(a.balanceFor('vegetables').surplus, 0),
        0,
      );
    });
  });
}
