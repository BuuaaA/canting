package com.canting.canting

import kotlin.math.roundToInt

/** Preserve unknown instead of turning missing structure into a measured zero. */
internal object PetWidgetCompletion {
    fun percent(rate: Double?, structureComplete: Boolean, mealCount: Int): Int? {
        if (!structureComplete || mealCount <= 0 || rate == null || !rate.isFinite()) return null
        return (if (rate <= 1.0) rate * 100 else rate).roundToInt().coerceIn(0, 100)
    }

    fun label(percent: Int?, mealCount: Int): String = when {
        mealCount <= 0 -> "当日还没有记录"
        percent == null -> "记录不完整"
        else -> "完成度 $percent%"
    }
}
