enum GrowthStage { egg, baby, adult }

enum VitalityState { energetic, good, low, expecting }

const _unset = Object();

class PetData {
  PetData({
    this.petId = 'default',
    required this.petType,
    required this.petName,
    required this.growthStage,
    required this.vitality,
    required this.growth,
    required this.lastVitalityUpdate,
    required this.createdAt,
    this.lastMealTime,
    this.lastPetTapTime,
    this.lastOfflineDecayCheck,
    this.lastDailyLogin,
    this.petTapCountDate,
    this.evolvedAt,
    this.consecutiveGoodMeals = 0,
    this.consecutiveBadMeals = 0,
    this.consecutiveNoRecordDays = 0,
    this.petTapsToday = 0,
    this.todayMealCount = 0,
    this.todayCompletionRate = 0,
    this.nextMealSummary,
  }) {
    if (!supportedPetTypes.contains(petType)) {
      throw ArgumentError.value(petType, 'petType', 'Unsupported pet type');
    }
    if (petName.runes.isEmpty || petName.runes.length > 6) {
      throw ArgumentError.value(
        petName,
        'petName',
        'Pet name must contain 1 to 6 characters',
      );
    }
    if (vitality < 15 || vitality > 100) {
      throw RangeError.range(vitality, 15, 100, 'vitality');
    }
    if (growth < 0) {
      throw RangeError.value(growth, 'growth', 'Must not be negative');
    }
    if (todayCompletionRate < 0 || todayCompletionRate > 1) {
      throw RangeError.range(todayCompletionRate, 0, 1, 'todayCompletionRate');
    }
  }

  static const supportedPetTypes = {'cat', 'dog', 'hamster'};

  final String petId;
  final String petType;
  final String petName;
  final GrowthStage growthStage;
  final int vitality;
  final int growth;
  final DateTime lastVitalityUpdate;
  final DateTime? lastMealTime;
  final DateTime? lastPetTapTime;
  final DateTime? lastOfflineDecayCheck;
  final DateTime? lastDailyLogin;
  final DateTime? petTapCountDate;
  final DateTime createdAt;
  final DateTime? evolvedAt;
  final int consecutiveGoodMeals;
  final int consecutiveBadMeals;
  final int consecutiveNoRecordDays;
  final int petTapsToday;
  final int todayMealCount;
  final double todayCompletionRate;
  final String? nextMealSummary;

  PetData copyWith({
    String? petId,
    String? petType,
    String? petName,
    GrowthStage? growthStage,
    int? vitality,
    int? growth,
    DateTime? lastVitalityUpdate,
    Object? lastMealTime = _unset,
    Object? lastPetTapTime = _unset,
    Object? lastOfflineDecayCheck = _unset,
    Object? lastDailyLogin = _unset,
    Object? petTapCountDate = _unset,
    DateTime? createdAt,
    Object? evolvedAt = _unset,
    int? consecutiveGoodMeals,
    int? consecutiveBadMeals,
    int? consecutiveNoRecordDays,
    int? petTapsToday,
    int? todayMealCount,
    double? todayCompletionRate,
    Object? nextMealSummary = _unset,
  }) {
    return PetData(
      petId: petId ?? this.petId,
      petType: petType ?? this.petType,
      petName: petName ?? this.petName,
      growthStage: growthStage ?? this.growthStage,
      vitality: vitality ?? this.vitality,
      growth: growth ?? this.growth,
      lastVitalityUpdate: lastVitalityUpdate ?? this.lastVitalityUpdate,
      lastMealTime: identical(lastMealTime, _unset)
          ? this.lastMealTime
          : lastMealTime as DateTime?,
      lastPetTapTime: identical(lastPetTapTime, _unset)
          ? this.lastPetTapTime
          : lastPetTapTime as DateTime?,
      lastOfflineDecayCheck: identical(lastOfflineDecayCheck, _unset)
          ? this.lastOfflineDecayCheck
          : lastOfflineDecayCheck as DateTime?,
      lastDailyLogin: identical(lastDailyLogin, _unset)
          ? this.lastDailyLogin
          : lastDailyLogin as DateTime?,
      petTapCountDate: identical(petTapCountDate, _unset)
          ? this.petTapCountDate
          : petTapCountDate as DateTime?,
      createdAt: createdAt ?? this.createdAt,
      evolvedAt: identical(evolvedAt, _unset)
          ? this.evolvedAt
          : evolvedAt as DateTime?,
      consecutiveGoodMeals: consecutiveGoodMeals ?? this.consecutiveGoodMeals,
      consecutiveBadMeals: consecutiveBadMeals ?? this.consecutiveBadMeals,
      consecutiveNoRecordDays:
          consecutiveNoRecordDays ?? this.consecutiveNoRecordDays,
      petTapsToday: petTapsToday ?? this.petTapsToday,
      todayMealCount: todayMealCount ?? this.todayMealCount,
      todayCompletionRate: todayCompletionRate ?? this.todayCompletionRate,
      nextMealSummary: identical(nextMealSummary, _unset)
          ? this.nextMealSummary
          : nextMealSummary as String?,
    );
  }

