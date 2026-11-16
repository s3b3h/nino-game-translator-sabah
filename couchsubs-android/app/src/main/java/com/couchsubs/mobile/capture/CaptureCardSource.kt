// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Yalnız Android'in Camera2 arayüzünü kullanır.
package com.couchsubs.mobile.capture

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import com.couchsubs.mobile.remoteplay.DisconnectKind
import com.couchsubs.mobile.remoteplay.FrameSource
import com.couchsubs.mobile.remoteplay.FrameSourceFactory
import com.couchsubs.mobile.remoteplay.SessionState

/** Telefona takılı yakalama kartlarını bulur (izin gerekmez; yalnız kamera listesi okunur). */
object CaptureCards {
    private const val TAG = "NinoCapture"

    fun cameras(manager: CameraManager): List<CameraInfo> = try {
        manager.cameraIdList.mapNotNull { id ->
            try {
                val traits = manager.getCameraCharacteristics(id)
                val facing = traits.get(CameraCharacteristics.LENS_FACING) ?: return@mapNotNull null
                val map = traits.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val sizes = map?.getOutputSizes(ImageFormat.YUV_420_888).orEmpty().map { FrameSize(it.width, it.height) }
                CameraInfo(id, facing, sizes)
            } catch (error: Exception) {
                Log.w(TAG, "kamera $id okunamadı", error)
                null
            }
        }
    } catch (error: Exception) {
        Log.w(TAG, "kamera listesi", error)
        emptyList()
    }

    /** Takılı ve kullanılabilir yakalama kartı (harici kamera); yoksa null. */
    fun find(context: Context): CameraInfo? {
        val manager = context.getSystemService(CameraManager::class.java) ?: return null
        return CaptureCardPicker.pick(cameras(manager))
    }

    fun hasPermission(context: Context) =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /** Çeviri hizmetinin kare kaynağı (PS5 Remote Play oturumunun yerine). */
    val factory = FrameSourceFactory { context, onFrame, onState -> CaptureCardSource(context, onFrame, onState) }
}

/**
 * Yakalama kartından (Camera2'de harici kamera) görüntü okur: 1920x1080 (yoksa en yakın 16:9) YUV_420_888 kareler
 * PS5 oturumundaki gibi bir ImageReader'dan [onFrame]'e verilir (kare yalnız çağrı süresince geçerlidir). Kart
 * çıkarılınca "kart yok" bildirilir, yeniden takılınca kendiliğinden açılır. Görüntü 4 sn simsiyah kalırsa (PS5'te
 * HDCP açık ya da PS5 kapalı) bu da bildirilir.
 */
