import 'package:canting/pet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final clockStart = DateTime(2026, 9, 4, 12);
  var now = clockStart;
  final engine = PetEngine(clock: () => now);

  PetData pet() => engine.createPet(petType: 'cat', petName: '小挑食');

  Map<String, double> byCategory(double rate) => {
    'grains': rate,
    'vegetables': rate,
    'fruits': rate,
    'protein': rate,
    'protein_soy': rate,
    'oil': rate,
  };

  setUp(() {
    now = clockStart;
  });

  group('成长值只增不减（模块 7 规则）', () {
    test('记录餐食后成长值增加', () {
      final before = pet();
      final result = engine.onMealRecorded(
        pet: before,
        completionRate: 0.9,
        completionByCategory: byCategory(0.9),
        mealId: 'm1',
      );

      expect(result.growthChange, greaterThan(0));
      expect(result.pet.growth, greaterThan(before.growth));
    });

    test('删除记录：活力值回退但成长值不回退', () {
      final initial = pet();
      final recorded = engine.onMealRecorded(
        pet: initial,
        completionRate: 0.9,
        completionByCategory: byCategory(0.9),
        mealId: 'm1',
      );
      final afterDelete = engine.onMealDeleted(
        pet: recorded.pet,
        mealId: 'm1',
        logs: recorded.logs,
      );

      expect(afterDelete.vitalityChange, lessThan(0));
      expect(afterDelete.growthChange, 0);
      expect(afterDelete.pet.growth, recorded.pet.growth);
      expect(afterDelete.pet.growth, greaterThan(initial.growth));
    });

    test('编辑记录：成长值不回退', () {
      final initial = pet();
      final recorded = engine.onMealRecorded(
        pet: initial,
        completionRate: 0.9,
        completionByCategory: byCategory(0.9),
        mealId: 'm1',
      );
      now = clockStart.add(const Duration(hours: 1));
      final afterEdit = engine.onMealEdited(
        pet: recorded.pet,
        mealId: 'm1',
        logs: recorded.logs,
        newCompletionRate: 0.2,
        newCompletionByCategory: byCategory(0.2),
      );

      expect(afterEdit.growthChange, 0);
      expect(afterEdit.pet.growth, recorded.pet.growth);
    });

    test('进化阈值：成长值跨过 50 触发 egg → baby', () {
      var current = pet();
      // 每次 0.9 完成度 +10 成长，前 4 次从 egg(0) 到 baby(50) 附近。
      for (var i = 0; i < 5; i++) {
        final result = engine.onMealRecorded(
          pet: current,
          completionRate: 0.9,
          completionByCategory: byCategory(0.9),
          mealId: 'm$i',
        );
        current = result.pet;
        if (i == 4) {
          expect(result.previousGrowthStage, GrowthStage.egg);
          expect(current.growthStage, GrowthStage.baby);
        }
      }
      expect(current.growth, greaterThanOrEqualTo(50));
    });
  });

  group('摸摸头互动（冷却 + 当日去重）', () {
    test('第一次互动 +1 成长值', () {
      final initial = pet();
      final result = engine.onPetTap(pet: initial, now: clockStart);

      expect(result.wasApplied, isTrue);
      expect(result.growthChange, 1);
      expect(result.pet.growth, initial.growth + 1);
      expect(result.pet.petTapsToday, 1);
    });

    test('冷却时间内不生效（当日去重：同一时间点连点无效）', () {
      final initial = pet();
      final first = engine.onPetTap(pet: initial, now: clockStart);
      final second = engine.onPetTap(
        pet: first.pet,
        now: clockStart.add(const Duration(minutes: 30)),
      );

      expect(second.wasApplied, isFalse);
      expect(second.growthChange, 0);
      expect(second.pet.petTapsToday, first.pet.petTapsToday);
    });

    test('每日上限 3 次：第 4 次即使过了冷却也无效', () {
      var current = pet();
      // 从早上 6 点开始，保证 4 次尝试都落在同一天。
      var tapTime = DateTime(
        clockStart.year,
        clockStart.month,
        clockStart.day,
        6,
      );
      for (var i = 0; i < 3; i++) {
        final result = engine.onPetTap(pet: current, now: tapTime);
        expect(result.wasApplied, isTrue, reason: '第 ${i + 1} 次应生效');
        current = result.pet;
        tapTime = tapTime
            .add(PetStateMachine.petTapCooldown)
            .add(const Duration(minutes: 1));
      }
      final fourth = engine.onPetTap(pet: current, now: tapTime);

      expect(fourth.wasApplied, isFalse);
      expect(current.petTapsToday, 3);
    });

    test('次日计数重置，可以再次互动', () {
      var current = pet();
      var tapTime = DateTime(
        clockStart.year,
        clockStart.month,
        clockStart.day,
        6,
      );
      for (var i = 0; i < 3; i++) {
        final result = engine.onPetTap(pet: current, now: tapTime);
        current = result.pet;
        tapTime = tapTime
            .add(PetStateMachine.petTapCooldown)
            .add(const Duration(minutes: 1));
      }
      final nextDay = DateTime(
        tapTime.year,
        tapTime.month,
        tapTime.day + 1,
        9,
      );
      final nextDayTap = engine.onPetTap(pet: current, now: nextDay);

      expect(nextDayTap.wasApplied, isTrue);
      expect(nextDayTap.pet.petTapsToday, 1);
    });
  });
}
