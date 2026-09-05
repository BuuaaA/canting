package com.canting.canting

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import android.view.View
import java.time.ZonedDateTime

data class PetWidgetStatus(
    val recordDate: String? = null,
    val recordOffsetMinutes: Int? = null,
    val vitality: Int = 60,
    val vitalityState: String = "good",
    val todayMealCount: Int = 0,
    val todayCompletionPercent: Int? = null,
    val nextMealSummary: String = "暂无建议",
    val petSpriteName: String? = null,
)

object PetWidgetViews {
    private const val MEDIUM_MIN_WIDTH_DP = 250

    fun build(
        context: Context,
        appWidgetId: Int,
        options: Bundle?,
    ): RemoteViews {
        val status = parseStatus(SharedDataManager.getPetStatus(context))
        val now = ZonedDateTime.now()
        val current = PetWidgetFreshness.isCurrent(
            status.recordDate, status.recordOffsetMinutes,
            now.toLocalDate(), now.offset.totalSeconds / 60,
        )
        val dateLabel = status.recordDate ?: "日期未知"
        val updatePrompt = "打开餐盘更新今日记录"
        val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
        val isMedium = minWidth >= MEDIUM_MIN_WIDTH_DP
        val layoutId = if (isMedium) R.layout.widget_medium else R.layout.widget_small

        return RemoteViews(context.packageName, layoutId).apply {
            bindSprite(this, status.petSpriteName)
            setTextViewText(R.id.widget_vitality, if (current) "活力 ${status.vitality}" else "记录待更新")
            setTextViewText(R.id.widget_vitality_state,
                if (current) "$dateLabel · ${vitalityLabel(status.vitalityState)}" else updatePrompt)
            setOnClickPendingIntent(
                R.id.widget_root,
                widgetTapIntent(context, appWidgetId),
            )

            if (isMedium) {
                setTextViewText(
                    R.id.widget_meal_count,
                    if (current) "$dateLabel · ${status.todayMealCount} 餐" else "记录已过期",
                )
                setTextViewText(
                    R.id.widget_completion,
                    if (current) PetWidgetCompletion.label(status.todayCompletionPercent, status.todayMealCount) else "等待更新",
                )
                setProgressBar(
                    R.id.widget_completion_progress,
                    100,
                    status.todayCompletionPercent ?: 0,
                    false,
                )
                setViewVisibility(
                    R.id.widget_completion_progress,
                    if (!current || status.todayCompletionPercent == null) View.GONE else View.VISIBLE,
                )
                setTextViewText(
                    R.id.widget_next_meal,
                    if (current) "记录时建议 ${status.nextMealSummary}" else updatePrompt,
                )
            }
        }
    }

    internal fun parseStatus(json: String?): PetWidgetStatus {
        if (json.isNullOrBlank()) return PetWidgetStatus()
        return runCatching {
            val value = JSONObject(json)
            val completion = value.optDouble("today_completion_rate", Double.NaN)
            val mealCount = value.optInt("today_meal_count", 0).coerceAtLeast(0)
            PetWidgetStatus(
                recordDate = value.optString("record_date", "").takeIf {
                    runCatching { java.time.LocalDate.parse(it).toString() == it }.getOrDefault(false)
                },
                recordOffsetMinutes = if (value.has("record_utc_offset_minutes") && !value.isNull("record_utc_offset_minutes"))
                    value.optInt("record_utc_offset_minutes", Int.MIN_VALUE) else null,
                vitality = value.optInt("vitality", 60).coerceIn(0, 100),
                vitalityState = value.optString("vitality_state", "good"),
                todayMealCount = mealCount,
                todayCompletionPercent = PetWidgetCompletion.percent(
                    completion,
                    value.optBoolean("structure_complete", true),
                    mealCount,
                ),
                nextMealSummary = value
                    .optString("next_meal_summary", "暂无建议")
                    .trim()
                    .ifBlank { "暂无建议" },
                petSpriteName = value
                    .optString("pet_sprite_name", "")
                    .trim()
                    .ifBlank { null },
            )
        }.getOrDefault(PetWidgetStatus())
    }

    /**
     * Sprite names follow `pet_<type>_<stage>_<state>_<frame>`, matching
     * PetSpriteWidget.assetPath on the Flutter side. The widget always shows
     * frame 0, drawn natively by [PetSpritePainter].
     */
    private fun bindSprite(views: RemoteViews, spriteName: String?) {
        val parts = spriteName?.split("_").orEmpty()
        if (parts.size < 4 || parts[0] != "pet") {
            views.setImageViewResource(
                R.id.widget_sprite,
                R.drawable.widget_pet_placeholder,
            )
            return
        }
        val bitmap = PetSpritePainter.createBitmap(
            petType = parts[1],
            growthStage = parts[2],
            vitalityState = parts[3],
        )
        views.setImageViewBitmap(R.id.widget_sprite, bitmap)
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
