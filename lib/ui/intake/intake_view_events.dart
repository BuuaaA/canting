typedef IntakeViewEventSink = void Function(String eventName);

abstract final class IntakeViewEvents {
  static IntakeViewEventSink? sink;
  static void emit(String eventName) => sink?.call(eventName);
}
