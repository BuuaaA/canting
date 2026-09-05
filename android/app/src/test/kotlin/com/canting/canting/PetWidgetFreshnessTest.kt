package com.canting.canting

import java.time.LocalDate
import org.junit.Assert.*
import org.junit.Test

class PetWidgetFreshnessTest {
    private val day = LocalDate.of(2026, 9, 5)
    @Test fun sameDateAndZoneIsCurrent() {
        assertTrue(PetWidgetFreshness.isCurrent("2026-09-05", 480, day, 480))
    }
    @Test fun midnightExpiresYesterday() {
        assertFalse(PetWidgetFreshness.isCurrent("2026-09-04", 480, day, 480))
    }
    @Test fun legacyOrMissingMetadataExpires() {
        assertFalse(PetWidgetFreshness.isCurrent(null, null, day, 480))
        assertFalse(PetWidgetFreshness.isCurrent("2026-09-05", null, day, 480))
        assertFalse(PetWidgetFreshness.isCurrent("", 480, day, 480))
    }
    @Test fun malformedDateExpires() {
        assertFalse(PetWidgetFreshness.isCurrent("2026-02-30", 480, day, 480))
        assertFalse(PetWidgetFreshness.isCurrent("2026-9-5", 480, day, 480))
    }
    @Test fun clockRollbackExpiresFutureSnapshot() {
        assertFalse(PetWidgetFreshness.isCurrent("2026-09-06", 480, day, 480))
    }
    @Test fun timezoneChangeExpiresEvenOnSameDate() {
        assertFalse(PetWidgetFreshness.isCurrent("2026-09-05", 480, day, 540))
        assertFalse(PetWidgetFreshness.isCurrent("2026-09-04", -420, day, 480))
    }
}
