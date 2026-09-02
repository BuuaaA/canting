enum VitalityChangeType {
  mealGood,
  mealMid,
  mealPoor,
  noRecord,
  petTap,
  evolve,
  mealDelete,
  mealEdit,
}

extension VitalityChangeTypeCode on VitalityChangeType {
  String get code {
    return switch (this) {
      VitalityChangeType.mealGood => 'meal_good',
      VitalityChangeType.mealMid => 'meal_mid',
      VitalityChangeType.mealPoor => 'meal_poor',
      VitalityChangeType.noRecord => 'no_record',
      VitalityChangeType.petTap => 'pet_tap',
      VitalityChangeType.evolve => 'evolve',
      VitalityChangeType.mealDelete => 'meal_delete',
      VitalityChangeType.mealEdit => 'meal_edit',
    };
  }

  static VitalityChangeType fromCode(String code) {
    return VitalityChangeType.values.firstWhere(
      (value) => value.code == code,
      orElse: () =>
          throw FormatException('Unknown vitality change type: $code'),
    );
  }
}

const _unset = Object();

class VitalityLog {
  VitalityLog({
    required this.logId,
    required this.timestamp,
    required this.changeType,
    required this.changeValue,
    required this.vitalityBefore,
    required this.vitalityAfter,
    this.relatedMealId,
    this.isReversed = false,
    this.completionRate,
    this.reversesLogId,
  }) {
    if (vitalityBefore < 15 || vitalityBefore > 100) {
      throw RangeError.range(vitalityBefore, 15, 100, 'vitalityBefore');
    }
    if (vitalityAfter < 15 || vitalityAfter > 100) {
      throw RangeError.range(vitalityAfter, 15, 100, 'vitalityAfter');
    }
    if (vitalityAfter - vitalityBefore != changeValue) {
      throw ArgumentError(
        'changeValue must equal vitalityAfter - vitalityBefore',
      );
    }
    final checkedCompletionRate = completionRate;
    if (checkedCompletionRate != null &&
        (checkedCompletionRate < 0 || checkedCompletionRate > 1)) {
      throw RangeError.range(checkedCompletionRate, 0, 1, 'completionRate');
    }
  }

  final String logId;
  final DateTime timestamp;
  final VitalityChangeType changeType;
  final int changeValue;
  final int vitalityBefore;
  final int vitalityAfter;
  final String? relatedMealId;
  final bool isReversed;

  /// Stored on active meal effects so counters can be rebuilt after deletion.
  final double? completionRate;

  /// Set on rollback records to identify the original effect they cancel.
  final String? reversesLogId;

  bool get isActiveMealEffect {
    return !isReversed &&
        completionRate != null &&
        relatedMealId != null &&
        {
          VitalityChangeType.mealGood,
          VitalityChangeType.mealMid,
          VitalityChangeType.mealPoor,
          VitalityChangeType.mealEdit,
        }.contains(changeType);
  }

  VitalityLog copyWith({
    String? logId,
    DateTime? timestamp,
    VitalityChangeType? changeType,
    int? changeValue,
    int? vitalityBefore,
    int? vitalityAfter,
    Object? relatedMealId = _unset,
    bool? isReversed,
    Object? completionRate = _unset,
    Object? reversesLogId = _unset,
  }) {
    return VitalityLog(
      logId: logId ?? this.logId,
      timestamp: timestamp ?? this.timestamp,
      changeType: changeType ?? this.changeType,
      changeValue: changeValue ?? this.changeValue,
      vitalityBefore: vitalityBefore ?? this.vitalityBefore,
      vitalityAfter: vitalityAfter ?? this.vitalityAfter,
      relatedMealId: identical(relatedMealId, _unset)
          ? this.relatedMealId
          : relatedMealId as String?,
      isReversed: isReversed ?? this.isReversed,
      completionRate: identical(completionRate, _unset)
          ? this.completionRate
          : completionRate as double?,
      reversesLogId: identical(reversesLogId, _unset)
          ? this.reversesLogId
          : reversesLogId as String?,
    );
  }

  factory VitalityLog.fromJson(Map<String, dynamic> json) {
    return VitalityLog(
      logId: json['log_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      changeType: VitalityChangeTypeCode.fromCode(
        json['change_type'] as String,
      ),
      changeValue: (json['change_value'] as num).toInt(),
      vitalityBefore: (json['vitality_before'] as num).toInt(),
      vitalityAfter: (json['vitality_after'] as num).toInt(),
      relatedMealId: json['related_meal_id'] as String?,
      isReversed: json['is_reversed'] as bool? ?? false,
      completionRate: (json['completion_rate'] as num?)?.toDouble(),
      reversesLogId: json['reverses_log_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'log_id': logId,
      'timestamp': timestamp.toIso8601String(),
      'change_type': changeType.code,
      'change_value': changeValue,
      'vitality_before': vitalityBefore,
      'vitality_after': vitalityAfter,
      'related_meal_id': relatedMealId,
      'is_reversed': isReversed,
      'completion_rate': completionRate,
      'reverses_log_id': reversesLogId,
    };
  }
}
