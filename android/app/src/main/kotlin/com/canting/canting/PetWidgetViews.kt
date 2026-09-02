package com.canting.canting

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import kotlin.math.roundToInt

data class PetWidgetStatus(
    val vitality: Int = 60,
    val vitalityState: String = "good",
    val todayMealCount: Int = 0,
    val todayCompletionPercent: Int = 0,
    val nextMealSummary: String = "暂无建议",
)

object PetWidgetViews {
    private const val MEDIUM_MIN_WIDTH_DP = 250

    fun build(
        context: Context,
        appWidgetId: Int,
        options: Bundle?,
    ): RemoteViews {
        val status = parseStatus(SharedDataManager.getPetStatus(context))
        val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
        val isMedium = minWidth >= MEDIUM_MIN_WIDTH_DP
        val layoutId = if (isMedium) R.layout.widget_medium else R.layout.widget_small

        return RemoteViews(context.packageName, layoutId).apply {
            setImageViewResource(R.id.widget_sprite, R.drawable.widget_pet_placeholder)
            setTextViewText(R.id.widget_vitality, "活力 ${status.vitality}")
            setTextViewText(R.id.widget_vitality_state, vitalityLabel(status.vitalityState))
            setOnClickPendingIntent(
                R.id.widget_root,
                widgetTapIntent(context, appWidgetId),
            )

            if (isMedium) {
                setTextViewText(
                    R.id.widget_meal_count,
                    "今天吃了 ${status.todayMealCount} 餐",
                )
                setTextViewText(
                    R.id.widget_completion,
                    "今日完成度 ${status.todayCompletionPercent}%",
                )
                setProgressBar(
                    R.id.widget_completion_progress,
                    100,
                    status.todayCompletionPercent,
                    false,
                )
                setTextViewText(
                    R.id.widget_next_meal,
                    "下一餐 ${status.nextMealSummary}",
                )
            }
        }
    }

    internal fun parseStatus(json: String?): PetWidgetStatus {
        if (json.isNullOrBlank()) return PetWidgetStatus()
        return runCatching {
            val value = JSONObject(json)
            val completion = value.optDouble("today_completion_rate", 0.0)
            PetWidgetStatus(
                vitality = value.optInt("vitality", 60).coerceIn(0, 100),
                vitalityState = value.optString("vitality_state", "good"),
                todayMealCount = value.optInt("today_meal_count", 0).coerceAtLeast(0),
                todayCompletionPercent = (
                    if (completion <= 1.0) completion * 100 else completion
                    ).roundToInt().coerceIn(0, 100),
                nextMealSummary = value
                    .optString("next_meal_summary", "暂无建议")
                    .trim()
                    .ifBlank { "暂无建议" },
            )
        }.getOrDefault(PetWidgetStatus())
    }

    private fun vitalityLabel(state: String): String = when (state) {
        "energetic" -> "元气满满"
        "good" -> "状态不错"
        "low" -> "有点累"
        "expecting" -> "等你投喂"
        else -> "等待更新"
    }

    private fun widgetTapIntent(context: Context, appWidgetId: Int): PendingIntent {
        val intent = Intent(context, PetWidgetProvider::class.java).apply {
            action = PetWidgetProvider.ACTION_WIDGET_TAP
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        return PendingIntent.getBroadcast(
            context,
            appWidgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
