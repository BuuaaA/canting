import 'models/portions.dart';

/// 单类食物的 7 天滚动盈亏（单位：APP 份）。
class CategoryBalance {
  const CategoryBalance({this.surplus = 0, this.deficit = 0});

  /// 盈余：吃超的份数（如油脂 +2 份），随天数衰减 50%/日。
  final double surplus;

  /// 欠账：不足的份数（如蔬菜 -3 份），随天数衰减 20%/日，
  /// 长期不足则持续累积影响推荐。
  final double deficit;

  bool get isEmpty => surplus < _epsilon && deficit < _epsilon;

  static const double _epsilon = 1e-9;
}

/// 7 天滚动平衡台账报表：每类 {surplus, deficit}，供推荐引擎与文案使用。
class BalanceReport {
  BalanceReport({
    required Map<String, CategoryBalance> byCategory,
    required this.asOf,
    this.windowDays = BalanceLedger.windowDays,
  }) : byCategory = Map.unmodifiable(byCategory);

  /// APP 六类（grains/vegetables/fruits/protein/protein_soy/oil）的盈亏。
  final Map<String, CategoryBalance> byCategory;

  /// 台账结算日期（仅日期部分有效）。
  final DateTime asOf;
  final int windowDays;

  static final BalanceReport _empty = BalanceReport(
    byCategory: const {
      'grains': CategoryBalance(),
      'vegetables': CategoryBalance(),
      'fruits': CategoryBalance(),
      'protein': CategoryBalance(),
      'protein_soy': CategoryBalance(),
      'oil': CategoryBalance(),
    },
    asOf: DateTime(2026, 1, 1),
  );

  /// 全零台账（无历史数据时的中性缺省：引擎等同 routine 模式）。
  factory BalanceReport.empty({DateTime? asOf}) {
    if (asOf == null) {
      return _empty;
    }
    return BalanceReport(
      byCategory: const {
        'grains': CategoryBalance(),
        'vegetables': CategoryBalance(),
        'fruits': CategoryBalance(),
        'protein': CategoryBalance(),
        'protein_soy': CategoryBalance(),
        'oil': CategoryBalance(),
      },
      asOf: asOf,
    );
  }

  CategoryBalance balanceFor(String category) =>
      byCategory[category] ?? const CategoryBalance();

  bool get isEmpty => byCategory.values.every((item) => item.isEmpty);
}

/// 7 天滚动平衡台账（模块：指南重蒸馏与滚动平衡推荐引擎）。
///
/// 产品哲学：一次不健康的影响要持续传导到后面几天的推荐，最终让长期
/// （一周）膳食结构收敛到指南目标——指南口径是「一段时间内平衡即可」，
/// 不要求每一餐都精确达标。
///
/// 每类维护「盈亏账」：
/// - 盈余（吃超）：次日衰减 50%（day1 +2.0 → day2 余 1.0 → day3 余 0.5）；
/// - 欠账（不足）：衰减 20%/日（day1 -3.0 → day2 余 2.4 → day3 余 1.92），
///   长期不足则持续累积影响；
/// - 当日新增盈亏先与相反方向的结转对冲，余量计入自身方向；
/// - 空数据天（无记录）不产生新盈亏，但结转照常衰减（时间流逝会稀释）。
///
/// 纯 Dart 纯函数：注入 [compute] 的 now 与按日摄入，无 IO、无时钟，
/// 可完全离线测试。衰减参数与指南 JSON 的 weekly_balance 区块保持一致。
class BalanceLedger {
  BalanceLedger._();

  /// 滚动窗口天数（含今天）。
  static const int windowDays = 7;

  /// 盈余次日衰减比例（衰减 50%）。
  static const double surplusDecay = 0.5;

  /// 欠账每日衰减比例（衰减 20%）。
  static const double deficitDecay = 0.2;

  static const double _epsilon = 1e-9;

  /// 计算以 [now] 所在日为末日的 7 天滚动台账。
  ///
  /// [intakeByDay]：日期（仅取年月日）→ 当日六类摄入份数；窗口外的键
  /// 自动忽略，窗口内缺失的日期视为 0 摄入（空数据天）。
  /// [weeklyTarget]：六类 7 天目标份数（= 单日目标 × 7，IntakeCalculator
  /// 的周目标口径），日目标 = 周目标 ÷ 7。
  static BalanceReport compute({
    required Map<DateTime, Portions> intakeByDay,
    required Portions weeklyTarget,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final byCategory = <String, CategoryBalance>{};

    for (final entry in weeklyTarget.byCategory.entries) {
      final category = entry.key;
      final dailyTarget = entry.value / windowDays;
      var surplus = 0.0;
      var deficit = 0.0;

      // 从窗口最老的一天滚到今天：先衰减昨日结转，再结算当日净盈亏。
      for (var offset = windowDays - 1; offset >= 0; offset--) {
        final day = today.subtract(Duration(days: offset));
        surplus *= 1 - surplusDecay;
        deficit *= 1 - deficitDecay;

        // 无记录日 = 无信息（净额 0，不产生欠账）：外卖/手动记录不代表
        // 全部饮食，没记录的一天不该被记成「什么都没吃」；但结转的
        // 盈亏照常衰减（时间流逝会稀释影响）。有记录的日子才结算盈亏。
        final portions = intakeByDay[day];
        final known = portions != null;
        final eaten = known ? portions.valueFor(category) : 0.0;
        var net = known ? eaten - dailyTarget : 0.0;
        if (net > 0) {
          // 当日吃超：先偿还历史欠账，余量计盈余。
          if (deficit > 0) {
            final settled = deficit < net ? deficit : net;
            deficit -= settled;
            net -= settled;
          }
          surplus += net;
        } else if (net < 0) {
          // 当日不足：先消耗历史盈余，余量计欠账。
          if (surplus > 0) {
            final settled = surplus < -net ? surplus : -net;
            surplus -= settled;
            net += settled;
          }
          deficit += -net;
        }
      }

      byCategory[category] = CategoryBalance(
        surplus: _clean(surplus),
        deficit: _clean(deficit),
      );
    }

    return BalanceReport(byCategory: byCategory, asOf: today);
  }

  /// 清理浮点尾数（1e-9 以下视为 0），避免 -0.0 与尘埃值外溢。
  static double _clean(double value) =>
      value.abs() < _epsilon ? 0 : value;
}