  factory PetData.fromJson(Map<String, dynamic> json) {
    return PetData(
      petId: json['pet_id'] as String? ?? 'default',
      petType: json['pet_type'] as String,
      petName: json['pet_name'] as String,
      growthStage: GrowthStage.values.byName(json['growth_stage'] as String),
      vitality: (json['vitality'] as num).toInt(),
      growth: (json['growth'] as num).toInt(),
      lastVitalityUpdate: DateTime.parse(
        json['last_vitality_update'] as String,
      ),
      lastMealTime: _dateFromJson(json['last_meal_time']),
      lastPetTapTime: _dateFromJson(json['last_pet_tap_time']),
      lastOfflineDecayCheck: _dateFromJson(json['last_offline_decay_check']),
      lastDailyLogin: _dateFromJson(json['last_daily_login']),
      petTapCountDate: _dateFromJson(json['pet_tap_count_date']),
      createdAt: DateTime.parse(json['created_at'] as String),
      evolvedAt: _dateFromJson(json['evolved_at']),
      consecutiveGoodMeals:
          (json['consecutive_good_meals'] as num?)?.toInt() ?? 0,
      consecutiveBadMeals:
          (json['consecutive_bad_meals'] as num?)?.toInt() ?? 0,
      consecutiveNoRecordDays:
          (json['consecutive_no_record_days'] as num?)?.toInt() ?? 0,
      petTapsToday: (json['pet_taps_today'] as num?)?.toInt() ?? 0,
      todayMealCount: (json['today_meal_count'] as num?)?.toInt() ?? 0,
      todayCompletionRate:
          (json['today_completion_rate'] as num?)?.toDouble() ?? 0,
      nextMealSummary: json['next_meal_summary'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pet_id': petId,
      'pet_type': petType,
      'pet_name': petName,
      'growth_stage': growthStage.name,
      'vitality': vitality,
      'growth': growth,
      'last_vitality_update': lastVitalityUpdate.toIso8601String(),
      'last_meal_time': lastMealTime?.toIso8601String(),
      'last_pet_tap_time': lastPetTapTime?.toIso8601String(),
      'last_offline_decay_check': lastOfflineDecayCheck?.toIso8601String(),
      'last_daily_login': lastDailyLogin?.toIso8601String(),
      'pet_tap_count_date': petTapCountDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'evolved_at': evolvedAt?.toIso8601String(),
      'consecutive_good_meals': consecutiveGoodMeals,
      'consecutive_bad_meals': consecutiveBadMeals,
      'consecutive_no_record_days': consecutiveNoRecordDays,
      'pet_taps_today': petTapsToday,
      'today_meal_count': todayMealCount,
      'today_completion_rate': todayCompletionRate,
      'next_meal_summary': nextMealSummary,
    };
  }

  Map<String, dynamic> toWidgetJson() {
    return {
      'pet_type': petType,
      'pet_name': petName,
      'growth_stage': growthStage.name,
      'vitality': vitality,
      'vitality_state': vitalityState.name,
      'today_meal_count': todayMealCount,
      'today_completion_rate': todayCompletionRate,
      'next_meal_summary': nextMealSummary,
      'pet_sprite_name':
          'pet_${petType}_${growthStage.name}_${vitalityState.name}_0',
    };
  }

  VitalityState get vitalityState {
    if (vitality >= 80) return VitalityState.energetic;
    if (vitality >= 50) return VitalityState.good;
    if (vitality >= 25) return VitalityState.low;
    return VitalityState.expecting;
  }

  static DateTime? _dateFromJson(Object? value) {
    return value == null ? null : DateTime.parse(value as String);
  }
}
