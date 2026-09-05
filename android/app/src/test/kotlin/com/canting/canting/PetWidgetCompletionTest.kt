package com.canting.canting

import org.junit.Assert.*
import org.junit.Test

class PetWidgetCompletionTest {
    @Test fun incompleteMealDoesNotBecomeZero() {
        assertNull(PetWidgetCompletion.percent(0.0, false, 1))
        assertEquals("记录不完整", PetWidgetCompletion.label(null, 1))
    }
    @Test fun missingRateRemainsUnknown() {
        assertNull(PetWidgetCompletion.percent(null, true, 1))
        assertNull(PetWidgetCompletion.percent(Double.NaN, true, 1))
        assertNull(PetWidgetCompletion.percent(Double.POSITIVE_INFINITY, true, 1))
    }
    @Test fun emptyDayHasNoCompletionClaim() {
        assertNull(PetWidgetCompletion.percent(0.0, true, 0))
        assertEquals("当日还没有记录", PetWidgetCompletion.label(null, 0))
    }
    @Test fun knownZeroIsDifferentFromUnknown() {
        assertEquals(0, PetWidgetCompletion.percent(0.0, true, 1))
        assertEquals("完成度 0%", PetWidgetCompletion.label(0, 1))
    }
    @Test fun fractionAndLegacyPercentRemainCompatible() {
        assertEquals(75, PetWidgetCompletion.percent(0.75, true, 1))
        assertEquals(75, PetWidgetCompletion.percent(75.0, true, 1))
        assertEquals(100, PetWidgetCompletion.percent(1.0, true, 1))
    }
    @Test fun limitsAreClamped() {
        assertEquals(0, PetWidgetCompletion.percent(-1.0, true, 1))
        assertEquals(100, PetWidgetCompletion.percent(150.0, true, 1))
    }
}
