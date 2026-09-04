import 'dart:async';

import 'package:canting/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(NotificationService.resetForTest);

  group('通知内容构造', () {
    test('识别成功通知：标题带餐次、正文为菜名 · 宠物台词', () {
      final content = NotificationService.buildSuccessContent(
        mealType: '午餐',
        dishName: '黄焖鸡米饭',
        petText: '嗯，吃得不错嘛～',
      );

      expect(content.title, '已记录午餐');
      expect(content.body, '黄焖鸡米饭 · 嗯，吃得不错嘛～');
      expect(content.payload, NotificationService.payloadSuccess);
    });

    test('识别成功通知：宠物台词为空时正文只有菜名', () {
      final content = NotificationService.buildSuccessContent(
        mealType: '早餐',
        dishName: '豆浆包子',
        petText: '  ',
      );

      expect(content.title, '已记录早餐');
      expect(content.body, '豆浆包子');
    });

    test('识别失败通知：固定文案与失败载荷', () {
      final content = NotificationService.buildFailureContent();

      expect(content.title, contains('没认出来'));
      expect(content.body, contains('手动添加'));
      expect(content.payload, NotificationService.payloadFailure);
    });

    test('成功与失败使用不同的点击载荷', () {
      expect(
        NotificationService.payloadSuccess,
        isNot(NotificationService.payloadFailure),
      );
    });
  });

  group('通知开关状态', () {
    test('默认开启识别结果通知', () {
      expect(NotificationService.recognitionEnabled, isTrue);
    });

    test('关闭后开关状态保持', () {
      NotificationService.recognitionEnabled = false;

      expect(NotificationService.recognitionEnabled, isFalse);
    });

    test('重置后恢复默认开启', () {
      NotificationService.recognitionEnabled = false;
      NotificationService.resetForTest();

      expect(NotificationService.recognitionEnabled, isTrue);
    });
  });

  group('通知点击事件流', () {
    test('广播流会把载荷发给所有监听者', () async {
      final received1 = <String>[];
      final received2 = <String>[];
      final sub1 = NotificationService.onTap.listen(received1.add);
      final sub2 = NotificationService.onTap.listen(received2.add);
      addTearDown(() {
        unawaited(sub1.cancel());
        unawaited(sub2.cancel());
      });

      NotificationService.emitTapForTest(NotificationService.payloadFailure);
      await Future<void>.delayed(Duration.zero);

      expect(received1, [NotificationService.payloadFailure]);
      expect(received2, [NotificationService.payloadFailure]);
    });
  });
}
