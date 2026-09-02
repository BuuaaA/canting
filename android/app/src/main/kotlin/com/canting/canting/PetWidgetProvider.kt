package com.canting.canting

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle

class PetWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId, newOptions)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_WIDGET_TAP) {
            val widgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            )
            SharedDataManager.recordWidgetTap(context, widgetId)
            context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                ?.let(context::startActivity)
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        const val ACTION_WIDGET_TAP = "com.canting.canting.action.WIDGET_TAP"

        fun refreshAll(context: Context) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val component = ComponentName(appContext, PetWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(component)
            widgetIds.forEach { widgetId ->
                updateWidget(appContext, manager, widgetId)
            }
            notifyDataChanged(manager, widgetIds)
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            options: Bundle? = null,
        ) {
            val resolvedOptions = options ?: manager.getAppWidgetOptions(widgetId)
            manager.updateAppWidget(
                widgetId,
                PetWidgetViews.build(context, widgetId, resolvedOptions),
            )
        }

        @Suppress("DEPRECATION")
        private fun notifyDataChanged(
            manager: AppWidgetManager,
            widgetIds: IntArray,
        ) {
            if (widgetIds.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(widgetIds, R.id.widget_root)
            }
        }
    }
}
