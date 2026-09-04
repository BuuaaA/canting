import 'dart:convert';
import 'dart:io';

import 'package:canting/core_engine.dart';
import 'package:canting/ui/settings/profile_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile() {
  final now = DateTime(2026, 9, 1);
  return UserProfile(
    gender: 'female',
    age: 28,
    heightCm: 165,
    weightKg: 55,
    dietGoal: 'balanced',
    activityLevel: 'light',
    breakfastTime: '08:00',
    lunchTime: '12:00',
    dinnerTime: '18:30',
    dayStartTime: '01:00',
    onboardingCompleted: true,
    createdAt: now,
    updatedAt: now,
  );
}

DietaryGuidelines _guidelines() => DietaryGuidelines.fromJson(
  (jsonDecode(
        File('assets/data/dietary_guidelines.json').readAsStringSync(),
      )
      as Map)
      .cast<String, dynamic>(),
);

Future<void> _pumpPage(
  WidgetTester tester, {
  required List<UserProfile> saved,
  DietaryGuidelines? guidelines,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ProfileEditPage(
        profile: _profile(),
        guidelines: guidelines,
        onSave: (profile) async => saved.add(profile),
      ),
    ),
  );
  await tester.pump();
}

/// 保存按钮在长列表底部，先滚动到可见再点击。
Future<void> _tapSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('保存修改'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('保存修改'));
}

void main() {
  late DietaryGuidelines guidelines;

  setUpAll(() {
    guidelines = _guidelines();
  });

  testWidgets('用当前档案预填表单', (tester) async {
    await _pumpPage(tester, saved: [], guidelines: guidelines);

    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('165'), findsOneWidget);
    expect(find.text('55'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('轻度活动'), findsOneWidget);
    expect(find.text('吃得更均衡'), findsOneWidget);
  });

  testWidgets('保存需经过二次确认，确认后回调重算过的新档案', (tester) async {
    final saved = <UserProfile>[];
    await _pumpPage(tester, saved: saved, guidelines: guidelines);

    await tester.enterText(
      find.widgetWithText(TextField, '体重（公斤）'),
      '62',
    );
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('保存修改？'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.weightKg, 62);
    expect(saved.single.dailyIntake, isNotNull);
  });

  testWidgets('取消确认弹窗则不落库', (tester) async {
    final saved = <UserProfile>[];
    await _pumpPage(tester, saved: saved, guidelines: guidelines);

    await _tapSave(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(saved, isEmpty);
  });

  testWidgets('非法数值给出提示且不弹确认框', (tester) async {
    final saved = <UserProfile>[];
    await _pumpPage(tester, saved: [], guidelines: guidelines);

    await tester.enterText(
      find.widgetWithText(TextField, '年龄（岁）'),
      '999',
    );
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('年龄需要在 1-120 岁之间'), findsOneWidget);
    expect(saved, isEmpty);
  });

  testWidgets('缺少膳食指南数据时拒绝保存', (tester) async {
    final saved = <UserProfile>[];
    await _pumpPage(tester, saved: []);

    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('膳食指南数据未加载，暂时无法保存'), findsOneWidget);
    expect(saved, isEmpty);
  });
}
