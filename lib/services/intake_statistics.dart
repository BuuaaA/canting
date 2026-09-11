import '../core/models/meal_record.dart';
import '../state/app_state.dart';
import 'intake_snapshot.dart';

const _categories = <String>[
  'grain',
  'tuber',
  'vegetable',
  'fruit',
  'animal_food',
  'dairy',
  'soy',
  'nut',
  'cooking_oil',
  'salt',
];

/// Product display tolerance. This is not a medical threshold.
const _nearRatio = .9;

class IntakeTarget {
  const IntakeTarget({this.min, this.max, this.kind = 'range'});
  final double? min;
  final double? max;
  final String kind;
  Map<String, dynamic> toJson() => {
    'targetMin': min,
    'targetMax': max,
    'targetKind': kind,
  };
}

class IntakeCategoryStat {
  const IntakeCategoryStat({
    required this.category,
    required this.amount,
    required this.knownSubtotal,
    required this.completeness,
    required this.target,
    required this.status,
    required this.gap,
    this.actualKnownSubtotal = 0,
    this.actualKnownByUnit = const {},
    this.unit = 'g',
  });
  final String category;
  final double? amount;
  final double knownSubtotal;
  final String completeness;
  final IntakeTarget target;
  final String? status;
  final double? gap;
  final double actualKnownSubtotal;
  final Map<String, double> actualKnownByUnit;
  final String unit;
  Map<String, dynamic> toJson() => {
    'category': category,
    'amount': amount,
    'comparisonAmount': amount,
    'knownSubtotal': knownSubtotal,
    'actualKnownSubtotal': actualKnownSubtotal,
    'actualKnownByUnit': actualKnownByUnit,
    'unit': unit,
    'completeness': completeness,
    ...target.toJson(),
    'status': status,
    'gap': gap,
  };
}

class IntakeDayStat {
  const IntakeDayStat({
    required this.date,
    required this.completeness,
    required this.categories,
    required this.foodVariety,
    required this.fishCount,
  });
  final String date;
  final String completeness;
  final Map<String, IntakeCategoryStat> categories;
  final int? foodVariety;
  final int? fishCount;
  Map<String, dynamic> toJson() => {
    'date': date,
    'completeness': completeness,
    'categories': categories.values.map((v) => v.toJson()).toList(),
    'foodVariety': foodVariety,
    'fishCount': fishCount,
  };
}

class IntakeAverageStat {
  const IntakeAverageStat({
    required this.category,
    required this.average,
    required this.denominator,
    required this.target,
  });
  final String category;
  final double? average;
  final int? denominator;
  final IntakeTarget target;
  Map<String, dynamic> toJson() => {
    'category': category,
    'average': average,
    'denominator': denominator,
    ...target.toJson(),
  };
}

class TodayIntakeStats {
  const TodayIntakeStats({
    required this.date,
    required this.revision,
    required this.categories,
    required this.completeness,
    this.stale = false,
  });
  final String date;
  final int revision;
  final Map<String, IntakeCategoryStat> categories;
  final String completeness;
  final bool stale;
  Map<String, dynamic> toJson() => {
    'date': date,
    'dataRevision': revision,
    'stale': stale,
    'completeness': completeness,
    'categories': categories.values.map((v) => v.toJson()).toList(),
  };
}

