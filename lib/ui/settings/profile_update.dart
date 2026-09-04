import 'package:canting/core_engine.dart';

/// 个人信息编辑的落库前组装逻辑（模块 10）。
///
/// 纯函数，不依赖 Provider 或数据库：把编辑页提交的字段合并到当前档案上，
/// 并用 IntakeCalculator + 膳食指南重算每日目标份数快照。
/// 与 onboarding 的 [OnboardingDraft.toProfile] 保持同一口径。
class ProfileUpdate {
  ProfileUpdate._();

  /// 一次编辑可变更的全部字段；null 表示保持原值。
  static UserProfile apply({
    required UserProfile current,
    required DietaryGuidelines guidelines,
    String? gender,
    int? age,
    double? heightCm,
    double? weightKg,
    String? activityLevel,
    String? dietGoal,
    String? breakfastTime,
    String? lunchTime,
    String? dinnerTime,
    String? dayStartTime,
  }) {
    final next = current.copyWith(
      gender: gender,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      activityLevel: activityLevel,
      dietGoal: dietGoal,
      breakfastTime: breakfastTime,
      lunchTime: lunchTime,
      dinnerTime: dinnerTime,
      dayStartTime: dayStartTime,
    );
    final intake = IntakeCalculator().calculate(
      guidelines: guidelines,
      gender: next.gender,
      heightCm: next.heightCm.round(),
      weightKg: next.weightKg,
      age: next.age,
      activityLevel: next.activityLevel,
      dietGoal: next.dietGoal,
    );
    return next.copyWith(dailyIntake: intake, updatedAt: DateTime.now());
  }

  /// 表单数值校验；返回null表示合法，否则为给用户的提示文案。
  static String? validate({
    required int age,
    required double heightCm,
    required double weightKg,
  }) {
    if (age < 1 || age > 120) {
      return '年龄需要在 1-120 岁之间';
    }
    if (heightCm < 50 || heightCm > 250) {
      return '身高需要在 50-250 厘米之间';
    }
    if (weightKg < 10 || weightKg > 300) {
      return '体重需要在 10-300 公斤之间';
    }
    return null;
  }
}