class CaptureCardSource(
    context: Context,
    private val onFrame: (Image) -> Unit,
    private val onState: (SessionState) -> Unit,
) : FrameSource {
    private companion object {
        const val TAG = "NinoCapture"
        const val BLACK_AFTER_MS = 4000L
        const val BLACK_CHECK_MS = 500L
        const val RETRY_MS = 2000L
    }

    private val app = context.applicationContext
    private val manager = app.getSystemService(CameraManager::class.java)
    private val thread = HandlerThread("Nino capture").apply { start() }
    private val handler = Handler(thread.looper)

    // Aşağıdakiler yalnız [handler] iş parçacığında değişir.
    @Volatile private var running = false
    private var opening = false
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var lastState: SessionState? = null
    private var blackSince = 0L
    private var lastBlackCheck = 0L
    private var blackReported = false
    private var streaming = false
    /** Son başarısız açılış; kapanan kamera hemen "kullanılabilir" bildirildiği için bu süre dolmadan yeniden denenmez. */
    private var failedAt = 0L

    @Volatile override var framesReceived = 0L
        private set

    private val availability = object : CameraManager.AvailabilityCallback() {
        // Kart takılınca (ya da başka uygulama bırakınca) yeniden denenir; open() yalnız harici kamerayı seçer.
        override fun onCameraAvailable(cameraId: String) {
            if (running && device == null && !opening) open()
        }
    }

    override fun start() {
        running = true
        handler.post {
            try { manager?.registerAvailabilityCallback(availability, handler) } catch (error: Exception) { Log.w(TAG, "izleme", error) }
            open()
        }
    }

    override fun dispose() {
        running = false
        handler.post {
            try { manager?.unregisterAvailabilityCallback(availability) } catch (error: Exception) { }
            handler.removeCallbacks(retry)
            closeCamera()
            thread.quitSafely()
        }
    }

    private fun emit(state: SessionState) {
        if (state == lastState) return
        lastState = state
        onState(state)
    }

    private fun open() {
        if (!running || device != null || opening) return
        val wait = failedAt + RETRY_MS - System.currentTimeMillis()
        if (wait > 0) {
            handler.removeCallbacks(retry)
            handler.postDelayed(retry, wait)
            return
        }
        val cameras = manager ?: return emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
        if (!CaptureCards.hasPermission(app)) return emit(SessionState.Disconnected(DisconnectKind.NO_CAMERA_PERMISSION))
        val card = CaptureCardPicker.pick(CaptureCards.cameras(cameras))
            ?: return emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
        val size = CaptureCardPicker.size(card.yuvSizes) ?: return emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
        emit(SessionState.Connecting)
        opening = true
        Log.i(TAG, "Yakalama kartı açılıyor: ${card.id} $size")
        try {
            cameras.openCamera(card.id, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    opening = false
                    if (!running) { camera.close(); return }
                    device = camera
                    startSession(camera, size)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    // Kart çıkarıldı (ya da başka uygulama aldı): takılınca AvailabilityCallback yeniden açar.
                    opening = false
                    camera.close()
                    lost(camera)
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.w(TAG, "kamera hatası $error")
                    opening = false
                    camera.close()
                    lost(camera)
                    handler.postDelayed(retry, RETRY_MS)
                }
            }, handler)
        } catch (error: SecurityException) {
            opening = false
            emit(SessionState.Disconnected(DisconnectKind.NO_CAMERA_PERMISSION))
        } catch (error: CameraAccessException) {
            Log.w(TAG, "kart açılamadı", error)
            opening = false
            failedAt = System.currentTimeMillis()
            emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
            handler.postDelayed(retry, RETRY_MS)
        } catch (error: RuntimeException) {
            Log.w(TAG, "kart açılamadı", error)
            opening = false
            emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
        }
    }

    private val retry = Runnable { open() }

    private fun lost(camera: CameraDevice) {
        failedAt = System.currentTimeMillis()
        if (device === camera || device == null) closeCamera()
        if (running) emit(SessionState.Disconnected(DisconnectKind.NO_CAPTURE_CARD))
    }

    @Suppress("DEPRECATION")
    private fun startSession(camera: CameraDevice, size: FrameSize) {
        val images = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 3)
        reader = images
        images.setOnImageAvailableListener({ source ->
            val image = try {
                source.acquireLatestImage()
            } catch (error: IllegalStateException) {
                null
            } ?: return@setOnImageAvailableListener
            framesReceived++
            try {
                watchPicture(image)
                onFrame(image)
            } catch (error: RuntimeException) {
                Log.e(TAG, "frame handler", error)
            } finally {
                image.close()
            }
        }, handler)
        try {
            // Android 9 öncesinde de çalışsın diye eski imza (SessionConfiguration 28+).
            camera.createCaptureSession(listOf(images.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(configured: CameraCaptureSession) {
                    if (!running || device !== camera) { configured.close(); return }
                    session = configured
                    try {
                        val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply { addTarget(images.surface) }
                        configured.setRepeatingRequest(request.build(), null, handler)
                        Log.i(TAG, "Yakalama kartı akışı başladı: $size")
                    } catch (error: Exception) {
                        Log.w(TAG, "akış başlatılamadı", error)
                        lost(camera)
                    }
                }

                override fun onConfigureFailed(failed: CameraCaptureSession) {
                    Log.w(TAG, "oturum kurulamadı ($size)")
                    lost(camera)
                }
            }, handler)
        } catch (error: Exception) {
            Log.w(TAG, "oturum", error)
            lost(camera)
        }
    }

    /** İlk karede "akış"; görüntü 4 sn simsiyah kalırsa "siyah görüntü", geri gelince yeniden "akış". */
    private fun watchPicture(image: Image) {
        val now = System.currentTimeMillis()
        if (!streaming) {
            streaming = true
            emit(SessionState.Streaming)
        }
        if (now - lastBlackCheck < BLACK_CHECK_MS) return
        lastBlackCheck = now
        val plane = image.planes[0]
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val limit = buffer.limit()
        val black = BlackFrame.isBlack(image.width, image.height) { x, y ->
            val index = y * rowStride + x * pixelStride
            if (index < limit) buffer.get(index).toInt() and 0xff else 0
        }
        if (!black) {
            blackSince = 0L
            if (blackReported) {
                blackReported = false
                emit(SessionState.Streaming)
            }
            return
        }
        if (blackSince == 0L) blackSince = now
        if (!blackReported && now - blackSince >= BLACK_AFTER_MS) {
            blackReported = true
            emit(SessionState.Disconnected(DisconnectKind.BLACK_PICTURE))
        }
    }

    private fun closeCamera() {
        try { session?.close() } catch (error: Exception) { }
        session = null
        try { device?.close() } catch (error: Exception) { }
        device = null
        try { reader?.close() } catch (error: Exception) { }
        reader = null
        streaming = false
        blackSince = 0L
        blackReported = false
    }
}
