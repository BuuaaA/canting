import 'models/meal_record.dart';
import 'models/portions.dart';

DateTime localDay(DateTime value) {
  final d = value.toLocal();
  return DateTime(d.year, d.month, d.day);
}

class RecordWindow {
  RecordWindow._(this.asOf, this.days, this.meals, this.dataStatus);
  final DateTime asOf;
  final int days;
  final List<MealRecord> meals;
  final String dataStatus;
  DateTime get windowEnd {
    final d = localDay(asOf);
    return DateTime(d.year, d.month, d.day + 1);
  }

  DateTime get windowStart {
    final d = localDay(asOf);
    return DateTime(d.year, d.month, d.day - days + 1);
  }

  factory RecordWindow.build(
    Iterable<MealRecord> records, {
    required int days,
    required DateTime asOf,
    String? status,
  }) {
    final d = localDay(asOf),
        start = DateTime(
          asOf.toLocal().year,
          asOf.toLocal().month,
          asOf.toLocal().day - days + 1,
        );
    final end = DateTime(d.year, d.month, d.day + 1);
    final meals = records
        .where((m) => !m.timestamp.isBefore(start) && m.timestamp.isBefore(end))
        .toList();
    return RecordWindow._(
      asOf,
      days,
      List.unmodifiable(meals),
      status ?? (meals.isEmpty ? 'insufficient' : 'ready'),
    );
  }
  Map<DateTime, List<MealRecord>> get byDay {
    final result = <DateTime, List<MealRecord>>{};
    for (final meal in meals) {
      result.putIfAbsent(localDay(meal.timestamp), () => []).add(meal);
    }
    return result;
  }

  bool get hasKnownContributions => meals.any(
    (m) => m.structureComplete || m.dishes.any((d) => d.contributionsKnown),
  );
  int get recordedDays => byDay.length;
  int get partialDays =>
      byDay.values.where((day) => day.any((m) => !m.structureComplete)).length;
  int get missingDays => days - recordedDays;
  int get unknownItemCount =>
      meals.expand((m) => m.dishes).where((d) => !d.contributionsKnown).length;
  Portions get knownSubtotal =>
      meals.fold(Portions.zero, (sum, m) => sum + m.portionsTotal);
  Map<DateTime, Portions> get knownDays => {
    for (final e in byDay.entries)
      if (e.value.every((m) => m.structureComplete))
        e.key: e.value.fold(Portions.zero, (s, m) => s + m.portionsTotal),
  };
  bool get todayKnown =>
      dataStatus == 'ready' && knownDays.containsKey(localDay(asOf));
  String get coverageText =>
      '$days天：有记录$recordedDays天，其中估算不完整$partialDays天；无记录$missingDays天；未知条目$unknownItemCount个。仅代表已记录餐食，不代表全天摄入。';
  Map<String, dynamic> toJson() => {
    'windowStart': windowStart.toIso8601String(),
    'windowEnd': windowEnd.toIso8601String(),
    'asOf': asOf.toIso8601String(),
    'recordedDays': recordedDays,
    'partialDays': partialDays,
    'missingDays': missingDays,
    'unknownItemCount': unknownItemCount,
    'knownSubtotal': knownSubtotal.toJson(),
    'dataStatus': dataStatus,
  };
}
