import 'package:canting/core/balance_ledger.dart';
import 'package:canting/core/recommendation_engine.dart';
import 'package:canting/pet/pet_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// 宠物台词按 7 天台账趋势生成（模块：指南重蒸馏与滚动平衡引擎）。
void main() {
  final engine = PetEngine();

  BalanceReport ledger({
    double oilSurplus = 0,
    double grainSurplus = 0,
    double vegDeficit = 0,
    double fruitDeficit = 0,
  }) => BalanceReport(
    asOf: DateTime(2026, 9, 4),
    byCategory: {
      'grains': CategoryBalance(surplus: grainSurplus),
      'vegetables': CategoryBalance(deficit: vegDeficit),
      'fruits': CategoryBalance(deficit: fruitDeficit),
      'protein': const CategoryBalance(),
      'protein_soy': const CategoryBalance(),
      'oil': CategoryBalance(surplus: oilSurplus),
    },
  );

  test('油与主食双盈余 → 双双吃超的调侃台词', () {
    final line = engine.rollingBalanceDialogue(
      report: ledger(oilSurplus: 2, grainSurplus: 1),
      petType: 'cat',
    );
    expect(line, '昨天吃得很香，这两天咱们清爽一点？');
  });

  test('仅油盈余 → 清淡一点的提示', () {
    final line = engine.rollingBalanceDialogue(
      report: ledger(oilSurplus: 1),
      petType: 'cat',
    );
    expect(line, '昨天吃得很香，今天咱们清爽一点？');
  });

  test('仅主食盈余 → 少盛点饭的提示', () {
    final line = engine.rollingBalanceDialogue(
      report: ledger(grainSurplus: 1),
      petType: 'cat',
    );
    expect(line, '主食这两天有点多，下顿少盛点饭？');
  });

  test('蔬菜/水果长期欠账 → 鼓励性提醒', () {
    expect(
      engine.rollingBalanceDialogue(
        report: ledger(vegDeficit: 3),
        petType: 'cat',
      ),
      '这周蔬菜欠了不少，多吃点青菜呀～',
    );
    expect(
      engine.rollingBalanceDialogue(
        report: ledger(fruitDeficit: 2.5),
        petType: 'cat',
      ),
      '好久没吃水果啦，来点水果？',
    );
  });

  test('无趋势 → 空串（调用方回退当日场景台词）', () {
    expect(
      engine.rollingBalanceDialogue(
        report: ledger(),
        petType: 'cat',
      ),
      isEmpty,
    );
  });

  test('盈余低于清淡阈值 0.5 → 不触发台词（与引擎口径一致）', () {
    expect(
      engine.rollingBalanceDialogue(
        report: ledger(oilSurplus: 0.49),
        petType: 'cat',
      ),
      isEmpty,
    );
    expect(RecommendationEngine.lightSurplusThreshold, 0.5);
  });
}
