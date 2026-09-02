import 'package:canting/pet/widgets/pet_dialog_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('PetDialogWidget', () {
    testWidgets('shows the supplied pet dialogue immediately', (tester) async {
      await tester.pumpWidget(host(const PetDialogWidget(text: '今天吃了什么呀？')));

      expect(find.text('今天吃了什么呀？'), findsOne);
    });

    testWidgets('dismisses after the configured duration', (tester) async {
      var dismissCount = 0;
      await tester.pumpWidget(
        host(
          PetDialogWidget(
            text: '吃饱啦！',
            duration: const Duration(seconds: 1),
            onDismissed: () => dismissCount += 1,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 999));
      expect(find.text('吃饱啦！'), findsOne);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('吃饱啦！'), findsNothing);
      expect(dismissCount, 1);
    });

    testWidgets('restarts its timer when the dialogue changes', (tester) async {
      await tester.pumpWidget(
        host(
          const PetDialogWidget(text: '第一句', duration: Duration(seconds: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));

      await tester.pumpWidget(
        host(
          const PetDialogWidget(text: '第二句', duration: Duration(seconds: 1)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('第二句'), findsOne);
    });
  });
}
