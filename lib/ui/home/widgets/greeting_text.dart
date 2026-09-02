import 'package:canting/ui/theme/pixel_widgets.dart';
import 'package:flutter/material.dart';

class GreetingText extends StatelessWidget {
  const GreetingText({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final value = now ?? DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PixelBadge(
          label: '${value.month}.${value.day}',
          icon: Icons.calendar_today_outlined,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            greetingFor(value),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  static String greetingFor(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    if (minutes >= 300 && minutes < 540) {
      return '早上好，今天感觉怎么样？';
    }
    if (minutes < 690) return '上午好，中午打算吃什么？';
    if (minutes < 810) return '中午好，午饭吃了吗？';
    if (minutes < 1020) return '下午好，记得起来走一走';
    if (minutes < 1170) return '晚上好，晚餐吃了吗？';
    if (minutes < 1320) return '晚上好，今天吃得怎么样？';
    return '夜深了，早点休息';
  }
}
