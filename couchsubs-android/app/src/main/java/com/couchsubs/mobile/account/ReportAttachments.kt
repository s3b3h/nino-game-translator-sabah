// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.account

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Process
import java.io.ByteArrayOutputStream

/** "Sorun Bildir"in Android'e bağlı parçaları: seçilen fotoğrafı JPEG'e çevirip küçültmek ve uygulamanın günlüğü. */
object ReportAttachments {
    /**
     * Fotoğraf seçicinin verdiği görüntüyü (JPEG, PNG, HEIC…) çözer, EXIF yönünü düzeltir, uzun kenarı en çok 1600 px
     * ve en çok [maxBytes] (varsayılan [ProblemReport.MAX_IMAGE_BYTES]) olan JPEG'e çevirir. Ağır iş: arka planda çağrılmalı. Çözülemezse null.
     */
    fun loadImage(context: Context, uri: Uri, maxBytes: Int = ProblemReport.MAX_IMAGE_BYTES): ByteArray? = try {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) null
        else {
            val options = BitmapFactory.Options().apply { inSampleSize = ProblemReport.sampleSize(bounds.outWidth, bounds.outHeight) }
            val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            decoded?.let { bitmap ->
                val rotation = resolver.openInputStream(uri)?.use { exifRotation(ExifInterface(it)) } ?: 0
                val upright = if (rotation == 0) bitmap
                    else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postRotate(rotation.toFloat()) }, true)
                try {
                    ProblemReport.fitJpeg(upright.width, upright.height, maxBytes) { width, height, quality ->
                        val scaled = if (width == upright.width && height == upright.height) upright
                            else Bitmap.createScaledBitmap(upright, width, height, true)
                        val out = ByteArrayOutputStream()
                        scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
                        if (scaled !== upright) scaled.recycle()
                        out.toByteArray()
                    }
                } finally {
                    if (upright !== bitmap) upright.recycle()
                    bitmap.recycle()
                }
            }
        }
    } catch (error: Exception) {
        null
    } catch (error: OutOfMemoryError) {
        null
    }

    private fun exifRotation(exif: ExifInterface): Int = when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
        ExifInterface.ORIENTATION_ROTATE_90 -> 90
        ExifInterface.ORIENTATION_ROTATE_180 -> 180
        ExifInterface.ORIENTATION_ROTATE_270 -> 270
        else -> 0
    }

    /**
     * Uygulamanın kendi günlüğü (logcat; Android uygulamaya yalnız kendi satırlarını verir), anahtar ve jetonlar
     * gizlenmiş, son 60 000 karakter. Okunamazsa null. Arka planda çağrılmalı.
     */
    fun recentLog(): String? = try {
        val process = ProcessBuilder("logcat", "-d", "-v", "threadtime", "-t", "3000", "--pid=${Process.myPid()}")
            .redirectErrorStream(true).start()
        val text = process.inputStream.bufferedReader().use { it.readText() }
        process.waitFor()
        text.takeIf { it.isNotBlank() }?.let(ProblemReport::scrubLog)
    } catch (error: Exception) {
        null
    }
}
