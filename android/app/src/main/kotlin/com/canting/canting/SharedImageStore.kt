package com.canting.canting

import android.content.Context
import android.net.Uri
import java.io.File

/** Owns only direct FileProvider cache children; never album paths or symlinks. */
object SharedImageStore {
    private val active = mutableMapOf<String, Int>()
    private fun owned(context: Context, uri: Uri): File? {
        if (uri.scheme != "content" || uri.authority != ShareActivity.FILE_PROVIDER_AUTHORITY ||
            uri.query != null || uri.fragment != null) return null
        val parts = uri.pathSegments
        if (parts.size != 2 || parts[0] != "shared_images" ||
            !parts[1].matches(Regex("[a-zA-Z0-9._-]+")) || parts[1] in listOf(".", "..")) return null
        val directory = File(context.cacheDir.canonicalFile, "shared_images")
        if (directory.absolutePath != directory.canonicalPath) return null
        val root = directory.canonicalFile
        val file = File(root, parts[1])
        return file.takeIf { it.canonicalFile.parentFile == root && it.absolutePath == it.canonicalPath }
    }
    @Synchronized fun retain(context: Context, uri: Uri) {
        val file = owned(context, uri) ?: return
        active[file.path] = (active[file.path] ?: 0) + 1
    }
    @Synchronized fun release(context: Context, uri: Uri, finished: Boolean = false) {
        val file = owned(context, uri) ?: return
        if (finished) {
            val count = (active[file.path] ?: 1) - 1
            if (count <= 0) active.remove(file.path) else active[file.path] = count
        }
        if (!active.containsKey(file.path)) file.delete()
    }
    @Synchronized fun sweep(context: Context) {
        val directory = File(context.cacheDir.canonicalFile, "shared_images")
        if (directory.absolutePath != directory.canonicalPath) return
        val root = directory.canonicalFile
        // At most 100 stale copies per entry; files younger than 24h may await handoff.
        root.listFiles()?.asSequence()?.filter {
            it.isFile && it.canonicalFile.parentFile == root && it.absolutePath == it.canonicalPath &&
                !active.containsKey(it.path) && System.currentTimeMillis() - it.lastModified() > 86400000L
        }?.take(100)?.forEach { it.delete() }
    }
}
