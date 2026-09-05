package com.canting.canting

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions

data class OcrLine(
    val text: String,
    val left: Int?,
    val top: Int?,
    val right: Int?,
    val bottom: Int?,
)

data class OcrRecognitionResult(
    val fullText: String,
    val lines: List<OcrLine>,
    val merchant: String,
    val dishes: List<ExtractedDish>,
    val engine: String,
    val warnings: List<String>,
)

class OCRService(private val context: Context) {
    private var recognizer: TextRecognizer? = null
    private var inFlight = 0
    private var closing = false

    val isAvailable: Boolean
        get() = runCatching {
            Class.forName("com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions")
        }.isSuccess

    fun recognize(
        imageUri: Uri,
        onSuccess: (OcrRecognitionResult) -> Unit,
        onFailure: (Exception) -> Unit,
    ) {
        SharedImageStore.sweep(context)
        SharedImageStore.retain(context, imageUri)
        fun failed(error: Exception) {
            SharedImageStore.release(context, imageUri, finished = true)
            onFailure(error)
        }
        if (closing || !isAvailable) {
            failed(IllegalStateException("ML Kit Chinese text recognition is unavailable"))
            return
        }

        val inputImage = runCatching {
            InputImage.fromFilePath(context, imageUri)
        }.getOrElse {
            failed(it as? Exception ?: IllegalStateException(it.message, it))
            return
        }

        val client = runCatching { recognizer ?: TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build(),
        ).also { recognizer = it } }.getOrElse {
            failed(it as? Exception ?: IllegalStateException(it))
            return
        }

        inFlight++
        try {
            client.process(inputImage).addOnCompleteListener { task ->
                try {
                    if (task.isSuccessful) onSuccess(toResult(task.result))
                    else onFailure(task.exception ?: IllegalStateException("OCR failed"))
                } finally {
                    SharedImageStore.release(context, imageUri, finished = true)
                    inFlight--
                    if (closing && inFlight == 0) closeClient()
                }
            }
        } catch (error: Exception) {
            inFlight--
            failed(error)
        }
    }

    fun close() {
        closing = true
        if (inFlight == 0) closeClient()
    }

    private fun closeClient() {
        recognizer?.close()
        recognizer = null
    }

    private fun toResult(recognizedText: Text): OcrRecognitionResult {
        val lines = recognizedText.textBlocks
            .flatMap { block -> block.lines }
            .map { line ->
                val bounds = line.boundingBox
                OcrLine(
                    text = line.text.trim(),
                    left = bounds?.left,
                    top = bounds?.top,
                    right = bounds?.right,
                    bottom = bounds?.bottom,
                )
            }
            .filter { it.text.isNotEmpty() }
        val extracted = DishNameExtractor.extract(lines.map(OcrLine::text))
        return OcrRecognitionResult(
            fullText = recognizedText.text,
            lines = lines,
            merchant = extracted.merchant,
            dishes = extracted.dishes,
            engine = ML_KIT_ENGINE,
            warnings = extracted.warnings,
        )
    }

    companion object {
        private const val ML_KIT_ENGINE = "mlkit_chinese"
    }
}
