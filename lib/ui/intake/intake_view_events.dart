import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef IntakeViewEventSink = void Function(String eventName);

abstract final class IntakeViewEvents {
  static const _key = 'intake_view_events';
  static IntakeViewEventSink? sink;
  static void emit(String eventName, {required IntakeViewEventSink fallback}) =>
      (sink ?? fallback)(eventName);

  static Future<void> persist(String eventName) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final previous = preferences.getStringList(_key) ?? <String>[];
      final event = jsonEncode({
        'event': eventName,
        'at': DateTime.now().toIso8601String(),
      });
      final retained = previous.length >= 100
          ? previous.sublist(previous.length - 99)
          : previous;
      await preferences.setStringList(_key, [...retained, event]);
    } catch (_) {
      // Analytics must never block a statistics page.
    }
  }
}
