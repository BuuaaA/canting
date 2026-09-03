package com.canting.canting

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint

/**
 * Renders the pixel pet as a [Bitmap] for the home-screen widget.
 *
 * Mirrors the 16x16 grid drawing in
 * lib/pet/widgets/pet_sprite_widget.dart (_PixelPetPainter): the widget cannot
 * use Flutter's CustomPainter, so the same pixel rectangles are drawn natively.
 */
object PetSpritePainter {
    private const val OUTLINE = 0xFF4E3524.toInt()
    private const val CREAM = 0xFFFFE7AD.toInt()
    private const val BLUSH = 0xFFE98A6A.toInt()
    private const val SHADOW = 0x55332B24
    private const val WHITE = 0xFFFFFFFF.toInt()
    private const val EGG_GREEN = 0xFF78A554.toInt()
    private const val EGG_RED = 0xFFC75B45.toInt()
    private const val SPARKLE = 0xFFF2C66D.toInt()

    fun createBitmap(
        petType: String,
        growthStage: String,
        vitalityState: String,
        unitPx: Int = 12,
    ): Bitmap {
        val size = 16 * unitPx
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint().apply {
            isAntiAlias = false
            style = Paint.Style.FILL
        }

        fun rect(x: Int, y: Int, w: Int, h: Int, color: Int) {
            paint.color = color
            canvas.drawRect(
                (x * unitPx).toFloat(),
                (y * unitPx).toFloat(),
                ((x + w) * unitPx).toFloat(),
                ((y + h) * unitPx).toFloat(),
                paint,
            )
        }

        rect(3, 14, 10, 1, SHADOW)
        if (growthStage == "egg") {
            rect(6, 2, 4, 1, OUTLINE)
            rect(4, 3, 8, 2, OUTLINE)
            rect(3, 5, 10, 6, OUTLINE)
            rect(4, 11, 8, 2, OUTLINE)
            rect(6, 13, 4, 1, OUTLINE)
            rect(6, 3, 4, 1, CREAM)
            rect(5, 4, 6, 2, CREAM)
            rect(4, 6, 8, 5, CREAM)
            rect(5, 11, 6, 1, CREAM)
            rect(5, 6, 2, 2, EGG_GREEN)
            rect(9, 9, 2, 2, EGG_RED)
            return bitmap
        }

        val base = petColor(petType, vitalityState)
        val light = lerpColor(base, WHITE, 0.28f)
        val dark = lerpColor(base, OUTLINE, 0.22f)
        val isAdult = growthStage == "adult"

        when (petType) {
            "cat" -> {
                rect(3, 2, 3, 3, OUTLINE)
                rect(10, 2, 3, 3, OUTLINE)
                rect(4, 3, 2, 2, base)
                rect(10, 3, 2, 2, base)
                rect(12, 10, 2, 1, OUTLINE)
                rect(13, 8, 1, 3, OUTLINE)
                rect(12, 8, 1, 1, base)
            }
            "dog" -> {
                rect(2, 4, 3, 5, OUTLINE)
                rect(11, 4, 3, 5, OUTLINE)
                rect(3, 5, 2, 3, dark)
                rect(11, 5, 2, 3, dark)
                rect(13, 11, 2, 2, OUTLINE)
                rect(13, 10, 1, 1, base)
            }
            else -> {
                rect(3, 3, 3, 3, OUTLINE)
                rect(10, 3, 3, 3, OUTLINE)
                rect(4, 4, 1, 1, BLUSH)
                rect(11, 4, 1, 1, BLUSH)
            }
        }

        rect(3, 4, 10, 8, OUTLINE)
        rect(4, 5, 8, 6, base)
        rect(5, 10, 6, 4, OUTLINE)
        rect(6, 10, 4, 3, dark)
        if (isAdult) {
            rect(3, 11, 2, 3, OUTLINE)
            rect(11, 11, 2, 3, OUTLINE)
            rect(4, 11, 1, 2, base)
            rect(11, 11, 1, 2, base)
        }

        rect(5, 5, 6, 1, light)
        val tired = vitalityState == "low" || vitalityState == "expecting"
        if (tired) {
            rect(5, 7, 2, 1, OUTLINE)
            rect(9, 7, 2, 1, OUTLINE)
        } else {
            rect(5, 7, 2, 2, OUTLINE)
            rect(9, 7, 2, 2, OUTLINE)
            rect(5, 7, 1, 1, WHITE)
            rect(9, 7, 1, 1, WHITE)
        }
        rect(7, 9, 2, 1, OUTLINE)
        rect(6, 10, 1, 1, BLUSH)
        rect(10, 10, 1, 1, BLUSH)

        if (vitalityState == "energetic") {
            rect(1, 2, 1, 2, SPARKLE)
            rect(14, 3, 1, 2, SPARKLE)
        }

        return bitmap
    }

    private fun petColor(petType: String, vitalityState: String): Int {
        val base = when (petType) {
            "cat" -> 0xFFE59A57.toInt()
            "dog" -> 0xFFD8AF68.toInt()
            else -> 0xFFC99069.toInt()
        }
        return when (vitalityState) {
            "energetic" -> base
            "good" -> lerpColor(base, 0xFF78A554.toInt(), 0.12f)
            "low" -> lerpColor(base, 0xFF7C91A4.toInt(), 0.36f)
            else -> lerpColor(base, 0xFF9B8AA7.toInt(), 0.28f)
        }
    }

    private fun lerpColor(from: Int, to: Int, t: Float): Int {
        fun channel(start: Int, end: Int): Int =
            (start + (end - start) * t).toInt().coerceIn(0, 255)
        return Color.argb(
            channel(Color.alpha(from), Color.alpha(to)),
            channel(Color.red(from), Color.red(to)),
            channel(Color.green(from), Color.green(to)),
            channel(Color.blue(from), Color.blue(to)),
        )
    }
}