class Rolling7dIntakeStats {
  const Rolling7dIntakeStats({
    required this.startDate,
    required this.endDate,
    required this.revision,
    required this.days,
    required this.averages,
    required this.foodVarietyAverage,
    required this.foodVarietyDenominator,
    required this.fishCount,
    required this.fishGrams,
    required this.nutGrams,
    required this.dairyMetDays,
    required this.dairyKnownDays,
    required this.dairyUnknownDays,
    required this.soyMetDays,
    required this.soyKnownDays,
    required this.soyUnknownDays,
    required this.fishCompleteness,
    required this.nutCompleteness,
    this.stale = false,
  });
  final String startDate, endDate;
  final int revision;
  final List<IntakeDayStat> days;
  final Map<String, IntakeAverageStat> averages;
  final double? foodVarietyAverage;
  final int? foodVarietyDenominator;
  final int? fishCount;
  final double? fishGrams, nutGrams;
  final int dairyMetDays, dairyKnownDays, dairyUnknownDays;
  final int soyMetDays, soyKnownDays, soyUnknownDays;
  final String fishCompleteness, nutCompleteness;
  final bool stale;
  Map<String, dynamic> toJson() => {
    'startDate': startDate,
    'endDate': endDate,
    'dataRevision': revision,
    'stale': stale,
    'fish': {
      'count': fishCount,
      'grams': fishGrams,
      'completeness': fishCompleteness,
      'targetCount': 2,
      'targetMinGrams': 300,
      'targetMaxGrams': 500,
    },
    'nut': {
      'grams': nutGrams,
      'completeness': nutCompleteness,
      'targetMinGrams': 50,
      'targetMaxGrams': 70,
    },
    'dairy': {
      'metDays': dairyMetDays,
      'knownDays': dairyKnownDays,
      'unknownDays': dairyUnknownDays,
      'windowDays': 7,
    },
    'soy': {
      'metDays': soyMetDays,
      'knownDays': soyKnownDays,
      'unknownDays': soyUnknownDays,
      'windowDays': 7,
    },
    'foodVariety': {
      'average': foodVarietyAverage,
      'denominator': foodVarietyDenominator,
    },
    'averages': averages.values.map((v) => v.toJson()).toList(),
    'days': days.map((v) => v.toJson()).toList(),
  };
}

/// Local, query-time statistics over the same SQLite facts as AppState.
class IntakeStatisticsService {
  IntakeStatisticsService(this._state);
  final AppState _state;

  Future<TodayIntakeStats> today({DateTime? date}) async {
    final end = _day(date ?? _state.clock());
    final read = await _read(end);
    final days = _buildDays(end, read.meals);
    final day = days.last;
    return TodayIntakeStats(
      date: day.date,
      revision: read.revision,
      categories: day.categories,
      completeness: day.completeness,
      stale: read.stale,
    );
  }

  Future<Rolling7dIntakeStats> rolling7d({DateTime? date}) async {
    final end = _day(date ?? _state.clock());
    final read = await _read(end);
    final days = _buildDays(end, read.meals);
    final records = read.meals;
    final items = records.expand(IntakeSnapshot.itemsForMeal).toList();
    final knownFish = items.where((i) => i['fishKind'] == 'fish');
    final fishCount = _fishMealsFromRecords(records);
    final fishGrams = _sumComparable(knownFish, 'animal_food');
    final nutGrams = _sumComparable(
      items.where((i) => i['category'] == 'nut'),
      'nut',
    );
    final varietyValues = days
        .map((d) => d.foodVariety)
        .whereType<int>()
        .toList();
    final averages = <String, IntakeAverageStat>{};
    for (final category in const [
      'grain',
      'vegetable',
      'fruit',
      'animal_food',
    ]) {
      final values = days
          .map((d) => d.categories[category]!.amount)
          .whereType<double>()
          .toList();
      averages[category] = IntakeAverageStat(
        category: category,
        average: _average(values),
        denominator: values.isEmpty ? null : values.length,
        target: _target(category),
      );
    }
    final dairy = _metDayCounts(days, 'dairy');
    final soy = _metDayCounts(days, 'soy');
    return Rolling7dIntakeStats(
      startDate: days.first.date,
      endDate: days.last.date,
      revision: read.revision,
      days: days,
      averages: averages,
      foodVarietyAverage: _average(varietyValues),
      foodVarietyDenominator: varietyValues.length,
      fishCount: fishCount,
      fishGrams: fishGrams,
      nutGrams: nutGrams,
      dairyMetDays: dairy.met,
      dairyKnownDays: dairy.known,
      dairyUnknownDays: 7 - dairy.known,
      soyMetDays: soy.met,
      soyKnownDays: soy.known,
      soyUnknownDays: 7 - soy.known,
      fishCompleteness: fishCount == null
          ? 'unknown'
          : _summaryCompleteness(knownFish, items),
      nutCompleteness: _summaryCompleteness(
        items.where((i) => i['category'] == 'nut'),
        items,
      ),
      stale: read.stale,
    );
  }

