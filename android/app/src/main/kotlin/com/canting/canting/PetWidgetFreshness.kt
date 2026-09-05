package com.canting.canting

import java.time.LocalDate

/** Local calendar day is the business date. Missing metadata fails closed.
 * A timezone-offset change invalidates even a same-day snapshot; opening the
 * app recomputes it. A clock rollback to another date also invalidates it.
 */
internal object PetWidgetFreshness {
    fun isCurrent(date: String?, offsetMinutes: Int?, today: LocalDate, currentOffsetMinutes: Int): Boolean {
        if (date == null || offsetMinutes != currentOffsetMinutes) return false
        return date == today.toString()
    }
}
