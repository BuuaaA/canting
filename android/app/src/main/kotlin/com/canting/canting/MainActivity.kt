package com.canting.canting

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var ocrChannel: MethodChannel? = null
    private var petChannel: MethodChannel? = null
    private var ocrService: OCRService? = null
    private var pendingSharedImageUri: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        captureSharedImage(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedImage" -> result.success(pendingSharedImageUri)
                    "acknowledgeSharedImage" -> {
                        val acknowledgedUri = call.argument<String>("imageUri")
                        if (acknowledgedUri == pendingSharedImageUri) {
                            pendingSharedImageUri = null
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        SharedImageStore.sweep(applicationContext)
        ocrService = OCRService(applicationContext)
        ocrChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OCR_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognizeImage" -> recognizeImage(
                        call.argument<String>("imageUri"),
                        result,
                    )
                    "releaseImage" -> {
                        call.argument<String>("imageUri")?.let { SharedImageStore.release(applicationContext, Uri.parse(it)) }
                        result.success(null)
                    }
                    "getOcrStatus" -> result.success(
                        mapOf(
                            "available" to (ocrService?.isAvailable == true),
                            "engine" to "mlkit_chinese",
                            "offline" to true,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
        }
        petChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PET_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePetStatus" -> savePetStatus(
                        call.argument<String>("json"),
                        result,
                    )
                    "saveMealRecord" -> saveMealRecord(
                        call.argument<String>("json"),
                        result,
                    )
                    "getShareExtensionStatus" -> result.success(
                        mapOf(
                            "available" to true,
                            "mimeTypes" to listOf("image/*"),
                            "fileProviderAuthority" to ShareActivity.FILE_PROVIDER_AUTHORITY,
                        ),
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val imageUri = captureSharedImage(intent) ?: return
        shareChannel?.invokeMethod(
            "onSharedImage",
            mapOf("imageUri" to imageUri),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        ocrChannel?.setMethodCallHandler(null)
        ocrChannel = null
        petChannel?.setMethodCallHandler(null)
        petChannel = null
        ocrService?.close()
        ocrService = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun savePetStatus(json: String?, result: MethodChannel.Result) {
        if (json.isNullOrBlank()) {
            result.error("INVALID_PET_STATUS", "Pet status JSON is required", null)
            return
        }
        runCatching { SharedDataManager.savePetStatus(applicationContext, json) }
            .onSuccess(result::success)
            .onFailure {
                result.error(
                    "PET_STATUS_SAVE_FAILED",
                    it.message ?: "Could not save pet status",
                    it.javaClass.simpleName,
                )
            }
    }

    private fun saveMealRecord(json: String?, result: MethodChannel.Result) {
        if (json.isNullOrBlank()) {
            result.error("INVALID_MEAL_RECORD", "Meal record JSON is required", null)
            return
        }
        runCatching { SharedDataManager.saveMealRecord(applicationContext, json) }
            .onSuccess(result::success)
            .onFailure {
                result.error(
                    "MEAL_RECORD_SAVE_FAILED",
                    it.message ?: "Could not save meal record",
                    it.javaClass.simpleName,
                )
            }
    }

    private fun recognizeImage(imageUriValue: String?, result: MethodChannel.Result) {
        val imageUri = imageUriValue
            ?.let(Uri::parse)
            ?.takeIf {
                it.scheme == "content" &&
                    it.authority == ShareActivity.FILE_PROVIDER_AUTHORITY
            }
        if (imageUri == null) {
            result.error("INVALID_IMAGE_URI", "A valid shared image URI is required", null)
            return
        }

        val service = ocrService
        if (service == null) {
            result.error("OCR_UNAVAILABLE", "The OCR service is not initialized", null)
            return
        }
        service.recognize(
            imageUri = imageUri,
            onSuccess = { recognition ->
                result.success(
                    mapOf(
                        "fullText" to recognition.fullText,
                        "engine" to recognition.engine,
                        "merchant" to recognition.merchant,
                        "warnings" to recognition.warnings,
                        "lines" to recognition.lines.map { line ->
                            mapOf(
                                "text" to line.text,
                                "left" to line.left,
                                "top" to line.top,
                                "right" to line.right,
                                "bottom" to line.bottom,
                            )
                        },
                        "dishes" to recognition.dishes.map { dish ->
                            mapOf(
                                "name" to dish.name,
                                "quantity" to dish.quantity,
                                "requiresConfirmation" to dish.requiresConfirmation,
                            )
                        },
                    ),
                )
            },
            onFailure = { error ->
                result.error(
                    "OCR_FAILED",
                    error.message ?: "Text recognition failed",
                    error.javaClass.simpleName,
                )
            },
        )
    }

    private fun captureSharedImage(sourceIntent: Intent?): String? {
        if (sourceIntent?.action != ShareActivity.ACTION_OPEN_SHARED_IMAGE) {
            return null
        }
        val imageUri = sourceIntent.getStringExtra(ShareActivity.EXTRA_SHARED_IMAGE_URI)
            ?.takeIf { it.startsWith("content://${ShareActivity.FILE_PROVIDER_AUTHORITY}/") }
            ?: return null
        pendingSharedImageUri = imageUri
        return imageUri
    }

    companion object {
        private const val SHARE_CHANNEL = "com.canting.app/share"
        private const val OCR_CHANNEL = "com.canting.app/ocr"
        private const val PET_CHANNEL = "com.canting.app/pet"
    }
}
