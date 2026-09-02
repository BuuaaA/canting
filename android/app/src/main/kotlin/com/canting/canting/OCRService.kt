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
)

class OCRService(private val context: Context) {
    private var recognizer: TextRecognizer? = null

    val isAvailable: Boolean
        get() = runCatching {
            Class.forName("com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions")
        }.isSuccess

    fun recognize(
        imageUri: Uri,
        onSuccess: (OcrRecognitionResult) -> Unit,
        onFailure: (Exception) -> Unit,
    ) {
        if (!isAvailable) {
            onFailure(IllegalStateException("ML Kit Chinese text recognition is unavailable"))
            return
        }

        val inputImage = runCatching {
            InputImage.fromFilePath(context, imageUri)
        }.getOrElse {
            onFailure(it as? Exception ?: IllegalStateException(it.message, it))
            return
        }

        val client = recognizer ?: TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build(),
        ).also { recognizer = it }

        client.process(inputImage)
            .addOnSuccessListener { text -> onSuccess(toResult(text)) }
            .addOnFailureListener(onFailure)
    }

    fun close() {
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
        )
    }

    companion object {
        private const val ML_KIT_ENGINE = "mlkit_chinese"
    }
}
