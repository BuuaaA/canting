package com.canting.canting

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.SharedPreferences
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets

class SharedDataProvider : ContentProvider() {
    override fun onCreate(): Boolean = context != null

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        val appContext = requireNotNull(context).applicationContext
        return when (method) {
            METHOD_SAVE_PET_STATUS -> {
                val json = requireJson(extras, EXTRA_JSON)
                SharedDataStore.savePetStatus(appContext, json)
                PetWidgetProvider.refreshAll(appContext)
                resultBundle()
            }
            METHOD_GET_PET_STATUS -> Bundle().apply {
                putString(EXTRA_JSON, SharedDataStore.getPetStatus(appContext))
            }
            METHOD_SAVE_MEAL_RECORD -> {
                val json = requireJson(extras, EXTRA_JSON)
                val path = SharedDataStore.saveMealRecord(appContext, json)
                resultBundle().apply { putString(EXTRA_PATH, path) }
            }
            METHOD_RECORD_WIDGET_TAP -> {
                SharedDataStore.recordWidgetTap(
                    context = appContext,
                    widgetId = extras?.getInt(EXTRA_WIDGET_ID, -1) ?: -1,
                )
                resultBundle()
            }
            METHOD_GET_LAST_WIDGET_EVENT -> Bundle().apply {
                putString(
                    EXTRA_JSON,
                    SharedDataStore.preferences(appContext)
                        .getString(KEY_LAST_WIDGET_EVENT, null),
                )
            }
            else -> super.call(method, arg, extras) ?: Bundle()
        }
    }

    override fun getType(uri: Uri): String? = null

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(
        uri: Uri,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun requireJson(extras: Bundle?, key: String): String {
        val json = extras?.getString(key)?.takeIf(String::isNotBlank)
            ?: throw IllegalArgumentException("Missing JSON payload")
        JSONObject(json)
        return json
    }

    private fun resultBundle() = Bundle().apply { putBoolean(EXTRA_SUCCESS, true) }

    companion object {
        const val AUTHORITY = "com.canting.app.shareddata"
        val CONTENT_URI: Uri = Uri.parse("content://$AUTHORITY")

        const val METHOD_SAVE_PET_STATUS = "save_pet_status"
        const val METHOD_GET_PET_STATUS = "get_pet_status"
        const val METHOD_SAVE_MEAL_RECORD = "save_meal_record"
        const val METHOD_RECORD_WIDGET_TAP = "record_widget_tap"
        const val METHOD_GET_LAST_WIDGET_EVENT = "get_last_widget_event"

        const val EXTRA_JSON = "json"
        const val EXTRA_PATH = "path"
        const val EXTRA_SUCCESS = "success"
        const val EXTRA_WIDGET_ID = "widget_id"

        const val KEY_LAST_WIDGET_EVENT = "last_widget_event_json"
    }
}

object SharedDataManager {
    fun savePetStatus(context: Context, json: String): Boolean {
        val extras = Bundle().apply {
            putString(SharedDataProvider.EXTRA_JSON, json)
        }
        return context.contentResolver.call(
            SharedDataProvider.CONTENT_URI,
            SharedDataProvider.METHOD_SAVE_PET_STATUS,
            null,
            extras,
        )?.getBoolean(SharedDataProvider.EXTRA_SUCCESS) == true
    }

    fun getPetStatus(context: Context): String? {
        return context.contentResolver.call(
            SharedDataProvider.CONTENT_URI,
            SharedDataProvider.METHOD_GET_PET_STATUS,
            null,
            null,
        )?.getString(SharedDataProvider.EXTRA_JSON)
    }

    fun saveMealRecord(context: Context, json: String): String? {
        val extras = Bundle().apply {
            putString(SharedDataProvider.EXTRA_JSON, json)
        }
        return context.contentResolver.call(
            SharedDataProvider.CONTENT_URI,
            SharedDataProvider.METHOD_SAVE_MEAL_RECORD,
            null,
            extras,
        )?.getString(SharedDataProvider.EXTRA_PATH)
    }

    fun recordWidgetTap(context: Context, widgetId: Int) {
        val extras = Bundle().apply {
            putInt(SharedDataProvider.EXTRA_WIDGET_ID, widgetId)
        }
        context.contentResolver.call(
            SharedDataProvider.CONTENT_URI,
            SharedDataProvider.METHOD_RECORD_WIDGET_TAP,
            null,
            extras,
        )
    }
}

private object SharedDataStore {
    private const val PREFERENCES_NAME = "canting_shared"
    private const val KEY_PET_STATUS = "pet_status_json"
    private const val KEY_WIDGET_TAP_COUNT = "widget_tap_count"
    private const val SHARED_DIRECTORY = "shared"
    private const val MEAL_DIRECTORY = "meals"

    fun preferences(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    fun savePetStatus(context: Context, json: String) {
        preferences(context).edit().putString(KEY_PET_STATUS, json).apply()
    }

    fun getPetStatus(context: Context): String? {
        return preferences(context).getString(KEY_PET_STATUS, null)
    }

    fun saveMealRecord(context: Context, json: String): String {
        val mealId = JSONObject(json).optString("meal_id")
            .replace(Regex("[^a-zA-Z0-9._-]"), "_")
            .take(96)
            .ifBlank { throw IllegalArgumentException("meal_id is required") }
        val directory = File(context.filesDir, "$SHARED_DIRECTORY/$MEAL_DIRECTORY")
            .apply { mkdirs() }
        val destination = File(directory, "$mealId.json")
        val atomicFile = AtomicFile(destination)
        val stream = atomicFile.startWrite()
        try {
            stream.write(json.toByteArray(StandardCharsets.UTF_8))
            stream.flush()
            atomicFile.finishWrite(stream)
        } catch (error: Throwable) {
            atomicFile.failWrite(stream)
            throw error
        }
        return destination.absolutePath
    }

    fun recordWidgetTap(context: Context, widgetId: Int) {
        val preferences = preferences(context)
        val event = JSONObject()
            .put("event", "widget_tap")
            .put("timestamp", System.currentTimeMillis())
            .put("widget_id", widgetId)
            .toString()
        preferences.edit()
            .putString(SharedDataProvider.KEY_LAST_WIDGET_EVENT, event)
            .putInt(
                KEY_WIDGET_TAP_COUNT,
                preferences.getInt(KEY_WIDGET_TAP_COUNT, 0) + 1,
            )
            .apply()
    }
}