  Future<_Read> _read(DateTime end) async {
    final before = _state.dataRevision;
    final records = await _state.queryMealsInRange(
      DateTime(end.year, end.month, end.day - 6),
      DateTime(end.year, end.month, end.day + 1),
    );
    final after = _state.dataRevision;
    if (before == after) return _Read(records, after, false);
    final retryBefore = after;
    final retry = await _state.queryMealsInRange(
      DateTime(end.year, end.month, end.day - 6),
      DateTime(end.year, end.month, end.day + 1),
    );
    final retryAfter = _state.dataRevision;
    return _Read(retry, retryAfter, retryBefore != retryAfter);
  }

  List<IntakeDayStat> _buildDays(DateTime end, List<MealRecord> records) {
    final byDay = <String, List<MealRecord>>{};
    for (final meal in records) {
      byDay.putIfAbsent(_key(meal.timestamp.toLocal()), () => []).add(meal);
    }
    return [
      for (var offset = -6; offset <= 0; offset++)
        _dayStat(DateTime(end.year, end.month, end.day + offset), byDay),
    ];
  }

  IntakeDayStat _dayStat(DateTime date, Map<String, List<MealRecord>> byDay) {
    final records = byDay[_key(date)] ?? const [];
    final items = records.expand(IntakeSnapshot.itemsForMeal).toList();
    final globallyIncomplete = records.any(
      (meal) =>
          !meal.structureComplete ||
          IntakeSnapshot.itemsForMeal(meal).any((i) => i['complete'] != true),
    );
    final categories = <String, IntakeCategoryStat>{};
    for (final category in _categories) {
      final categoryItems = items.where((i) => i['category'] == category);
      final list = categoryItems.toList();
      final values = list
          .map((i) => _comparableAmount(i, category))
          .whereType<double>()
          .toList();
      final known = values.fold<double>(0, (a, b) => a + b);
      final hasUnknown = list.any(
        (i) => _comparableAmount(i, category) == null,
      );
      final target = _target(category);
      final complete = list.isNotEmpty && !hasUnknown;
      categories[category] = IntakeCategoryStat(
        category: category,
        amount: complete && !globallyIncomplete ? known : null,
        knownSubtotal: known,
        completeness: records.isEmpty
            ? 'missing'
            : complete
            ? 'complete'
            : 'partial',
        target: target,
        status: complete && !globallyIncomplete ? _status(known, target) : null,
        gap:
            complete &&
                !globallyIncomplete &&
                target.kind != 'maximum' &&
                target.min != null
            ? (target.min! - known).clamp(0, double.infinity)
            : null,
        unit: category == 'dairy' ? 'ml' : 'g',
        actualKnownSubtotal: _sumActual(list),
        actualKnownByUnit: _sumActualByUnit(list),
      );
    }
    final foodKeys = items
        .map((i) => i['foodKey'])
        .whereType<String>()
        .where((k) => k.isNotEmpty)
        .toSet();
    final variety = records.isEmpty
        ? null
        : items.any((i) => i['foodKey'] == null)
        ? null
        : foodKeys.length;
    return IntakeDayStat(
      date: _key(date),
      completeness: records.isEmpty
          ? 'missing'
          : items.isEmpty || items.any((i) => i['complete'] != true)
          ? 'partial'
          : 'complete',
      categories: categories,
      foodVariety: variety,
      fishCount: _fishMealsFromRecords(records),
    );
  }

  static IntakeTarget _target(String category) => switch (category) {
    'grain' => const IntakeTarget(min: 200, max: 300),
    'tuber' => const IntakeTarget(min: 50, max: 100),
    'vegetable' => const IntakeTarget(min: 300, max: 500),
    'fruit' => const IntakeTarget(min: 200, max: 350),
    'animal_food' => const IntakeTarget(min: 120, max: 200),
    'dairy' => const IntakeTarget(min: 300, kind: 'minimum'),
    'soy' => const IntakeTarget(min: 20, max: 25),
    'nut' => const IntakeTarget(min: 50 / 7, max: 70 / 7),
    'cooking_oil' => const IntakeTarget(max: 30, kind: 'maximum'),
    'salt' => const IntakeTarget(max: 5, kind: 'maximum'),
    _ => const IntakeTarget(),
  };

