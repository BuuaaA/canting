package com.canting.canting

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (intent?.action != Intent.ACTION_SEND ||
            intent.type?.startsWith("image/") != true
        ) {
            finish()
            return
        }

        val sourceUri = sharedImageUri(intent)
        if (sourceUri == null) {
            Toast.makeText(this, "没有找到可识别的图片", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        runCatching { copyToAppCache(sourceUri) }
            .onSuccess(::openRecognitionPage)
            .onFailure {
                Toast.makeText(this, "图片读取失败，请重试", Toast.LENGTH_SHORT).show()
            }
        finish()
    }

    private fun copyToAppCache(sourceUri: Uri): Uri {
        val directory = File(cacheDir, SHARED_IMAGE_DIRECTORY).apply { mkdirs() }
        val extension = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(contentResolver.getType(sourceUri))
            ?.takeIf { it.matches(Regex("[a-zA-Z0-9]+")) }
            ?: "jpg"
        val destination = File(directory, "${UUID.randomUUID()}.$extension")

        contentResolver.openInputStream(sourceUri).use { input ->
            requireNotNull(input) { "The shared image cannot be opened" }
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                var totalBytes = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    totalBytes += count
                    require(totalBytes <= MAX_IMAGE_BYTES) {
                        "The shared image exceeds the supported size"
                    }
                    output.write(buffer, 0, count)
                }
            }
        }

        return FileProvider.getUriForFile(
            this,
            FILE_PROVIDER_AUTHORITY,
            destination,
        )
    }

    private fun openRecognitionPage(imageUri: Uri) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_OPEN_SHARED_IMAGE
            putExtra(EXTRA_SHARED_IMAGE_URI, imageUri.toString())
            clipData = ClipData.newUri(contentResolver, "shared meal image", imageUri)
            addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        startActivity(launchIntent)
    }

    @Suppress("DEPRECATION")
    private fun sharedImageUri(sourceIntent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            sourceIntent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
        }
    }

    companion object {
        const val ACTION_OPEN_SHARED_IMAGE = "com.canting.canting.OPEN_SHARED_IMAGE"
        const val EXTRA_SHARED_IMAGE_URI = "shared_image_uri"
        const val FILE_PROVIDER_AUTHORITY = "com.canting.fileprovider"

        private const val SHARED_IMAGE_DIRECTORY = "shared_images"
        private const val MAX_IMAGE_BYTES = 25L * 1024L * 1024L
    }
}
