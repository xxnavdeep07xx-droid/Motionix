package com.motionix.motionix

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Motionix media bridge (Phase 1).
 *
 * Everything pixel-heavy is delegated to Media3 Transformer, which drives
 * the hardware codecs: the CPU never touches frame data, which is exactly
 * the discipline the 4 GB target demands.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val METHODS = "motionix/media"
        private const val PROGRESS = "motionix/progress"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioPool = Executors.newSingleThreadExecutor()

    private var progressSink: EventChannel.EventSink? = null
    private var activeTransformer: Transformer? = null
    private var activeStage: String? = null
    @Volatile private var pollGeneration = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    progressSink = sink
                }
                override fun onCancel(args: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "deviceInfo" -> result.success(deviceInfo())
                        "probe" -> ioProbe(call.argument<String>("path")!!, result)
                        "thumbnails" -> ioThumbnails(
                            call.argument<String>("path")!!,
                            call.argument<Int>("count") ?: 12,
                            call.argument<Int>("height") ?: 128,
                            result)
                        "buildProxy" -> buildProxy(
                            call.argument<String>("src")!!,
                            call.argument<String>("out")!!,
                            call.argument<Int>("height") ?: 720,
                            call.argument<Long>("videoBitrate") ?: 4_000_000L,
                            call.argument<Long>("audioBitrate") ?: 128_000L,
                            result)
                        "exportTrim" -> exportTrim(
                            call.argument<String>("src")!!,
                            call.argument<String>("out")!!,
                            call.argument<Long>("startUs") ?: 0L,
                            call.argument<Long>("endUs") ?: Long.MAX_VALUE,
                            call.argument<Int>("height") ?: 1080,
                            result)
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NATIVE", e.message ?: e.toString(), null)
                }
            }
    }

    // ---------------------------------------------------------------- device

    private fun deviceInfo(): Map<String, Any?> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val isLowRam = if (Build.VERSION.SDK_INT >= 19) am.isLowRamDevice else false
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        return mapOf(
            "memoryClass" to am.memoryClass,
            "totalRamMb" to (mi.totalMem / (1024.0 * 1024.0)).roundToInt(),
            "isLowRamDevice" to isLowRam,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "androidSdk" to Build.VERSION.SDK_INT,
            "model" to Build.MODEL
        )
    }

    // ----------------------------------------------------------------- probe

    /** Probe on the IO pool; replies on the main thread. */
    private fun ioProbe(path: String, result: MethodChannel.Result) {
        ioPool.execute {
            val info = try { probeSync(path) } catch (e: Exception) { null }
            mainHandler.post {
                if (info != null) result.success(info)
                else result.error("PROBE", "could not read $path", null)
            }
        }
    }

    private fun probeSync(path: String): Map<String, Any?> {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) { val t = w; w = h; h = t }

            val durMs = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val hasAudio = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            val (fpsNum, fpsDen) = probeFps(path)

            return mapOf(
                "width" to w, "height" to h, "rotation" to rotation,
                "durationUs" to durMs * 1000, "hasAudio" to hasAudio,
                "fpsNum" to fpsNum, "fpsDen" to fpsDen
            )
        } finally {
            r.release()
        }
    }

    /**
     * Read the declared frame rate from the video track via MediaExtractor.
     * (MediaMetadataRetriever#METADATA_KEY_FRAME_COUNT is not public API on
     * recent SDKs, and phone footage is often variable-rate anyway — the
     * container-declared rate is the honest editing basis.)
     */
    private fun probeFps(path: String): Pair<Long, Long> {
        try {
            val ex = MediaExtractor()
            try {
                ex.setDataSource(path)
                for (i in 0 until ex.trackCount) {
                    val fmt = ex.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                    if (!mime.startsWith("video/")) continue
                    if (fmt.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        val fps = try {
                            fmt.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                        } catch (e: ClassCastException) {
                            fmt.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
                        }
                        if (fps > 0.0) return snapFps(fps)
                    }
                }
            } finally {
                ex.release()
            }
        } catch (_: Exception) {
        }
        return 30L to 1L
    }

    /** Snap measured fps onto the canonical rates editors expect. */
    private fun snapFps(fps: Double): Pair<Long, Long> {
        val ints = listOf(24L, 25L, 30L, 48L, 50L, 60L)
        for (i in ints) if (abs(fps - i) < 0.15) return i to 1L
        val ntsc = listOf(24000L to 1001L, 30000L to 1001L, 60000L to 1001L)
        for ((n, d) in ntsc) if (abs(fps - n.toDouble() / d) < 0.15) return n to d
        return fps.roundToInt().toLong().coerceAtLeast(1L) to 1L
    }

    // ----------------------------------------------------------- thumbnails

    private fun ioThumbnails(path: String, count: Int, height: Int,
                             result: MethodChannel.Result) {
        ioPool.execute {
            try {
                val r = MediaMetadataRetriever()
                val files = mutableListOf<String>()
                try {
                    r.setDataSource(path)
                    val durUs = (r.extractMetadata(
                        MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000
                    val dir = File(cacheDir, "thumbs_${UUID.randomUUID()}")
                    dir.mkdirs()
                    for (i in 0 until count) {
                        val us = durUs * i / count
                        val bmp: Bitmap? =
                            r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        if (bmp == null) continue
                        val f = File(dir, "t$i.jpg")
                        FileOutputStream(f).use { out ->
                            if (bmp.height > height) {
                                val scale = height.toFloat() / bmp.height
                                val w = (bmp.width * scale).toInt().coerceAtLeast(1)
                                val small = Bitmap.createScaledBitmap(bmp, w, height, true)
                                small.compress(Bitmap.CompressFormat.JPEG, 72, out)
                                small.recycle()
                            } else {
                                bmp.compress(Bitmap.CompressFormat.JPEG, 72, out)
                            }
                        }
                        bmp.recycle()
                        files.add(f.absolutePath)
                    }
                } finally {
                    r.release()
                }
                mainHandler.post { result.success(files) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("THUMBS", e.message ?: e.toString(), null)
                }
            }
        }
    }

    // ---------------------------------------------------------- transformer

    private fun emit(stage: String, vararg pairs: Pair<String, Any?>) {
        val map = HashMap<String, Any?>()
        map["stage"] = stage
        for ((k, v) in pairs) map[k] = v
        mainHandler.post { progressSink?.success(map) }
    }

    private fun runTransformer(stage: String, outPath: String, item: EditedMediaItem,
                               onDone: () -> Unit) {
        if (activeTransformer != null) {
            emit(stage, "error" to "another $activeStage operation is already running")
            return
        }
        val transformer = Transformer.Builder(this)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    activeTransformer = null; activeStage = null; pollGeneration++
                    emit(stage, "percent" to 100, "done" to true, "path" to outPath)
                    onDone()
                }
                override fun onError(composition: Composition, exportResult: ExportResult,
                                     exception: ExportException) {
                    activeTransformer = null; activeStage = null; pollGeneration++
                    emit(stage, "error" to (exception.message ?: "transform failed"))
                }
            })
            .build()
        activeTransformer = transformer
        activeStage = stage
        File(outPath).parentFile?.mkdirs()

        // Progress is polled (media3 has no push-based progress callback).
        val gen = ++pollGeneration
        transformer.start(item, outPath)
        thread(isDaemon = true, name = "motionix-progress") {
            val holder = ProgressHolder()
            while (pollGeneration == gen) {
                try {
                    val state = transformer.getProgress(holder)
                    if (state == Transformer.PROGRESS_STATE_AVAILABLE &&
                        holder.progress in 0..100) {
                        emit(stage, "percent" to holder.progress)
                    }
                } catch (_: Exception) {
                }
                Thread.sleep(250)
            }
        }
    }

    private fun buildProxy(src: String, out: String, height: Int,
                           videoBitrate: Long, audioBitrate: Long,
                           result: MethodChannel.Result) {
        val videoEffects: List<Effect> =
            listOf(Presentation.createForHeight(height))
        val effects = Effects(emptyList(), videoEffects)
        val item = EditedMediaItem.Builder(
            MediaItem.Builder().setUri(Uri.fromFile(File(src))).build())
            .setEffects(effects)
            .setRemoveAudio(false)
            .build()
        runTransformer("proxy", out, item) {}
        result.success(true)
    }

    private fun exportTrim(src: String, out: String, startUs: Long, endUs: Long,
                           height: Int, result: MethodChannel.Result) {
        val clipping = MediaItem.ClippingConfiguration.Builder()
            .setStartPositionUs(startUs)
            .setEndPositionUs(endUs)
            .build()
        val videoEffects: List<Effect> =
            listOf(Presentation.createForHeight(height))
        val effects = Effects(emptyList(), videoEffects)
        val item = EditedMediaItem.Builder(
            MediaItem.Builder()
                .setUri(Uri.fromFile(File(src)))
                .setClippingConfiguration(clipping)
                .build())
            .setEffects(effects)
            .setRemoveAudio(false)
            .build()
        runTransformer("export", out, item) {}
        result.success(true)
    }

    override fun onDestroy() {
        pollGeneration++
        activeTransformer?.cancel()
        activeTransformer = null
        ioPool.shutdown()
        super.onDestroy()
    }
}