  static String? _status(double value, IntakeTarget target) {
    if (target.kind == 'maximum') {
      return target.max == null
          ? null
          : value <= target.max!
          ? 'met'
          : 'high';
    }
    if (target.min == null) return null;
    if (value < target.min! * _nearRatio) return 'below';
    if (target.max != null && value > target.max!) return 'high';
    return value < target.min! ? 'near' : 'met';
  }

  static double? _comparableAmount(Map<String, dynamic> i, String category) {
    if (i['complete'] != true) return null;
    final equivalent = (i['equivalentAmount'] as num?)?.toDouble();
    final equivalentUnit = i['equivalentUnit'];
    if (equivalent != null &&
        equivalentUnit == (category == 'dairy' ? 'ml' : 'g')) {
      return equivalent;
    }
    final unit = i['unit'];
    final amount = (i['amount'] as num?)?.toDouble();
    if (amount == null) return null;
    final basis = i['amountBasis'];
    if (category == 'dairy') {
      return unit == 'ml' && basis == 'as_sold' ? amount : null;
    }
    return unit == 'g' && (basis == 'raw' || basis == 'as_sold')
        ? amount
        : null;
  }

  static double? _sumComparable(
    Iterable<Map<String, dynamic>> items,
    String category,
  ) {
    final values = items.map((i) => _comparableAmount(i, category)).toList();
    if (values.isEmpty || values.any((v) => v == null || v <= 0)) return null;
    return values.fold<double>(0, (a, b) => a + b!);
  }

  static double _sumActual(List<Map<String, dynamic>> items) => items
      .map((i) => (i['amount'] as num?)?.toDouble())
      .whereType<double>()
      .fold(0, (a, b) => a + b);
  static Map<String, double> _sumActualByUnit(
    List<Map<String, dynamic>> items,
  ) {
    final result = <String, double>{};
    for (final item in items) {
      final unit = item['unit'];
      final amount = (item['amount'] as num?)?.toDouble();
      if (unit is String && amount != null) {
        result[unit] = (result[unit] ?? 0) + amount;
      }
    }
    return result;
  }

  static int? _fishMealsFromRecords(List<MealRecord> records) {
    if (records.isEmpty) return null;
    final ids = records
        .where(
          (meal) => meal.dishes.any(
            (dish) => dish.food?.facts.category == 'fish' && dish.quantity > 0,
          ),
        )
        .map((meal) => meal.mealId)
        .toSet();
    return ids.isEmpty ? 0 : ids.length;
  }

  static String _summaryCompleteness(
    Iterable<Map<String, dynamic>> selected,
    List<Map<String, dynamic>> all,
  ) {
    if (all.isEmpty) return 'missing';
    final values = selected.toList();
    if (values.isEmpty) {
      return all.any((i) => i['category'] == 'animal_food')
          ? 'partial'
          : 'unknown';
    }
    return values.every(
          (i) =>
              _comparableAmount(i, i['category'] as String? ?? 'animal_food') !=
              null,
        )
        ? 'complete'
        : 'partial';
  }

  static double? _average(Iterable<num> values) {
    final v = values.toList();
    return v.isEmpty
        ? null
        : v.fold<double>(0, (a, b) => a + b.toDouble()) / v.length;
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _Read {
  const _Read(this.meals, this.revision, this.stale);
  final List<MealRecord> meals;
  final int revision;
  final bool stale;
}

class _DayCounts {
  const _DayCounts(this.met, this.known);
  final int met, known;
}

_DayCounts _metDayCounts(List<IntakeDayStat> days, String category) {
  var met = 0, known = 0;
  for (final day in days) {
    final stat = day.categories[category]!;
    if (stat.completeness == 'complete') {
      known++;
      if (stat.status == 'met' || stat.status == 'high') met++;
    }
  }
  return _DayCounts(met, known);
}
